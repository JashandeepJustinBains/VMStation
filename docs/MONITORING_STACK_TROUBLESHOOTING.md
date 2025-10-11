# Monitoring Stack Troubleshooting Guide

## Overview

This document addresses common monitoring stack issues and their resolutions, based on real-world incidents in the VMStation deployment.

## Table of Contents

1. [Grafana Dashboard Issues](#grafana-dashboard-issues)
2. [Loki Syslog Ingestion Problems](#loki-syslog-ingestion-problems)
3. [Prometheus TSDB Issues](#prometheus-tsdb-issues)
4. [General Troubleshooting](#general-troubleshooting)

---

## Grafana Dashboard Issues

### Dashboard Templating Error: ".map is not a function"

**Symptom:**
- Grafana dashboards display error: `Error updating options: (intermediate value).map is not a function`
- Template variables fail to load
- Dashboard shows "No data" despite data being available

**Root Cause:**
- Missing or malformed `templating` section in dashboard JSON
- Grafana expects `templating.list` to be an array, but the property is undefined or not an array

**Solution:**
1. Ensure all dashboard JSON files include a `templating` section with a `list` array:
   ```json
   {
     "schemaVersion": 27,
     "title": "Dashboard Name",
     "templating": {
       "list": []
     },
     "panels": [...]
   }
   ```

2. If the dashboard doesn't need template variables, use an empty array:
   ```json
   "templating": {
     "list": []
   }
   ```

3. Update the dashboard file, minify it, and update the Grafana ConfigMap:
   ```bash
   # Minify the dashboard
   python3 -c "import json; f=open('dashboard.json'); d=json.load(f); f.close(); print(json.dumps(d, separators=(',',':')))" > dashboard-minified.json
   
   # Update ConfigMap
   kubectl apply -f manifests/monitoring/grafana.yaml
   
   # Restart Grafana to reload dashboards
   kubectl delete pod -n monitoring -l app=grafana
   ```

**Prevention:**
- Always include `templating.list` in dashboard JSON exports
- Validate dashboard JSON structure before deployment
- Use template from existing working dashboards

---

## Loki Syslog Ingestion Problems

### JSON Parser Errors in Loki Logs

**Symptom:**
- Loki pod logs show repeated `JSONParserErr` messages
- Error: `Value looks like object, but can't find closing '}' symbol`
- Syslog dashboard shows "No data" for recent messages
- Syslog fields (facility, host, severity) show parse errors

**Root Cause:**
- Malformed JSON payloads from syslog-ng or upstream syslog sources
- Incomplete JSON objects in log stream
- Missing or truncated closing braces in JSON messages
- Line size limits causing JSON truncation

**Diagnosis:**
```bash
# Check Loki logs for JSON parser errors
kubectl logs -n monitoring loki-0 | grep -i "json\|parse"

# Check syslog server configuration
kubectl get cm -n infrastructure syslog-ng-config -o yaml

# Test syslog message format
kubectl logs -n infrastructure -l app=syslog-server | tail -20
```

**Solutions:**

1. **Configure Loki to handle parsing errors gracefully:**
   - Loki queries already use `| json | __error__=""` to filter out parse errors
   - This prevents parse failures from breaking queries

2. **Fix syslog-ng JSON output format:**
   - Ensure syslog-ng destination uses proper JSON template
   - Increase `log-msg-size()` if messages are being truncated
   - Example syslog-ng configuration:
     ```
     destination d_loki {
       http(
         url("http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push")
         method("POST")
         headers("Content-Type: application/json")
         body('{"streams": [{"stream": {"job": "syslog", "facility": "${FACILITY}", "severity": "${SEVERITY}", "hostname": "${HOST}"}, "values": [["${S_UNIXTIME}000000000", "${MESSAGE}"]]}]}')
         log-msg-size(8192)
       );
     };
     ```

3. **Validate incoming syslog messages:**
   ```bash
   # Monitor syslog messages in real-time
   kubectl exec -n infrastructure deploy/syslog-server -- tail -f /var/log/messages
   
   # Check for malformed JSON
   kubectl exec -n infrastructure deploy/syslog-server -- grep -v "^{" /var/log/messages | head
   ```

4. **Increase Loki line size limits if needed:**
   ```yaml
   # In loki.yaml ConfigMap
   limits_config:
     max_line_size: 512KB  # Increase from default 256KB
   ```

**Workaround:**
If fixing the upstream source is not immediately possible:
- Filter out parse errors in dashboard queries using `| __error__=""`
- Monitor parse error rate with: `sum(rate({job="syslog"} | json | __error__!="" [5m]))`
- Set up alerts for high parse error rates

---

## Prometheus TSDB Issues

### TSDB Chunk Corruption / Out-of-Sequence Errors

**Symptom:**
- Prometheus pod shows high restart count (CrashLoopBackOff history)
- Pod eventually starts but logs show TSDB errors during startup:
  ```
  Error: "Loading on-disk chunks failed"
  msg="out of sequence m-mapped chunk for series ref..."
  "Deletion of corrupted mmap chunk files failed, discarding chunk files completely"
  ```
- After errors, Prometheus proceeds: "WAL replay completed", "TSDB started", "Server is ready"

**Root Cause:**
- On-disk TSDB chunk files have sequence/ordering inconsistencies
- Can occur due to:
  - Unclean pod shutdown or OOM kills
  - Disk I/O errors or filesystem issues
  - Kubernetes evictions during high memory usage
  - Multiple Prometheus instances writing to same PVC (rare, but possible with misconfiguration)

**Impact:**
- **Data Integrity:** Some historical metrics may be lost or incomplete
- **Availability:** Pod experiences restarts but ultimately recovers
- **Performance:** WAL replay takes longer during startup

**Diagnosis:**
```bash
# Check Prometheus pod restart count and state
kubectl get pod -n monitoring prometheus-0 -o wide

# Review recent pod events
kubectl get events -n monitoring --field-selector involvedObject.name=prometheus-0 --sort-by='.lastTimestamp'

# Check Prometheus logs for TSDB errors
kubectl logs -n monitoring prometheus-0 | grep -i "tsdb\|chunk\|mmap\|wal"

# Check PVC and filesystem
kubectl get pvc -n monitoring prometheus-storage-prometheus-0
kubectl exec -n monitoring prometheus-0 -- df -h /prometheus
kubectl exec -n monitoring prometheus-0 -- ls -lh /prometheus/
```

**Automatic Recovery:**
- Prometheus has built-in recovery mechanisms:
  1. Detects corrupted mmap chunk files
  2. Attempts to delete corrupted chunks
  3. If deletion fails, discards chunk files completely
  4. Replays WAL (Write-Ahead Log) to rebuild TSDB
  5. Continues operation with remaining valid data

**Manual Intervention (if pod won't start):**
```bash
# Option 1: Delete corrupted chunk files (requires pod shell access)
kubectl exec -n monitoring prometheus-0 -- sh -c "find /prometheus -name '*.mmap' -delete"

# Option 2: If persistent corruption, clear TSDB and start fresh (DATA LOSS)
kubectl scale statefulset prometheus -n monitoring --replicas=0
kubectl exec -n monitoring prometheus-0 -- rm -rf /prometheus/wal /prometheus/chunks_head
kubectl scale statefulset prometheus -n monitoring --replicas=1

# Option 3: Restore from backup (if available)
# See backup/restore documentation
```

**Prevention:**

1. **Increase memory limits** to prevent OOM kills:
   ```yaml
   resources:
     limits:
       memory: 4Gi  # Was 2Gi
   ```

2. **Ensure proper graceful shutdown:**
   ```yaml
   terminationGracePeriodSeconds: 120  # Give Prometheus time to flush
   ```

3. **Use startup probe** to allow slow TSDB initialization:
   ```yaml
   startupProbe:
     failureThreshold: 20  # 5 minutes to start
     periodSeconds: 15
   ```

4. **Monitor TSDB stats:**
   - Query: `prometheus_tsdb_storage_blocks_bytes`
   - Query: `prometheus_tsdb_head_series`
   - Alert on high head series count (indicates high cardinality)

5. **Enable WAL compression** (already configured):
   ```yaml
   args:
     - '--storage.tsdb.wal-compression'
   ```

6. **Set retention limits** to prevent disk exhaustion:
   ```yaml
   args:
     - '--storage.tsdb.retention.time=30d'
     - '--storage.tsdb.retention.size=4GB'
   ```

**Post-Incident Actions:**
1. Review metrics retention and cardinality
2. Check for high-churn series (labels changing frequently)
3. Verify filesystem integrity (`fsck` during maintenance window)
4. Consider increasing PVC size if near capacity
5. Document incident and metrics lost (if any)

---

## General Troubleshooting

### Quick Health Checks

```bash
# Check all monitoring pods
kubectl get pods -n monitoring -o wide

# Check service endpoints
kubectl get endpoints -n monitoring prometheus loki grafana

# Test Prometheus health
kubectl exec -n monitoring prometheus-0 -- wget -qO- http://localhost:9090/-/healthy
kubectl exec -n monitoring prometheus-0 -- wget -qO- http://localhost:9090/-/ready

# Test Loki health
kubectl exec -n monitoring loki-0 -- wget -qO- http://localhost:3100/ready

# Check Grafana datasources
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Open browser: http://localhost:3000/datasources
```

### Common "No Data" Causes

1. **Time Range Issues:**
   - Dashboard time range doesn't match data retention
   - Solution: Extend time range to 6h or 24h

2. **Datasource Not Configured:**
   - Check Grafana → Configuration → Data Sources
   - Solution: Verify Prometheus and Loki URLs and test connection

3. **Query Syntax Errors:**
   - Check panel query syntax in Grafana
   - Test query in Prometheus/Loki UI first

4. **Label Mismatches:**
   - Query labels don't match actual metric labels
   - Solution: Use Prometheus/Loki label browser to find correct labels

5. **Scrape Failures:**
   - Target is down or unreachable
   - Solution: Check Prometheus targets page for errors

### Logs Analysis

```bash
# Tail all monitoring pod logs
kubectl logs -n monitoring -l app=prometheus --tail=50 -f
kubectl logs -n monitoring -l app=loki --tail=50 -f
kubectl logs -n monitoring -l app=grafana --tail=50 -f

# Check for specific errors
kubectl logs -n monitoring prometheus-0 | grep -i "error\|warn\|fail"
kubectl logs -n monitoring loki-0 | grep -i "error\|warn\|fail"
```

### Performance Tuning

1. **Prometheus:**
   - Increase query timeout: `--query.timeout=2m`
   - Increase concurrency: `--query.max-concurrency=20`
   - Monitor TSDB compaction: `prometheus_tsdb_compactions_total`

2. **Loki:**
   - Adjust query parallelism: `querier.max_concurrent: 10`
   - Enable query result caching: `query_range.cache_results: true`
   - Monitor chunk operations: `loki_ingester_chunks_created_total`

3. **Grafana:**
   - Reduce dashboard refresh interval
   - Limit time range for expensive queries
   - Use query caching where possible

---

## Related Documentation

- [Monitoring Stack Deployment Guide](MONITORING_DASHBOARD_DEPLOYMENT.md)
- [Dashboard Enhancement Summary](../DASHBOARD_ENHANCEMENT_SUMMARY.md)
- [Prometheus Enterprise Rewrite](raw/PROMETHEUS_ENTERPRISE_REWRITE.md)
- [Loki Enterprise Rewrite](raw/LOKI_ENTERPRISE_REWRITE.md)
- [Remediation Scripts](../scripts/remediate-monitoring-stack.sh)

---

## Emergency Contacts

For critical monitoring stack failures:
1. Run diagnostic script: `./scripts/diagnose-monitoring-stack.sh`
2. Run remediation script: `./scripts/remediate-monitoring-stack.sh`
3. Review this troubleshooting guide
4. Check pod logs and events
5. Escalate if unresolved after following standard procedures

---

*Last Updated: 2025-10-11*
*Document Version: 1.0*

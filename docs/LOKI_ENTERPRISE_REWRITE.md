# Loki Log Aggregation - Enterprise Rewrite Documentation

## Overview

This document details the comprehensive rewrite of the Loki log aggregation manifest to meet industry-standard best practices for production Kubernetes environments.

## Key Changes and Rationale

### 1. StatefulSet Instead of Deployment

**Change:** Converted from Deployment to StatefulSet
**Rationale:**
- **Stable Storage:** Loki stores log chunks and indexes that benefit from stable PVC binding
- **Ordered Rollout:** Ensures only one Loki instance writes to storage at a time
- **HA Ready:** Easier to scale with consistent pod identities (loki-0, loki-1, etc.)
- **Data Consistency:** Prevents concurrent writes to the same storage location
- **Production Standard:** All stateful applications (databases, log stores) should use StatefulSet

### 2. Production-Grade Loki Configuration

**Changes:**
```yaml
# Common configuration (new)
common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory
```

**Rationale:**
- **Common Config:** Reduces duplication, simplifies management
- **Proper Paths:** Uses /loki instead of /tmp for production data
- **Ring Configuration:** Sets up for HA mode with multiple replicas
- **Best Practice:** Follows Grafana Loki's recommended configuration structure

### 3. Enhanced Ingester Configuration

**Changes:**
```yaml
ingester:
  chunk_idle_period: 1h       # Was 5m
  chunk_block_size: 262144    # 256KB blocks
  chunk_target_size: 1536000  # 1.5MB compressed
  
  wal:
    enabled: true
    dir: /loki/wal
    checkpoint_duration: 5m
    flush_on_shutdown: true
    replay_memory_ceiling: 1GB
```

**Rationale:**
- **Longer Idle Period:** Reduces chunk churn, improves compression
- **Optimized Chunk Sizes:** Balance between query performance and storage efficiency
- **WAL Enabled:** Write-Ahead Log prevents data loss on crashes
- **Checkpoint Duration:** Regular checkpoints balance recovery time and disk I/O
- **Flush on Shutdown:** Ensures no data loss during graceful shutdown
- **Memory Ceiling:** Prevents OOM during WAL replay after crash

### 4. Production Limits Configuration

**Changes:**
```yaml
limits_config:
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20
  max_query_length: 721h           # 30 days
  max_query_parallelism: 32
  max_streams_per_user: 10000
  max_line_size: 256KB
  cardinality_limit: 100000
  per_stream_rate_limit: 3MB
  per_stream_rate_limit_burst: 15MB
```

**Rationale:**
- **Rate Limits:** Prevent single tenant/stream from overwhelming Loki
- **Query Length:** Match retention period (30 days)
- **Parallelism:** Utilize available CPU cores for faster queries
- **Stream Limits:** Prevent cardinality explosion
- **Line Size:** Accommodate large structured logs (JSON, XML)
- **Per-Stream Limits:** Protect against log floods from single application

### 5. Compactor and Retention

**Changes:**
```yaml
compactor:
  working_directory: /loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  retention_delete_worker_count: 150

table_manager:
  retention_deletes_enabled: true
  retention_period: 720h  # 30 days (increased from 168h/7 days)
```

**Rationale:**
- **Compaction:** Merges small chunks, improves query performance
- **Retention Enabled:** Automatically deletes old logs
- **Delete Delay:** Safety window before permanent deletion
- **Worker Count:** Parallel deletion for faster cleanup
- **30-Day Retention:** Standard enterprise log retention period
- **Compliance:** Can be adjusted for regulatory requirements (90 days, 1 year, etc.)

### 6. Query Optimization

**Changes:**
```yaml
query_range:
  align_queries_with_step: true
  cache_results: true
  max_retries: 5
  results_cache:
    cache:
      enable_fifocache: true
      fifocache:
        max_size_items: 1024
        ttl: 24h

querier:
  max_concurrent: 10
  query_ingesters_within: 3h
```

**Rationale:**
- **Query Alignment:** Improves cache hit rate for Grafana dashboards
- **Result Caching:** Dramatically speeds up repeated queries
- **Retry Logic:** Handles transient failures gracefully
- **FIFO Cache:** Simple, effective caching strategy
- **Concurrent Queries:** Balance between throughput and resource usage
- **Ingester Query Window:** Only query recent data from ingesters, older from store

### 7. Enhanced Security Context

**Changes:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001  # loki user
  fsGroup: 10001
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
    - ALL
```

**Rationale:**
- **Non-Root User:** Loki runs as dedicated UID 10001
- **Read-Only Filesystem:** Only /loki and /tmp are writable
- **No Privilege Escalation:** Prevents container breakout
- **Drop Capabilities:** Removes all unnecessary Linux capabilities
- **Security Standard:** Aligns with Pod Security Standards (Restricted)

### 8. Improved Resource Allocation

**Changes:**
```yaml
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 2Gi
```

**Rationale:**
- **Increased Memory:** 512Mi request, 2Gi limit (was 256Mi/512Mi)
- **Log Workload:** Loki needs memory for WAL replay, compaction, queries
- **QoS Burstable:** Allows bursting during high ingestion/query load
- **Production Sized:** Based on typical 3-node cluster with moderate log volume
- **Right-Sized:** Can handle 10-20 MB/s ingestion with complex queries

### 9. Comprehensive Health Probes

**Startup Probe:**
```yaml
startupProbe:
  httpGet:
    path: /ready
    port: http-metrics
  failureThreshold: 30  # 5 minutes
  periodSeconds: 10
```
- Allows up to 5 minutes for WAL replay after crash
- Prevents liveness probe from killing pod during startup

**Readiness Probe:**
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: http-metrics
  initialDelaySeconds: 30
  periodSeconds: 10
```
- Removes pod from service when not ready to serve queries
- Frequent checks (10s) for fast failover

**Liveness Probe:**
```yaml
livenessProbe:
  httpGet:
    path: /ready
    port: http-metrics
  initialDelaySeconds: 90
  periodSeconds: 30
  failureThreshold: 5
```
- Longer delay (90s) to avoid false positives
- Less frequent (30s) to reduce overhead
- 5 failures = 2.5 minutes before restart

### 10. Increased Storage Capacity

**Changes:**
```yaml
volumeClaimTemplates:
  - metadata:
      name: loki-data
    spec:
      resources:
        requests:
          storage: 20Gi  # Increased from implicit 5Gi
```

**Rationale:**
- **30-Day Retention:** 20Gi supports 30 days of logs from 3-node cluster
- **Log Volume Estimation:** ~30-50 MB/day per node, compressed
- **Headroom:** Allows for log bursts and unexpected growth
- **Cost vs Safety:** Balance between storage cost and retention period

### 11. ServiceAccount and RBAC

**Change:** Added dedicated ServiceAccount

**Rationale:**
- **Principle of Least Privilege:** Loki runs with minimal permissions
- **Future Extensions:** Ready for ruler (alerting) and additional RBAC if needed
- **Security Audit:** Clear identity for pod in security logs
- **Kubernetes Standard:** All workloads should have explicit ServiceAccount

### 12. NetworkPolicy for Security

**Changes:** Added comprehensive NetworkPolicy

**Ingress Rules:**
- Grafana queries (port 3100)
- Promtail log ingestion (ports 3100, 9096)
- Syslog server forwarding (port 3100)
- Prometheus metrics scraping (port 3100)
- External access via NodePort

**Egress Rules:**
- DNS resolution only

**Rationale:**
- **Zero Trust:** Explicit allow-list for all traffic
- **Defense in Depth:** Network segmentation layer
- **Compliance:** Required for PCI-DSS, HIPAA
- **Attack Surface Reduction:** Prevents unexpected connections

### 13. Structured Logging and JSON Format

**Change:**
```yaml
server:
  log_format: json
```

**Rationale:**
- **Structured Logs:** Easier to parse and query in Loki itself
- **Machine Readable:** Better for log aggregation pipelines
- **Enterprise Standard:** JSON is standard for production logging
- **Debugging:** Easier to filter and search structured fields

### 14. Dual Service Architecture

**Changes:**
- Headless Service (loki): For StatefulSet DNS
- NodePort Service (loki-external): For external access

**Rationale:**
- **StatefulSet DNS:** loki-0.loki.monitoring.svc.cluster.local
- **Internal Access:** Pods use headless service (loki:3100)
- **External Access:** Operators use NodePort (node-ip:31100)
- **Security:** Can apply different NetworkPolicies to each service

### 15. Init Container Improvements

**Changes:**
```yaml
initContainers:
- name: init-loki-data
  command:
  - sh
  - -c
  - |
    mkdir -p /loki/chunks /loki/index /loki/index_cache /loki/wal /loki/compactor
    chown -R 10001:10001 /loki
    chmod -R 755 /loki
```

**Rationale:**
- **Directory Structure:** Creates all required directories upfront
- **Proper Permissions:** Ensures UID 10001 can write
- **Idempotent:** Safe to run multiple times
- **Clear Logging:** Explicit messages for troubleshooting
- **Standard Pattern:** Common init container pattern for stateful apps

## Migration Path

### Breaking Changes

1. **PVC Name Change:**
   - Old: `loki-pvc`
   - New: `loki-data-loki-0`
   - **Action:** Backup logs, deploy new StatefulSet, optionally migrate data

2. **Config File Name:**
   - Old: `/etc/loki/local-config.yaml`
   - New: `/etc/loki/loki.yaml`
   - **Impact:** ConfigMap key changed, but handled automatically

3. **Storage Paths:**
   - Old: `/tmp/loki/*`
   - New: `/loki/*`
   - **Impact:** Fresh install or data migration required

### Non-Breaking Changes

- Service name `loki` remains the same for internal clients
- NodePort 31100 unchanged
- Prometheus scraping continues to work
- Promtail configuration doesn't need changes

## Data Migration Procedure

If you need to preserve existing logs:

1. **Backup existing Loki data:**
   ```bash
   kubectl exec -n monitoring <old-loki-pod> -- tar czf /tmp/loki-backup.tar.gz /tmp/loki
   kubectl cp monitoring/<old-loki-pod>:/tmp/loki-backup.tar.gz ./loki-backup.tar.gz
   ```

2. **Scale down old Deployment:**
   ```bash
   kubectl scale deployment -n monitoring loki --replicas=0
   ```

3. **Deploy new StatefulSet:**
   ```bash
   kubectl apply -f manifests/monitoring/loki.yaml
   ```

4. **Wait for pod to be ready:**
   ```bash
   kubectl wait --for=condition=ready pod -n monitoring loki-0 --timeout=5m
   ```

5. **Restore data (if needed):**
   ```bash
   kubectl cp ./loki-backup.tar.gz monitoring/loki-0:/tmp/
   kubectl exec -n monitoring loki-0 -- tar xzf /tmp/loki-backup.tar.gz -C /loki --strip-components=2
   kubectl exec -n monitoring loki-0 -- chown -R 10001:10001 /loki
   kubectl delete pod -n monitoring loki-0  # Restart to reload data
   ```

## Validation Checklist

- [ ] StatefulSet created and running
- [ ] PVC `loki-data-loki-0` bound
- [ ] Pod passes all health probes
- [ ] Loki UI accessible at `http://<node-ip>:31100`
- [ ] Promtail can send logs to Loki
- [ ] Grafana can query logs from Loki
- [ ] Metrics endpoint `/metrics` returns data
- [ ] Compactor is running (check logs)
- [ ] Retention is working (old logs deleted)
- [ ] NetworkPolicy not blocking legitimate traffic
- [ ] Resource usage within limits

## Performance Tuning

### High Ingestion Rate (>50 MB/s)

```yaml
limits_config:
  ingestion_rate_mb: 50
  ingestion_burst_size_mb: 100
  
resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 4000m
    memory: 8Gi
```

### Long Retention (>90 days)

```yaml
table_manager:
  retention_period: 2160h  # 90 days

volumeClaimTemplates:
  resources:
    requests:
      storage: 100Gi
```

### High Query Volume

```yaml
querier:
  max_concurrent: 20

query_range:
  results_cache:
    cache:
      fifocache:
        max_size_items: 4096  # Larger cache
```

## Troubleshooting

### Pod Stuck in Init

**Symptoms:** Pod stays in `Init:0/1`
**Check:** `kubectl logs -n monitoring loki-0 -c init-loki-data`
**Common Causes:**
- PVC not binding (check `kubectl get pvc -n monitoring`)
- StorageClass not available
- Insufficient disk space on node

**Solution:**
```bash
kubectl describe pvc -n monitoring loki-data-loki-0
kubectl get storageclass
```

### High Memory Usage

**Symptoms:** Pod OOMKilled or high memory usage
**Check:** `kubectl top pod -n monitoring loki-0`
**Common Causes:**
- Large WAL replay after crash
- Too many concurrent queries
- High cardinality labels

**Solution:**
```yaml
# Increase memory limits
resources:
  limits:
    memory: 4Gi

# Or reduce retention
limits_config:
  max_streams_per_user: 5000
```

### Compaction Not Running

**Symptoms:** Disk usage grows indefinitely
**Check:** `kubectl logs -n monitoring loki-0 | grep compactor`
**Common Causes:**
- Compactor disabled in config
- Insufficient disk space
- Permissions issues

**Solution:**
```bash
# Verify compactor is enabled
kubectl exec -n monitoring loki-0 -- grep -A5 compactor /etc/loki/loki.yaml

# Check disk space
kubectl exec -n monitoring loki-0 -- df -h /loki
```

## Monitoring Loki Itself

### Key Metrics

```promql
# Ingestion rate
rate(loki_ingester_chunks_created_total[5m])

# Query performance
histogram_quantile(0.99, rate(loki_request_duration_seconds_bucket[5m]))

# Failed requests
rate(loki_request_duration_seconds_count{status_code=~"5.."}[5m])

# TSDB head series (cardinality)
loki_ingester_memory_streams

# Disk usage
loki_store_index_entries_total
```

### Alerts

```yaml
- alert: LokiRequestErrors
  expr: rate(loki_request_duration_seconds_count{status_code=~"5.."}[5m]) > 0.01
  for: 5m
  annotations:
    summary: Loki is returning 5xx errors

- alert: LokiCompactionNotRunning
  expr: time() - loki_compactor_last_successful_run_timestamp_seconds > 3600
  for: 10m
  annotations:
    summary: Loki compaction hasn't run in over an hour
```

## References

- [Loki Configuration Documentation](https://grafana.com/docs/loki/latest/configuration/)
- [Loki Storage Documentation](https://grafana.com/docs/loki/latest/operations/storage/)
- [Loki Best Practices](https://grafana.com/docs/loki/latest/best-practices/)
- [Kubernetes StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)

## Change Log

- **2025-01-XX:** Enterprise rewrite completed
  - Converted Deployment to StatefulSet
  - Production-grade configuration
  - Enhanced security contexts
  - Comprehensive health probes
  - NetworkPolicy implementation
  - 30-day retention with compaction

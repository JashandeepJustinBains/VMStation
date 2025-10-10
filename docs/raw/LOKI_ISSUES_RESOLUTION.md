# Loki Deployment Issues - Resolution Summary

## Problem Statement

Three critical issues were affecting the VMStation monitoring stack:

1. **Loki Query Errors**: Status 500 with message "parse error: queries require at least one regexp or equality matcher that does not have an empty-compatible value"
2. **Blackbox Probe Failures**: Grafana probe status showing `http://loki.monitoring.svc.cluster.local:3100 | blackbox | Fail`
3. **No Homelab Data**: Missing logs and metrics from the homelab RHEL 10 node running RKE2

## Root Causes

### Issue 1: Invalid LogQL Queries
Loki dashboards used queries with only empty-compatible matchers (e.g., `{namespace!="kube-system"}`), which Loki 2.9.2 rejects. LogQL requires at least one non-empty-compatible matcher.

### Issue 2: Incorrect Blackbox Probe Endpoints
The blackbox exporter was probing the root path `/` on services, but not all services have a valid root endpoint. Loki requires `/ready` for health checks.

### Issue 3: Missing Homelab Integration
The homelab node at 192.168.4.62 runs its own RKE2 cluster (due to RHEL 10 requirements) but had no mechanism to forward logs to the masternode Loki or expose metrics to the masternode Prometheus.

## Solutions Implemented

### Fix 1: Updated Loki Dashboard Queries

**Changes**: All Loki queries in Grafana dashboards now use proper matchers.

**Before** (Invalid):
```logql
{namespace!="kube-system"}
{namespace="monitoring"}
```

**After** (Valid):
```logql
{job=~".+"} | namespace !~ "kube-system|kube-flannel|monitoring"
{job=~".+", namespace="kube-system"}
{job=~".+", namespace="monitoring"}
```

**Files Modified**:
- `manifests/monitoring/grafana.yaml` - Updated 5 dashboard queries in the Loki dashboard

**Impact**: ✅ Eliminates "parse error" in all Loki dashboards

### Fix 2: Corrected Blackbox Probe Endpoints

**Changes**: Updated blackbox targets to use proper health check endpoints.

**Before**:
```yaml
- http://loki.monitoring.svc.cluster.local:3100
- http://prometheus.monitoring.svc.cluster.local:9090
- http://grafana.monitoring.svc.cluster.local:3000
```

**After**:
```yaml
- http://loki.monitoring.svc.cluster.local:3100/ready
- http://prometheus.monitoring.svc.cluster.local:9090/-/healthy
- http://grafana.monitoring.svc.cluster.local:3000/api/health
```

**Files Modified**:
- `manifests/monitoring/prometheus.yaml` - Updated blackbox scrape job

**Impact**: ✅ Blackbox probes now correctly detect service health

### Fix 3: Homelab Monitoring Integration

**Changes**: Created complete automation for deploying monitoring on homelab RKE2.

**Components Deployed**:
1. **Promtail DaemonSet**: Forwards logs to masternode Loki (192.168.4.63:31100)
2. **Node Exporter DaemonSet**: Exposes system metrics for Prometheus scraping
3. **RBAC**: ServiceAccount, ClusterRole, ClusterRoleBinding for Promtail

**Additional Changes**:
- Added `homelab-node-exporter` scrape target to Prometheus
- Updated Promtail configuration to include job labels
- Added external labels for cluster identification (`cluster: rke2-homelab`)

**Files Created**:
- `ansible/playbooks/configure-homelab-monitoring.yml` - Deployment automation
- `docs/HOMELAB_MONITORING_INTEGRATION.md` - Complete integration guide
- `docs/LOKI_FIX_QUICK_REFERENCE.md` - Quick deployment reference

**Files Modified**:
- `manifests/monitoring/prometheus.yaml` - Added homelab scrape target
- `manifests/monitoring/loki.yaml` - Added job label to Promtail
- `ansible/playbooks/README.md` - Documented new playbook

**Impact**: ✅ Centralizes all monitoring data from homelab to masternode

## Deployment Instructions

### Quick Start

```bash
# 1. Apply updated manifests to masternode
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/grafana.yaml
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/prometheus.yaml
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/loki.yaml

# 2. Restart affected services
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/grafana -n monitoring
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/prometheus -n monitoring
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart daemonset/promtail -n monitoring

# 3. Configure homelab monitoring (if RKE2 is installed)
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/configure-homelab-monitoring.yml
```

### Detailed Instructions

See `docs/LOKI_FIX_QUICK_REFERENCE.md` for step-by-step deployment and validation.

## Verification

### Verify Loki Queries Work

1. Access Grafana: `http://192.168.4.63:30300`
2. Navigate to: Dashboards → Loki Logs & Aggregation
3. ✅ All panels load without "parse error"
4. ✅ Log data is visible

### Verify Blackbox Probe Passes

1. Access Grafana: `http://192.168.4.63:30300`
2. Navigate to: Dashboards → Network & DNS Performance
3. Check "Probe Status Table"
4. ✅ Loki shows "OK" (green) instead of "Fail" (red)

### Verify Homelab Data

**Logs**:
```bash
# Query Loki for homelab logs
curl -G -s "http://192.168.4.63:31100/loki/api/v1/query" \
  --data-urlencode 'query={cluster="rke2-homelab"}' | jq
```
✅ Should return log entries

**Metrics**:
```bash
# Check Prometheus targets
curl -s http://192.168.4.63:30090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.labels.job == "homelab-node-exporter")'
```
✅ Target should be UP

**Dashboards**:
- Node Metrics dashboard shows homelab node
- IPMI Hardware Monitoring shows hardware stats (if IPMI available)

## Architecture

```
┌─────────────────────────────────────────┐
│ Masternode (192.168.4.63)              │
│                                         │
│  Prometheus ◄──┐                        │
│  Loki       ◄──┼─── Metrics & Logs     │
│  Grafana       │                        │
└────────────────┼────────────────────────┘
                 │
                 │ Federation, Scraping,
                 │ Log Forwarding
                 │
┌────────────────┼────────────────────────┐
│                │                        │
│ Homelab (192.168.4.62) - RKE2         │
│                                         │
│  Promtail ─────┘                        │
│  Node Exporter (9100)                   │
│  IPMI Exporter (9290)                   │
│  RKE2 Prometheus (30090) - Optional     │
└─────────────────────────────────────────┘
```

## Key Concepts

### LogQL Query Requirements

Loki requires at least one label matcher that is **not** empty-compatible:

**Empty-compatible** (reject):
- `label != "value"` - Matches everything without this exact value
- `label !~ "pattern"` - Matches everything not matching pattern

**Non-empty-compatible** (accept):
- `label = "value"` - Exact match
- `label =~ ".+"` - Any non-empty value
- `label =~ "pattern"` - Regex match

**Valid Queries**:
```logql
{job=~".+"}                                    ✅
{job="kubernetes-pods"}                        ✅
{job=~".+"} | namespace !~ "kube-system"      ✅
{cluster="rke2-homelab", node="homelab"}      ✅
```

**Invalid Queries**:
```logql
{namespace!="kube-system"}                     ❌
{namespace!="kube-system", pod!="test"}       ❌
```

### Health Check Endpoints

Different services use different health check paths:

| Service | Health Endpoint |
|---------|----------------|
| Loki | `/ready` |
| Prometheus | `/-/healthy` or `/-/ready` |
| Grafana | `/api/health` |
| Node Exporter | `/metrics` (no dedicated health) |

### Cross-Cluster Monitoring

The homelab node runs a separate RKE2 cluster but integrates with masternode monitoring via:

1. **Log Forwarding**: Promtail → Masternode Loki
2. **Metric Scraping**: Prometheus → Node Exporter
3. **Hardware Monitoring**: Prometheus → IPMI Exporter
4. **Federation** (optional): Prometheus → RKE2 Prometheus

## Testing

### Manual Testing

```bash
# Test Loki query
curl -G -s "http://192.168.4.63:31100/loki/api/v1/query" \
  --data-urlencode 'query={job=~".+"}' --data-urlencode 'limit=10'

# Test blackbox probe
curl -s http://192.168.4.63:30090/api/v1/query?query=probe_success

# Test homelab connectivity
ssh jashandeepjustinbains@192.168.4.62 \
  'curl -sf http://192.168.4.63:31100/ready'
```

### Automated Testing

```bash
# Run Loki validation tests
./tests/test-loki-validation.sh

# Run complete validation
./tests/test-complete-validation.sh
```

## Troubleshooting

### Common Issues

1. **Loki still shows parse errors**
   - Clear browser cache or force Grafana restart
   - Verify ConfigMap was updated: `kubectl get cm grafana-datasources -n monitoring -o yaml`

2. **Blackbox probe still failing**
   - Check Loki logs: `kubectl logs -n monitoring -l app=loki`
   - Verify service: `kubectl get svc -n monitoring loki`
   - Test endpoint: `kubectl exec -n monitoring deploy/loki -- wget -qO- http://localhost:3100/ready`

3. **No homelab logs**
   - Verify RKE2 running: `ssh homelab 'systemctl status rke2-server'`
   - Check Promtail: `ssh homelab 'kubectl get pods -n monitoring'`
   - Test connectivity: `ssh homelab 'curl -sf http://192.168.4.63:31100/ready'`

4. **No homelab metrics**
   - Check node-exporter: `curl http://192.168.4.62:9100/metrics`
   - Verify Prometheus target: Check Status → Targets in Prometheus UI
   - Check firewall: `ssh homelab 'firewall-cmd --list-ports'`

See `docs/LOKI_FIX_QUICK_REFERENCE.md` for detailed troubleshooting steps.

## Performance Considerations

### Loki Log Volume

Current configuration supports ~10MB/s ingestion rate. If you have high log volume:

1. Increase ingestion limits in `manifests/monitoring/loki.yaml`:
   ```yaml
   limits_config:
     ingestion_rate_mb: 20
     ingestion_burst_size_mb: 40
   ```

2. Adjust retention period (default 168h = 7 days):
   ```yaml
   table_manager:
     retention_period: 720h  # 30 days
   ```

### Promtail Buffering

For unreliable networks, configure Promtail backoff:

```yaml
clients:
  - url: http://192.168.4.63:31100/loki/api/v1/push
    backoff_config:
      min_period: 100ms
      max_period: 10s
      max_retries: 10
```

## Security Notes

1. **Network Access**: Ensure firewall allows:
   - Homelab → Masternode:31100 (Loki)
   - Masternode → Homelab:9100 (Node Exporter)
   - Masternode → Homelab:9290 (IPMI Exporter)

2. **Authentication**: Current setup uses no authentication for Loki push. Consider adding auth in production.

3. **TLS**: All connections use HTTP. Consider TLS for production deployments.

## Future Enhancements

1. **Dynamic Service Discovery**: Replace static targets with Kubernetes service discovery
2. **Alert Manager Integration**: Add alerting for missing logs/metrics
3. **Log Parsing**: Add structured log parsing in Promtail
4. **Metric Aggregation**: Add recording rules for common queries
5. **Multi-Tenancy**: Separate logs by tenant using Loki tenants

## References

- **Main Documentation**: `docs/HOMELAB_MONITORING_INTEGRATION.md`
- **Quick Reference**: `docs/LOKI_FIX_QUICK_REFERENCE.md`
- **Loki Config Guide**: `docs/LOKI_CONFIG_DRIFT_PREVENTION.md`
- **Playbook Documentation**: `ansible/playbooks/README.md`

## Change Summary

| Component | Changes | Files |
|-----------|---------|-------|
| Loki Dashboards | Fixed 5 queries with proper matchers | `manifests/monitoring/grafana.yaml` |
| Blackbox Probes | Updated to use health endpoints | `manifests/monitoring/prometheus.yaml` |
| Promtail Config | Added job labels | `manifests/monitoring/loki.yaml` |
| Homelab Integration | Created deployment automation | `ansible/playbooks/configure-homelab-monitoring.yml` |
| Documentation | Created 2 comprehensive guides | `docs/HOMELAB_MONITORING_INTEGRATION.md`, `docs/LOKI_FIX_QUICK_REFERENCE.md` |

## Conclusion

All three reported issues have been addressed:

1. ✅ **Loki Query Errors**: Fixed by updating all dashboard queries to use non-empty-compatible matchers
2. ✅ **Blackbox Probe Failures**: Fixed by using proper health check endpoints
3. ✅ **No Homelab Data**: Fixed by deploying Promtail and Node Exporter on homelab RKE2 with proper configuration

The monitoring stack now provides:
- Centralized log aggregation from both clusters
- Unified metrics collection from all nodes
- Proper health monitoring via blackbox probes
- Clear separation of concerns (RKE2 for compute, masternode for monitoring)

Deploy these changes following the instructions in `docs/LOKI_FIX_QUICK_REFERENCE.md` to resolve all reported issues.

# Quick Fix: Loki Deployment Issues

## Issues Addressed

1. ✅ **Loki Query Error**: "parse error: queries require at least one regexp or equality matcher that does not have an empty-compatible value"
2. ✅ **Blackbox Probe Failure**: Loki service showing as "Fail" in Grafana probe status table
3. ✅ **No Homelab Data**: Missing logs and metrics from homelab RHEL 10 node

## Immediate Fixes Applied

### 1. Fixed Loki Dashboard Queries

**Problem**: Dashboard queries used empty-compatible matchers like `{namespace!="kube-system"}` which Loki rejects.

**Solution**: All queries now use non-empty-compatible matchers:

```logql
# Before (WRONG)
{namespace!="kube-system"}

# After (CORRECT)
{job=~".+", namespace!="kube-system"}
# or
{job=~".+"} | namespace !~ "kube-system|kube-flannel|monitoring"
```

**Files Modified**:
- `manifests/monitoring/grafana.yaml` - Updated all Loki dashboard queries

### 2. Fixed Blackbox Probe Endpoints

**Problem**: Blackbox was probing root path `/` which doesn't exist on all services.

**Solution**: Updated probe targets to use proper health endpoints:

```yaml
# Before
- http://loki.monitoring.svc.cluster.local:3100

# After
- http://loki.monitoring.svc.cluster.local:3100/ready
- http://prometheus.monitoring.svc.cluster.local:9090/-/healthy
- http://grafana.monitoring.svc.cluster.local:3000/api/health
```

**Files Modified**:
- `manifests/monitoring/prometheus.yaml` - Updated blackbox targets

### 3. Configured Homelab Log and Metric Export

**Problem**: Homelab node running RKE2 wasn't sending logs or metrics to masternode.

**Solution**: Created playbook to deploy Promtail and Node Exporter on homelab:

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/configure-homelab-monitoring.yml
```

**Files Created**:
- `ansible/playbooks/configure-homelab-monitoring.yml` - Deployment automation
- `docs/HOMELAB_MONITORING_INTEGRATION.md` - Complete integration guide

**Files Modified**:
- `manifests/monitoring/prometheus.yaml` - Added homelab-node-exporter scrape target
- `manifests/monitoring/loki.yaml` - Updated Promtail job labels
- `ansible/playbooks/README.md` - Documented new playbook

## Deployment Instructions

### Step 1: Apply Updated Manifests to Masternode

```bash
# On masternode (192.168.4.63)
cd /home/runner/work/VMStation/VMStation

# Apply updated Grafana dashboards
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/grafana.yaml

# Apply updated Prometheus configuration
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/prometheus.yaml

# Apply updated Loki/Promtail configuration
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/loki.yaml

# Restart affected deployments
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/grafana -n monitoring
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/prometheus -n monitoring
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart daemonset/promtail -n monitoring
```

### Step 2: Configure Homelab Monitoring (If RKE2 is Installed)

If you have RKE2 installed on the homelab node:

```bash
# From masternode or local machine
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/configure-homelab-monitoring.yml
```

If RKE2 is not yet installed:

```bash
# Install RKE2 first
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/install-rke2-homelab.yml

# Then configure monitoring
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/configure-homelab-monitoring.yml
```

### Step 3: Verify Fixes

#### Verify Loki Queries Work

1. Access Grafana: `http://192.168.4.63:30300`
2. Navigate to Dashboards → Loki Logs & Aggregation
3. All panels should load without "parse error"
4. You should see log data (may take a few minutes for data to appear)

#### Verify Blackbox Probe Passes

1. Access Grafana: `http://192.168.4.63:30300`
2. Navigate to Dashboards → Network & DNS Performance
3. Check the "Probe Status Table"
4. Loki probe should show "OK" (green) instead of "Fail" (red)

#### Verify Homelab Data

1. **Check Logs**:
   - In Grafana → Explore → Loki
   - Query: `{cluster="rke2-homelab"}`
   - Should see logs from homelab node

2. **Check Metrics**:
   - Access Prometheus: `http://192.168.4.63:30090`
   - Go to Status → Targets
   - Look for `homelab-node-exporter` - should be UP
   - Look for `ipmi-exporter` - should be UP (if IPMI hardware available)

3. **Check Dashboards**:
   - Node Metrics dashboard should show homelab node
   - IPMI Hardware Monitoring dashboard should show hardware stats

## Validation Commands

### Check Loki is Healthy

```bash
# From masternode
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring -l app=loki

# Should show Running
kubectl --kubeconfig=/etc/kubernetes/admin.conf exec -n monitoring deploy/loki -- \
  wget -qO- http://localhost:3100/ready

# Should return: ready
```

### Check Blackbox Probe

```bash
# Check probe status via Prometheus API
curl -s http://192.168.4.63:30090/api/v1/query?query=probe_success | \
  jq '.data.result[] | {instance: .metric.instance, success: .value[1]}'
```

### Check Homelab Logs Arriving

```bash
# Query Loki API for homelab logs
curl -G -s "http://192.168.4.63:31100/loki/api/v1/query" \
  --data-urlencode 'query={cluster="rke2-homelab"}' | \
  jq '.data.result | length'

# Should return a number > 0
```

### Check Homelab Metrics

```bash
# Query Prometheus for homelab metrics
curl -s http://192.168.4.63:30090/api/v1/query?query=up\{job=\"homelab-node-exporter\"\} | \
  jq '.data.result[0].value[1]'

# Should return: "1"
```

## Troubleshooting

### If Loki Dashboard Still Shows Parse Errors

**Cause**: Grafana might have cached the old dashboard.

**Fix**:
```bash
# Force Grafana to reload dashboards
kubectl --kubeconfig=/etc/kubernetes/admin.conf delete pod -n monitoring -l app=grafana
```

Wait for Grafana pod to restart, then refresh the browser.

### If Blackbox Probe Still Shows Fail

**Check Loki is actually ready**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf exec -n monitoring deploy/loki -- \
  wget -qO- http://localhost:3100/ready
```

**Check Loki logs**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf logs -n monitoring -l app=loki --tail=50
```

**Check blackbox can reach Loki**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf exec -n monitoring deploy/blackbox-exporter -- \
  wget -qO- http://loki.monitoring.svc.cluster.local:3100/ready
```

### If No Homelab Data

**Verify RKE2 is running**:
```bash
ssh jashandeepjustinbains@192.168.4.62 'sudo systemctl status rke2-server'
```

**Check Promtail on homelab**:
```bash
ssh jashandeepjustinbains@192.168.4.62 \
  'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml && \
   /var/lib/rancher/rke2/bin/kubectl get pods -n monitoring -l app=promtail'
```

**Test connectivity from homelab to masternode Loki**:
```bash
ssh jashandeepjustinbains@192.168.4.62 \
  'curl -sf -X POST "http://192.168.4.63:31100/loki/api/v1/push" \
   -H "Content-Type: application/json" \
   -d '"'"'{
     "streams": [{
       "stream": {"job": "test", "cluster": "rke2-homelab"},
       "values": [["'$(date +%s)000000000'", "Test"]]
     }]
   }'"'"' && echo "✅ OK" || echo "❌ FAILED"'
```

**Check firewall on homelab**:
```bash
ssh jashandeepjustinbains@192.168.4.62 \
  'sudo firewall-cmd --list-ports | grep -E "9100|31100"'
```

If ports not open:
```bash
ssh jashandeepjustinbains@192.168.4.62 \
  'sudo firewall-cmd --permanent --add-port=9100/tcp && \
   sudo firewall-cmd --permanent --add-port=9290/tcp && \
   sudo firewall-cmd --reload'
```

## Summary of Changes

| File | Change | Purpose |
|------|--------|---------|
| `manifests/monitoring/grafana.yaml` | Updated all Loki query expressions | Fix "parse error" in dashboards |
| `manifests/monitoring/prometheus.yaml` | Updated blackbox probe targets, added homelab-node-exporter | Fix probe failures, collect homelab metrics |
| `manifests/monitoring/loki.yaml` | Added job label to Promtail relabel_configs | Ensure queries have proper matchers |
| `ansible/playbooks/configure-homelab-monitoring.yml` | New playbook | Deploy Promtail and Node Exporter on homelab RKE2 |
| `docs/HOMELAB_MONITORING_INTEGRATION.md` | New documentation | Complete guide for homelab integration |

## Next Steps

After applying these fixes:

1. ✅ Loki dashboards should work without parse errors
2. ✅ Blackbox probe should show Loki as healthy
3. ✅ Homelab logs should appear in Loki (if RKE2 configured)
4. ✅ Homelab metrics should appear in Prometheus (if RKE2 configured)

For complete homelab integration details, see: `docs/HOMELAB_MONITORING_INTEGRATION.md`

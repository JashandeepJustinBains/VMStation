# Monitoring Stack Failure - Quick Fix Guide

**Emergency Fix for Prometheus and Loki Failures**

---

## TL;DR - Run This

```bash
# On the masternode, run these commands in order:
cd /srv/monitoring_data/VMStation

# 1. Apply the manifest fixes (contains the corrected configurations)
kubectl apply -f manifests/monitoring/prometheus.yaml
kubectl apply -f manifests/monitoring/loki.yaml

# 2. Delete pods to force recreation with new configs
kubectl delete pod prometheus-0 loki-0 -n monitoring

# 3. Wait for pods to restart (about 2-3 minutes)
kubectl get pods -n monitoring -w

# 4. Verify endpoints are populated
kubectl get endpoints prometheus loki -n monitoring

# Expected output:
# NAME         ENDPOINTS
# prometheus   <pod-ip>:9090
# loki         <pod-ip>:3100,<pod-ip>:9096
```

---

## What Was Fixed?

### 1. Prometheus - Added `runAsGroup` to SecurityContext

**Before:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  fsGroup: 65534
```

**After:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  runAsGroup: 65534  # ← ADDED
  fsGroup: 65534
```

**Why:** Without `runAsGroup`, the container process may run with a different primary group, causing permission denied errors on the `/prometheus` volume.

---

### 2. Loki - Disabled `frontend_worker`

**Before:**
```yaml
frontend_worker:
  frontend_address: 127.0.0.1:9095
  parallelism: 10
```

**After:**
```yaml
# Frontend worker - DISABLED for single-instance deployment
# frontend_worker:
#   frontend_address: 127.0.0.1:9095
#   parallelism: 10
```

**Why:** In all-in-one mode, the frontend_worker tries to connect to the query-frontend before it's ready, causing connection refused errors and preventing the pod from becoming Ready.

---

## Verification Steps

### Check Pod Status
```bash
kubectl get pods -n monitoring
```

**Expected:**
```
NAME                                  READY   STATUS    RESTARTS   AGE
prometheus-0                          2/2     Running   0          2m
loki-0                                1/1     Running   0          2m
```

### Check Endpoints
```bash
kubectl get endpoints prometheus loki -n monitoring
```

**Expected:**
```
NAME         ENDPOINTS                          AGE
prometheus   10.244.0.228:9090                  30m
loki         10.244.0.225:3100,10.244.0.225:9096   30m
```

### Test Health
```bash
# Prometheus
kubectl exec prometheus-0 -n monitoring -c prometheus -- wget -O- http://localhost:9090/-/healthy

# Loki
kubectl exec loki-0 -n monitoring -- wget -O- http://localhost:3100/ready
```

**Expected:**
```
Prometheus is Healthy.
ready
```

### Test from Grafana
1. Open Grafana: `http://<masternode-ip>:30300`
2. Go to: Configuration → Data Sources
3. Test both Prometheus and Loki
4. Both should show: ✅ "Data source is working"

---

## If It Still Doesn't Work

### Run the Full Diagnostic
```bash
cd /srv/monitoring_data/VMStation
./scripts/diagnose-monitoring-stack.sh

# Review the analysis
cat /tmp/monitoring-diagnostics-*/00-ANALYSIS-AND-RECOMMENDATIONS.txt
```

### Run Automated Remediation
```bash
cd /srv/monitoring_data/VMStation
./scripts/remediate-monitoring-stack.sh
```

### Check Logs
```bash
# Prometheus logs
kubectl logs prometheus-0 -n monitoring -c prometheus --tail=50

# Loki logs
kubectl logs loki-0 -n monitoring --tail=50
```

---

## Still Having Issues?

See the comprehensive guide:
```bash
cat docs/MONITORING_STACK_DIAGNOSTICS_AND_REMEDIATION.md
```

Or run the validation script:
```bash
./scripts/validate-monitoring-stack.sh
```

---

**Expected Total Downtime:** 3-5 minutes (pod restart time)

**Rollback:** If needed, restore from backup:
```bash
kubectl apply -f /tmp/monitoring-backups-*/monitoring-all-backup.yaml
```

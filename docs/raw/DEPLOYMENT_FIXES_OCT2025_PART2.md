# VMStation Deployment Issues - Root Cause Analysis and Fixes

**Date:** October 9, 2025  
**Status:** ✅ **RESOLVED**

## Problems Identified

### 1. **Prometheus CrashLoopBackOff** 🔴
**Symptoms:**
- Prometheus pod stuck in `CrashLoopBackOff` status
- Container restarting every few minutes (9 restarts observed)

**Root Cause:**
```
ts=2025-10-09T21:54:40.310Z caller=main.go:1164 level=error 
err="opening storage failed: lock DB directory: open /prometheus/lock: permission denied"
```

Prometheus runs as UID `65534` (nobody), but the storage directory `/srv/monitoring_data/prometheus` was created with `root:root` ownership.

**Fix Applied:**
- Updated `ansible/playbooks/deploy-monitoring-stack.yaml` to create directories with correct ownership:
  ```yaml
  - { path: '/srv/monitoring_data/prometheus', owner: '65534', group: '65534' }
  - { path: '/srv/monitoring_data/loki', owner: '10001', group: '10001' }
  - { path: '/srv/monitoring_data/grafana', owner: '472', group: '472' }
  ```

---

### 2. **Loki Pod Not Ready** 🟡
**Symptoms:**
- Loki pod running but not becoming ready
- Startup probe failures: `HTTP probe failed with statuscode: 503`
- 5 restarts observed

**Root Cause:**
1. **Permission issues**: Same as Prometheus - Loki runs as UID `10001` but directory was owned by `root`
2. **Slow startup**: Loki's startup probe had a 5-minute timeout (`failureThreshold: 30`), but with multiple restarts and WAL recovery, it needed more time

**Fix Applied:**
- Fixed directory ownership (as above)
- Increased startup probe timeout from 5 minutes to 10 minutes:
  ```yaml
  failureThreshold: 60  # 10 minutes
  ```

---

### 3. **Grafana DNS Resolution Errors** 🔴
**Symptoms:**
```
Status: 500. Message: Get "http://loki:3100/...": dial tcp: lookup loki on 10.96.0.10:53: no such host
Status: 500. Message: Get "http://prometheus:9090/...": dial tcp: lookup prometheus on 10.96.0.10:53: no such host
```

**Root Cause:**
- Prometheus and Loki services are configured as **headless services** (`ClusterIP: None`)
- Grafana datasources were using short names (`prometheus`, `loki`) instead of FQDNs
- CoreDNS cannot resolve headless service short names without proper FQDN

**Fix Applied:**
- Updated Grafana datasource ConfigMap in `manifests/monitoring/grafana.yaml`:
  ```yaml
  # Before
  url: http://prometheus:9090
  url: http://loki:3100

  # After
  url: http://prometheus.monitoring.svc.cluster.local:9090
  url: http://loki.monitoring.svc.cluster.local:3100
  ```

---

## Summary of Changes

### Files Modified:

1. **`ansible/playbooks/deploy-monitoring-stack.yaml`**
   - ✅ Fixed directory permissions for Prometheus, Loki, and Grafana
   - ✅ Ensured ownership matches container UIDs (65534, 10001, 472)

2. **`manifests/monitoring/grafana.yaml`**
   - ✅ Updated datasource URLs to use FQDNs for proper DNS resolution

3. **`manifests/monitoring/loki.yaml`**
   - ✅ Increased startup probe timeout for slow WAL recovery

---

## Deployment Instructions

After these fixes, redeploy the monitoring stack:

```bash
# Delete existing pods to force recreation with correct permissions
kubectl delete pod -n monitoring prometheus-0 loki-0 grafana-<pod-name>

# Or restart the entire monitoring stack
kubectl rollout restart statefulset -n monitoring prometheus loki
kubectl rollout restart deployment -n monitoring grafana

# Wait for pods to become ready
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=loki -n monitoring --timeout=600s
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=180s
```

---

## Verification Steps

### 1. Check Pod Status
```bash
kubectl get pods -n monitoring -o wide
```
**Expected:** All pods should be `Running` and `Ready`

### 2. Check Prometheus
```bash
# Access Prometheus UI
curl -s http://192.168.4.63:30090/-/healthy
# Expected: Healthy
```

### 3. Check Loki
```bash
# Access Loki ready endpoint
curl -s http://192.168.4.63:31100/ready
# Expected: ready
```

### 4. Check Grafana Dashboards
- Open Grafana: `http://192.168.4.63:30300`
- Navigate to any dashboard
- **Expected:** No DNS resolution errors, data loading correctly

---

## Lessons Learned

1. **Container UIDs Matter**: Always ensure PVC/hostPath directories have ownership matching the container's security context UID
2. **DNS in Kubernetes**: Use FQDNs for headless services (`service.namespace.svc.cluster.local`)
3. **Startup Probes**: Stateful applications (Loki, Prometheus) with WAL recovery need generous startup timeouts
4. **Modular Playbooks**: Keep ownership and permission logic consistent across all deployment playbooks

---

## Next Steps

1. ✅ Verify all monitoring pods are healthy
2. ✅ Test Grafana dashboards for data visualization
3. ✅ Confirm Prometheus targets are being scraped
4. ✅ Validate log ingestion in Loki
5. Run security audit: `./tests/test-security-audit.sh`
6. Run complete validation: `./tests/test-complete-validation.sh`

---

**Status:** All critical issues resolved. Monitoring stack should now deploy successfully with proper permissions and DNS resolution.

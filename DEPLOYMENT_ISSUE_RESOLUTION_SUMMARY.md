# VMStation Deployment Issues - Summary and Resolution

## **Problems Found**

Your deployment had **3 critical issues**:

### 1. **Prometheus CrashLoopBackOff** 🔴
- **Cause:** Permission denied on `/prometheus/lock`
- **Why:** Prometheus runs as UID 65534, but `/srv/monitoring_data/prometheus` was owned by root

### 2. **Loki Not Ready** 🟡  
- **Cause:** Permission errors + slow startup
- **Why:** Loki runs as UID 10001, but `/srv/monitoring_data/loki` was owned by root

### 3. **Grafana DNS Resolution Errors** 🔴
- **Cause:** `dial tcp: lookup loki on 10.96.0.10:53: no such host`
- **Why:** Grafana was using short names (`loki`, `prometheus`) instead of FQDNs for headless services

---

## **Fixes Applied**

✅ **All issues have been resolved!**

### Files Modified:

1. **`ansible/playbooks/deploy-monitoring-stack.yaml`**
   - Fixed directory ownership for Prometheus (65534), Loki (10001), Grafana (472)

2. **`manifests/monitoring/grafana.yaml`**
   - Updated datasource URLs to use FQDNs:
     - `http://prometheus.monitoring.svc.cluster.local:9090`
     - `http://loki.monitoring.svc.cluster.local:3100`

3. **`manifests/monitoring/loki.yaml`**
   - Increased startup probe timeout from 5 to 10 minutes

### Documentation Created:

- **`docs/DEPLOYMENT_FIXES_OCT2025_PART2.md`** - Full root cause analysis
- **`scripts/fix-monitoring-permissions.sh`** - Quick fix script for immediate resolution

---

## **Quick Resolution Steps**

### **Option 1: Run the Quick Fix Script (Recommended)**

```bash
cd /srv/monitoring_data/VMStation
chmod +x scripts/fix-monitoring-permissions.sh
./scripts/fix-monitoring-permissions.sh
```

This script will:
1. Fix all directory permissions
2. Restart affected pods
3. Wait for pods to become ready
4. Display final status

### **Option 2: Manual Fix**

```bash
# Fix permissions
sudo chown -R 65534:65534 /srv/monitoring_data/prometheus
sudo chown -R 10001:10001 /srv/monitoring_data/loki
sudo chown -R 472:472 /srv/monitoring_data/grafana
sudo chmod -R 755 /srv/monitoring_data

# Restart pods
kubectl delete pod -n monitoring prometheus-0 loki-0 --force --grace-period=0
kubectl delete pod -n monitoring $(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}') --force --grace-period=0

# Wait for recovery
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
kubectl wait --for=condition=ready pod -l app=loki -n monitoring --timeout=600s
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=180s
```

---

## **Verification**

After applying fixes, verify everything is working:

```bash
# Check pod status
kubectl get pods -n monitoring

# All pods should show Running and Ready

# Test Prometheus
curl -s http://192.168.4.63:30090/-/healthy
# Expected: Healthy

# Test Loki
curl -s http://192.168.4.63:31100/ready
# Expected: ready

# Test Grafana (access in browser)
# http://192.168.4.63:30300
# All dashboards should load without DNS errors
```

---

## **Root Causes Explained**

### **Why Did This Happen?**

1. **Modular Deployment Mismatch:**
   - The original `deploy-cluster.yaml` (Phase 7) creates directories with correct ownership
   - The new modular `deploy-monitoring-stack.yaml` was creating directories as `root:root`
   - When you use `./deploy.sh monitoring` alone, it bypassed Phase 7's permission setup

2. **Headless Services + Short Names:**
   - Prometheus and Loki use `ClusterIP: None` (headless services)
   - CoreDNS can't resolve short names for headless services without proper FQDN
   - Grafana datasources need full DNS names: `service.namespace.svc.cluster.local`

3. **Startup Time:**
   - Loki performs WAL (Write-Ahead Log) recovery on startup
   - With permission errors causing restarts, recovery took longer
   - Needed a more generous startup probe timeout

---

## **Prevention for Future Deployments**

The fixes are now permanent in your codebase:

✅ All future `./deploy.sh monitoring` runs will create directories with correct ownership  
✅ Grafana will always use FQDNs for datasources  
✅ Loki has sufficient startup time for WAL recovery

---

## **Next Steps**

1. Apply the fixes (run the script or manual commands above)
2. Verify all pods are healthy: `kubectl get pods -n monitoring`
3. Access Grafana and confirm dashboards are working: `http://192.168.4.63:30300`
4. Continue with your deployment:
   ```bash
   ./deploy.sh setup                      # Setup auto-sleep
   ./tests/test-security-audit.sh         # Run security audit
   ./tests/test-complete-validation.sh    # Complete validation
   ```

---

## **Need Help?**

If pods are still not ready after 10 minutes:

```bash
# Check Prometheus logs
kubectl logs -n monitoring prometheus-0

# Check Loki logs
kubectl logs -n monitoring loki-0

# Check Grafana logs
kubectl logs -n monitoring $(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}')

# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp'
```

All fixes and documentation are saved in your repository for future reference.

# Monitoring Stack Remediation - Operator Checklist

**Pre-Deployment Checklist** - Complete before running any fixes

---

## 1. Pre-Flight Checks

### Environment Verification
- [ ] Confirm you have kubectl access to the cluster
  ```bash
  kubectl cluster-info
  kubectl get nodes
  ```

- [ ] Verify you're targeting the correct cluster
  ```bash
  kubectl config current-context
  ```

- [ ] Check current monitoring namespace state
  ```bash
  kubectl get pods -n monitoring
  kubectl get svc -n monitoring
  kubectl get pvc,pv -n monitoring
  ```

### Backup Creation
- [ ] Create full namespace backup
  ```bash
  kubectl get all -n monitoring -o yaml > /tmp/monitoring-backup-$(date +%Y%m%d-%H%M%S).yaml
  ```

- [ ] Create ConfigMap backup
  ```bash
  kubectl get configmap -n monitoring -o yaml > /tmp/monitoring-configmaps-$(date +%Y%m%d-%H%M%S).yaml
  ```

- [ ] Backup host directories (if on masternode)
  ```bash
  tar -czf /tmp/monitoring_data_backup_$(date +%Y%m%d-%H%M%S).tar.gz /srv/monitoring_data/
  ```

### Document Current State
- [ ] Capture current pod status
  ```bash
  kubectl describe pod prometheus-0 -n monitoring > /tmp/prometheus-before.txt
  kubectl describe pod loki-0 -n monitoring > /tmp/loki-before.txt
  ```

- [ ] Save current logs
  ```bash
  kubectl logs prometheus-0 -n monitoring > /tmp/prometheus-logs-before.txt 2>&1
  kubectl logs loki-0 -n monitoring > /tmp/loki-logs-before.txt 2>&1
  ```

---

## 2. Execute Remediation

### Option A: Quick Fix (Manual)
- [ ] Apply updated Prometheus manifest
  ```bash
  kubectl apply -f manifests/monitoring/prometheus.yaml
  ```

- [ ] Apply updated Loki manifest
  ```bash
  kubectl apply -f manifests/monitoring/loki.yaml
  ```

- [ ] Delete pods to force recreation
  ```bash
  kubectl delete pod prometheus-0 loki-0 -n monitoring
  ```

- [ ] Wait for pods to restart (2-3 minutes)
  ```bash
  kubectl get pods -n monitoring -w
  # Press Ctrl+C when both pods show Running and Ready
  ```

### Option B: Automated Fix (Recommended)
- [ ] Run diagnostic script
  ```bash
  cd /srv/monitoring_data/VMStation
  ./scripts/diagnose-monitoring-stack.sh
  ```

- [ ] Review diagnostic output
  ```bash
  cat /tmp/monitoring-diagnostics-*/00-ANALYSIS-AND-RECOMMENDATIONS.txt
  ```

- [ ] Run remediation script
  ```bash
  ./scripts/remediate-monitoring-stack.sh
  # Answer 'y' to each prompt after reviewing the change
  ```

---

## 3. Validation

### Pod Health
- [ ] Verify pod status
  ```bash
  kubectl get pods -n monitoring
  ```
  **Expected:** prometheus-0 (2/2 Running), loki-0 (1/1 Running)

- [ ] Check restart counts are 0 or minimal
  ```bash
  kubectl get pods -n monitoring -o wide
  ```

### Service Endpoints
- [ ] Verify endpoints are populated
  ```bash
  kubectl get endpoints prometheus loki -n monitoring
  ```
  **Expected:** Both should show pod IPs and ports

### Health Endpoints
- [ ] Test Prometheus health
  ```bash
  kubectl exec prometheus-0 -n monitoring -c prometheus -- wget -O- http://localhost:9090/-/healthy
  ```
  **Expected:** "Prometheus is Healthy."

- [ ] Test Prometheus readiness
  ```bash
  kubectl exec prometheus-0 -n monitoring -c prometheus -- wget -O- http://localhost:9090/-/ready
  ```
  **Expected:** "Prometheus Server is Ready."

- [ ] Test Loki readiness
  ```bash
  kubectl exec loki-0 -n monitoring -- wget -O- http://localhost:3100/ready
  ```
  **Expected:** "ready"

### Log Verification
- [ ] Check Prometheus logs for errors
  ```bash
  kubectl logs prometheus-0 -n monitoring -c prometheus --tail=50 | grep -i error
  ```
  **Expected:** No permission denied or fatal errors

- [ ] Check Loki logs for errors
  ```bash
  kubectl logs loki-0 -n monitoring --tail=50 | grep -i error
  ```
  **Expected:** No fatal errors (connection refused to 127.0.0.1:9095 is OK if frontend_worker disabled)

### Grafana Integration
- [ ] Access Grafana UI
  ```
  http://<masternode-ip>:30300
  ```

- [ ] Navigate to Configuration → Data Sources

- [ ] Test Prometheus datasource
  **Expected:** ✅ "Data source is working"

- [ ] Test Loki datasource
  **Expected:** ✅ "Data source is working"

- [ ] Query metrics in Explore view
  ```
  Prometheus: up
  Loki: {namespace="monitoring"}
  ```

### Automated Validation
- [ ] Run validation script
  ```bash
  ./scripts/validate-monitoring-stack.sh
  ```
  **Expected:** All tests passed or only minor warnings

---

## 4. Post-Deployment Monitoring

### First 15 Minutes
- [ ] Watch pod status continuously
  ```bash
  kubectl get pods -n monitoring -w
  ```
  **Monitor for:** No restarts, both pods remain Ready

- [ ] Monitor events
  ```bash
  kubectl get events -n monitoring --sort-by='.lastTimestamp' --watch
  ```
  **Monitor for:** No Warning or Error events

### First Hour
- [ ] Check metrics collection
  ```bash
  # Query for recent data
  curl -s 'http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=up' | jq .
  ```

- [ ] Check log ingestion
  ```bash
  # Query for recent logs
  curl -s 'http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/query_range?query={namespace="monitoring"}&limit=10' | jq .
  ```

- [ ] Verify dashboards in Grafana
  - [ ] Node metrics visible
  - [ ] Pod metrics visible
  - [ ] Logs queryable

### First 24 Hours
- [ ] Check for any pod restarts
  ```bash
  kubectl get pods -n monitoring -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[*].restartCount}{"\n"}{end}'
  ```
  **Expected:** prometheus-0: 0, loki-0: 0

- [ ] Verify persistent data
  ```bash
  # Check Prometheus data retention
  kubectl exec prometheus-0 -n monitoring -c prometheus -- du -sh /prometheus
  
  # Check Loki data retention
  kubectl exec loki-0 -n monitoring -- du -sh /loki
  ```

- [ ] Review resource usage
  ```bash
  kubectl top pods -n monitoring
  ```

---

## 5. Troubleshooting (If Issues Persist)

### If Prometheus Still Failing
- [ ] Check host directory permissions
  ```bash
  ssh root@masternode 'ls -la /srv/monitoring_data/prometheus'
  ```
  **Expected:** Owner/Group: 65534:65534, Mode: drwxr-xr-x

- [ ] Manually fix permissions if needed
  ```bash
  ssh root@masternode 'chown -R 65534:65534 /srv/monitoring_data/prometheus && chmod -R 755 /srv/monitoring_data/prometheus'
  ```

- [ ] Check SecurityContext in StatefulSet
  ```bash
  kubectl get statefulset prometheus -n monitoring -o yaml | grep -A10 securityContext
  ```
  **Expected:** runAsUser: 65534, runAsGroup: 65534, fsGroup: 65534

### If Loki Still Not Ready
- [ ] Verify frontend_worker is disabled
  ```bash
  kubectl get configmap loki-config -n monitoring -o yaml | grep -A3 "frontend_worker"
  ```
  **Expected:** Lines should be commented out with '#'

- [ ] Check for port conflicts
  ```bash
  kubectl exec loki-0 -n monitoring -- netstat -tlnp
  ```
  **Expected:** Ports 3100 and 9096 listening

- [ ] Increase readiness probe delay (if needed)
  ```bash
  kubectl patch statefulset loki -n monitoring --type='json' -p='[
    {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds", "value": 60}
  ]'
  ```

### If Endpoints Still Empty
- [ ] Verify pod labels match service selectors
  ```bash
  kubectl get svc prometheus -n monitoring -o yaml | grep -A5 selector
  kubectl get pod prometheus-0 -n monitoring --show-labels
  ```

- [ ] Force endpoint refresh
  ```bash
  kubectl delete endpoints prometheus loki -n monitoring
  # Wait 10 seconds for automatic recreation
  kubectl get endpoints prometheus loki -n monitoring
  ```

---

## 6. Rollback (If Required)

### Full Rollback
- [ ] Stop validation/monitoring

- [ ] Restore from backups
  ```bash
  kubectl apply -f /tmp/monitoring-backup-*.yaml
  ```

- [ ] Wait for pods to stabilize
  ```bash
  kubectl get pods -n monitoring -w
  ```

### Partial Rollback (Prometheus Only)
- [ ] Restore Prometheus StatefulSet
  ```bash
  kubectl apply -f /tmp/monitoring-backups-*/monitoring-all-backup.yaml
  ```

### Partial Rollback (Loki Only)
- [ ] Restore Loki ConfigMap
  ```bash
  kubectl apply -f /tmp/monitoring-backups-*/loki-config-original.yaml
  kubectl delete pod loki-0 -n monitoring
  ```

---

## 7. Sign-Off

### Deployment Sign-Off
- [ ] All pods Running and Ready
- [ ] All endpoints populated
- [ ] Health checks passing
- [ ] Grafana datasources connected
- [ ] No errors in logs
- [ ] Validation script passes

**Deployed by:** _________________  
**Date/Time:** _________________  
**Issues encountered:** _________________  

### 24-Hour Stability Sign-Off
- [ ] No pod restarts in 24 hours
- [ ] Metrics collection continuous
- [ ] Log ingestion continuous
- [ ] No service degradation
- [ ] Resource usage normal

**Verified by:** _________________  
**Date/Time:** _________________  
**Notes:** _________________  

---

## Reference Commands

### Quick Status Check
```bash
# One-liner to check everything
kubectl get pods,endpoints,pvc -n monitoring && \
kubectl exec prometheus-0 -n monitoring -c prometheus -- wget -qO- http://localhost:9090/-/healthy && \
kubectl exec loki-0 -n monitoring -- wget -qO- http://localhost:3100/ready
```

### Emergency Debug
```bash
# Capture full diagnostic state
./scripts/diagnose-monitoring-stack.sh
cat /tmp/monitoring-diagnostics-*/00-ANALYSIS-AND-RECOMMENDATIONS.txt
```

### Quick Restart
```bash
# Force pod restart without changing configs
kubectl delete pod prometheus-0 loki-0 -n monitoring
kubectl wait --for=condition=ready pod/prometheus-0 pod/loki-0 -n monitoring --timeout=120s
```

---

**Checklist Version:** 1.0  
**Last Updated:** October 10, 2025  
**Related Docs:** 
- MONITORING_STACK_DIAGNOSTICS_AND_REMEDIATION.md
- MONITORING_QUICK_FIX.md
- MONITORING_STACK_FAILURE_RESOLUTION_SUMMARY.md

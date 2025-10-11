# Quick Deployment Guide - Monitoring Stack Fixes

## Overview

This guide provides step-by-step instructions to deploy the monitoring stack fixes for:
- Grafana syslog dashboard templating error
- Loki syslog JSON parse error handling
- Prometheus TSDB corruption recovery documentation

## Prerequisites

- `kubectl` access to the monitoring namespace
- Ability to apply Kubernetes manifests
- Grafana admin access (for verification)

## Deployment Steps

### 1. Apply Grafana ConfigMap Update

```bash
# Navigate to repository root
cd /home/runner/work/VMStation/VMStation

# Apply the updated ConfigMap
kubectl apply -f manifests/monitoring/grafana.yaml
```

**Expected Output:**
```
configmap/grafana-datasources unchanged
configmap/grafana-dashboard-providers unchanged
configmap/grafana-dashboards configured
```

### 2. Restart Grafana Pod

```bash
# Delete Grafana pod to reload dashboards
kubectl delete pod -n monitoring -l app=grafana

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=60s
```

**Expected Output:**
```
pod "grafana-..." deleted
pod/grafana-... condition met
```

### 3. Verify Grafana Dashboard

**Option A: Port Forward (Local Access)**
```bash
# Forward Grafana port to localhost
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Open in browser: http://localhost:3000
# Default credentials: admin/admin (change on first login)
```

**Option B: NodePort (Network Access)**
```bash
# Get NodePort
kubectl get svc -n monitoring grafana -o jsonpath='{.spec.ports[0].nodePort}'

# Access Grafana at: http://<node-ip>:<nodeport>
```

**Verification Steps:**
1. Navigate to **Dashboards** → **Browse**
2. Open **"Syslog Infrastructure Monitoring"**
3. Check browser console (F12) for JavaScript errors
4. Verify no templating error appears
5. Confirm dashboard panels load correctly

### 4. Check Pod Status

```bash
# Verify all monitoring pods are running
kubectl get pods -n monitoring

# Check Grafana logs for errors
kubectl logs -n monitoring -l app=grafana --tail=50 | grep -i error
```

**Expected Output:**
```
NAME                      READY   STATUS    RESTARTS   AGE
grafana-...               1/1     Running   0          1m
loki-0                    1/1     Running   0          ...
prometheus-0              2/2     Running   0          ...
```

## Verification Checklist

- [ ] ConfigMap applied successfully
- [ ] Grafana pod restarted
- [ ] Grafana pod is Running (1/1)
- [ ] Syslog dashboard loads without errors
- [ ] No JavaScript console errors
- [ ] Dashboard panels display data (or "No data" message)
- [ ] Template variables dropdown works (empty list is OK)

## Rollback (If Needed)

```bash
# Rollback ConfigMap to previous version
kubectl rollout undo -n monitoring configmap/grafana-dashboards

# Restart Grafana
kubectl delete pod -n monitoring -l app=grafana
```

## Common Issues

### Dashboard Still Shows Error

**Problem:** Templating error persists after restart

**Solution:**
```bash
# Force ConfigMap reload
kubectl delete cm -n monitoring grafana-dashboards
kubectl apply -f manifests/monitoring/grafana.yaml
kubectl delete pod -n monitoring -l app=grafana

# Clear browser cache
# Hard refresh: Ctrl+Shift+R (Chrome/Firefox)
```

### Pod Not Starting

**Problem:** Grafana pod stuck in CrashLoopBackOff

**Solution:**
```bash
# Check pod logs
kubectl logs -n monitoring -l app=grafana

# Check ConfigMap syntax
kubectl get cm -n monitoring grafana-dashboards -o yaml | grep -A10 "syslog-dashboard"

# Verify JSON is valid
kubectl get cm -n monitoring grafana-dashboards -o json | jq '.data["syslog-dashboard.json"]' | jq .
```

### Dashboard Shows "No Data"

**Problem:** Panels show "No data" instead of metrics/logs

**This is NOT related to the templating fix.** Possible causes:
1. Datasources not configured (check Grafana → Configuration → Data Sources)
2. Prometheus/Loki not running or not ready
3. No actual data in time range (extend time range to 24h)
4. Metrics/logs not being collected (check scrape configs)

**Troubleshooting:**
```bash
# Check datasources
kubectl get svc -n monitoring prometheus loki

# Test Prometheus
kubectl exec -n monitoring prometheus-0 -- wget -qO- http://localhost:9090/-/ready

# Test Loki
kubectl exec -n monitoring loki-0 -- wget -qO- http://localhost:3100/ready

# See full troubleshooting guide
cat docs/MONITORING_STACK_TROUBLESHOOTING.md
```

## Additional Resources

- **Troubleshooting Guide:** `docs/MONITORING_STACK_TROUBLESHOOTING.md`
- **Resolution Summary:** `MONITORING_ISSUES_RESOLUTION.md`
- **Dashboard Files:** `ansible/files/grafana_dashboards/`
- **Monitoring Manifests:** `manifests/monitoring/`

## Support

For issues not covered in this guide:
1. Check `docs/MONITORING_STACK_TROUBLESHOOTING.md`
2. Review Grafana/Prometheus/Loki pod logs
3. Run diagnostic script: `./scripts/diagnose-monitoring-stack.sh`
4. Run remediation script: `./scripts/remediate-monitoring-stack.sh`

---

**Last Updated:** 2025-10-11  
**Version:** 1.0

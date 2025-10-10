# Monitoring Stack Failure Diagnostics and Remediation

**Date:** October 10, 2025  
**Purpose:** Diagnose and fix Prometheus and Loki failures in the VMStation monitoring stack  
**Status:** Production-ready automated remediation

---

## Executive Summary

This document provides comprehensive diagnostics and automated remediation for monitoring stack failures observed in the VMStation homelab cluster.

### Issues Identified

1. **Prometheus** - CrashLoopBackOff due to permission denied errors
2. **Loki** - Running but not Ready due to frontend_worker connection errors
3. **Service Endpoints** - Empty due to pods not being Ready

### Impact

- ❌ Prometheus metrics collection stopped
- ❌ Loki log aggregation not accessible
- ❌ Grafana unable to query Prometheus and Loki datasources
- ⚠️ All other monitoring components (Grafana, node-exporter, promtail, etc.) working correctly

---

## Quick Start

### Prerequisites

- Access to the Kubernetes cluster (kubectl configured)
- Access to the masternode (for host-level fixes if needed)
- Backup of current state (recommended)

### Automated Remediation (Recommended)

Run these scripts in order:

```bash
# Step 1: Diagnose the current state
./scripts/diagnose-monitoring-stack.sh

# Step 2: Review the analysis
cat /tmp/monitoring-diagnostics-*/00-ANALYSIS-AND-RECOMMENDATIONS.txt

# Step 3: Apply automated fixes
./scripts/remediate-monitoring-stack.sh

# Step 4: Validate the fixes
./scripts/validate-monitoring-stack.sh
```

**Estimated time:** 20-30 minutes (including waiting for pod restarts)

---

## Detailed Issue Analysis

### Issue 1: Prometheus CrashLoopBackOff

**Symptom:**
```
prometheus-0   1/2   CrashLoopBackOff   9 (2m5s ago)   24m
```

**Error in logs:**
```
ts=2025-10-09T21:54:40.310Z caller=main.go:1164 level=error 
err="opening storage failed: lock DB directory: open /prometheus/lock: permission denied"
```

**Root Cause:**

The Prometheus container runs without an explicit SecurityContext specifying the user/group. Even though the init container (`init-chown-data`) successfully sets ownership to `65534:65534`, the main container may be running as a different user or the fsGroup is not set, causing permission conflicts.

**Fix Applied:**

Add explicit SecurityContext to the Prometheus StatefulSet:

```yaml
securityContext:
  fsGroup: 65534        # nobody group
  runAsUser: 65534      # nobody user
  runAsGroup: 65534     # nobody group
  runAsNonRoot: true
```

This ensures the container process runs as UID 65534 and all volume-mounted files are accessible with the correct group ownership.

---

### Issue 2: Loki Running but Not Ready

**Symptom:**
```
loki-0   0/1   Running   4 (4m11s ago)   24m
```

**Errors in logs:**
```json
{"address":"127.0.0.1:9095","caller":"frontend_processor.go:63",
 "err":"rpc error: code = Unavailable desc = connection error: 
 desc = \"transport: Error while dialing: dial tcp 127.0.0.1:9095: connect: connection refused\"",
 "level":"error","msg":"error contacting frontend"}
```

**Root Cause:**

Loki is configured to run in all-in-one mode (`-target=all`) with the `frontend_worker` component enabled. The configuration includes:

```yaml
frontend_worker:
  frontend_address: 127.0.0.1:9095
  parallelism: 10
```

In all-in-one mode, the querier workers try to connect to the query-frontend on port 9095 before the frontend is fully initialized, causing "connection refused" errors. While Loki eventually starts successfully, the readiness probe fails because it waits for all components (including frontend workers) to be healthy.

**Fix Applied:**

Disable the `frontend_worker` configuration in the Loki ConfigMap:

```yaml
# Frontend worker - DISABLED for single-instance deployment
# Uncommenting this can cause "connection refused" errors in all-in-one mode
# frontend_worker:
#   frontend_address: 127.0.0.1:9095
#   parallelism: 10
```

The frontend_worker is not necessary for single-instance deployments and removing it eliminates the startup race condition. Loki will continue to function normally for log ingestion and querying.

---

### Issue 3: Empty Service Endpoints

**Symptom:**
```
prometheus.monitoring.svc.cluster.local   ClusterIP   None    <none>   9090/TCP   24m
loki.monitoring.svc.cluster.local        ClusterIP   None    <none>   3100/TCP   24m
```

Both services show empty endpoint lists when queried:

```bash
kubectl get endpoints prometheus loki -n monitoring
NAME         ENDPOINTS   AGE
prometheus   <none>      24m
loki         <none>      24m
```

**Root Cause:**

Kubernetes only adds pods to service endpoints when they are in the `Ready` state. Since:
- `prometheus-0` is in CrashLoopBackOff (not Ready)
- `loki-0` is Running but not Ready (readiness probe failing)

No endpoints are created, causing DNS resolution to fail in Grafana and other clients.

**Fix:**

This is automatically resolved once Issues 1 and 2 are fixed. After the pods become Ready, the endpoints will be populated within seconds.

---

## Scripts Overview

### 1. diagnose-monitoring-stack.sh

**Purpose:** Comprehensive diagnostics collection

**What it does:**
- Gathers pod status, logs, and events
- Collects ConfigMaps and StatefulSet configurations
- Checks PVC/PV bindings
- Tests readiness probes
- Analyzes host directory permissions
- Generates detailed analysis and recommendations

**Output:** Creates a timestamped directory in `/tmp/monitoring-diagnostics-*` with all diagnostic files

**Usage:**
```bash
./scripts/diagnose-monitoring-stack.sh
```

**Output files:**
- `00-ANALYSIS-AND-RECOMMENDATIONS.txt` - **START HERE**
- `06-prometheus-logs.txt` - Prometheus container logs
- `10-loki-logs.txt` - Loki container logs
- `18-host-permissions.txt` - Host directory permissions
- Plus 15+ other diagnostic files

---

### 2. remediate-monitoring-stack.sh

**Purpose:** Automated, safe remediation

**What it does:**
- Creates backups of all configurations
- Patches Prometheus StatefulSet with SecurityContext
- Updates Loki ConfigMap to disable frontend_worker
- Optionally fixes host directory permissions
- Restarts affected pods
- Waits for pods to become Ready
- Validates the changes

**Safety features:**
- Interactive confirmation for each step
- Full backups before any changes
- Non-destructive changes only
- Rollback instructions provided

**Usage:**
```bash
./scripts/remediate-monitoring-stack.sh
```

**Backups created in:** `/tmp/monitoring-backups-<timestamp>/`

---

### 3. validate-monitoring-stack.sh

**Purpose:** Comprehensive validation testing

**What it does:**
- Tests pod status and readiness
- Validates service endpoints
- Checks PVC/PV bindings
- Tests health endpoints (HTTP)
- Validates DNS resolution
- Analyzes restart counts
- Scans logs for errors

**Usage:**
```bash
./scripts/validate-monitoring-stack.sh
```

**Exit codes:**
- `0` - All tests passed or only warnings
- `1` - One or more tests failed

---

## Manual Remediation Steps

If you prefer to apply fixes manually or the automated script fails:

### Fix 1: Prometheus SecurityContext

```bash
# Backup current StatefulSet
kubectl get statefulset prometheus -n monitoring -o yaml > /tmp/prometheus-statefulset-backup.yaml

# Patch the StatefulSet
kubectl patch statefulset prometheus -n monitoring --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/securityContext",
    "value": {
      "fsGroup": 65534,
      "runAsUser": 65534,
      "runAsGroup": 65534,
      "runAsNonRoot": true
    }
  }
]'

# Delete the pod to apply changes
kubectl delete pod prometheus-0 -n monitoring --wait

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/prometheus-0 -n monitoring --timeout=120s
```

### Fix 2: Loki Frontend Worker

```bash
# Backup current ConfigMap
kubectl get configmap loki-config -n monitoring -o yaml > /tmp/loki-config-backup.yaml

# Edit the ConfigMap
kubectl edit configmap loki-config -n monitoring

# Find and comment out or remove these lines:
#   frontend_worker:
#     frontend_address: 127.0.0.1:9095
#     parallelism: 10

# Or apply the patched version from manifests/monitoring/loki.yaml

# Delete the pod to reload config
kubectl delete pod loki-0 -n monitoring --wait

# Wait for pod to be ready
kubectl wait --for=condition=ready pod/loki-0 -n monitoring --timeout=120s
```

### Fix 3: Host Directory Permissions (if needed)

```bash
# SSH to masternode
ssh root@masternode

# Fix ownership
chown -R 65534:65534 /srv/monitoring_data/prometheus
chown -R 10001:10001 /srv/monitoring_data/loki
chown -R 472:472 /srv/monitoring_data/grafana
chmod -R 755 /srv/monitoring_data

# Verify
ls -la /srv/monitoring_data
```

---

## Validation Checklist

After applying fixes, verify:

### ✅ Pod Status
```bash
kubectl get pods -n monitoring
```

**Expected:**
```
NAME                                  READY   STATUS    RESTARTS   AGE
prometheus-0                          2/2     Running   0          5m
loki-0                                1/1     Running   0          5m
grafana-5f879c7654-dnmhs              1/1     Running   0          30m
```

### ✅ Service Endpoints
```bash
kubectl get endpoints prometheus loki -n monitoring
```

**Expected:**
```
NAME         ENDPOINTS                     AGE
prometheus   10.244.0.228:9090             30m
loki         10.244.0.225:3100,10.244.0.225:9096   30m
```

### ✅ Health Checks
```bash
# Prometheus health
kubectl exec -n monitoring prometheus-0 -c prometheus -- wget -O- http://localhost:9090/-/healthy

# Loki ready
kubectl exec -n monitoring loki-0 -- wget -O- http://localhost:3100/ready
```

**Expected:**
```
Prometheus is Healthy.
ready
```

### ✅ Grafana Datasources

1. Access Grafana: `http://<masternode-ip>:30300`
2. Go to: Configuration → Data Sources
3. Check both Prometheus and Loki datasources
4. Both should show: "Data source is working"

### ✅ Metrics and Logs

**Test Prometheus:**
```bash
# Query 'up' metric
curl -s 'http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=up' | jq .
```

**Test Loki:**
```bash
# Query recent logs
curl -s 'http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/query_range?query={namespace="monitoring"}&limit=10' | jq .
```

---

## Troubleshooting

### Pods Still Not Ready After Fixes

1. **Check pod events:**
   ```bash
   kubectl describe pod prometheus-0 -n monitoring
   kubectl describe pod loki-0 -n monitoring
   ```

2. **Check logs:**
   ```bash
   kubectl logs prometheus-0 -n monitoring -c prometheus --tail=100
   kubectl logs loki-0 -n monitoring --tail=100
   ```

3. **Verify host permissions:**
   ```bash
   ssh root@masternode 'ls -la /srv/monitoring_data/'
   ```

### Endpoints Still Empty

1. **Verify pods are Ready:**
   ```bash
   kubectl get pods -n monitoring -o wide
   ```

2. **Check service selectors match pod labels:**
   ```bash
   kubectl get svc prometheus -n monitoring -o yaml | grep -A5 selector
   kubectl get pod prometheus-0 -n monitoring --show-labels
   ```

### Grafana Still Shows "No Such Host"

1. **Wait 30-60 seconds** for DNS cache to clear
2. **Restart Grafana pod:**
   ```bash
   kubectl delete pod -n monitoring -l app=grafana
   ```
3. **Test DNS from Grafana pod:**
   ```bash
   kubectl exec -n monitoring -l app=grafana -- nslookup prometheus.monitoring.svc.cluster.local
   ```

---

## Rollback Procedures

If the fixes cause issues:

### Rollback Prometheus

```bash
# Restore from backup
kubectl apply -f /tmp/monitoring-backups-*/monitoring-all-backup.yaml

# Or remove the SecurityContext patch
kubectl patch statefulset prometheus -n monitoring --type='json' -p='[
  {
    "op": "remove",
    "path": "/spec/template/spec/securityContext"
  }
]'
```

### Rollback Loki

```bash
# Restore from backup
kubectl apply -f /tmp/monitoring-backups-*/loki-config-original.yaml

# Restart pod
kubectl delete pod loki-0 -n monitoring
```

---

## Prevention and Best Practices

### 1. Always Set SecurityContext

For all StatefulSets with persistent volumes, explicitly set:
```yaml
securityContext:
  fsGroup: <expected-gid>
  runAsUser: <expected-uid>
  runAsGroup: <expected-gid>
  runAsNonRoot: true
```

### 2. Pre-create Directories with Correct Ownership

Before deploying StatefulSets:
```bash
ssh root@masternode '
  mkdir -p /srv/monitoring_data/{prometheus,loki,grafana}
  chown 65534:65534 /srv/monitoring_data/prometheus
  chown 10001:10001 /srv/monitoring_data/loki
  chown 472:472 /srv/monitoring_data/grafana
  chmod -R 755 /srv/monitoring_data
'
```

### 3. Disable Unnecessary Features in Single-Instance Deployments

For Loki, Prometheus, and similar applications running in all-in-one mode:
- Disable multi-tenancy features
- Disable query-frontend workers (unless using microservices mode)
- Simplify ring/memberlist configurations

### 4. Use Adequate Readiness Probe Delays

For complex applications with multiple components:
```yaml
readinessProbe:
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3
```

### 5. Monitor and Alert on Endpoint Status

Set up alerts when service endpoints become empty:
```prometheus
absent(kube_endpoint_address_available{namespace="monitoring",endpoint="prometheus"}) == 1
```

---

## Related Documentation

- `docs/HEADLESS_SERVICE_ENDPOINTS_TROUBLESHOOTING.md` - General endpoint troubleshooting
- `scripts/fix-monitoring-permissions.sh` - Legacy permission fix script
- `CRASHLOOPBACKOFF_FIXES_VERIFIED.md` - Previous CrashLoopBackOff fixes
- `VALIDATION_SUMMARY.md` - Manifest validation summary

---

## References

### Prometheus
- SecurityContext: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/
- Prometheus Storage: https://prometheus.io/docs/prometheus/latest/storage/

### Loki
- Deployment modes: https://grafana.com/docs/loki/latest/fundamentals/architecture/deployment-modes/
- Configuration: https://grafana.com/docs/loki/latest/configuration/

### Kubernetes
- Endpoints: https://kubernetes.io/docs/concepts/services-networking/service/#endpoints
- StatefulSets: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/

---

## Change Log

**2025-10-10**
- Created comprehensive diagnostic, remediation, and validation scripts
- Identified and documented Prometheus SecurityContext issue
- Identified and documented Loki frontend_worker issue
- Automated all fixes with safety checks and backups

---

## Support

For issues or questions:
1. Run diagnostic script: `./scripts/diagnose-monitoring-stack.sh`
2. Review analysis: `cat /tmp/monitoring-diagnostics-*/00-ANALYSIS-AND-RECOMMENDATIONS.txt`
3. Check logs: `kubectl logs -n monitoring <pod-name>`
4. Review events: `kubectl get events -n monitoring --sort-by='.lastTimestamp'`

---

**End of Document**

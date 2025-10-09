# Blackbox Exporter & Monitoring Stack Diagnostic Report

## Short Diagnosis

**Blackbox Exporter**: Config parsing error - `timeout` field incorrectly nested within DNS prober section instead of at module level.

**Loki**: Schema validation error - `boltdb-shipper` requires 24h index period, but 168h was configured.

**Jellyfin**: Scheduling blocked - `storagenodet3500` node was in unschedulable state, preventing pod placement.

## Root Cause Checklist

- [ ] **Scheduling** - Jellyfin affected (storagenodet3500 unschedulable)
- [ ] **Image Pull** - Not applicable (images pulled successfully)
- [x] **Readiness** - Blackbox & Loki couldn't start, so readiness probes failed
- [ ] **Capability** - Not applicable (NET_RAW capability properly configured)
- [x] **Other - Configuration Errors**:
  - Blackbox: Invalid YAML structure for blackbox_exporter v0.25.0
  - Loki: Incompatible schema_config period for boltdb-shipper

## Diagnostic Commands & Outputs

### 1. Get Pods Status
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods -o wide
```

**Expected Output (from error log):**
```
NAME                                      READY   STATUS             RESTARTS         AGE
pod/blackbox-exporter-5949885fb9-8mkls    0/1     CrashLoopBackOff   11 (2m28s ago)   33m
pod/loki-74577b9557-s5pg6                 0/1     CrashLoopBackOff   11 (2m27s ago)   33m
pod/grafana-5f879c7654-c6rv4              1/1     Running            0                33m
pod/prometheus-5d89d5fc7f-grlqx           1/1     Running            0                33m
```

### 2. Describe Blackbox Deployment
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring describe deployment blackbox-exporter
```

**Key Finding**: Pod scheduled correctly on control-plane node but container crashes on startup.

### 3. Blackbox Exporter Logs
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring logs deployment/blackbox-exporter --tail=200
```

**Key Error**:
```
Error loading config
error parsing config file: yaml: unmarshal errors:
  line 15: field timeout not found in type config.plain
```

**Root Cause**: In blackbox_exporter v0.25.0, the `timeout` field must be at the module level, not nested within prober-specific sections like `dns:`.

### 4. Loki Logs
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring logs deployment/loki --tail=200
```

**Key Error**:
```
validating config
invalid schema config: boltdb-shipper works best with 24h periodic index config.
Either add a new config with future date set to 24h ... or change the existing config to use 24h period
```

**Root Cause**: Loki schema_config had `period: 168h` (7 days) but boltdb-shipper storage backend requires `period: 24h`.

### 5. Jellyfin Status
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n jellyfin get pod jellyfin -o yaml
```

**Key Finding**: Pod in Pending state with event:
```
0/2 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }, 
1 node(s) were unschedulable.
```

**Root Cause**: Jellyfin has `nodeSelector: kubernetes.io/hostname=storagenodet3500` but that node was marked as unschedulable.

### 6. Node Status
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide
```

**Expected Output**:
```
NAME               STATUS   ROLES           AGE   VERSION
masternode         Ready    control-plane   36s   v1.29.15
storagenodet3500   Ready    <none>          12s   v1.29.15
```

**Issue**: Node shows Ready but may have SchedulingDisabled status (requires `kubectl describe node`).

## Remediation Options

### Option A (Fast, Low-Risk): Apply Fixed Manifests

**Commands**:
```bash
# Apply the fixed blackbox-exporter config
kubectl --kubeconfig=/etc/kubernetes/admin.conf delete configmap blackbox-exporter-config -n monitoring
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/prometheus.yaml

# Apply the fixed Loki config
kubectl --kubeconfig=/etc/kubernetes/admin.conf delete configmap loki-config -n monitoring
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/loki.yaml

# Ensure all nodes are schedulable
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --no-headers | awk '{print $1}' | xargs -n1 kubectl --kubeconfig=/etc/kubernetes/admin.conf uncordon

# Restart deployments to pick up new configs
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/blackbox-exporter -n monitoring
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/loki -n monitoring
```

**Risk**: Low - Only restarts affected pods with corrected configs. No data loss.

**Rollback**:
```bash
# Revert to previous config if needed
git checkout HEAD~1 -- manifests/monitoring/prometheus.yaml manifests/monitoring/loki.yaml
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/prometheus.yaml
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/loki.yaml
```

### Option B (Manifest Changes): Manual Patch via kubectl

**Blackbox Exporter Config Patch**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf patch configmap blackbox-exporter-config -n monitoring --type merge -p '
{
  "data": {
    "blackbox.yml": "modules:\n  http_2xx:\n    prober: http\n    timeout: 5s\n    http:\n      preferred_ip_protocol: ip4\n  icmp:\n    prober: icmp\n    timeout: 5s\n  dns:\n    prober: dns\n    timeout: 5s\n    dns:\n      query_name: kubernetes.default.svc.cluster.local\n      query_type: A\n"
  }
}
'
```

**Loki Config Patch**:
```bash
# Edit the ConfigMap directly
kubectl --kubeconfig=/etc/kubernetes/admin.conf edit configmap loki-config -n monitoring

# Change line with "period: 168h" to "period: 24h" in schema_config section
```

**Node Scheduling Fix**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf uncordon storagenodet3500
```

**Risk**: Moderate - Manual editing can introduce typos. Config changes require pod restart.

**Rollback**: Same as Option A.

## Exact Changes Applied

### manifests/monitoring/prometheus.yaml
```diff
--- a/manifests/monitoring/prometheus.yaml
+++ b/manifests/monitoring/prometheus.yaml
@@ -526,10 +526,10 @@ data:
         timeout: 5s
       dns:
         prober: dns
+        timeout: 5s
         dns:
           query_name: kubernetes.default.svc.cluster.local
           query_type: A
-          timeout: 5s
```

**Rationale**: Moved `timeout` field from nested `dns:` section to module level for compliance with blackbox_exporter v0.25.0 config schema.

### manifests/monitoring/loki.yaml
```diff
--- a/manifests/monitoring/loki.yaml
+++ b/manifests/monitoring/loki.yaml
@@ -46,7 +46,7 @@ data:
         schema: v11
         index:
           prefix: index_
-          period: 168h
+          period: 24h
```

**Rationale**: Changed index period to 24h as required by boltdb-shipper storage backend for optimal performance and compatibility.

### ansible/playbooks/deploy-cluster.yaml
```diff
--- a/ansible/playbooks/deploy-cluster.yaml
+++ b/ansible/playbooks/deploy-cluster.yaml
@@ -422,6 +422,12 @@ tasks:
       delay: 10
       until: ready_nodes.stdout | int >= 2
 
+    - name: "Ensure all nodes are schedulable (uncordon)"
+      shell: |
+        kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --no-headers | awk '{print $1}' | xargs -n1 kubectl --kubeconfig=/etc/kubernetes/admin.conf uncordon
+      register: uncordon_result
+      failed_when: false
+
     - name: "Get node status"
       shell: kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide
       register: nodes_status
```

**Rationale**: Added explicit uncordon task to ensure all nodes (especially storagenodet3500) are schedulable before deploying applications.

## Verification Commands

After applying fixes, run these commands to verify:

```bash
# 1. Wait for deployments to be available
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring wait --for=condition=available deployment/blackbox-exporter --timeout=300s
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring wait --for=condition=available deployment/loki --timeout=300s

# 2. Check pod status
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods -l app=blackbox-exporter -o wide
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods -l app=loki -o wide

# 3. Check logs (should show no errors)
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring logs deployment/blackbox-exporter --tail=200
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring logs deployment/loki --tail=200

# 4. Test endpoints
# Get the node IP (masternode)
NODE_IP=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes masternode -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

# Test blackbox-exporter metrics endpoint
curl -I http://${NODE_IP}:9115/metrics

# Or exec into pod and test locally
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring exec -it deployment/blackbox-exporter -- curl -sS -I http://127.0.0.1:9115/metrics

# Test Loki ready endpoint
curl http://${NODE_IP}:31100/ready

# 5. Check Jellyfin scheduling
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n jellyfin get pods -o wide
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n jellyfin wait --for=condition=ready pod/jellyfin --timeout=600s

# 6. Verify node schedulability
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
# All nodes should show "Ready" status with no "SchedulingDisabled"
```

## Expected Results After Fix

### Blackbox Exporter
- **Status**: Running
- **Logs**: "Server is ready to receive web requests" or similar
- **Metrics Endpoint**: Returns HTTP 200 with Prometheus metrics
- **Restarts**: 0

### Loki
- **Status**: Running
- **Logs**: "Loki started" or "module server running"
- **Ready Endpoint**: Returns HTTP 200
- **Restarts**: 0

### Jellyfin
- **Status**: Running on storagenodet3500
- **Node**: Scheduled on storagenodet3500
- **Service**: Accessible at http://192.168.4.61:30096

### Monitoring Stack Overall
```
NAME                                   READY   STATUS    RESTARTS   AGE   NODE
blackbox-exporter-xxxxxxxxx-xxxxx      1/1     Running   0          5m    masternode
grafana-xxxxxxxxx-xxxxx                1/1     Running   0          33m   masternode
kube-state-metrics-xxxxxxxxx-xxxxx     1/1     Running   0          33m   masternode
loki-xxxxxxxxx-xxxxx                   1/1     Running   0          5m    masternode
node-exporter-xxxxx                    1/1     Running   0          33m   masternode
node-exporter-xxxxx                    1/1     Running   0          33m   storagenodet3500
prometheus-xxxxxxxxx-xxxxx             1/1     Running   0          33m   masternode
promtail-xxxxx                         1/1     Running   0          33m   masternode
promtail-xxxxx                         1/1     Running   0          33m   storagenodet3500
```

## Risk Assessment & Rollback

### Option A Risk Assessment
- **Downtime**: ~2-5 minutes while pods restart
- **Data Loss**: None (Loki data persisted on PVC, Prometheus has local storage)
- **Impact**: Temporary monitoring gap during restart
- **Safety**: High - automated rollout, Kubernetes handles graceful shutdown

### Option B Risk Assessment
- **Downtime**: ~2-5 minutes while pods restart
- **Data Loss**: None
- **Impact**: Same as Option A, but manual editing increases risk of typos
- **Safety**: Moderate - requires careful manual editing

### Rollback Steps (Both Options)
1. **Immediate rollback** (if pods fail to start):
   ```bash
   # Restore previous configs
   git checkout HEAD~1 -- manifests/monitoring/prometheus.yaml manifests/monitoring/loki.yaml
   kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/prometheus.yaml
   kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/loki.yaml
   kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/blackbox-exporter -n monitoring
   kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/loki -n monitoring
   ```

2. **Monitor rollback**:
   ```bash
   kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods -w
   ```

3. **Verify services**:
   ```bash
   kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get svc
   curl http://192.168.4.63:30300  # Grafana
   curl http://192.168.4.63:30090  # Prometheus
   ```

## Additional Troubleshooting

If issues persist after fixes:

1. **Check for pending PVCs**:
   ```bash
   kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pvc
   ```

2. **Verify storage directories exist**:
   ```bash
   ls -la /srv/monitoring_data/
   ls -la /srv/monitoring_data/loki/
   ```

3. **Check node taints** (in case control-plane taint blocks scheduling):
   ```bash
   kubectl --kubeconfig=/etc/kubernetes/admin.conf describe nodes | grep -A5 Taints
   ```

4. **Review all events**:
   ```bash
   kubectl --kubeconfig=/etc/kubernetes/admin.conf get events -n monitoring --sort-by='.lastTimestamp'
   kubectl --kubeconfig=/etc/kubernetes/admin.conf get events -n jellyfin --sort-by='.lastTimestamp'
   ```

## Future Enhancements (Mentioned in Problem Statement)

The following enhancements are noted for future implementation:

1. **Enhanced Grafana Dashboards**: Network/security analyst-grade monitoring with detailed blackbox-exporter metrics
2. **Homelab RKE2 Scraping**: Configure Prometheus federation for the separate RKE2 cluster
3. **Syslog Server**: Deploy syslog-ng or rsyslog as DaemonSet to ingest logs from network devices
4. **Syslog Grafana Dashboard**: Visualization for syslog data with filtering, alerting, and trend analysis
5. **Dashboard Organization**: Split dashboards into user-friendly categories (Infrastructure, Applications, Security, Network)
6. **Loki Connection Fix**: Resolve 502 errors and connection refused issues with Loki ingestion
7. **Syslog Exporters**: Configure for Cisco Catalyst 3650, RHEL 10, and Debian nodes
8. **Simplified Dashboard Names**: Use clear, non-technical names for better UX

These enhancements require additional manifests and configuration files and are beyond the scope of the immediate CrashLoopBackOff fixes.

# PersistentVolume Claims Fix - October 2025

## Problem Summary

Multiple pods were stuck in `Pending` state due to unbound PersistentVolumeClaims (PVCs):
- `prometheus-0`: Pending due to unbound PVC `prometheus-storage-prometheus-0`
- `loki-0`: Pending due to unbound PVC `loki-data-loki-0`
- `syslog-server-0`: Pending due to unbound PVC `syslog-data-syslog-server-0`
- `chrony-ntp-*`: ImagePullBackOff due to invalid image reference

## Root Causes

### 1. PVC Naming Mismatch
StatefulSets use `volumeClaimTemplates` which automatically create PVCs with the naming pattern:
```
{volumeClaimTemplate.name}-{statefulset.name}-{ordinal}
```

**Before (Incorrect):**
- Prometheus PV claimed: `prometheus-pvc`
- Actual PVC created: `prometheus-storage-prometheus-0`
- Result: PV and PVC don't bind ❌

**After (Fixed):**
- Prometheus PV claims: `prometheus-storage-prometheus-0`
- Actual PVC created: `prometheus-storage-prometheus-0`
- Result: PV and PVC bind successfully ✅

### 2. Missing Syslog PersistentVolume
The syslog-server StatefulSet requested a PVC but no PV existed to fulfill it.

### 3. Missing nodeAffinity
PVs didn't specify which nodes they should be scheduled on, potentially causing scheduling issues.

### 4. Invalid Chrony Exporter Image
The image `superq/chrony-exporter:latest` doesn't exist on Docker Hub. The correct image is on Quay.io.

## Changes Made

### Files Modified

#### 1. `manifests/monitoring/prometheus-pv.yaml`
```yaml
# Changed claimRef name from prometheus-pvc to prometheus-storage-prometheus-0
# Added nodeAffinity for control-plane nodes
  claimRef:
    namespace: monitoring
    name: prometheus-storage-prometheus-0
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
```

#### 2. `manifests/monitoring/loki-pv.yaml`
```yaml
# Changed claimRef name from loki-pvc to loki-data-loki-0
# Removed standalone PVC definition (StatefulSet creates it automatically)
# Added nodeAffinity for control-plane nodes
  claimRef:
    namespace: monitoring
    name: loki-data-loki-0
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
```

#### 3. `manifests/monitoring/grafana-pv.yaml`
```yaml
# Added nodeAffinity for control-plane nodes
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
```

#### 4. `manifests/monitoring/promtail-pv.yaml`
```yaml
# Added nodeAffinity for control-plane nodes
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
```

#### 5. `manifests/infrastructure/syslog-pv.yaml` (NEW)
```yaml
---
# HostPath PersistentVolume for Syslog Server
apiVersion: v1
kind: PersistentVolume
metadata:
  name: syslog-pv
  labels:
    app: syslog-server
    vmstation.io/component: logging
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /srv/monitoring_data/syslog
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
  claimRef:
    namespace: infrastructure
    name: syslog-data-syslog-server-0
```

#### 6. `manifests/infrastructure/chrony-ntp.yaml`
```yaml
# Fixed chrony-exporter image reference
# Before: image: superq/chrony-exporter:latest
# After:  image: quay.io/superq/chrony-exporter:latest
      - name: chrony-exporter
        image: quay.io/superq/chrony-exporter:latest
```

#### 7. `ansible/playbooks/deploy-cluster.yaml`
```yaml
# Added syslog directory creation
      loop:
        - { path: '/srv/monitoring_data' }
        - { path: '/srv/monitoring_data/grafana', owner: '472', group: '472' }
        - { path: '/srv/monitoring_data/prometheus', owner: '65534', group: '65534' }
        - { path: '/srv/monitoring_data/loki', owner: '10001', group: '10001' }
        - { path: '/srv/monitoring_data/promtail', owner: '0', group: '0' }
        - { path: '/srv/monitoring_data/syslog', owner: '0', group: '0' }  # NEW
```

#### 8. `ansible/playbooks/deploy-syslog-service.yaml`
```yaml
# Added PV application step
    - name: "Apply syslog PersistentVolume"
      command: |
        kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f /srv/monitoring_data/VMStation/manifests/infrastructure/syslog-pv.yaml
```

## Storage Architecture

All persistent storage is now centralized on the masternode (control-plane) at `/srv/monitoring_data/`:

```
/srv/monitoring_data/
├── prometheus/       (10Gi) - Time-series metrics data (UID:GID 65534:65534)
├── loki/            (20Gi) - Log storage (UID:GID 10001:10001)
├── grafana/          (2Gi) - Dashboards, users, settings (UID:GID 472:472)
├── promtail/         (1Gi) - Position tracking (UID:GID 0:0)
└── syslog/           (5Gi) - Syslog server data (UID:GID 0:0)
```

### Node Affinity Strategy

All PersistentVolumes now have `nodeAffinity` requiring the `node-role.kubernetes.io/control-plane` label. This ensures:
- ✅ All monitoring data stays on the masternode
- ✅ Worker nodes (storagenodet3500, homelab) only forward/export data
- ✅ PVs won't accidentally bind on worker nodes
- ✅ Consistent storage location for backups and maintenance

## Verification Steps

### 1. Check PVs are created and bound
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pv
```

Expected output:
```
NAME            CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM
prometheus-pv   10Gi       RWO            Retain           Bound    monitoring/prometheus-storage-prometheus-0
loki-pv         20Gi       RWO            Retain           Bound    monitoring/loki-data-loki-0
grafana-pv      2Gi        RWO            Retain           Bound    monitoring/grafana-pvc
promtail-pv     1Gi        RWO            Retain           Bound    monitoring/promtail-pvc
syslog-pv       5Gi        RWO            Retain           Bound    infrastructure/syslog-data-syslog-server-0
```

### 2. Check PVCs are bound
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pvc -A
```

Expected output:
```
NAMESPACE        NAME                              STATUS   VOLUME         CAPACITY
monitoring       prometheus-storage-prometheus-0   Bound    prometheus-pv  10Gi
monitoring       loki-data-loki-0                  Bound    loki-pv        20Gi
monitoring       grafana-pvc                       Bound    grafana-pv     2Gi
monitoring       promtail-pvc                      Bound    promtail-pv    1Gi
infrastructure   syslog-data-syslog-server-0       Bound    syslog-pv      5Gi
```

### 3. Check pods are running
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n infrastructure
```

Expected: All pods should be `Running` and `Ready`

### 4. Verify storage directories exist with correct permissions
```bash
ls -la /srv/monitoring_data/
```

Expected output:
```
drwxr-xr-x  2 472   472   4096 Oct  9 16:00 grafana
drwxr-xr-x  2 10001 10001 4096 Oct  9 16:00 loki
drwxr-xr-x  2 65534 65534 4096 Oct  9 16:00 prometheus
drwxr-xr-x  2 root  root  4096 Oct  9 16:00 promtail
drwxr-xr-x  2 root  root  4096 Oct  9 16:00 syslog
```

## Troubleshooting

### If pods are still pending:

1. **Check PV status:**
   ```bash
   kubectl describe pv prometheus-pv
   ```
   Look for "Status: Bound" and correct claimRef

2. **Check PVC status:**
   ```bash
   kubectl describe pvc -n monitoring prometheus-storage-prometheus-0
   ```
   Look for "Status: Bound" and correct volume name

3. **Check pod events:**
   ```bash
   kubectl describe pod -n monitoring prometheus-0
   ```
   Look for scheduling errors or volume mount issues

4. **Verify directories exist:**
   ```bash
   ls -la /srv/monitoring_data/
   ```
   All directories should exist with correct ownership

### If chrony-exporter fails:

1. **Check image pull:**
   ```bash
   kubectl describe pod -n infrastructure chrony-ntp-xxxxx
   ```
   Should show `Successfully pulled image "quay.io/superq/chrony-exporter:latest"`

2. **Verify image exists:**
   ```bash
   docker pull quay.io/superq/chrony-exporter:latest
   ```

## Testing

Run the validation test:
```bash
/tmp/test-pv-configuration.sh
```

All tests should pass with green checkmarks.

## Related Issues

- Prometheus pod pending: Fixed by correcting PVC name
- Loki pod pending: Fixed by correcting PVC name and removing standalone PVC
- Syslog pod pending: Fixed by creating syslog-pv.yaml
- Chrony ImagePullBackOff: Fixed by correcting image registry

## Production Considerations

1. **Backup Strategy**: All data is on `/srv/monitoring_data/` - ensure this directory is backed up regularly
2. **Disk Space**: Monitor disk usage on masternode (total: 33Gi allocated)
3. **High Availability**: Current setup is single-node (masternode). For HA, consider:
   - NFS/Ceph for shared storage
   - Multiple control-plane nodes
   - PV replication

## References

- Kubernetes StatefulSets: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- PersistentVolumes: https://kubernetes.io/docs/concepts/storage/persistent-volumes/
- Node Affinity: https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/

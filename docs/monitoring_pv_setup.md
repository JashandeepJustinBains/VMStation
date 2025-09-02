# Monitoring PV Creation and Permissions Setup

This document explains the new automated PV (PersistentVolume) creation and monitoring permissions setup that has been integrated into the VMStation deployment pipeline.

## Overview

The implementation addresses the complete monitoring stack PV setup workflow:

1. **Host Directory Setup** - Creates `/srv/monitoring_data` directories with proper permissions
2. **Grafana-Specific Permissions** - Sets UID:GID 472:472 for Grafana directories
3. **Static PV Creation** - Creates PersistentVolumes for Grafana and Loki
4. **PVC Binding** - Ensures existing PVCs can bind to the new PVs
5. **Pod Restart** - Triggers pod recreation to pick up new storage

## Automatic Integration

### Pre-Deployment (Host Setup)
```bash
# Runs automatically in update_and_deploy.sh
sudo ./scripts/fix_monitoring_permissions.sh
```

**What it does:**
- Creates `/srv/monitoring_data/grafana` with UID:GID 472:472
- Creates `/srv/monitoring_data/loki` with root:root
- Sets proper permissions (755) for all directories
- Handles SELinux contexts if enabled

### Post-Deployment (Kubernetes Setup)
```bash
# Runs automatically after cluster deployment
./scripts/create_monitoring_pvs.sh --auto-approve
```

**What it does:**
- Creates `pv-grafana-local` (5Gi) pointing to `/srv/monitoring_data/grafana`
- Creates `pv-loki-local` (20Gi) pointing to `/srv/monitoring_data/loki`
- Uses `storageClassName: local-path` for PVC compatibility
- Applies `nodeAffinity` to target `homelab` node
- Checks PVC binding status
- Optionally restarts monitoring pods

## Manual Usage

### Individual Script Execution

**Permissions Setup:**
```bash
sudo ./scripts/fix_monitoring_permissions.sh
```

**PV Creation:**
```bash
./scripts/create_monitoring_pvs.sh --auto-approve
```

### Verification Commands

**Check PV Status:**
```bash
kubectl get pv -o wide
```

**Check PVC Binding:**
```bash
kubectl -n monitoring get pvc -o wide
kubectl -n monitoring describe pvc kube-prometheus-stack-grafana
```

**Check Pod Status:**
```bash
kubectl -n monitoring get pods -w
```

**Check Grafana Init Logs:**
```bash
kubectl -n monitoring logs <grafana-pod-name> -c init-chown-data --tail=200
```

**Verify Host Permissions:**
```bash
sudo ls -la /srv/monitoring_data/
sudo stat -c 'UID:%u GID:%g MODE:%a' /srv/monitoring_data/grafana
```

## PV Manifest Details

### Grafana PV
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-grafana-local
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
  local:
    path: /srv/monitoring_data/grafana
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - homelab
```

### Loki PV
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-loki-local
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
  local:
    path: /srv/monitoring_data/loki
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - homelab
```

## Troubleshooting

### If Cluster is Not Accessible
```bash
# Run this sequence manually when cluster is available
scripts/fix_monitoring_permissions.sh && \
scripts/create_monitoring_pvs.sh --auto-approve && \
scripts/fix_k8s_dashboard_permissions.sh --auto-approve && \
scripts/fix_k8s_monitoring_pods.sh --auto-approve
```

### Permission Issues
```bash
# Manually fix Grafana permissions
sudo chown -R 472:472 /srv/monitoring_data/grafana
sudo chmod -R 755 /srv/monitoring_data/grafana

# Manually fix Loki permissions
sudo chown -R root:root /srv/monitoring_data/loki
sudo chmod -R 755 /srv/monitoring_data/loki
```

### SELinux Issues (RHEL/CentOS)
```bash
# Set SELinux contexts for containers
sudo chcon -R -t container_file_t /srv/monitoring_data/grafana
sudo chcon -R -t container_file_t /srv/monitoring_data/loki
```

### PV Already Exists
The script automatically detects existing PVs and skips creation to avoid conflicts:
```
⚠ pv-grafana-local already exists, skipping creation
```

## Implementation Files

| File | Purpose |
|------|---------|
| `scripts/create_monitoring_pvs.sh` | Creates and applies PV manifests |
| `scripts/fix_monitoring_permissions.sh` | Sets up host directories and permissions |
| `update_and_deploy.sh` | Main deployment script with integration |

## Safety Features

- **Idempotent Operations** - Safe to run multiple times
- **Existing PV Detection** - Won't overwrite existing resources  
- **Permission Validation** - Reports success/failure clearly
- **Graceful Degradation** - Continues deployment if some steps fail
- **Comprehensive Logging** - Detailed output for troubleshooting

This implementation resolves the monitoring stack PV binding issues while maintaining safety and automation.
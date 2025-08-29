# Monitoring Stack Permission Fix Guide

## Problem
Grafana and Loki pods are stuck in "Pending" or "Unknown" status due to file permission and SELinux context issues.

## Critical Directories That Need Read/Write Access

The following directories must have proper permissions for the monitoring stack to function:

### 1. Primary Monitoring Data Directory
```bash
/srv/monitoring_data
```
- **Purpose**: Main storage for all monitoring components
- **Required Permissions**: 755 (rwxr-xr-x)
- **Owner**: root:root (for Kubernetes) or current user (for Podman)
- **SELinux Context**: container_file_t (if SELinux enabled)

### 2. Grafana Subdirectories
```bash
/srv/monitoring_data/grafana/
/srv/monitoring_data/grafana/dashboards/
/srv/monitoring_data/grafana/datasources/
/srv/monitoring_data/grafana/data/
```
- **Purpose**: Grafana configuration, dashboards, and persistent data
- **Required Permissions**: 755
- **SELinux Context**: container_file_t

### 3. Prometheus Data Directory
```bash
/srv/monitoring_data/prometheus/
/srv/monitoring_data/prometheus/data/
```
- **Purpose**: Prometheus time-series database storage
- **Required Permissions**: 755
- **SELinux Context**: container_file_t

### 4. Loki Storage Directories
```bash
/srv/monitoring_data/loki/
/srv/monitoring_data/loki/chunks/
/srv/monitoring_data/loki/index/
```
- **Purpose**: Loki log storage and indexing
- **Required Permissions**: 755
- **SELinux Context**: container_file_t

### 5. Promtail Directories
```bash
/srv/monitoring_data/promtail/
/srv/monitoring_data/promtail/data/
/var/promtail/
/opt/promtail/
```
- **Purpose**: Promtail log collection configuration and working data
- **Required Permissions**: 755
- **SELinux Context**: container_file_t

### 6. System Log Directory
```bash
/var/log/
```
- **Purpose**: System logs that Promtail needs to read
- **Required Permissions**: 755 (read access for containers)
- **SELinux Context**: container_file_t

## Automated Fix Solutions

### Option 1: Run Diagnostic Script (Recommended First Step)
```bash
./scripts/diagnose_monitoring_permissions.sh
```
This script will identify specific permission issues without making changes.

### Option 2: Run Automated Fix Script
```bash
./scripts/fix_monitoring_permissions.sh
```
For full permissions (if you have sudo access):
```bash
sudo ./scripts/fix_monitoring_permissions.sh
```

### Option 3: Use Ansible Playbook
```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/fix_selinux_contexts.yaml
```

## Manual Fix Commands

If you prefer to fix permissions manually, run these commands:

### Create and Set Basic Permissions
```bash
# Create main monitoring directory
sudo mkdir -p /srv/monitoring_data
sudo chmod 755 /srv/monitoring_data
sudo chown -R root:root /srv/monitoring_data

# Create subdirectories
sudo mkdir -p /srv/monitoring_data/{grafana,prometheus,loki,promtail}
sudo mkdir -p /srv/monitoring_data/grafana/{dashboards,datasources,data}
sudo mkdir -p /srv/monitoring_data/prometheus/data
sudo mkdir -p /srv/monitoring_data/loki/{chunks,index}
sudo mkdir -p /srv/monitoring_data/promtail/data

# Set permissions for all subdirectories
sudo chmod -R 755 /srv/monitoring_data

# Create promtail working directories
sudo mkdir -p /var/promtail /opt/promtail
sudo chmod 755 /var/promtail /opt/promtail
```

### Fix SELinux Contexts (Only if SELinux is Enabled)
```bash
# Check if SELinux is enabled
getenforce

# If SELinux is enabled (Enforcing or Permissive), run:
sudo chcon -R -t container_file_t /srv/monitoring_data
sudo chcon -R -t container_file_t /var/log
sudo chcon -R -t container_file_t /var/promtail
sudo chcon -R -t container_file_t /opt/promtail

# Set SELinux booleans for container access
sudo setsebool -P container_use_cephfs 1
sudo setsebool -P container_manage_cgroup 1
```

### Verify Permissions
```bash
# Check directory permissions
ls -la /srv/monitoring_data
ls -la /var/promtail
ls -la /opt/promtail

# Check SELinux contexts (if enabled)
ls -Z /srv/monitoring_data
ls -Z /var/log
```

## After Fixing Permissions

1. **Restart Failed Pods**:
   ```bash
   kubectl delete pods -n monitoring --field-selector=status.phase=Pending
   kubectl delete pods -n monitoring --field-selector=status.phase=Unknown
   ```

2. **Redeploy Monitoring Stack**:
   ```bash
   ./update_and_deploy.sh
   ```

3. **Validate the Fix**:
   ```bash
   ./scripts/validate_monitoring.sh
   ```

4. **Check Pod Status**:
   ```bash
   kubectl get pods -n monitoring
   ```

## Troubleshooting

If pods are still failing after permission fixes:

1. **Check Pod Events**:
   ```bash
   kubectl describe pod -n monitoring <pod-name>
   ```

2. **Check Container Logs**:
   ```bash
   kubectl logs -n monitoring <pod-name>
   ```

3. **Verify Node Resources**:
   ```bash
   kubectl describe nodes
   ```

4. **Check Storage Classes**:
   ```bash
   kubectl get storageclass
   ```

## Common Issues

- **NFS Mounts**: If `/srv` is an NFS mount, you may need additional NFS export options like `no_root_squash`
- **File System Types**: Some file systems may not support SELinux contexts
- **User Namespaces**: In some Kubernetes setups, container user mapping may require specific ownership

## Summary

The key directories that need read/write permissions are:
- `/srv/monitoring_data` and all subdirectories
- `/var/log` (read access for log collection)
- `/var/promtail` and `/opt/promtail` (promtail working directories)

Run the diagnostic script first to identify specific issues, then use the fix script or manual commands above.
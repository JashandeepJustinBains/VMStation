# ANSWER: Files That Need Read/Write Permissions

Based on the analysis of your monitoring stack issues, here are the **specific files and directories** you should allow read/write permissions for:

## Primary Directories (CRITICAL)

### 1. `/srv/monitoring_data` 
- **Purpose**: Main monitoring data storage for all components
- **Required for**: Grafana, Prometheus, Loki data persistence
- **Permissions needed**: 755 (rwxr-xr-x)
- **Subdirectories to create**:
  - `/srv/monitoring_data/grafana/`
  - `/srv/monitoring_data/prometheus/`  
  - `/srv/monitoring_data/loki/`
  - `/srv/monitoring_data/promtail/`

### 2. `/var/log`
- **Purpose**: System log files for Promtail to read
- **Required for**: Log collection into Loki
- **Permissions needed**: 755 (read access for containers)

### 3. `/var/promtail`
- **Purpose**: Promtail working directory
- **Required for**: Promtail operation and data processing
- **Permissions needed**: 755

### 4. `/opt/promtail`  
- **Purpose**: Promtail configuration storage
- **Required for**: Promtail startup and configuration
- **Permissions needed**: 755

## Quick Fix Commands

Run these commands to fix permissions manually:

```bash
# Create directories
sudo mkdir -p /srv/monitoring_data/{grafana,prometheus,loki,promtail}
sudo mkdir -p /var/promtail /opt/promtail

# Set permissions
sudo chmod -R 755 /srv/monitoring_data /var/promtail /opt/promtail

# Set ownership
sudo chown -R root:root /srv/monitoring_data /var/promtail /opt/promtail

# If SELinux is enabled, set contexts
sudo chcon -R -t container_file_t /srv/monitoring_data
sudo chcon -R -t container_file_t /var/log  
sudo chcon -R -t container_file_t /var/promtail
sudo chcon -R -t container_file_t /opt/promtail
```

## Automated Solution

I've created scripts that will do this automatically:

```bash
# Quick guidance
./scripts/quick_permission_guide.sh

# Diagnose current issues
./scripts/diagnose_monitoring_permissions.sh

# Fix automatically (recommended)
sudo ./scripts/fix_monitoring_permissions.sh
```

## After Fixing Permissions

Restart your stuck pods:
```bash
kubectl delete pods -n monitoring --field-selector=status.phase=Pending
kubectl delete pods -n monitoring --field-selector=status.phase=Unknown
```

The main issue is that your Grafana and Loki pods cannot access the storage directories they need due to missing directories and/or permission problems.
# Container Restart and SELinux Issues - Fix Documentation

## Problem Summary

The VMStation monitoring stack was experiencing frequent container restarts, particularly affecting:

- **loki** - Exiting with code 1
- **promtail** containers - Exiting with code 1  
- SELinux preventing containers from accessing `/var/log` on compute nodes

## Root Cause Analysis

### Primary Issues Identified:

1. **SELinux Context Issues**: Container volume mounts lacked proper SELinux contexts
2. **Loki Configuration**: Incorrect volume mounting of configuration directory
3. **Promtail Volume Access**: SELinux blocking access to `/var/log` and configuration files
4. **Missing SELinux Policies**: Container-specific SELinux contexts not configured

### Technical Details:

- Containers need `:Z` suffix for SELinux volume mounts in enforcing environments
- Loki was mounting entire config directory instead of specific config file
- Promtail configuration file needs `:ro` (read-only) mount for stability
- SELinux needs `container_file_t` context for container-accessible files

## Implemented Fixes

### 1. Fixed Loki Volume Mounting (`install_node.yaml`)

**Before:**
```yaml
volumes:
  - "{{ monit_root }}/loki:/etc/loki:Z"
```

**After:**
```yaml
volumes:
  - "{{ monit_root }}/loki/local-config.yaml:/etc/loki/local-config.yaml:Z"
```

**Reason**: Mounting entire directory can cause permission conflicts. Mounting specific config file is more reliable.

### 2. Fixed Promtail Configuration Mounting

**Before:**
```yaml
volumes:
  - "{{ monit_root }}/promtail:/etc/promtail:Z"
```

**After:**
```yaml
volumes:
  - "{{ monit_root }}/promtail/promtail-config.yaml:/etc/promtail/promtail-config.yaml:Z"
```

**Reason**: Direct config file mounting prevents directory permission issues.

### 3. Enhanced SELinux Context Handling (`deploy_promtail.yaml`)

**Added:**
- `:ro` (read-only) flag for configuration files
- Improved conditional SELinux context handling
- Better error handling with `ignore_errors: yes`

### 4. Created Comprehensive SELinux Fix Playbook (`fix_selinux_contexts.yaml`)

**Features:**
- Automatic SELinux detection
- Cross-platform SELinux tool installation
- Proper `container_file_t` context setting for:
  - `/var/log` (for promtail log access)
  - `/srv/monitoring_data` (for container data)
  - `/var/promtail` (for promtail working directory)
  - `/opt/promtail` (for promtail configuration)
- SELinux boolean configuration for container access

### 5. Created Automated Fix Script (`fix_container_restarts.sh`)

**Capabilities:**
- Detect and diagnose failing containers
- Check SELinux status automatically
- Apply manual SELinux fixes when Ansible unavailable
- Recreate containers with proper volume mounts
- Comprehensive verification and testing

### 6. Updated Monitoring Stack Integration

- Added SELinux fix playbook to `monitoring_stack.yaml`
- Enhanced directory creation with SELinux context setting
- Improved error handling throughout stack

## Usage Instructions

### Quick Fix (Automated)

```bash
# Run the comprehensive fix script
./scripts/fix_container_restarts.sh
```

### Ansible-based Fix

```bash
# Run the full monitoring stack with SELinux fixes
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml

# Or run just the SELinux fixes
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/fix_selinux_contexts.yaml
```

### Manual SELinux Fix (if needed)

```bash
# Set SELinux contexts manually
chcon -R -t container_file_t /var/log
chcon -R -t container_file_t /srv/monitoring_data
chcon -R -t container_file_t /var/promtail
chcon -R -t container_file_t /opt/promtail

# Set SELinux booleans
setsebool -P container_use_cephfs 1
setsebool -P container_manage_cgroup 1
```

## Verification

### Check Container Status
```bash
podman ps
# Should show all containers as "Up" status
```

### Check SELinux Contexts
```bash
ls -Z /var/log
ls -Z /srv/monitoring_data
# Should show container_file_t context
```

### Check Container Logs
```bash
podman logs loki
podman logs promtail
# Should show no permission errors
```

### Test Log Access
```bash
# Test if promtail can access logs
curl http://localhost:3100/loki/api/v1/labels
```

## Prevention Measures

1. **Always use `:Z` SELinux context** for container volume mounts in SELinux environments
2. **Mount specific files** instead of entire directories when possible
3. **Set proper SELinux contexts** before container deployment
4. **Use read-only mounts** for configuration files
5. **Include SELinux fixes** in deployment automation

## Common Error Patterns Fixed

- **"Permission denied"** → Fixed with proper SELinux contexts
- **"No such file or directory"** → Fixed with correct volume mounting
- **Container immediately exits** → Fixed with proper configuration file access
- **Log ingestion failures** → Fixed with `/var/log` SELinux contexts

## Files Modified

- `ansible/plays/monitoring/install_node.yaml` - Fixed loki and promtail volume mounts
- `ansible/plays/monitoring/deploy_promtail.yaml` - Enhanced SELinux handling
- `ansible/plays/monitoring/fix_selinux_contexts.yaml` - **NEW** comprehensive SELinux fix
- `ansible/plays/monitoring_stack.yaml` - Added SELinux fix integration
- `scripts/fix_container_restarts.sh` - **NEW** automated fix script

## Jellyfin Container Preservation Fix

**Issue:** The monitoring cleanup script was killing ALL podman containers, including non-monitoring containers like Jellyfin.

**Root Cause:** `monitoring/cleanup.yaml` used `podman ps -q | xargs -r podman stop` which stops all containers indiscriminately.

**Fix:** Modified cleanup to only target specific monitoring containers:
- `prometheus`, `loki`, `grafana`, `promtail_local`, `local_registry`
- `promtail`, `node-exporter`, `podman_exporter`, `podman_system_metrics`

**Result:** Non-monitoring containers (like Jellyfin) are now preserved during deployment.

## Success Criteria

- ✅ All containers show "Up" status consistently
- ✅ No restart loops or exit code 1 failures
- ✅ Promtail successfully ingests logs from `/var/log`
- ✅ Loki accepts log data without errors
- ✅ SELinux contexts properly set for all container volumes
- ✅ No SELinux AVC denials in audit logs
- ✅ **NEW**: Non-monitoring containers (Jellyfin) preserved during monitoring stack deployment
# Podman System Metrics Issue Resolution Summary

## Problem Statement
The `podman_system_metrics` container was immediately exiting and the metrics endpoint at `http://127.0.0.1:19882/metrics` was refusing connections as part of the VMStation monitoring playbooks.

## Root Cause Analysis

### Primary Issues Identified:
1. **Missing Configuration**: `ansible/group_vars/all.yml` file was missing (gitignored for security)
2. **Missing Container Image**: The required `podman-system-metrics` image wasn't available in the local registry
3. **Registry Configuration**: Local registry not configured for insecure access
4. **Port Conflicts**: Potential conflicts on port 19882
5. **Image Source Confusion**: The image is actually `quay.io/podman/stable` tagged as `podman-system-metrics`

### Technical Details:
- Container expects to bind to `127.0.0.1:19882:9882` (host:container)
- Uses local registry at `192.168.4.63:5000/podman-system-metrics:latest`
- Requires Podman socket access for metrics collection
- Part of monitoring stack with Prometheus, Grafana, and Loki

## Solution Implemented

### 1. Configuration Template
**File**: `ansible/group_vars/all.yml.template`
- Provides template for required variables
- User copies to `all.yml` and customizes
- Defines `podman_system_metrics_host_port: 19882`
- Enables `enable_podman_exporters: true`

### 2. Diagnostic Script
**File**: `scripts/podman_metrics_diagnostic.sh`
- Comprehensive system analysis
- Checks container status, port usage, image availability
- Tests manual container startup
- Provides detailed troubleshooting information
- **Command**: `./scripts/podman_metrics_diagnostic.sh`

### 3. Automated Fix Script  
**File**: `scripts/fix_podman_metrics.sh`
- Complete automated resolution
- Ensures local registry is running
- Pulls and publishes required images
- Configures insecure registry access
- Stops conflicting processes
- Starts container with proper configuration
- **Command**: `./scripts/fix_podman_metrics.sh`

### 4. Monitoring Validation Script
**File**: `scripts/validate_monitoring.sh`
- Tests entire monitoring stack health
- Checks all exporters and core services
- Validates Prometheus target status
- Provides color-coded status output
- **Command**: `./scripts/validate_monitoring.sh`

### 5. Comprehensive Documentation
**File**: `docs/monitoring/troubleshooting_podman_metrics.md`
- Step-by-step troubleshooting guide
- Exact commands with result interpretation
- Common fixes for all scenarios
- Testing and validation procedures

### 6. Updated Main Documentation
**File**: `docs/monitoring/README.md`
- Added troubleshooting section
- References to new scripts and guides
- Quick fix commands

## Exact Commands to Run

### Quick Fix (Most Common Solution):
```bash
# Run automated fix
./scripts/fix_podman_metrics.sh
```

### Detailed Diagnosis:
```bash
# Comprehensive analysis
./scripts/podman_metrics_diagnostic.sh
```

### Monitoring Health Check:
```bash
# Validate entire stack
./scripts/validate_monitoring.sh
```

### Manual Steps (if automation fails):
```bash
# 1. Create configuration
cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml

# 2. Check container status
podman ps -a --filter name="podman_system_metrics"

# 3. Check logs
podman logs podman_system_metrics

# 4. Check port usage
lsof -i :19882

# 5. Test metrics endpoint
curl http://127.0.0.1:19882/metrics

# 6. Redeploy if needed
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/install_exporters.yaml
```

## How to Interpret Results

### Successful Fix Indicators:
- `podman ps` shows container status as "Up"
- `curl http://127.0.0.1:19882/metrics` returns Prometheus-format metrics
- Prometheus targets page shows podman_system_metrics as "UP"
- No errors in `podman logs podman_system_metrics`

### Common Error Patterns:
- **"Port already in use"**: Another process using 19882 → Kill process or change port
- **"Image not found"**: Local registry missing image → Run fix script to pull/push
- **"Permission denied"**: Podman socket access → Check container volumes and SELinux
- **Container exits immediately**: Wrong image or missing dependencies → Check logs

### Prometheus Integration:
- Metrics appear at `http://192.168.4.63:9090/targets` 
- Job name: `podman_system_metrics`
- Expected targets: All nodes (monitoring, storage, compute) on port 19882
- Status should show "UP" for all targets

## Files Created/Modified

### New Files:
- `ansible/group_vars/all.yml.template` - Configuration template
- `scripts/podman_metrics_diagnostic.sh` - Diagnostic script
- `scripts/fix_podman_metrics.sh` - Automated fix script  
- `scripts/validate_monitoring.sh` - Monitoring validation
- `scripts/README.md` - Scripts documentation
- `docs/monitoring/troubleshooting_podman_metrics.md` - Troubleshooting guide

### Modified Files:
- `docs/monitoring/README.md` - Added troubleshooting references

### Repository Impact:
- All changes are minimal and focused on diagnostics/troubleshooting
- No modifications to existing working monitoring playbooks
- No breaking changes to current configuration
- Backward compatible with existing setups

## Usage in Monitoring Playbooks

The solution integrates seamlessly with existing Ansible playbooks:

```bash
# Deploy full monitoring stack
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml

# Deploy only exporters  
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/install_exporters.yaml

# Run debug collection
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/debug_collect.yaml
```

## Validation

After running the fix:
1. Validate with script: `./scripts/validate_monitoring.sh`
2. Check Prometheus: `http://192.168.4.63:9090/targets`
3. Verify Grafana dashboards have podman metrics
4. Test metrics endpoint: `curl http://127.0.0.1:19882/metrics`

This solution provides a complete toolkit for diagnosing and resolving podman_system_metrics issues with exact commands and clear interpretation of results.
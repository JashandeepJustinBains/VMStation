# Loki Stack CrashLoopBackOff Fix

## Problem Summary

The VMStation monitoring stack was experiencing CrashLoopBackOff issues with:
- `loki-stack-0` pod - CrashLoopBackOff with 932 restarts
- `loki-stack-promtail-4xp5t` pod - ContainerCreating status

## Root Cause Analysis

The original Loki stack configuration had several issues that caused instability:

### 1. Resource Constraints
- No resource limits defined, leading to OOM kills
- Insufficient memory allocation for Loki workloads
- No CPU limits causing scheduling issues

### 2. Configuration Issues
- Using outdated/unstable Loki image versions
- Inefficient ingester configuration causing memory pressure
- Missing storage optimization settings
- Inadequate timeout and retry settings for promtail

### 3. Volume Mount Issues
- Promtail lacking proper volume mounts for log access
- Missing security contexts for filesystem permissions
- Inadequate hostPath configurations

## Solution Implemented

### 1. Enhanced Resource Management
- Added proper resource limits and requests for both Loki and Promtail
- Loki: 1000m CPU / 1Gi memory limits, 200m CPU / 256Mi memory requests
- Promtail: 500m CPU / 256Mi memory limits, 100m CPU / 128Mi memory requests

### 2. Improved Loki Configuration
- Updated to stable Loki 2.9.2 image version
- Optimized ingester settings for single-node deployment:
  - Increased chunk idle period to 1h
  - Set max chunk age to 1h
  - Optimized chunk size and retention
- Enhanced storage configuration with safer directory paths
- Added proper limits configuration to prevent ingestion issues

### 3. Fixed Promtail Configuration
- Matched Promtail version (2.9.2) with Loki version
- Added proper volume mounts for log access (`/var/log`, `/var/lib/docker/containers`)
- Improved client configuration with timeout and backoff settings
- Enhanced Kubernetes pod discovery configuration

### 4. Security and Permissions
- Added proper security contexts for both components
- Configured filesystem group and user settings
- Set read-only root filesystem for Promtail

## Files Modified

### Core Fix Files
- `ansible/plays/kubernetes/deploy_monitoring.yaml` - Updated Loki stack configuration
- `fix_loki_stack_crashloop.sh` - Standalone fix script for immediate resolution
- `verify_loki_stack_fix.sh` - Verification script to check fix success

## Usage Instructions

### Option 1: Apply Fix via Ansible Playbook (Recommended)
```bash
# Deploy the updated monitoring stack
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml

# Verify the fix
./verify_loki_stack_fix.sh
```

### Option 2: Apply Immediate Fix Script
```bash
# Run the standalone fix script
./fix_loki_stack_crashloop.sh

# Verify the fix
./verify_loki_stack_fix.sh
```

## Verification Steps

1. **Check Pod Status**:
   ```bash
   kubectl get pods -n monitoring -l app=loki
   kubectl get pods -n monitoring -l app=promtail
   ```

2. **Verify No CrashLoopBackOff**:
   - Pods should show "Running" status
   - Restart count should not be increasing
   - No "CrashLoopBackOff" or "ContainerCreating" status

3. **Check Working Pods Preservation**:
   ```bash
   kubectl get pods -n jellyfin  # Should remain unaffected
   kubectl get pods --all-namespaces | grep Running
   ```

4. **Test Loki Connectivity**:
   ```bash
   # Get node IP and test health endpoint
   kubectl get nodes -o wide
   curl http://<NODE_IP>:31100/ready
   ```

## Working Pods Preservation

This fix specifically ensures that:
- **Jellyfin pods remain untouched** - No restarts or volume unmounting
- **Other working services continue normally** - Only Loki stack components are affected
- **No drive unmounting/remounting** - Existing volume mounts are preserved
- **Minimal compute impact** - Targeted fix avoids unnecessary resource usage

## Success Criteria

- ✅ Loki stack pods show "Running" status consistently
- ✅ No CrashLoopBackOff or restart loops
- ✅ Promtail successfully connects to Loki
- ✅ Log ingestion is working
- ✅ Jellyfin and other working pods remain unaffected
- ✅ No mounted drives are disturbed

## Troubleshooting

If the fix doesn't resolve the issues immediately:

1. **Check Resource Availability**:
   ```bash
   kubectl describe nodes
   kubectl top nodes
   ```

2. **Review Pod Events**:
   ```bash
   kubectl describe pod <loki-pod-name> -n monitoring
   kubectl get events -n monitoring --sort-by=.metadata.creationTimestamp
   ```

3. **Check Logs**:
   ```bash
   kubectl logs -n monitoring -l app=loki --tail=100
   kubectl logs -n monitoring -l app=promtail --tail=100
   ```

4. **Verify Storage**:
   ```bash
   kubectl get pvc -n monitoring
   kubectl get storageclass
   ```

## Prevention Measures

To prevent future CrashLoopBackOff issues:
1. **Always set resource limits** for monitoring components
2. **Use stable image versions** rather than latest tags
3. **Monitor resource usage** regularly via Prometheus metrics
4. **Keep configurations optimized** for your cluster size
5. **Test changes in staging** before applying to production

## Rollback Plan

If the fix causes any issues, rollback is possible:

```bash
# Rollback Helm release
helm rollback loki-stack -n monitoring

# Or restore previous configuration
git checkout HEAD~1 -- ansible/plays/kubernetes/deploy_monitoring.yaml
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml
```
# CNI Bridge IP Conflict Fix

## Problem

Kubernetes pods get stuck in "ContainerCreating" state with errors like:
```
Failed to create pod sandbox: plugin type="bridge" failed (add): failed to set bridge addr: "cni0" already has an IP address different from 10.244.0.1/16
```

## Root Cause

The CNI bridge (cni0) has an IP address that conflicts with the Flannel subnet (10.244.0.0/16). This prevents new pods from being created because the container runtime cannot set up proper networking.

## Solution

### Automatic Fix (Recommended)

The fix is automatically integrated into the deployment system:

1. **During deployment**: `./deploy.sh` automatically detects and fixes CNI bridge conflicts
2. **Manual diagnosis**: `./scripts/check_cni_bridge_conflict.sh`
3. **Manual fix**: `./scripts/fix_cni_bridge_conflict.sh`

### How It Works

1. **Detects** CNI bridge IP conflicts by checking:
   - Pods stuck in ContainerCreating state
   - Recent events for bridge configuration errors
   - Current cni0 bridge IP configuration

2. **Fixes** the issue by:
   - Safely deleting the conflicting cni0 bridge
   - Restarting containerd to clear network state
   - Restarting Flannel pods to recreate the bridge with correct IP
   - Verifying the fix with a test pod

3. **Validates** the fix by:
   - Checking new cni0 bridge has correct Flannel subnet IP
   - Testing pod creation works properly
   - Monitoring for any remaining ContainerCreating pods

## Integration

### With Existing Scripts

- **`fix_homelab_node_issues.sh`**: Now includes CNI bridge conflict detection as Step 0
- **`deploy.sh`**: Automatically applies CNI bridge fix if other methods fail
- **Error handling**: Graceful fallback from CoreDNS fixes to CNI bridge fixes

### Exit Codes

The check script returns:
- `0`: No issues detected
- `1`: General networking issues
- `2`: Specific CNI bridge IP conflicts detected

## Usage Examples

### Check for Issues
```bash
./scripts/check_cni_bridge_conflict.sh
```

### Apply Fix
```bash
./scripts/fix_cni_bridge_conflict.sh
```

### Test the Fix
```bash
./scripts/test_cni_bridge_fix.sh
```

### Monitor Results
```bash
# Check pod status
kubectl get pods --all-namespaces | grep ContainerCreating

# Check events for errors
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -10

# Check CNI bridge
ip addr show cni0
```

## Prevention

This issue typically occurs when:
- Previous cluster deployments left conflicting network state
- Network interfaces were not properly cleaned up
- Different CNI plugins were tried and left residual configuration

The fix ensures clean network state for reliable pod creation.

## Troubleshooting

If the automatic fix doesn't work:

1. **Check containerd status**: `sudo systemctl status containerd`
2. **Check Flannel logs**: `kubectl logs -n kube-flannel -l app=flannel`
3. **Check node network config**: `ip addr show` and `ip route show`
4. **Manual cleanup**: 
   ```bash
   sudo ip link delete cni0
   sudo systemctl restart containerd
   kubectl delete pods -n kube-flannel --all
   ```

## Benefits

- **Minimal changes**: Surgically fixes only the specific CNI bridge issue
- **Safe operation**: Validates state before and after changes
- **Automatic integration**: Works with existing deployment and fix infrastructure
- **Non-destructive**: Preserves working pods and configurations
- **Comprehensive**: Handles the root cause rather than symptoms
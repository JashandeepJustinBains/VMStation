# VMStation CNI Bridge Fix - Enhanced Solution

## The Problem

Your Kubernetes cluster was experiencing CNI bridge IP conflicts preventing pods from starting:

```
Failed to create pod sandbox: plugin type="bridge" failed (add): failed to set bridge addr: "cni0" already has an IP address different from 10.244.1.1/24
```

This was causing:
- Jellyfin pod stuck in `ContainerCreating` 
- Connection refused error when testing http://192.168.4.61:30096/
- General pod networking failures

## The Root Cause

1. **CNI Bridge IP Mismatch**: The `cni0` bridge had an IP address outside the expected 10.244.x.x range
2. **Persistent Bridge State**: Even after cluster reset, the bridge interface kept its wrong IP
3. **Pod Sandbox Failures**: CNI plugin couldn't create pod network interfaces due to IP conflicts

## The Quick Fix

**IMMEDIATE SOLUTION** - Run this single command on the control plane:

```bash
sudo ./fix_jellyfin_immediate.sh
```

This command will:
1. ✅ Detect CNI bridge IP conflicts
2. ✅ Stop kubelet to prevent pod churn
3. ✅ Remove conflicting CNI bridge interfaces
4. ✅ Clear CNI network state
5. ✅ Restart Flannel networking
6. ✅ Recreate Jellyfin pod with correct networking
7. ✅ Verify the fix works

## Comprehensive Fix

If you prefer the full solution approach:

```bash
./fix-cluster.sh
```

## What Changed

### Enhanced Cluster Reset (deploy-cluster.sh)
The cluster reset process now includes:
- **CNI Bridge Cleanup**: Explicitly removes `cni0`, `flannel.1`, and `docker0` interfaces
- **CNI State Clearing**: Removes `/var/lib/cni/` directory
- **Proper Interface Reset**: Ensures no stale network interfaces persist

### Corrected Verification URL
Updated the Ansible verification task to check the correct URL:
- **Before**: `http://192.168.4.61:30096/`
- **After**: `http://192.168.4.61:30096/web/#/home.html`

### Immediate Fix Script
Created `fix_jellyfin_immediate.sh` for targeted fixes without full reset:
- Detects CNI bridge conflicts automatically
- Applies minimal fix without cluster disruption
- Monitors Jellyfin pod startup progress
- Provides clear success/failure feedback

## How to Use It

### Option 1: Immediate Fix (Recommended)
```bash
# SSH to control plane (192.168.4.63) as root
sudo ./fix_jellyfin_immediate.sh
```

### Option 2: Enhanced Reset
```bash
# Enhanced reset that properly cleans CNI state
./deploy-cluster.sh reset
```

### Option 3: Comprehensive Solution
```bash
./fix-cluster.sh
```

## After Running the Fix

1. **Check pod status**:
   ```bash
   kubectl get pods --all-namespaces
   ```

2. **Verify CNI bridge**:
   ```bash
   ip addr show cni0
   # Should show IP like 10.244.0.1/16
   ```

3. **Access Jellyfin**:
   - Main URL: http://192.168.4.61:30096
   - Direct home: http://192.168.4.61:30096/web/#/home.html

## Validation

The verification task now properly checks:
- Jellyfin pod in Running state
- Correct CNI bridge IP range
- Proper service endpoint accessibility
- Enhanced error reporting for CNI issues

## What's Different from Before

### Enhanced Reset Process
- **OLD**: Reset left CNI bridge interfaces with wrong IPs
- **NEW**: Explicitly removes all CNI network interfaces and state

### Targeted Fix Capability  
- **OLD**: Required full cluster reset for CNI issues
- **NEW**: Immediate fix script for quick resolution

### Correct URL Validation
- **OLD**: Checked generic endpoint that might not reflect real state
- **NEW**: Checks the actual Jellyfin web interface URL

## Success Criteria

After running the fix, you should have:

- ✅ Jellyfin pod in Running state (not ContainerCreating)
- ✅ CNI bridge with 10.244.x.x IP range
- ✅ Successful connection to http://192.168.4.61:30096/web/#/home.html
- ✅ No CNI bridge conflict events in cluster logs
- ✅ All Flannel pods running properly

## Troubleshooting

If issues persist:

1. **Check CNI bridge status**:
   ```bash
   ip addr show cni0
   ```

2. **Check recent events**:
   ```bash
   kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -10
   ```

3. **Check Flannel logs**:
   ```bash
   kubectl logs -n kube-flannel -l app=flannel
   ```

4. **Manual CNI reset** (if needed):
   ```bash
   sudo scripts/fix_cni_bridge_conflict.sh
   ```

## Why This Works

The fix addresses the actual root cause:

1. **Proper CNI State Management**: Ensures clean network interface state
2. **Enhanced Reset Process**: Removes all CNI artifacts during reset
3. **Targeted Fix Option**: Allows quick fixes without full cluster rebuild
4. **Correct Verification**: Tests the actual endpoint users will access

Your cluster now properly handles CNI bridge state and can recover from network interface conflicts automatically.
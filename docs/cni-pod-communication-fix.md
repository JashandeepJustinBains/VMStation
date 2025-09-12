# CNI Pod Communication Fix

This document describes the solution for the CNI communication issue where pods cannot reach each other, specifically addressing the problem where a debug pod (10.244.0.20) on storagenodet3500 cannot ping the Jellyfin pod (10.244.0.19) on the same node with "Destination Host Unreachable" errors.

## Problem Analysis

The issue manifests as:
- Debug pod IP: `10.244.0.20/16` on storagenodet3500
- Jellyfin pod IP: `10.244.0.19/16` on storagenodet3500  
- Both pods are on the same worker node
- Ping fails with "Destination Host Unreachable"
- HTTP connectivity to pod fails: `curl http://10.244.0.19:8096/`
- External connectivity also fails: `curl https://repo.jellyfin.org/...`

This indicates a CNI bridge/routing issue on the worker node, not the control plane.

## Root Cause

The existing scripts primarily focused on control plane CNI issues. However, this is a worker node (storagenodet3500) specific problem where:

1. **CNI bridge misconfiguration**: The `cni0` bridge on the worker node has incorrect IP or routing
2. **Flannel configuration issues**: Mixed-OS environment may need specialized Flannel config
3. **veth interface problems**: Pod network interfaces not properly connected to bridge
4. **iptables rules**: Local pod-to-pod traffic may be blocked

## Solution Components

### 1. Worker Node CNI Fix (`scripts/fix_worker_node_cni.sh`)

**Purpose**: Targets specific worker node CNI issues including bridge configuration and pod connectivity.

**Key Features**:
- Detects and fixes CNI bridge IP conflicts on worker nodes
- Restarts Flannel pods on specific nodes
- Tests pod-to-pod connectivity with actual network tests
- Handles both control plane and worker node scenarios
- Provides detailed diagnostics for CNI bridge status

**Usage**:
```bash
sudo ./scripts/fix_worker_node_cni.sh --node storagenodet3500
```

### 2. Pod Connectivity Validation (`scripts/validate_pod_connectivity.sh`)

**Purpose**: Recreates the exact scenario from the problem statement for validation.

**Key Features**:
- Creates debug pod exactly as in problem statement (`nicolaka/netshoot` on storagenodet3500)
- Tests connectivity to Jellyfin pod (10.244.0.19:8096)
- Tests external connectivity to repo.jellyfin.org
- Provides comprehensive network diagnostics
- Reports specific failure modes matching the problem

**Usage**:
```bash
./scripts/validate_pod_connectivity.sh
```

### 3. Flannel Mixed-OS Fix (`scripts/fix_flannel_mixed_os.sh`)

**Purpose**: Optimizes Flannel configuration for mixed OS environments.

**Key Features**:
- Detects Windows/Linux mixed environments
- Applies VXLAN backend for cross-platform compatibility
- Updates ConfigMap with optimized settings
- Restarts Flannel pods with new configuration
- Tests pod creation and inter-node connectivity

**Usage**:
```bash
./scripts/fix_flannel_mixed_os.sh
```

### 4. Enhanced Main Fix Script

The main `scripts/fix_cluster_communication.sh` now includes:
- Integration of all worker node CNI fixes
- Pod-to-pod connectivity validation
- Better error handling and diagnostics collection
- Comprehensive validation steps

## Fix Workflow

### Quick Fix (Recommended)
```bash
sudo ./scripts/fix_cluster_communication.sh
```
This runs all fixes automatically in the correct order.

### Manual Step-by-Step Fix
1. **Worker node CNI fix**:
   ```bash
   sudo ./scripts/fix_worker_node_cni.sh --node storagenodet3500
   ```

2. **Flannel configuration fix**:
   ```bash
   ./scripts/fix_flannel_mixed_os.sh
   ```

3. **Validate the fix**:
   ```bash
   ./scripts/validate_pod_connectivity.sh
   ```

## Expected Outcomes

After running the fixes:

✅ **Pod-to-Pod Connectivity**: Debug pod (10.244.0.20) can ping Jellyfin pod (10.244.0.19)
✅ **HTTP Connectivity**: `curl http://10.244.0.19:8096/` succeeds
✅ **External Connectivity**: `curl https://repo.jellyfin.org/files/plugin/manifest.json` works
✅ **Jellyfin Health Probes**: Start passing and pod becomes Ready
✅ **CNI Bridge**: Has correct IP in 10.244.0.0/16 subnet
✅ **Flannel**: Properly configured for the environment

## Technical Details

### CNI Bridge Reset Process
1. Stop kubelet to prevent pod churn
2. Remove misconfigured `cni0` bridge
3. Clear CNI state in `/var/lib/cni`
4. Restart containerd and kubelet
5. Wait for Flannel to recreate bridge with correct IP

### Flannel Configuration Optimizations
- **VXLAN Backend**: Better for mixed OS environments
- **Force Address**: Ensures proper IP delegation
- **Standard Subnet**: Uses 10.244.0.0/16 consistently
- **Port Configuration**: Explicit VXLAN port settings

### Validation Tests
- Creates test pods on target nodes
- Tests ping connectivity between pods
- Tests HTTP connectivity to application pods
- Validates DNS resolution
- Checks external network access

## Troubleshooting

### If fixes don't work immediately:
1. **Check CNI bridge**: `ip addr show cni0`
2. **Check Flannel logs**: `kubectl logs -n kube-flannel -l app=flannel`
3. **Check iptables**: `iptables -t nat -L | grep CNI`
4. **Restart networking**: `sudo systemctl restart containerd kubelet`

### Common issues:
- **Bridge has wrong IP**: Run CNI bridge fix again
- **Flannel pods not starting**: Check node resources and tolerations
- **External connectivity fails**: May be DNS/routing, not CNI
- **Persistent issues**: Consider full node restart

## Files Modified/Added

### New Scripts:
- `scripts/fix_worker_node_cni.sh` - Worker node specific CNI fixes
- `scripts/validate_pod_connectivity.sh` - Problem statement scenario validation
- `scripts/fix_flannel_mixed_os.sh` - Flannel configuration optimization
- `test_cni_fix_scripts.sh` - Comprehensive testing script

### Modified Scripts:
- `scripts/fix_cluster_communication.sh` - Enhanced with new fixes

## Testing

Run the test suite to validate all scripts:
```bash
./test_cni_fix_scripts.sh
```

This confirms:
- All scripts are executable and syntactically correct
- Integration between scripts works properly
- Error handling is appropriate
- Problem statement scenario is addressed

## Summary

This solution provides a comprehensive fix for CNI pod communication issues, specifically targeting the worker node problems that existing scripts didn't address. The fixes are designed to be minimal, targeted, and safe, with extensive validation to ensure the problem is resolved.
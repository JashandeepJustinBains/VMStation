# Kubelet.conf Recovery Fix

## Problem Addressed

After spindown operations, worker nodes fail to start kubelet service with error:
```
failed to run Kubelet: unable to load kubeconfig: stat /etc/kubernetes/kubelet.conf: no such file or directory
```

This occurs because the spindown process removes `/etc/kubernetes/kubelet.conf` on worker nodes (192.168.4.62), which contains the kubeconfig needed for kubelet to connect to the API server.

## Solution Implemented

Two-pronged approach for robust kubelet.conf management:

### 1. Prevention (Enhanced Spindown)

**File:** `ansible/subsites/00-spindown.yaml`

- **Backup**: Automatically backs up worker `kubelet.conf` before cleanup
- **Selective cleanup**: Preserves worker kubelet.conf during `/etc/kubernetes` cleanup  
- **Restoration**: Restores kubelet.conf after cleanup for faster recovery
- **Scope**: Only applies to worker nodes, not control plane

### 2. Recovery (Enhanced Setup)

**File:** `ansible/plays/kubernetes/setup_cluster.yaml`

- **Validation**: Checks kubelet.conf content validity on worker startup
- **Auto-recovery**: Attempts to copy valid kubelet.conf from control plane
- **Fallback**: Triggers worker rejoin process if recovery fails
- **Guidance**: Provides clear status and next steps for operators

## Usage

### Normal Operation
No operator intervention required. The fix handles kubelet.conf issues automatically:

1. **During spindown**: Worker kubelet.conf is preserved
2. **During setup**: Missing or invalid kubelet.conf is detected and recovered

### Manual Recovery (if needed)
If automatic recovery fails, the playbook will display:
```
Action required: Worker node needs to rejoin the cluster
Run: kubeadm reset -f && <join-command>
```

### Testing
Validate the fix is working:
```bash
./test_kubelet_conf_recovery.sh
```

## Benefits

- **Prevents** kubelet.conf loss during spindown operations
- **Recovers** automatically when kubelet.conf is missing or corrupted  
- **Maintains** existing functionality and error handling
- **Provides** clear operator guidance for edge cases
- **Faster** recovery by avoiding unnecessary worker rejoin operations

## Files Modified

- `ansible/plays/kubernetes/setup_cluster.yaml` - Enhanced worker kubelet recovery
- `ansible/subsites/00-spindown.yaml` - Selective cleanup with kubelet.conf preservation
- `test_kubelet_conf_recovery.sh` - Comprehensive test validation (new)

## Compatibility

- Works with existing deployment workflows
- Maintains backward compatibility
- Tested with all existing kubelet recovery scenarios
- Safe for RHEL 10+ and Debian-based worker nodes
# VMStation CNI Namespace Termination Resolution

## Problem
The `fix-cluster.sh` script was failing with the error:
```
serviceaccounts "flannel" is forbidden: unable to create new content in namespace kube-flannel because it is being terminated
```

This occurred because the Ansible playbook was:
1. Deleting the `kube-flannel` namespace
2. Immediately trying to apply a new flannel manifest that recreates the same namespace
3. Kubernetes hadn't finished terminating the old namespace yet

## Root Cause
Kubernetes namespace deletion is asynchronous. When you delete a namespace, it enters a "Terminating" state and rejects new resource creation until termination completes. The original playbook only waited 30 seconds after deletion before trying to recreate resources.

## Solution Implemented

### 1. Separated Resource and Namespace Deletion
- First remove DaemonSet, Deployment, and other resources
- Then remove the namespace separately
- This ensures proper cleanup order

### 2. Added Proper Namespace Termination Waiting
- Wait up to 120 seconds for namespace to finish terminating
- Use Kubernetes wait conditions to detect completion
- Monitor for "Terminating" status to become "False"

### 3. Force Cleanup for Stuck Namespaces  
- If namespace gets stuck in terminating state (common with finalizers)
- Automatically patch to remove finalizers: `kubectl patch namespace kube-flannel -p '{"metadata":{"finalizers":[]}}' --type=merge`
- Wait additional time for cleanup to complete

### 4. Added Retry Logic for Manifest Application
- Retry flannel manifest application up to 5 times
- 15-second delay between retries
- Handles remaining race conditions gracefully

### 5. Enhanced Logging and Diagnostics
- Report namespace wait results
- Log cleanup status at each step
- Clear success/failure indicators
- Verify namespace is completely removed before proceeding

## Files Modified
- `ansible/playbooks/minimal-network-fix.yml` - Enhanced namespace cleanup logic

## How It Works
1. **Remove Resources First**: Delete DaemonSet and other resources from kube-flannel namespace
2. **Remove Namespace**: Delete the kube-flannel namespace separately  
3. **Wait Properly**: Use k8s_info with wait conditions to monitor termination
4. **Force Cleanup**: If termination stalls, remove finalizers to unstick it
5. **Verify Removal**: Double-check namespace is gone before proceeding
6. **Retry Application**: Apply flannel manifest with retries to handle any remaining issues

## Testing
The solution includes comprehensive error handling and logging to make debugging easier if issues persist. The retry mechanism should handle most race conditions automatically.

## Expected Behavior
After this change, `fix-cluster.sh` should:
- ✅ Successfully clean up old kube-flannel resources
- ✅ Wait for proper namespace termination  
- ✅ Apply new flannel manifest without forbidden errors
- ✅ Complete the full cluster recovery process
- ✅ Provide clear status messages throughout
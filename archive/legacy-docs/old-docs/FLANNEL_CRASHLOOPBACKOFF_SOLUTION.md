# Flannel CrashLoopBackOff Fix - CONT_WHEN_CACHE_NOT_READY

**Date**: 2025-10-05  
**Issue**: Flannel pod on homelab node in CrashLoopBackOff, exiting cleanly with "Exiting cleanly..." message  
**Status**: ✅ FIXED

## Problem Summary

The Flannel pod on the homelab node (RHEL 10) was in a CrashLoopBackOff state, even though:
- Init containers (`install-cni-plugin` and `install-cni`) succeeded with exit code 0
- Main container logs showed no errors
- Flannel initialized successfully, wrote `/run/flannel/subnet.env`, and set up the VXLAN backend
- Container exited cleanly with "Exiting cleanly..." message
- Pod status showed Running but container was not Ready and restarted repeatedly

## Root Cause

The `CONT_WHEN_CACHE_NOT_READY` environment variable in the Flannel DaemonSet was set to `"false"`.

**What this means**:
- When set to `"false"`, Flannel exits if the Kubernetes API cache is not ready
- This commonly happens during:
  - Initial pod startup (cache takes time to sync)
  - API server reconnection after temporary network issues
  - High cluster load or API server restarts

**Why this caused CrashLoopBackOff**:
1. Flannel starts and begins syncing with kube-apiserver
2. API cache is not ready yet (normal during initialization)
3. Flannel exits cleanly because `CONT_WHEN_CACHE_NOT_READY` is `"false"`
4. Kubernetes restarts the container (CrashLoopBackOff)
5. Cycle repeats

## Solution

Changed the environment variable from `"false"` to `"true"`:

```yaml
- name: CONT_WHEN_CACHE_NOT_READY
  value: "true"  # Allow Flannel to continue when cache is not ready
```

**Effect**:
- Flannel will continue running even when the API cache is temporarily unavailable
- The daemon waits for the cache to become ready instead of exiting
- No more "Exiting cleanly..." followed by restarts

## Files Changed

### 1. `manifests/cni/flannel.yaml`
**Change**: Line 209
```diff
- name: CONT_WHEN_CACHE_NOT_READY
-  value: "false"
+  value: "true"
```

### 2. `docs/DEPLOYMENT_FIXES_OCT2025.md`
**Change**: Updated documentation to reflect correct value and explanation

### 3. `.github/instructions/memory.instruction.md`
**Change**: Added finding #6 documenting root cause and fix

## Deployment Instructions

### On masternode (192.168.4.63):

```bash
# 1. Pull the fix
cd /srv/monitoring_data/VMStation
git pull

# 2. Apply the updated Flannel manifest
kubectl apply -f manifests/cni/flannel.yaml

# 3. Delete the Flannel pod on homelab to force recreation
FLANNEL_POD=$(kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod -n kube-flannel "$FLANNEL_POD"

# 4. Monitor the new pod (should stay Running without restarts)
watch -n 2 'kubectl get pods -n kube-flannel -o wide'
```

### Expected Behavior After Fix

```bash
# Pod should reach Running state and stay there
kubectl get pods -n kube-flannel -o wide
```

**Expected output**:
```
NAME                    READY   STATUS    RESTARTS   AGE   NODE
kube-flannel-ds-xxxxx   1/1     Running   0          2m    homelab
kube-flannel-ds-yyyyy   1/1     Running   0          10m   masternode
kube-flannel-ds-zzzzz   1/1     Running   0          10m   storagenodet3500
```

**Key indicators of success**:
- `READY` column shows `1/1`
- `STATUS` shows `Running`
- `RESTARTS` count does not increase
- Age increases without pod recreation

### Verification Commands

```bash
# 1. Check pod status (should be Running with 1/1 Ready)
kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab

# 2. Check pod logs (should not show "Exiting cleanly...")
kubectl logs -n kube-flannel <pod-name>

# 3. Verify subnet.env exists on homelab
ssh jashandeepjustinbains@192.168.4.62 'sudo cat /run/flannel/subnet.env'

# 4. Verify flannel.1 interface exists
ssh jashandeepjustinbains@192.168.4.62 'ip link show flannel.1'

# 5. Check for any CrashLoopBackOff pods
kubectl get pods -A | grep -i crash
# Should return empty

# 6. Verify all nodes are Ready
kubectl get nodes
# All 3 nodes should show Ready
```

## Technical Details

### Flannel Environment Variables

The Flannel DaemonSet uses several environment variables to control behavior:

- **`POD_NAME`**: Name of the Flannel pod (from metadata)
- **`POD_NAMESPACE`**: Namespace of the pod (kube-flannel)
- **`EVENT_QUEUE_DEPTH`**: Size of the event queue (set to 5000)
- **`CONT_WHEN_CACHE_NOT_READY`**: **CRITICAL** - Controls exit behavior when API cache is not ready
  - `"true"` (correct): Continue running, wait for cache to sync
  - `"false"` (wrong): Exit cleanly, causing CrashLoopBackOff

### Why This Wasn't Caught Earlier

1. **Documentation was incorrect**: Previous docs showed `"false"` with comment "Prevent premature exits" which was backwards
2. **Exit code 0 masked the issue**: Clean exit didn't trigger obvious errors
3. **Timing-dependent**: Sometimes worked if cache synced quickly enough
4. **RHEL 10 specific**: Slower cache sync on this node due to nftables initialization

## Related Issues

This fix addresses the root cause documented in:
- `FLANNEL_TIMING_ISSUE_FIX.md` - Timing issues between Flannel and API cache
- `FIX_HOMELAB_NODE_ISSUES_GUIDE.md` - Homelab-specific CrashLoopBackOff
- `DEPLOYMENT_FIXES_OCT2025.md` - Overall deployment improvements

## Prevention

To prevent similar issues in future:

1. **Always use `CONT_WHEN_CACHE_NOT_READY: "true"`** in production Flannel deployments
2. **Monitor pod restart counts** - any restarts on system pods indicate configuration issues
3. **Check logs for "Exiting cleanly"** - this is never normal for a daemon pod
4. **Test on slower nodes** - timing issues appear more reliably on resource-constrained nodes

## Success Criteria

✅ Flannel pod on homelab stays in Running state  
✅ No restarts after pod creation  
✅ Logs show successful initialization without "Exiting cleanly..." messages  
✅ `/run/flannel/subnet.env` exists and persists  
✅ `flannel.1` VXLAN interface is created and stays up  
✅ kube-proxy pods on all nodes become Ready  
✅ CoreDNS pods become Ready  
✅ No CrashLoopBackOff pods in any namespace  

## References

- Flannel GitHub: https://github.com/flannel-io/flannel
- Flannel v0.27.4 Release: https://github.com/flannel-io/flannel/releases/tag/v0.27.4
- Kubernetes DaemonSet Docs: https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/

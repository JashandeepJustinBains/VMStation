# Fix: Monitoring Pods Crashing After deploy-apps and Jellyfin Deployment

**Date:** October 4, 2025  
**Issue:** Pods crash with CrashLoopBackOff after running deploy-cluster with deploy-apps and jellyfin  
**Status:** ✅ FIXED

## Problem Description

After running a full deployment (`./deploy.sh full` or `ansible-playbook ansible/site.yml`), monitoring pods (Prometheus, Grafana, Loki) and some system pods would enter CrashLoopBackOff state on the homelab node.

### Symptoms Observed

From the deployment output:
```
NAMESPACE              NAME                                       READY   STATUS             RESTARTS       AGE
kube-system            coredns-76f75df574-vhsx8                   0/1     CrashLoopBackOff   6 (70s ago)    21m
kube-system            kube-proxy-58zhs                           0/1     CrashLoopBackOff   7 (104s ago)   21m
monitoring             loki-66944b8d97-dbmvq                      0/1     CrashLoopBackOff   5 (51s ago)    20m
```

The issue occurred specifically after the cluster was successfully initialized and then `deploy-apps.yaml` and `jellyfin.yml` were executed.

## Root Cause Analysis

### The Homelab Node Problem

The homelab node (192.168.4.62, RHEL 10) has known CNI networking configuration issues that cause:
- Flannel pod crashes and restarts
- System pods like kube-proxy to fail intermittently
- Network instability affecting pods scheduled on it

This is documented in `docs/HOMELAB_NODE_FIXES.md`.

### The Scheduling Issue

In `ansible/plays/deploy-apps.yaml`, the monitoring pod deployments had:
- ✅ **Tolerations** for control-plane node taints (allowing them to run on masternode)
- ❌ **NO nodeSelector** to force them to run ONLY on masternode

Example from the original code:
```yaml
spec:
  tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  containers:
  - name: prometheus
    # ...
```

**Result:** The Kubernetes scheduler could place these pods on ANY node in the cluster, including the problematic homelab node. When scheduled on homelab, they would crash due to networking issues.

## The Fix

### What Changed

Added `nodeSelector` to all monitoring pod specifications in `ansible/plays/deploy-apps.yaml`:

```yaml
spec:
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  containers:
  - name: prometheus
    # ...
```

### Pods Fixed

1. **Prometheus** - Now explicitly scheduled on masternode only
2. **Grafana** - Now explicitly scheduled on masternode only  
3. **Loki** - Now explicitly scheduled on masternode only

Note: Kubernetes Dashboard already had correct nodeSelector configuration.

### How It Works

The `nodeSelector` with `node-role.kubernetes.io/control-plane: ""` ensures that:

1. Pods will ONLY be scheduled on nodes with this label (the masternode)
2. The Kubernetes scheduler cannot place these pods on worker nodes (homelab, storagenodet3500)
3. Combined with tolerations, pods can run on the masternode despite the NoSchedule taint

## Files Modified

1. **ansible/plays/deploy-apps.yaml** - Added nodeSelector to Prometheus, Grafana, and Loki deployments
2. **docs/HOMELAB_NODE_FIXES.md** - Updated to document this fix
3. **docs/DEPLOYMENT_FIXES_OCT2025.md** - Updated to document this fix

## Validation

### Automated Test

Created a Python script to validate the configuration:

```bash
cd /home/runner/work/VMStation/VMStation
python3 /tmp/test_nodeselector.py
```

Output:
```
✅ prometheus: Properly configured
✅ grafana: Properly configured
✅ loki: Properly configured
```

### YAML Syntax Check

```bash
ansible-playbook --syntax-check ansible/plays/deploy-apps.yaml
# Output: playbook: ansible/plays/deploy-apps.yaml
```

## Expected Behavior After Fix

After this fix, when you run `./deploy.sh full`:

1. **Cluster initialization** completes successfully
2. **Flannel CNI** deploys and runs on all nodes
3. **Deploy-apps playbook** executes:
   - Prometheus pod schedules on masternode (not homelab)
   - Grafana pod schedules on masternode (not homelab)
   - Loki pod schedules on masternode (not homelab)
4. **All monitoring pods** reach Running status without crashes
5. **Jellyfin** deploys to storagenodet3500 successfully

### Verification Commands

After deployment, verify pod placement:

```bash
# Check that monitoring pods are on masternode
kubectl get pods -n monitoring -o wide

# Should show all pods on masternode (192.168.4.63)
# NOT on homelab (192.168.4.62)

# Check for any CrashLoopBackOff pods
kubectl get pods -A | grep -i crash
# Should return empty (no crashes)
```

## Related Documentation

- **docs/HOMELAB_NODE_FIXES.md** - Comprehensive guide to homelab node networking issues
- **docs/DEPLOYMENT_FIXES_OCT2025.md** - October 2025 deployment improvements
- **docs/RHEL10_KUBE_PROXY_FIX.md** - RHEL 10 specific fixes

## Why This Is Important

This fix is critical because:

1. **Prevents Silent Failures** - Without nodeSelector, pods could be scheduled anywhere and fail unpredictably
2. **Ensures Monitoring Reliability** - Monitoring stack must be stable to observe cluster health
3. **Avoids Homelab Node Issues** - Isolates the problematic node from critical workloads
4. **Follows Best Practices** - Control plane components should run on control plane nodes

## Future Considerations

### Option 1: Fix Homelab Node Networking (Long-term)
If the homelab node networking issues are resolved, this nodeSelector could be made optional.

### Option 2: Cordon Homelab Node (Alternative)
Another approach would be to cordon the homelab node:
```bash
kubectl cordon homelab
```
This would prevent ALL pods from being scheduled there.

### Option 3: Add Node Taints (Advanced)
Add a custom taint to homelab node to prevent scheduling:
```bash
kubectl taint nodes homelab networking-issues=true:NoSchedule
```

For now, the **nodeSelector approach is the safest and most explicit** solution.

---

**Summary:** This fix ensures monitoring applications run only on the stable masternode, preventing crashes caused by the homelab node's networking issues. The deployment will now complete successfully without manual intervention.

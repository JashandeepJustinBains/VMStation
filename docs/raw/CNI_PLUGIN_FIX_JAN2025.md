# CNI Plugin Installation Fix - January 2025

## Problem

The Jellyfin pod (and potentially other pods) on the `storagenodet3500` worker node was stuck in `Terminating` and `ContainerCreating` states with the following error:

```
Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox ...: 
plugin type="loopback" failed (add): failed to find plugin "loopback" in path [/opt/cni/bin]
```

### Root Cause

The CNI plugins (including the critical `loopback` plugin) were only being installed on the control plane node (`masternode`) during Phase 4 of the deployment. Worker nodes like `storagenodet3500` never received these plugins, so when pods tried to start, the container runtime could not set up the network sandbox.

**Why this happened:**
- Phase 4 (CNI Deployment) was scoped to `hosts: monitoring_nodes` only
- This meant only the masternode got the CNI plugins downloaded and extracted
- Worker nodes in `storage_nodes` group had the `/opt/cni/bin` directory created but it remained empty
- When Kubernetes tried to schedule pods on worker nodes, the CNI plugins were missing

## Solution

Moved the CNI plugin installation from Phase 4 to Phase 0 (System Preparation), which already targets both `monitoring_nodes` and `storage_nodes`.

### Changes Made

**File:** `ansible/playbooks/deploy-cluster.yaml`

1. **Phase 0 (lines 171-189):** Added CNI plugin installation tasks
   - Check if CNI plugins are already installed
   - Download CNI plugin tarball if needed
   - Extract plugins to `/opt/cni/bin`
   
2. **Phase 4 (lines 325-353):** Removed duplicate CNI plugin installation
   - Kept only the Flannel CNI deployment logic
   - Phase 4 now focuses solely on deploying the Flannel DaemonSet

### Why This Works

By installing CNI plugins in Phase 0:
- ✅ All Debian nodes get CNI plugins before cluster initialization
- ✅ Follows the gold-standard deployment pattern from legacy documentation
- ✅ Worker nodes have required plugins (`loopback`, `bridge`, `host-local`, `portmap`, etc.) when they join
- ✅ Pods can successfully create network sandboxes on any node
- ✅ Idempotent - re-running the playbook won't re-download if plugins already exist

## Verification

### Expected Result

After deploying with this fix:

```bash
# On storagenodet3500 (or any worker node)
ssh storagenodet3500 'ls -l /opt/cni/bin/'

# Should show multiple CNI plugin binaries:
# - loopback
# - bridge
# - host-local
# - portmap
# - bandwidth
# - firewall
# ... and others
```

### Test Pod Creation

```bash
# Deploy Jellyfin (or any pod) to storagenodet3500
kubectl apply -f manifests/jellyfin/jellyfin.yaml

# Pod should start successfully
kubectl get pod -n jellyfin -o wide

# Expected:
# NAME       READY   STATUS    RESTARTS   AGE   NODE
# jellyfin   1/1     Running   0          30s   storagenodet3500
```

### No More CNI Errors

Events should no longer show:
- ❌ `Failed to create pod sandbox: ... failed to find plugin "loopback"`
- ✅ Pod creates successfully with network sandbox initialized

## Industry Best Practice

This fix aligns with Kubernetes best practices:

1. **CNI plugins before cluster init:** Standard CNI plugins should be installed on all nodes before running `kubeadm init` or joining nodes
2. **Separation of concerns:** 
   - Phase 0: Install system prerequisites (CNI plugins, directories, containerd)
   - Phase 4: Deploy CNI network overlay (Flannel DaemonSet)
3. **All nodes equal:** Worker nodes need the same CNI plugins as the control plane

## References

- [GOLD_STANDARD_NETWORK_SETUP.md](../archive/legacy-docs/old-docs/GOLD_STANDARD_NETWORK_SETUP.md) - Phase 1 specifies CNI plugin installation on all nodes
- [CNI Plugin Documentation](https://github.com/containernetworking/plugins) - Standard CNI plugins repository
- [Kubernetes CNI Requirements](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/) - Network plugin documentation

## Related Issues

This fix also addresses:
- Pods stuck in `ContainerCreating` on worker nodes
- Network sandbox creation failures
- Intermittent pod scheduling issues when pods land on nodes without CNI plugins

---

**Status:** ✅ Fixed  
**Date:** January 2025  
**Impact:** All Debian worker nodes now have CNI plugins installed correctly

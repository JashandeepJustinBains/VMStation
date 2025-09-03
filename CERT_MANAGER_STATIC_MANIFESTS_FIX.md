# cert-manager Static Manifests Fix

## Problem Summary

The VMStation site.yaml playbook was stalling on cert-manager installation because worker nodes lacked the `/etc/kubernetes/manifests/` directory. When worker nodes are joined to the cluster using standard `kubeadm join` (without `--control-plane`), they don't get the static manifests directory that cert-manager expects to monitor.

## Root Cause

1. **Standard kubeadm join behavior**: Worker nodes joined with `kubeadm join` don't automatically get `/etc/kubernetes/manifests/` directory
2. **cert-manager expectation**: cert-manager watches for static pod manifests across all nodes in the cluster
3. **Missing directory causes hanging**: Without the manifests directory, cert-manager installation stalls

## Solution Implemented

Modified `ansible/plays/kubernetes/setup_cluster.yaml` to create the `/etc/kubernetes/manifests/` directory on worker nodes after successful cluster join.

### Changes Made

**File: `ansible/plays/kubernetes/setup_cluster.yaml`**

Added a new task block after successful worker node join:

```yaml
- name: Setup static manifests directory on worker nodes (for cert-manager compatibility)
  block:
    - name: Create /etc/kubernetes/manifests directory on worker nodes
      file:
        path: /etc/kubernetes/manifests
        state: directory
        owner: root
        group: root
        mode: '0755'
      
    - name: Display manifests directory setup completion
      debug:
        msg: "✓ Created /etc/kubernetes/manifests directory on worker node {{ inventory_hostname }} for cert-manager compatibility"
        
  when: kubelet_conf.stat.exists or (join_result is defined and (join_result.rc | default(0)) == 0)
```

## Architecture Considerations

This fix maintains the existing CNI architecture:

- **Control plane nodes**: Continue to host actual static manifests and CNI controllers
- **Worker nodes**: Get empty `/etc/kubernetes/manifests/` directory for cert-manager compatibility only
- **No CNI controllers on workers**: The directory is empty, preventing CNI conflicts documented in FLANNEL_CNI_CONTROLLER_FIX.md

## Files Modified

1. **`ansible/plays/kubernetes/setup_cluster.yaml`** - Added static manifests directory creation for worker nodes
2. **`test_cert_manager_manifests_fix.sh`** (NEW) - Validation script for the fix

## Usage

The fix is automatically integrated into the normal deployment process:

```bash
# Full deployment with fix
./update_and_deploy.sh

# Or cluster setup only
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml

# Or full Kubernetes stack
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes_stack.yaml
```

## Validation

Run the test script to validate the fix:

```bash
./test_cert_manager_manifests_fix.sh
```

## Expected Results

### Before Fix:
- ❌ Worker nodes lack `/etc/kubernetes/manifests/` directory
- ❌ cert-manager installation hangs waiting for static manifests
- ❌ site.yaml playbook stalls during cert-manager setup

### After Fix:
- ✅ Worker nodes have `/etc/kubernetes/manifests/` directory (empty)
- ✅ cert-manager installation proceeds without hanging
- ✅ site.yaml playbook completes successfully
- ✅ CNI architecture remains intact (no CNI controllers on workers)

## Technical Details

### Why This Works

cert-manager performs cluster-wide discovery and expects to be able to read static pod manifests from all nodes. By providing the directory structure on worker nodes (even if empty), cert-manager can complete its initialization without hanging.

### Why This is Safe

1. **Empty directory**: Worker nodes get an empty manifests directory, not actual static manifests
2. **No CNI conflicts**: Maintains the control-plane-only CNI architecture
3. **Minimal change**: Only creates a directory, doesn't modify cluster join behavior
4. **Idempotent**: Safe to run multiple times

## Integration with Existing Fixes

This fix complements the existing CNI architecture documented in:
- `FLANNEL_CNI_CONTROLLER_FIX.md` - Restricts CNI controllers to control plane
- `CERT_MANAGER_CNI_FIX.md` - CNI cleanup for cert-manager stability

The static manifests fix ensures cert-manager can initialize while preserving the centralized CNI control architecture.
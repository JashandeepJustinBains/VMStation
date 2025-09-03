# Flannel CNI Controller Placement Fix

## Problem Statement

The VMStation Kubernetes deployment was experiencing issues where:

1. **CNI0 interfaces were being created on worker nodes** (homelab servers) where they should not be
2. **Flanneld controller was running on worker nodes** instead of only on the masternode
3. **This caused cert-manager installs to hang** and prevented the rest of the playbook from completing

## Root Cause

The issue was caused by the default Flannel deployment manifest from upstream, which deploys Flannel as a DaemonSet that runs on **ALL** nodes in the cluster. This includes:

- Control plane nodes (masternode - 192.168.4.63)
- Worker nodes (storage - 192.168.4.61, compute - 192.168.4.62)

In VMStation's architecture, the network control should be centralized on the control plane, with worker nodes only participating in pod networking without running their own CNI controllers.

## Solution Implemented

### 1. Custom Flannel Manifest

Created `ansible/plays/kubernetes/templates/kube-flannel-masteronly.yml` with the following key changes:

- **nodeSelector**: `node-role.kubernetes.io/control-plane: ""`
- **Node Affinity**: Requires `node-role.kubernetes.io/control-plane` label to exist
- **Tolerations**: Only tolerates control plane taints, not general node taints
- **Removed**: General tolerations that allowed running on any node

### 2. Modified Cluster Setup

Updated `ansible/plays/kubernetes/setup_cluster.yaml` to:

- Copy the custom Flannel manifest to the control plane node
- Apply the custom manifest instead of the upstream one
- Remove reference to the upstream Flannel URL

### 3. Key Configuration Changes

```yaml
# Original (problematic)
tolerations:
- effect: NoSchedule
  operator: Exists  # This allowed running on ANY node

# Fixed (restrictive)
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
tolerations:
- key: node-role.kubernetes.io/control-plane
  operator: Exists
  effect: NoSchedule
- key: node-role.kubernetes.io/master
  operator: Exists
  effect: NoSchedule
```

## Files Modified

1. **`ansible/plays/kubernetes/templates/kube-flannel-masteronly.yml`** (NEW)
   - Custom Flannel manifest restricted to control plane nodes
   - Prevents CNI daemon from running on worker nodes

2. **`ansible/plays/kubernetes/setup_cluster.yaml`**
   - Modified to use custom manifest instead of upstream
   - Added task to copy custom manifest to target node

3. **`test_flannel_fix.sh`** (NEW)
   - Validation script to ensure the fix is properly implemented

## Expected Results

### Before (Issues):
- ❌ Flannel DaemonSet runs on all nodes
- ❌ CNI0 interfaces created on worker nodes (192.168.4.61, 192.168.4.62)
- ❌ Flanneld controller runs on homelab servers
- ❌ Cert-manager hangs due to network conflicts
- ❌ Playbook cannot complete

### After (Fixed):
- ✅ Flannel DaemonSet only runs on control plane (192.168.4.63)
- ✅ No CNI0 interfaces on worker nodes
- ✅ Flanneld controller only on masternode
- ✅ Cert-manager installs complete successfully
- ✅ Full playbook execution without hanging

## Validation

Run the validation script to confirm the fix:

```bash
./test_flannel_fix.sh
```

## Usage

Deploy with the fix using any of these methods:

```bash
# Full deployment
./update_and_deploy.sh

# Individual cluster setup
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml

# Full site deployment
ansible-playbook -i ansible/inventory.txt ansible/site.yaml
```

## Network Architecture

The fixed configuration establishes this network topology:

```
┌─────────────────────────────────────────────┐
│ Control Plane (192.168.4.63)               │
│ ┌─────────────────────────────────────────┐ │
│ │ Flannel Controller (flanneld)           │ │
│ │ - Manages pod network allocation        │ │
│ │ - Creates CNI0 interface                │ │
│ │ - Handles VXLAN tunnels                 │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
               │
               │ Network Management
               ▼
┌─────────────────────┐    ┌─────────────────────┐
│ Storage Node        │    │ Compute Node        │
│ (192.168.4.61)      │    │ (192.168.4.62)      │
│                     │    │                     │
│ ✅ Pod Networking   │    │ ✅ Pod Networking   │
│ ❌ No CNI0          │    │ ❌ No CNI0          │
│ ❌ No flanneld      │    │ ❌ No flanneld      │
└─────────────────────┘    └─────────────────────┘
```

This centralized approach prevents network conflicts and ensures stable cert-manager operation.

## Troubleshooting

If issues persist after applying this fix:

1. **Check Flannel pod placement:**
   ```bash
   kubectl get pods -n kube-flannel -o wide
   ```

2. **Verify node labels:**
   ```bash
   kubectl get nodes --show-labels | grep control-plane
   ```

3. **Check for CNI interfaces on worker nodes:**
   ```bash
   # Should return empty on worker nodes
   ssh root@192.168.4.61 "ip link show cni0" 2>/dev/null || echo "No CNI0 (good)"
   ssh root@192.168.4.62 "ip link show cni0" 2>/dev/null || echo "No CNI0 (good)"
   ```

4. **Validate cert-manager:**
   ```bash
   kubectl get pods -n cert-manager
   ```

This fix ensures that VMStation's Kubernetes networking follows the intended centralized control plane architecture.
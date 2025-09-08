# Taints and Tolerations Removal - Host-Based Targeting Fix

## Problem Resolved

The VMStation Kubernetes deployment was experiencing pod scheduling issues due to taints and tolerations overriding the intended host-based architecture. Pods were being scheduled on incorrect nodes instead of following the Ansible `hosts:` field targeting.

## Changes Made

### ❌ Removed Control-Plane Tolerations

**File: `ansible/plays/kubernetes/setup_cert_manager.yaml`**
- Removed tolerations for `node-role.kubernetes.io/control-plane` 
- Removed tolerations for `node-role.kubernetes.io/master`
- Removed nodeSelector logic and node labeling operations
- Result: cert-manager now deploys based on `hosts: monitoring_nodes`

**File: `ansible/plays/kubernetes/deploy_monitoring.yaml`**
- Removed complex node targeting logic with monitoring labels
- Simplified to use empty nodeSelector `{}`
- Removed conditional scheduling modes
- Result: Monitoring stack now deploys based on `hosts: monitoring_nodes`

### ✅ Preserved System Component Tolerations

**File: `ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml`**
- Kept Flannel tolerations: `operator: Exists, effect: NoSchedule`
- Reason: System networking component must run on all nodes

## Expected Deployment Behavior

After these changes, your deployments will follow the intended architecture:

| Component | Target Host | IP Address | Ansible Hosts Field |
|-----------|------------|------------|---------------------|
| **cert-manager** | masternode | 192.168.4.63 | `monitoring_nodes` |
| **Prometheus** | masternode | 192.168.4.63 | `monitoring_nodes` |
| **Grafana** | masternode | 192.168.4.63 | `monitoring_nodes` |
| **Loki** | masternode | 192.168.4.63 | `monitoring_nodes` |
| **Jellyfin** | storagenodet3500 | 192.168.4.61 | `storage_nodes` |
| **Compute workloads** | r430computenode | 192.168.4.62 | `compute_nodes` |
| **Flannel** | All nodes | - | DaemonSet with tolerations |

## How It Works Now

1. **Ansible `hosts:` field determines deployment location**
   - `hosts: monitoring_nodes` → deploys to masternode (192.168.4.63)
   - `hosts: storage_nodes` → deploys to storagenodet3500 (192.168.4.61)
   - `hosts: compute_nodes` → deploys to r430computenode (192.168.4.62)

2. **No tolerations to override targeting**
   - Pods will only schedule where Ansible places them
   - No more unexpected scheduling on wrong nodes

3. **System components preserved**
   - Flannel keeps tolerations to ensure cluster-wide networking
   - Local path provisioner runs where needed for storage

## Resolution of Original Issues

The scheduling errors you saw should be resolved:
```
Warning  FailedScheduling  0/2 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }
```

**Before**: Tolerations were causing conflicts with control-plane taints
**After**: No tolerations means no conflicts - Ansible determines placement

## Usage

Deploy as usual using your existing playbooks:

```bash
# Deploy cert-manager to masternode
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cert_manager.yaml

# Deploy monitoring stack to masternode  
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml

# Deploy Jellyfin to storage node
ansible-playbook -i ansible/inventory.txt ansible/plays/jellyfin.yml
```

Each component will deploy exactly where the `hosts:` field specifies in your inventory.

## Validation

You can verify the changes work correctly by running:

```bash
# Check that tolerations have been removed
grep -r "tolerations:" ansible/plays/kubernetes/setup_cert_manager.yaml
grep -r "tolerations:" ansible/plays/kubernetes/deploy_monitoring.yaml

# Should return no results (or only comments)
```

Your cluster should now respect the intended architecture with pods deploying to their designated nodes as specified in your Ansible inventory.
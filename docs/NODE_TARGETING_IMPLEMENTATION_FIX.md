# VMStation Node Targeting Implementation Fix

## Problem Addressed

The VMStation deployment was experiencing incorrect node targeting where:

1. **Monitoring stack** (Prometheus, Grafana, Loki, Kubernetes Dashboard) was deploying on the compute node (192.168.4.62) instead of the monitoring node (192.168.4.63)
2. **Jellyfin** was targeting the wrong node (homelab/192.168.4.62) instead of the storage node (storagenodet3500/192.168.4.61)
3. **Node selectors** were not being applied consistently across deployments

## Root Causes Identified

1. **Missing Configuration**: `ansible/group_vars/all.yml` was not present, causing deployment to use default/incorrect values
2. **Faulty Logic**: Monitoring deployment was setting `monitoring_node_selector: {}` (empty), allowing pods to schedule anywhere
3. **Wrong Target**: Jellyfin was configured to target `homelab` node instead of `storagenodet3500`
4. **Missing Integration**: Node labeling script existed but wasn't integrated into the deployment flow

## Solution Implemented

### 1. Configuration File Creation
- **File**: `ansible/group_vars/all.yml`
- **Source**: Created from `all.yml.template` with proper targeting configuration
- **Key Settings**:
  - `monitoring_scheduling_mode: flexible` - Enables label-based node selection
  - `jellyfin_node_name: storagenodet3500` - Targets correct storage node

### 2. Fixed Monitoring Deployment Logic
- **File**: `ansible/plays/kubernetes/deploy_monitoring.yaml`
- **Changes**: 
  - Replaced empty node selector logic with conditional selector based on scheduling mode
  - Added proper node selector: `{"node-role.vmstation.io/monitoring": "true"}`
  - Added node labeling setup task

### 3. Updated Application Deployment
- **File**: `ansible/plays/deploy-apps.yaml`
- **Changes**:
  - Added monitoring node labeling at deployment start
  - Updated all monitoring components (Prometheus, Grafana, Loki) to use `node-role.vmstation.io/monitoring=true`
  - Added Kubernetes Dashboard node targeting patches
  - Integrated storage node labeling for Jellyfin targeting

### 4. Fixed Jellyfin Node Targeting
- **File**: `ansible/plays/kubernetes/jellyfin-minimal.yml`
- **Changes**:
  - Updated node selector from `kubernetes.io/hostname: homelab` to `kubernetes.io/hostname: storagenodet3500`

### 5. Enhanced Deployment Script
- **File**: `deploy.sh`
- **Changes**:
  - Added automatic `all.yml` creation from template if missing
  - Integrated node labeling script execution if cluster is accessible
  - Enhanced error handling and logging

### 6. Node Labeling Integration
- **File**: `scripts/setup_monitoring_node_labels.sh` 
- **Enhancements**:
  - Added storage node detection and labeling
  - Improved error handling and validation
  - Better node name resolution logic

## Expected Results After Fix

### Monitoring Stack Placement
- **Prometheus**: Only on masternode (192.168.4.63)
- **Grafana**: Only on masternode (192.168.4.63)
- **Loki**: Only on masternode (192.168.4.63)
- **Kubernetes Dashboard**: Only on masternode (192.168.4.63)
- **AlertManager**: Only on masternode (192.168.4.63)

### Jellyfin Placement
- **Jellyfin Pod**: Only on storagenodet3500 (192.168.4.61)

### Universal Components (All Nodes)
- **Node Exporters**: On all nodes for metrics collection
- **kube-proxy**: On all nodes (system component)
- **Flannel CNI**: On all nodes (networking)

## Validation Commands

After deployment, verify correct placement:

```bash
# Check monitoring pod placement (should all be on masternode)
kubectl get pods -n monitoring -o wide

# Check Jellyfin placement (should be on storagenodet3500)  
kubectl get pods -n jellyfin -o wide

# Verify node labels
kubectl get nodes --show-labels | grep -E "(monitoring|storage)"

# Confirm no monitoring pods on compute node
kubectl get pods -n monitoring -o wide | grep 192.168.4.62 || echo "✓ No monitoring pods on compute node"
```

## Files Modified

1. `ansible/group_vars/all.yml` - Created from template with correct settings
2. `ansible/plays/kubernetes/deploy_monitoring.yaml` - Fixed node selector logic  
3. `ansible/plays/deploy-apps.yaml` - Added node targeting and labeling
4. `ansible/plays/kubernetes/jellyfin-minimal.yml` - Fixed storage node targeting
5. `deploy.sh` - Enhanced with node labeling integration
6. `scripts/setup_monitoring_node_labels.sh` - Improved node handling

## Deployment Flow

The updated deployment now follows this sequence:

1. **Configuration Setup**: Create `all.yml` from template if missing
2. **Pre-Deployment Labeling**: Run node labeling script if cluster accessible
3. **Cluster Setup**: Initialize or validate Kubernetes cluster
4. **Node Labeling**: Ensure monitoring and storage nodes are properly labeled
5. **Application Deployment**: Deploy monitoring stack with proper node targeting
6. **Jellyfin Deployment**: Deploy Jellyfin to storage node
7. **Validation**: Verify correct pod placement and accessibility

## Security Considerations

- `all.yml` remains gitignored for security (contains configuration that may include paths/settings)
- Node targeting reduces attack surface by isolating workloads
- Monitoring components are centralized on control plane for better security oversight

## Rollback Procedure

If issues occur, rollback steps:

```bash
# 1. Remove node labels
kubectl label nodes --all node-role.vmstation.io/monitoring-
kubectl label nodes --all node-role.vmstation.io/storage-

# 2. Restore previous configuration
git checkout HEAD~1 -- ansible/plays/deploy-apps.yaml ansible/plays/kubernetes/

# 3. Redeploy with previous configuration
./deploy.sh
```
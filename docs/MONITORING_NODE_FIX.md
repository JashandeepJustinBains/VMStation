# VMStation Monitoring Node Configuration Fix

This document describes the changes made to ensure that Kubernetes monitoring components (Prometheus, Alertmanager, Grafana, Loki) are deployed only on the masternode (192.168.4.63) and not on the homelab compute node (192.168.4.62).

## Problem Description

The monitoring stack was being deployed on the homelab node (192.168.4.62) instead of the masternode (192.168.4.63). This is problematic because:

1. The homelab node should be reserved for compute workloads
2. The masternode (control-plane) is the proper location for monitoring infrastructure
3. Improper node targeting can cause resource conflicts and scheduling issues

## Solution Implemented

### 1. Configuration File Setup

**File**: `ansible/group_vars/all.yml` (created from template)
**Key Setting**: `monitoring_scheduling_mode: flexible`

This configuration enables label-based node selection with the node selector `node-role.vmstation.io/monitoring=true`.

### 2. Node Labeling Script

**File**: `scripts/setup_monitoring_node_labels.sh`

This script ensures proper node labeling:
- Labels the masternode (192.168.4.63) with `node-role.vmstation.io/monitoring=true`
- Removes monitoring labels from homelab node (192.168.4.62) and storage node (192.168.4.61)
- Validates cluster connectivity and node availability

### 3. Enhanced Deployment Process

**Modified Files**:
- `ansible/plays/kubernetes/deploy_monitoring.yaml` - Added node labeling logic
- `ansible/deploy.sh` - Integrated node labeling setup
- `deploy_kubernetes.sh` - Created main Kubernetes deployment script

### 4. Deployment Flow Integration

The deployment now follows this sequence:
1. Setup monitoring permissions
2. **Setup monitoring node labels** (new step)
3. Deploy monitoring stack with proper node targeting
4. Validate deployment and node placement

## How to Deploy

### Automatic Deployment

Run the main deployment script:
```bash
./ansible/deploy.sh
```

This will:
1. Create `all.yml` from template if missing
2. Setup monitoring node labels automatically
3. Deploy monitoring stack to masternode

### Manual Steps (if needed)

If automatic setup fails, run manually:

```bash
# 1. Create configuration file
cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml

# 2. Setup node labels
./scripts/setup_monitoring_node_labels.sh

# 3. Deploy monitoring
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml
```

## Verification

After deployment, verify correct node placement:

```bash
# Check monitoring pod placement
kubectl get pods -n monitoring -o wide

# Verify node labels
kubectl get nodes --show-labels | grep monitoring

# Ensure no pods on homelab node (192.168.4.62)
kubectl get pods -n monitoring -o wide | grep 192.168.4.62
```

Expected result:
- All monitoring pods should be on masternode (192.168.4.63)
- No monitoring pods should be on homelab node (192.168.4.62)
- Only masternode should have `node-role.vmstation.io/monitoring=true` label

## Troubleshooting

### If monitoring pods are still on wrong nodes:

```bash
# Re-run node labeling
./scripts/setup_monitoring_node_labels.sh

# Force pod rescheduling
kubectl delete pods -n monitoring --all

# Wait for pods to reschedule on correct node
kubectl get pods -n monitoring -w
```

### If deployment fails:

```bash
# Check Kubernetes connectivity
kubectl cluster-info

# Verify node availability
kubectl get nodes

# Check for existing monitoring namespace issues
kubectl get ns monitoring
```

## Files Changed

### New Files:
- `scripts/setup_monitoring_node_labels.sh` - Node labeling automation
- `deploy_kubernetes.sh` - Main Kubernetes deployment script
- `ansible/group_vars/all.yml` - Configuration file (created from template)

### Modified Files:
- `ansible/plays/kubernetes/deploy_monitoring.yaml` - Enhanced node targeting
- `ansible/deploy.sh` - Added node labeling step

## Configuration Options

In `ansible/group_vars/all.yml`, the `monitoring_scheduling_mode` can be set to:

- `flexible` (recommended): Use label-based targeting with `node-role.vmstation.io/monitoring=true`
- `strict`: Use hostname-based targeting (may cause issues)
- `unrestricted`: Allow scheduling on any node (not recommended for production)

## Security Note

The `ansible/group_vars/all.yml` file is gitignored for security. The deployment scripts automatically create this file from the template if it doesn't exist. For production deployments, review and customize the configuration as needed.
# VMStation Node Targeting Architecture Fix

This document describes the fix for ensuring proper node targeting in the VMStation Kubernetes deployment according to the intended architecture.

## Problem Statement

The Kubernetes monitoring stack (Prometheus, Alertmanager, Grafana, Loki) was being deployed on the homelab compute node (192.168.4.62) instead of the intended masternode (192.168.4.63), violating the intended architecture.

## Intended Architecture

### Node Roles and Responsibilities

- **Masternode (192.168.4.63)**: Control-plane and monitoring infrastructure
  - cert-manager
  - coredns
  - etcd-masternode
  - kube-apiserver
  - kube-scheduler
  - Monitoring stack (Prometheus, Alertmanager, Grafana, Loki)

- **Homelab/Compute node (192.168.4.62)**: Compute workloads only
  - Drone CI

- **Storage node (192.168.4.61)**: Storage-specific workloads
  - Jellyfin

- **All nodes**: Monitoring helpers
  - kube-proxy
  - Node exporters

## Changes Made

### 1. Drone CI Node Targeting Fix

**File**: `ansible/subsites/07-drone-ci.yaml`

**Change**: Updated `apps_node` from `homelab` to `r430computenode`

```yaml
vars:
  # === Node Scheduling Configuration ===
  apps_node: r430computenode  # Changed from: homelab
```

**Impact**: Drone CI will now be scheduled on the correct compute node (192.168.4.62).

### 2. cert-manager Node Targeting Implementation

**File**: `ansible/plays/kubernetes/setup_cert_manager.yaml`

**Changes**:
1. Added node selector configuration to Helm values
2. Added monitoring node labeling logic

```yaml
# Node targeting for cert-manager components
nodeSelector:
  node-role.vmstation.io/monitoring: "true"
webhook:
  nodeSelector:
    node-role.vmstation.io/monitoring: "true"
cainjector:
  nodeSelector:
    node-role.vmstation.io/monitoring: "true"
```

**Impact**: All cert-manager components will be constrained to monitoring nodes only.

### 3. Validation Scripts

**New Files**:
- `test_node_targeting_fix.sh` - Static configuration validation
- `scripts/validate_node_targeting.sh` - Runtime deployment validation

## Validation

### Static Validation (Configuration Check)

Run the configuration test to verify all targeting rules are properly set:

```bash
./test_node_targeting_fix.sh
```

### Runtime Validation (Live Cluster Check)

Run the runtime validation to verify actual pod placement:

```bash
./scripts/validate_node_targeting.sh
```

## Deployment Impact

### Before Fix
- Monitoring components could be scheduled anywhere
- Drone CI was using incorrect node name
- cert-manager had no node constraints

### After Fix
- Monitoring components: Constrained to masternode (192.168.4.63)
- Drone CI: Targeted to compute node (192.168.4.62)
- cert-manager: Constrained to masternode (192.168.4.63)
- Jellyfin: Continues to target storage node (192.168.4.61)

## Troubleshooting

### If Components Are Still on Wrong Nodes

1. **Check node labels**:
   ```bash
   kubectl get nodes --show-labels | grep monitoring
   ```

2. **Re-run node labeling**:
   ```bash
   ./scripts/setup_monitoring_node_labels.sh
   ```

3. **Force pod rescheduling**:
   ```bash
   kubectl delete pods -n monitoring --all
   kubectl delete pods -n cert-manager --all
   kubectl delete pods -n drone --all
   ```

4. **Validate deployment**:
   ```bash
   ./scripts/validate_node_targeting.sh
   ```

### Expected Node Labels

The masternode should have the monitoring label:
```bash
kubectl get node masternode --show-labels | grep "node-role.vmstation.io/monitoring=true"
```

## Compatibility

This fix is backward-compatible and:
- ✅ Does not affect existing monitoring functionality
- ✅ Preserves existing Jellyfin placement
- ✅ Maintains existing node exporter deployment to all nodes
- ✅ Works with existing monitoring scheduling modes (flexible/strict/unrestricted)

## Security Considerations

- Node targeting helps maintain security boundaries between different workload types
- Monitoring infrastructure is isolated on the control-plane node
- Compute workloads are separated from control-plane components
- Storage workloads remain on dedicated storage infrastructure
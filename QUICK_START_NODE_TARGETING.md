# VMStation Node Targeting Fix - Quick Start Guide

## Overview
This fix ensures that VMStation components are deployed on their intended nodes according to the proper architecture.

## Architecture Summary
- **Masternode (192.168.4.63)**: Monitoring stack + cert-manager + control-plane
- **Compute node (192.168.4.62)**: Drone CI
- **Storage node (192.168.4.61)**: Jellyfin
- **All nodes**: kube-proxy + node exporters

## Quick Validation

### 1. Test Configuration (Always Available)
```bash
./test_node_targeting_fix.sh
```
This validates that all configuration files have proper node targeting settings.

### 2. Test Runtime Deployment (Requires Active Cluster)
```bash
./scripts/validate_node_targeting.sh
```
This validates that pods are actually running on the correct nodes.

## Deployment Order

For new deployments, follow this order to ensure proper node targeting:

1. **Deploy cluster and set up node labels**:
   ```bash
   ./scripts/setup_monitoring_node_labels.sh
   ```

2. **Deploy cert-manager** (will be constrained to masternode):
   ```bash
   ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cert_manager.yaml
   ```

3. **Deploy monitoring stack** (will be constrained to masternode):
   ```bash
   ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml
   ```

4. **Deploy Drone CI** (will be targeted to compute node):
   ```bash
   ansible-playbook -i ansible/inventory.txt ansible/subsites/07-drone-ci.yaml
   ```

5. **Deploy Jellyfin** (already targets storage node):
   ```bash
   ansible-playbook -i ansible/inventory.txt ansible/plays/jellyfin.yml
   ```

## Troubleshooting

If components are on wrong nodes after deployment:

1. **Check node labels**:
   ```bash
   kubectl get nodes --show-labels | grep monitoring
   ```

2. **Fix labeling**:
   ```bash
   ./scripts/setup_monitoring_node_labels.sh
   ```

3. **Force rescheduling**:
   ```bash
   kubectl delete pods -n monitoring --all
   kubectl delete pods -n cert-manager --all
   kubectl delete pods -n drone --all
   ```

4. **Validate**:
   ```bash
   ./scripts/validate_node_targeting.sh
   ```

## Files Changed
- `ansible/subsites/07-drone-ci.yaml` - Fixed Drone CI targeting
- `ansible/plays/kubernetes/setup_cert_manager.yaml` - Added cert-manager constraints

## Files Added
- `test_node_targeting_fix.sh` - Configuration validation
- `scripts/validate_node_targeting.sh` - Runtime validation
- `docs/NODE_TARGETING_FIX.md` - Detailed documentation
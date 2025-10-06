# CoreDNS Masternode Enforcement Fix

## Problem
CoreDNS pods were being scheduled on the "homelab" worker node (192.168.4.62) instead of staying on the "masternode" control-plane node (192.168.4.63), causing networking instability and DNS resolution issues.

## Root Cause
The previous implementation used `preferredDuringSchedulingIgnoredDuringExecution` which is only a soft preference. The Kubernetes scheduler could still place CoreDNS on worker nodes if it determined it was beneficial for load balancing or resource constraints.

## Solution
Changed CoreDNS scheduling from **preferred** to **required** node affinity for control-plane nodes using `requiredDuringSchedulingIgnoredDuringExecution`. This ensures CoreDNS will **always** be scheduled only on control-plane nodes and never on worker nodes like "homelab".

## Files Modified

### 1. `manifests/network/coredns-deployment.yaml`
- Added `requiredDuringSchedulingIgnoredDuringExecution` node affinity
- Ensures base CoreDNS deployment manifest enforces control-plane scheduling

### 2. `scripts/fix_homelab_node_issues.sh`
- Updated patch command to use required instead of preferred node affinity
- Changed warning message to reflect stronger enforcement

### 3. `ansible/plays/setup-cluster.yaml`
- Updated CoreDNS patching during cluster setup to use required node affinity
- Ensures enforcement is applied during initial cluster deployment

### 4. `scripts/test_coredns_masternode_scheduling.sh` (New)
- Test script to validate CoreDNS is properly scheduled only on control-plane nodes
- Checks deployment configuration and actual pod placement

## Validation
Run the test script to verify CoreDNS stays on masternode:
```bash
./scripts/test_coredns_masternode_scheduling.sh
```

## Expected Behavior
- CoreDNS pods will **only** be scheduled on nodes with `node-role.kubernetes.io/control-plane`
- CoreDNS will **never** be scheduled on worker nodes like "homelab" or "storagenodet3500"
- If control-plane nodes are unavailable, CoreDNS pods will remain pending rather than scheduling to worker nodes

## Technical Details
### Before (Soft Preference)
```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
```

### After (Hard Requirement)
```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
```

This change ensures CoreDNS will always stay on the masternode and never move to homelab or other worker nodes.
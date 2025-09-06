# cert-manager Control-Plane Taint Fix

## Problem
cert-manager pods were failing to schedule with the error:
```
1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }
```

This caused all cert-manager components (cert-manager, cert-manager-webhook, cert-manager-cainjector) to remain in `Pending` state.

## Root Cause
The cert-manager Helm configuration was missing tolerations for control-plane taints. While the pods were correctly targeted to the monitoring node (192.168.4.63) via node selectors, they couldn't be scheduled because that node has a control-plane taint that prevents regular workloads from being scheduled.

## Solution
Added tolerations to all cert-manager components in `ansible/plays/kubernetes/setup_cert_manager.yaml`:

```yaml
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
  - key: node-role.kubernetes.io/master
    operator: Exists
    effect: NoSchedule
```

These tolerations are applied to:
- `cert-manager` (root component)
- `cert-manager-webhook`
- `cert-manager-cainjector`

## How It Works
1. **Node Targeting**: Pods are still targeted to the monitoring node via `nodeSelector: node-role.vmstation.io/monitoring: "true"`
2. **Taint Tolerance**: Pods can now tolerate the control-plane taint, allowing them to be scheduled
3. **Legacy Compatibility**: Supports both modern (`control-plane`) and legacy (`master`) taint keys

## Validation
The fix has been validated with:
- ✅ Ansible playbook syntax check
- ✅ cert-manager timeout fixes test
- ✅ Node targeting fix test
- ✅ cert-manager manifests test
- ✅ Custom tolerations validation test

## Expected Result
After applying this fix, cert-manager pods should successfully schedule on the masternode (192.168.4.63) and move from `Pending` to `Running` state, resolving the installation failure.

## Architecture Compliance
This fix maintains the intended VMStation architecture:
- **Masternode (192.168.4.63)**: Control-plane + monitoring infrastructure (including cert-manager)
- **Compute node (192.168.4.62)**: Compute workloads (Drone CI)
- **Storage node (192.168.4.61)**: Storage workloads (Jellyfin)
# RHEL10 Manifests (Staging)

This directory is reserved for Kubernetes manifests targeting **RHEL10 compute/homelab** nodes.

## Purpose

Future manifests for:
- Node: homelab (192.168.4.62)
- OS: RHEL 10
- Role: Compute node

## Node Selectors

Manifests in this directory should target:
```yaml
nodeSelector:
  vmstation.io/role: compute
  # OR
  vmstation.io/platform: rhel
```

Or use nodeAffinity:
```yaml
nodeAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
    - matchExpressions:
      - key: vmstation.io/role
        operator: In
        values:
        - compute
        - homelab
```

## Current Status

**EMPTY** - No manifests currently target RHEL10 nodes

All current monitoring manifests are configured for control-plane (Debian) deployment.

When RHEL-specific workloads are added (e.g., compute-specific monitoring, RHEL-only services), place them here.

## Examples of Future Content

- RHEL-specific node-exporter configurations
- Compute workload monitoring
- RHEL10-specific DaemonSets
- Storage class manifests for RHEL nodes

## Migration

When ready to deploy RHEL-specific manifests:

```bash
# Create final directory
mkdir -p manifests/rhel10

# Move staging to final location
mv manifests/staging-rhel10/* manifests/rhel10/

# Deploy to cluster
for f in manifests/rhel10/*.yaml; do
  kubectl apply -f "$f"
done
```

---
**Status:** RESERVED - Awaiting RHEL-specific manifests
**Created:** 2025-10-09

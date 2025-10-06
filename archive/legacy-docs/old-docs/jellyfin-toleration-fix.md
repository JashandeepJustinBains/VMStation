# Jellyfin Toleration Fix Verification

## Problem Resolved

The Jellyfin pod deployment was failing with the error:
```
Pod "jellyfin" is invalid: spec.tolerations[0].effect: Invalid value: "NoSchedule": effect must be 'NoExecute' when `tolerationSeconds` is set
```

## Root Cause

In `manifests/jellyfin/jellyfin.yaml`, line 170 had:
```yaml
effect: "NoSchedule"
tolerationSeconds: 300
```

However, Kubernetes API validation requires that when `tolerationSeconds` is specified, the `effect` must be `NoExecute`.

## Fix Applied

Changed the first toleration from:
```yaml
- key: "node.kubernetes.io/network-unavailable"
  operator: "Exists"
  effect: "NoSchedule"        # ← This was incorrect
  tolerationSeconds: 300
```

To:
```yaml
- key: "node.kubernetes.io/network-unavailable"
  operator: "Exists"
  effect: "NoExecute"         # ← Now correct
  tolerationSeconds: 300
```

## Verification

All validation tests pass:
- ✅ No more NoSchedule+tolerationSeconds combinations
- ✅ Both tolerationSeconds entries use NoExecute effect
- ✅ YAML structure remains valid
- ✅ Expected tolerations are correctly configured

## Impact

This minimal change resolves the immediate deployment failure while maintaining the intended behavior:
- Pod can tolerate network-unavailable nodes for 300 seconds
- Pod can tolerate not-ready nodes for 300 seconds
- Both tolerations now comply with Kubernetes API requirements
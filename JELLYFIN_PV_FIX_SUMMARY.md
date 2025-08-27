# Jellyfin Persistent Volume Fix Summary

## Problem Resolved
The Ansible playbook was failing with immutable field errors when trying to update existing Jellyfin PersistentVolumes:
```
spec.persistentvolumesource is immutable after creation
nodeAffinity: field is immutable, except for updating from beta label to GA
```

## Root Cause
- Kubernetes PersistentVolume resources already existed with specific configurations
- The playbook was attempting to patch/update these resources with different values
- PersistentVolume spec fields are immutable after creation in Kubernetes

## Solution Implemented
Modified `ansible/plays/kubernetes/deploy_jellyfin.yaml` to:

1. **Check for existing PVs** before attempting creation
2. **Skip creation** if PVs already exist (avoiding immutable field conflicts)
3. **Proceed normally** if PVs don't exist
4. **Provide clear logging** about what actions are being taken

## Key Changes
- Added `Check if Jellyfin Persistent Volumes already exist` task
- Made PV creation conditional with `when: not (existing_pvs.results | selectattr(...).resources`
- Added informative debug messages for transparency
- Restructured PV definitions for easier conditional handling

## Benefits
✅ **Respects existing user configurations** - No disruption to statically assigned drives  
✅ **Eliminates immutable field errors** - Skips modification of existing resources  
✅ **Maintains full functionality** - All other deployment steps work unchanged  
✅ **Backwards compatible** - Works for both new and existing deployments  
✅ **Clear feedback** - Users see exactly what's happening with their PVs  

## User Impact
- Users with existing PVs can now run the playbook without errors
- Static drive assignments (like `/mnt/media` and `/srv/media`) are preserved
- No manual intervention required - the fix is automatic
- PVCs, deployments, services, and all other resources are managed normally

## Validation
- Comprehensive test suite validates all scenarios
- Syntax validation confirms no regressions
- Integration tests cover existing, missing, and mixed PV states

This fix allows the user to benefit from the full Jellyfin HA deployment while respecting their existing storage configuration.
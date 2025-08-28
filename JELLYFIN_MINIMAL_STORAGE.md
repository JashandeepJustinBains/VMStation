# Jellyfin Minimal Storage Deployment

This update adds support for simplified Jellyfin deployments that avoid persistent volume complexities.

## Problem Solved

The original deployment required Persistent Volumes (PV) and Persistent Volume Claims (PVC), which could cause:
- Storage size conflicts ("field can not be less than previous value")
- Complex storage class configuration
- Unnecessary deployment complexity for simple use cases

## Solution

Added a new configuration option `jellyfin_use_persistent_volumes` that allows choosing between:

1. **Minimal deployment** (default): Uses direct hostPath volumes
2. **Advanced deployment**: Uses Persistent Volumes for better storage management

## Configuration

In `ansible/group_vars/all.yml`:

```yaml
# === Jellyfin Storage Configuration ===
# Use persistent volumes (PV/PVC) for Jellyfin storage
# Set to false for minimal deployment using direct hostPath volumes
jellyfin_use_persistent_volumes: false  # Default: minimal deployment

# Path for Jellyfin configuration storage on storage nodes
jellyfin_config_path: /var/lib/jellyfin
```

## Benefits

### Minimal Deployment (jellyfin_use_persistent_volumes: false)
✅ **Simpler setup** - No PV/PVC configuration needed  
✅ **Fewer failure points** - Direct volume mounting  
✅ **No storage conflicts** - Avoids PVC size mismatches  
✅ **Faster deployment** - Skips PV/PVC creation steps  

### Advanced Deployment (jellyfin_use_persistent_volumes: true)
✅ **Better storage management** - Kubernetes-native volume handling  
✅ **Dynamic provisioning** - Can use storage classes  
✅ **Portability** - Easier to move between nodes  
✅ **Volume lifecycle management** - Automatic cleanup and retention  

## Usage

### For Minimal Deployment (Recommended)
Keep the default setting in your configuration:
```yaml
jellyfin_use_persistent_volumes: false
```

### For Advanced Deployment
Set in your configuration:
```yaml
jellyfin_use_persistent_volumes: true
```

## Migration

Existing deployments will continue to work. The default is now minimal deployment, but you can explicitly enable persistent volumes if needed.

## Fixed Issues

- ✅ Storage size conflicts between PV (100Ti) and PVC (2Ti) 
- ✅ Complex PV/PVC setup for simple deployments
- ✅ Unnecessary persistent volume creation
- ✅ Template and playbook storage size mismatches
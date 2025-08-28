# Jellyfin High-Availability Kubernetes Deployment

## Overview

This implementation provides a comprehensive, highly-available Jellyfin media server deployment on Kubernetes with auto-scaling capabilities. It replaces the existing single Podman container setup with a robust, scalable solution optimized for 1080p+ streaming to multiple devices.

## Features

### High Availability & Scalability
- **Auto-scaling**: 1-3 pods based on CPU (>60%) and memory (>70%) usage
- **Session affinity**: Users maintain connection to the same pod during streaming
- **Load balancing**: Automatic traffic distribution across available pods
- **Resource constraints**: 2-2.5GB RAM per pod (respecting 8GB system limit)
- **Anti-affinity**: Pods distributed across different nodes when possible

### Hardware Acceleration
- **Intel/AMD GPU support**: Intel QSV and AMD VAAPI acceleration
- **Codec support**: H.264, HEVC (H.265), VP9, AV1 for efficient transcoding
- **Hardware decoding**: Reduces CPU load for 4K content streaming
- **Optimized encoding**: Low-power encoding options for battery-powered devices

### Network Optimization
- **Large file support**: 50GB upload capacity for media management
- **Extended timeouts**: 10-minute timeouts for large file operations
- **Buffer optimization**: Optimized buffer sizes for streaming
- **Discovery protocols**: UDP ports for automatic client discovery

### Storage Integration
- **Persistent volumes**: Preserves existing media structure (configurable path)
- **Configuration persistence**: Uses existing `/mnt/jellyfin-config`
- **Read-only media**: Media directory mounted read-only for security
- **Node affinity**: Storage volumes tied to storage node (192.168.4.61)
- **Flexible media paths**: Supports `/srv/media` (default) or `/mnt/media` via configuration

### Monitoring Integration
- **ServiceMonitor**: Prometheus metrics collection
- **Grafana dashboard**: Visual monitoring of pod performance
- **Resource tracking**: CPU, memory, and scaling metrics
- **Health checks**: Liveness and readiness probes

## Architecture

```
┌─── Load Balancer (NodePort 30096) ───┐
│                                      │
├─ Pod 1 (2.5GB RAM) ─┐                │
├─ Pod 2 (2.5GB RAM) ─┼─ Session       │
├─ Pod 3 (2.5GB RAM) ─┘   Affinity     │
│                                      │
└─ Shared Storage (configurable) ──────┘
   └─ Config Storage (/mnt/jellyfin-config)
```

## Deployment

### Prerequisites

1. **Kubernetes cluster** running (monitoring_nodes as control plane)
2. **Storage node** with media directory and `/mnt/jellyfin-config` directories
   - Default media path: `/srv/media` (legacy NFS export location)
   - Alternative: `/mnt/media` (if using mounted storage)
   - Configurable via `jellyfin_media_path` in `ansible/group_vars/all.yml`
3. **Metrics server** installed for auto-scaling functionality
4. **Hardware acceleration** devices available (`/dev/dri`)

### Quick Deployment

```bash
# Deploy Jellyfin HA stack
./deploy_jellyfin.sh

# Validate deployment
./scripts/validate_jellyfin_ha.sh
```

### Manual Deployment

```bash
# Deploy via Ansible
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml

# Or deploy as part of full stack
./deploy_kubernetes.sh
```

### Configuration Options

To customize the media directory path, edit `ansible/group_vars/all.yml`:

```yaml
# === Jellyfin Media Configuration ===
# Path to existing media directory on storage nodes
jellyfin_media_path: /srv/media  # Default (legacy NFS export)
# jellyfin_media_path: /mnt/media  # Alternative (mounted storage)

# Skip mount verification for media directory (useful if directory is guaranteed to exist)
jellyfin_skip_mount_verification: false  # Set to true to bypass pre-deployment checks
```

**Common scenarios:**
- **Legacy setup**: Use `/srv/media` (default) - media served directly from storage node  
- **Mounted storage**: Use `/mnt/media` - media mounted from external NFS/storage
- **Custom path**: Any valid directory path on the storage node

**Mount verification options:**
- **Default behavior**: The deployment validates that the media directory exists before proceeding
- **Skip verification**: Set `jellyfin_skip_mount_verification: true` to bypass mount checks
- **When to skip**: Use when the media directory is guaranteed to exist (e.g., in automated deployments)

## Access Information

### Primary Access URLs
- **HTTP**: `http://192.168.4.63:30096` (monitoring node)
- **HTTPS**: `https://192.168.4.63:30920`
- **Direct Storage**: `http://192.168.4.61:30096` (storage node)

### Discovery Ports
- **DLNA Discovery**: UDP 1900 → NodePort 31900
- **Jellyfin Discovery**: UDP 7359 → NodePort 30735

## Auto-Scaling Behavior

### Scaling Triggers
- **Scale UP**: CPU > 60% OR Memory > 70%
- **Scale DOWN**: CPU < 60% AND Memory < 70% for 5+ minutes

### User Experience
- **1 User**: Single pod handles streaming efficiently
- **2-3 Users**: Additional pods spin up automatically
- **4+ Users**: Maximum 3 pods maintain performance
- **Session Persistence**: Users stay connected to same pod (3-hour timeout)

### Resource Management
```yaml
Resources per Pod:
  Requests: 500m CPU, 2Gi Memory
  Limits:   2000m CPU, 2.5Gi Memory
  
Total System Impact:
  Minimum: 1 pod × 2.5GB = 2.5GB RAM
  Maximum: 3 pods × 2.5GB = 7.5GB RAM (within 8GB limit)
```

## Configuration

### Hardware Acceleration
The deployment automatically configures:
- **VAAPI device**: `/dev/dri/renderD128`
- **Hardware encoding**: H.264, HEVC, VP9, AV1
- **Low-power modes**: Intel Quick Sync optimization
- **Device access**: Proper permissions for transcoding

### Network Settings
- **Published URL**: Auto-configured for load balancer
- **Local networks**: `192.168.4.0/24`, `10.244.0.0/16` (Kubernetes pods)
- **Remote access**: Enabled with security restrictions
- **Buffer sizes**: Optimized for high-bandwidth streaming

## Monitoring

### Kubernetes Resources
```bash
# Monitor pods
kubectl get pods -n jellyfin -w

# Check auto-scaling
kubectl get hpa -n jellyfin -w

# Resource usage
kubectl top pods -n jellyfin
```

### Grafana Dashboard
Access at `http://192.168.4.63:30300`:
- Pod status and count
- Memory usage per pod
- CPU utilization
- Scaling events

### Prometheus Metrics
- Service availability
- Resource consumption
- Scaling decisions
- Performance trends

## Migration from Podman

### Before Migration
1. **Backup configuration**: Ensure `/mnt/jellyfin-config` is backed up
2. **Note current settings**: Document any custom transcoding settings
3. **Check media access**: Verify `/mnt/media` is accessible

### During Migration
1. **Parallel deployment**: Kubernetes version runs alongside Podman
2. **Test thoroughly**: Verify all features work correctly
3. **Check performance**: Monitor resource usage and streaming quality

### After Migration
```bash
# Stop Podman container (when satisfied with K8s version)
ssh 192.168.4.61 'podman stop jellyfin'

# Remove Podman container (optional)
ssh 192.168.4.61 'podman rm jellyfin'
```

## Troubleshooting

### Common Issues

**Pods not starting**:
```bash
kubectl describe pod -n jellyfin -l app=jellyfin
kubectl logs -n jellyfin -l app=jellyfin
```

**Storage issues**:
```bash
kubectl get pv,pvc
kubectl describe pvc -n jellyfin
```

**Auto-scaling not working**:
```bash
kubectl top nodes
kubectl get hpa -n jellyfin -o yaml
```

**Hardware acceleration issues**:
```bash
# Check device availability on storage node
ssh 192.168.4.61 'ls -la /dev/dri/'

# Check pod mounts
kubectl exec -n jellyfin deployment/jellyfin -- ls -la /dev/dri/
```

**Deployment timeout issues**:
```bash
# Check pod status and events
kubectl get pods -n jellyfin
kubectl describe pods -n jellyfin
kubectl get events -n jellyfin --sort-by=.metadata.creationTimestamp

# Check deployment status
kubectl get deployment jellyfin -n jellyfin -o yaml

# Check logs for startup issues
kubectl logs -n jellyfin -l app=jellyfin
```

**Node affinity/scheduling issues**:
```bash
# Check node labels and ensure storage node is properly labeled
kubectl get nodes --show-labels | grep storagenodet3500

# Check for pods stuck in Pending due to node affinity
kubectl get pods -n jellyfin --field-selector=status.phase=Pending
kubectl describe pods -n jellyfin --field-selector=status.phase=Pending

# If pods fail with "node(s) didn't match Pod's node affinity/selector":
# 1. Delete the problematic deployment
kubectl delete deployment jellyfin -n jellyfin

# 2. Redeploy with correct configuration
./deploy_jellyfin.sh

# 3. Verify pods schedule on correct node
kubectl get pods -n jellyfin -o wide
```

**Note**: The deployment wait timeout is set to 2 minutes to quickly identify configuration issues, such as missing storage directories or hardware acceleration devices.

### Performance Optimization

**For 4K streaming**:
- Ensure hardware acceleration is working
- Monitor transcoding performance
- Consider adjusting CPU limits if needed

**For multiple concurrent streams**:
- Monitor memory usage during peak times
- Adjust HPA thresholds if scaling is too aggressive
- Check network bandwidth utilization

## Security Considerations

### Pod Security
- **Non-privileged**: Containers run with minimal privileges
- **Capability restrictions**: Only required capabilities granted
- **Read-only media**: Media directory mounted read-only

### Network Security
- **Local network restrictions**: Access limited to known subnets
- **Session timeouts**: Automatic session expiration
- **Health checks**: Regular service availability verification

## Maintenance

### Regular Tasks
- **Monitor resource usage**: Weekly review of scaling patterns
- **Update images**: Regular Jellyfin container updates
- **Check logs**: Review for any error patterns
- **Backup verification**: Ensure configuration backup is working

### Scaling Adjustments
```bash
# Adjust HPA thresholds
kubectl edit hpa jellyfin-hpa -n jellyfin

# Modify resource limits
kubectl edit deployment jellyfin -n jellyfin
```

## Integration with VMStation

This deployment integrates with the existing VMStation Kubernetes infrastructure:
- **Monitoring**: Uses existing Prometheus/Grafana stack
- **Storage**: Leverages existing storage node setup
- **Network**: Works with established network configuration
- **Security**: Follows VMStation security patterns

The deployment maintains compatibility with existing automation and monitoring while providing enterprise-grade media streaming capabilities.
# Jellyfin Migration Guide: Podman to Kubernetes

## Overview

This guide helps you migrate your existing Jellyfin Podman container to a high-availability Kubernetes deployment with 100% uptime and 4K streaming capabilities.

## Before You Start

### Current Podman Setup
Your existing setup likely includes:
- Jellyfin container running on storage node (192.168.4.61)
- Media stored in `/mnt/media/TV Shows` and `/mnt/media/Movies`
- Configuration in `/mnt/media/jellyfin-config`
- Port 8096 exposed for web access

### New Kubernetes Benefits
- **Zero Downtime**: Rolling updates with no service interruption
- **High Availability**: 2 pod replicas with automatic failover
- **Better Performance**: Resource limits optimized for 4K streaming
- **Monitoring Integration**: Built-in Prometheus metrics and health checks
- **Scalability**: Easy scaling for multiple concurrent streams

## Pre-Migration Checklist

### 1. Backup Current Setup
```bash
# Create backup directory
sudo mkdir -p /tmp/jellyfin_backup_$(date +%Y%m%d)

# Backup Jellyfin configuration
sudo tar -czf /tmp/jellyfin_backup_$(date +%Y%m%d)/jellyfin-config-backup.tar.gz /mnt/media/jellyfin-config

# Export current container configuration
podman inspect jellyfin > /tmp/jellyfin_backup_$(date +%Y%m%d)/jellyfin-container-config.json
```

### 2. Verify Kubernetes Cluster
```bash
# Ensure Kubernetes cluster is running
kubectl cluster-info

# Check available nodes
kubectl get nodes

# Verify storage directories
ls -la /mnt/media/
```

### 3. Check Media Library
```bash
# Verify media directories exist
ls -la "/mnt/media/TV Shows"
ls -la "/mnt/media/Movies"

# Check disk space
df -h /mnt/media
```

## Migration Process

### Option 1: Automated Migration (Recommended)
```bash
# Run the automated deployment script
./deploy_jellyfin_k8s.sh
```

This script will:
1. Automatically detect existing Podman container
2. Create backup of configuration
3. Gracefully stop Podman container
4. Deploy Kubernetes version with same configuration
5. Validate the new deployment

### Option 2: Manual Migration

#### Step 1: Stop Podman Container
```bash
# Stop existing Jellyfin container
podman stop jellyfin

# Optionally remove container (keeps data)
podman rm jellyfin
```

#### Step 2: Deploy Kubernetes Version
```bash
# Deploy with Ansible
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml -v

# Or deploy manually
kubectl apply -f k8s/jellyfin/namespace.yaml
kubectl apply -f k8s/jellyfin/persistent-volumes.yaml
kubectl apply -f k8s/jellyfin/deployment.yaml
kubectl apply -f k8s/jellyfin/service.yaml
```

#### Step 3: Validate Migration
```bash
# Run validation script
./scripts/validate_jellyfin_k8s.sh

# Check pod status
kubectl get pods -n jellyfin

# Test access
curl -f http://192.168.4.61:30096/health
```

## Post-Migration Configuration

### 1. Initial Access
- **URL**: http://192.168.4.61:30096
- **Admin Setup**: Complete initial setup wizard if needed
- **Libraries**: Verify existing libraries are detected

### 2. Library Paths (if reconfiguring)
```bash
# TV Shows: /media/tv
# Movies: /media/movies
# Mixed Content: /media
```

### 3. Transcoding Settings
The Kubernetes deployment includes optimized settings:
- **CPU Limit**: 4 cores per pod for transcoding
- **Memory Limit**: 8GB per pod for 4K content
- **Hardware Decoding**: Enabled for H.264, HEVC, VP9, AV1

### 4. Network Configuration
- **Local Network**: 192.168.4.0/24 and 10.244.0.0/16 are pre-configured
- **Remote Access**: Configure in Jellyfin settings if needed
- **HTTPS**: Optional - use ingress for TLS termination

## Troubleshooting

### Migration Issues

#### Configuration Not Preserved
```bash
# Check if config volume is mounted
kubectl describe pod -n jellyfin | grep -A 5 "Mounts:"

# Restore from backup if needed
kubectl cp /tmp/jellyfin_backup_*/jellyfin-config-backup.tar.gz jellyfin/<pod-name>:/tmp/
kubectl exec -n jellyfin deployment/jellyfin -- tar -xzf /tmp/jellyfin-config-backup.tar.gz -C /
```

#### Media Not Accessible
```bash
# Check volume mounts
kubectl exec -n jellyfin deployment/jellyfin -- ls -la /media

# Verify host directories
ansible storage_nodes -i ansible/inventory.txt -m shell -a "ls -la /mnt/media"

# Check permissions
ansible storage_nodes -i ansible/inventory.txt -m shell -a "ls -la '/mnt/media/TV Shows'"
```

#### Pods Not Starting
```bash
# Check pod events
kubectl describe pods -n jellyfin

# Check storage
kubectl get pv,pvc -n jellyfin

# Verify node labels
kubectl get nodes --show-labels
```

### Performance Issues

#### Poor Streaming Performance
```bash
# Check resource usage
kubectl top pods -n jellyfin

# Scale up if needed
kubectl scale deployment jellyfin -n jellyfin --replicas=3

# Check transcoding logs
kubectl logs -n jellyfin deployment/jellyfin | grep -i transcode
```

#### Storage I/O Issues
```bash
# Check disk I/O
ansible storage_nodes -i ansible/inventory.txt -m shell -a "iostat -x 1 5"

# Monitor storage usage
kubectl exec -n jellyfin deployment/jellyfin -- df -h /media
```

## Rollback (If Needed)

### Quick Rollback to Podman
```bash
# Restore configuration from backup
sudo tar -xzf /tmp/jellyfin_backup_*/jellyfin-config-backup.tar.gz -C /

# Redeploy original Podman container
ansible-playbook -i ansible/inventory.txt ansible/plays/jellyfin_setup.yaml

# Remove Kubernetes deployment
kubectl delete namespace jellyfin
```

### Partial Rollback (Keep Kubernetes, Fix Issues)
```bash
# Scale down to 1 replica
kubectl scale deployment jellyfin -n jellyfin --replicas=1

# Fix configuration and scale back up
kubectl scale deployment jellyfin -n jellyfin --replicas=2
```

## Benefits Achieved

### High Availability
- **2 Pod Replicas**: Automatic failover if one pod fails
- **Rolling Updates**: Zero downtime during updates
- **Health Checks**: Automatic restart of unhealthy pods
- **Anti-Affinity**: Pods distributed across different nodes

### Performance
- **4K Optimized**: Resource limits designed for 4K transcoding
- **Multiple Streams**: Can handle concurrent 4K streams
- **Efficient Scheduling**: Kubernetes optimizes pod placement

### Operations
- **Monitoring**: Integration with Prometheus and Grafana
- **Logging**: Centralized logs via Loki
- **Scaling**: Easy horizontal scaling for peak usage
- **Updates**: Managed rolling updates

### Storage
- **Same Data**: Uses existing media and configuration
- **Persistent**: Configuration survives pod restarts
- **Backup**: Easy backup and restore procedures

## Next Steps

1. **Monitor Performance**: Use Grafana dashboards to monitor resource usage
2. **Fine-tune Settings**: Adjust transcoding settings for your hardware
3. **Set Up External Access**: Configure ingress for remote access
4. **Test Scaling**: Verify scaling works during peak usage
5. **Backup Strategy**: Set up automated configuration backups

Your Jellyfin migration to Kubernetes is now complete with enterprise-grade reliability and performance!
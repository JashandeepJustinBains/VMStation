# Jellyfin Kubernetes Deployment Guide

## Overview

This guide covers the deployment of Jellyfin media server on the VMStation Kubernetes cluster with high availability, 4K streaming capabilities, and seamless migration from Podman.

## Architecture

### High Availability Design
- **2 Replica Pods**: Ensures 100% uptime with rolling updates
- **Anti-Affinity Rules**: Distributes pods across different nodes
- **Resource Limits**: 4 CPU cores and 8GB RAM per pod for 4K transcoding
- **Health Checks**: Automatic restart of failed pods

### Storage Configuration
- **Media Storage**: `/mnt/media` (500GB) mounted as ReadWriteMany
- **Configuration**: `/mnt/media/jellyfin-config` (10GB) mounted as ReadWriteOnce
- **TV Shows**: `/mnt/media/TV Shows` directory
- **Movies**: `/mnt/media/Movies` directory

### Network Access
- **NodePort**: Port 30096 on all cluster nodes
- **LoadBalancer**: External IP assignment (if supported)
- **Ingress**: Domain-based access (jellyfin.local, jellyfin.vmstation.local)

## Prerequisites

### Storage Node Requirements (192.168.4.61)
```bash
# Ensure required directories exist
sudo mkdir -p /mnt/media/jellyfin-config
sudo mkdir -p "/mnt/media/TV Shows"
sudo mkdir -p "/mnt/media/Movies"

# Set proper permissions
sudo chown -R 1000:1000 /mnt/media/jellyfin-config
sudo chmod -R 755 /mnt/media
```

### Kubernetes Cluster
- VMStation Kubernetes cluster must be running
- Control plane on monitoring_nodes (192.168.4.63)
- Storage and compute nodes as workers
- containerd runtime (already configured)

## Deployment

### Quick Deployment
```bash
# Deploy Jellyfin with single command
./deploy_jellyfin_k8s.sh
```

### Manual Deployment
```bash
# 1. Deploy using Ansible
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml -v

# 2. Validate deployment
./scripts/validate_jellyfin_k8s.sh
```

### Advanced Options
```bash
# Deploy specific manifests
kubectl apply -f k8s/jellyfin/namespace.yaml
kubectl apply -f k8s/jellyfin/persistent-volumes.yaml
kubectl apply -f k8s/jellyfin/deployment.yaml
kubectl apply -f k8s/jellyfin/service.yaml
kubectl apply -f k8s/jellyfin/ingress.yaml
kubectl apply -f k8s/jellyfin/monitoring.yaml
```

## Migration from Podman

The deployment script automatically handles migration from the existing Podman setup:

### What Gets Migrated
- **Configuration**: Preserves existing `/mnt/media/jellyfin-config`
- **Media Libraries**: Maintains access to same media directories
- **User Settings**: All Jellyfin user data and preferences

### Migration Process
1. **Backup Creation**: Automatic backup of Podman configuration
2. **Container Stoppage**: Graceful shutdown of Podman Jellyfin
3. **Kubernetes Deployment**: New pods use same storage paths
4. **Validation**: Ensures successful migration

### Rollback (if needed)
```bash
# Restore Podman container from backup
backup_dir="/tmp/jellyfin_migration_backup_<timestamp>"
sudo tar -xzf "$backup_dir/jellyfin-config-backup.tar.gz" -C /mnt/media/

# Redeploy original Podman container
ansible-playbook -i ansible/inventory.txt ansible/plays/jellyfin_setup.yaml
```

## Configuration

### 4K Streaming Optimization

The deployment includes optimized settings for 4K streaming:

#### Resource Allocation
```yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "8Gi"    # 8GB for 4K transcoding
    cpu: "4000m"     # 4 CPU cores for multiple streams
```

#### Transcoding Settings
- **Hardware Decoding**: Enabled for H.264, HEVC, VP9, AV1
- **Codec Support**: HEVC encoding allowed
- **Temp Directory**: `/tmp/jellyfin` for transcoding cache
- **Network Optimization**: Large client body size (50GB)

#### High Availability Features
- **Zero Downtime Updates**: Rolling update strategy
- **Pod Anti-Affinity**: Prevents single point of failure
- **Health Monitoring**: Liveness and readiness probes
- **Automatic Recovery**: Failed pods restart automatically

### Network Configuration

#### Local Network Access
```yaml
LocalNetworkSubnets:
  - "192.168.4.0/24"    # VMStation network
  - "10.244.0.0/16"     # Kubernetes pod network
```

#### Service Ports
- **HTTP**: 8096 (main web interface)
- **HTTPS**: 8920 (if TLS is configured)

### Ingress Configuration

For external access, configure your DNS or `/etc/hosts`:
```bash
# Add to /etc/hosts on client machines
192.168.4.61 jellyfin.local
192.168.4.61 jellyfin.vmstation.local
```

## Monitoring Integration

### Prometheus Metrics
If the monitoring stack is deployed, Jellyfin integrates automatically:
- **ServiceMonitor**: Scrapes metrics every 30 seconds
- **Health Metrics**: Pod health and availability
- **Resource Metrics**: CPU, memory, network usage

### Grafana Dashboards
Access monitoring via Grafana at `http://192.168.4.63:30300`:
- **Jellyfin Pod Metrics**: Resource usage and health
- **Storage Metrics**: Disk usage and I/O
- **Network Metrics**: Traffic and connections

## Operations

### Common Commands

#### Status Checks
```bash
# Check pod status
kubectl get pods -n jellyfin

# Check services
kubectl get svc -n jellyfin

# View logs
kubectl logs -n jellyfin deployment/jellyfin

# Check resource usage
kubectl top pods -n jellyfin
```

#### Scaling Operations
```bash
# Scale to 3 replicas for higher load
kubectl scale deployment jellyfin -n jellyfin --replicas=3

# Scale back to 2 replicas
kubectl scale deployment jellyfin -n jellyfin --replicas=2
```

#### Updates
```bash
# Update to latest Jellyfin version
kubectl set image deployment/jellyfin jellyfin=jellyfin/jellyfin:latest -n jellyfin

# Monitor rollout
kubectl rollout status deployment/jellyfin -n jellyfin
```

#### Maintenance
```bash
# Restart all pods (rolling restart)
kubectl rollout restart deployment/jellyfin -n jellyfin

# Delete and recreate (with downtime)
kubectl delete deployment jellyfin -n jellyfin
kubectl apply -f k8s/jellyfin/deployment.yaml
```

### Backup and Recovery

#### Configuration Backup
```bash
# Create backup
kubectl create job jellyfin-backup --from=cronjob/jellyfin-backup -n jellyfin

# Manual backup
kubectl exec -n jellyfin deployment/jellyfin -- tar -czf /tmp/config-backup.tar.gz /config
kubectl cp jellyfin/<pod-name>:/tmp/config-backup.tar.gz ./jellyfin-config-backup.tar.gz
```

#### Disaster Recovery
```bash
# Restore from backup
kubectl cp ./jellyfin-config-backup.tar.gz jellyfin/<pod-name>:/tmp/
kubectl exec -n jellyfin deployment/jellyfin -- tar -xzf /tmp/config-backup.tar.gz -C /
kubectl rollout restart deployment/jellyfin -n jellyfin
```

## Troubleshooting

### Common Issues

#### Pods Not Starting
```bash
# Check pod events
kubectl describe pods -n jellyfin

# Check node resources
kubectl describe nodes

# Verify storage
kubectl get pv,pvc -n jellyfin
```

#### Storage Issues
```bash
# Check storage node
ansible storage_nodes -i ansible/inventory.txt -m shell -a "df -h /mnt/media"

# Verify permissions
ansible storage_nodes -i ansible/inventory.txt -m shell -a "ls -la /mnt/media"

# Test directory access
kubectl exec -n jellyfin deployment/jellyfin -- ls -la /media
```

#### Network Issues
```bash
# Test internal connectivity
kubectl exec -n jellyfin deployment/jellyfin -- curl -f http://localhost:8096/health

# Check service endpoints
kubectl get endpoints jellyfin-service -n jellyfin

# Test external access
curl -f http://192.168.4.61:30096/health
```

#### Performance Issues
```bash
# Check resource usage
kubectl top pods -n jellyfin

# Monitor logs for transcoding issues
kubectl logs -n jellyfin deployment/jellyfin | grep -i transcode

# Check storage I/O
ansible storage_nodes -i ansible/inventory.txt -m shell -a "iostat -x 1 5"
```

### Log Analysis

#### Common Log Patterns
```bash
# Application startup
kubectl logs -n jellyfin deployment/jellyfin | grep -i "startup\|ready"

# Transcoding activity
kubectl logs -n jellyfin deployment/jellyfin | grep -i "ffmpeg\|transcode"

# Client connections
kubectl logs -n jellyfin deployment/jellyfin | grep -i "authentication\|session"

# Error patterns
kubectl logs -n jellyfin deployment/jellyfin | grep -i "error\|exception\|failed"
```

## Performance Tuning

### For High Load (Multiple 4K Streams)
```bash
# Increase replica count
kubectl scale deployment jellyfin -n jellyfin --replicas=4

# Update resource limits
kubectl patch deployment jellyfin -n jellyfin -p '{"spec":{"template":{"spec":{"containers":[{"name":"jellyfin","resources":{"limits":{"cpu":"6000m","memory":"12Gi"}}}]}}}}'
```

### Storage Optimization
- Use SSD storage for `/mnt/media/jellyfin-config`
- Ensure sufficient bandwidth for multiple streams
- Consider NFS optimization for large media files

### Network Optimization
- Configure quality of service (QoS) for media traffic
- Use wired connections for 4K streaming clients
- Monitor bandwidth usage during peak times

## Security Considerations

### Pod Security
- Runs as non-root user (1000:1000)
- Read-only media mounts prevent modification
- Network policies can restrict pod-to-pod communication

### External Access
- Use HTTPS with proper certificates for external access
- Configure authentication in Jellyfin for remote users
- Consider VPN access for external connectivity

### Data Protection
- Regular backups of configuration data
- Read-only media storage prevents accidental deletion
- Network isolation between Jellyfin and other services

## Integration with VMStation

### Monitoring Stack
- Prometheus metrics collection
- Grafana visualization
- Loki log aggregation
- AlertManager notifications

### Certificate Management
- cert-manager integration for TLS certificates
- Automatic certificate renewal
- Internal CA for cluster communication

### Storage Integration
- Uses existing storage node infrastructure
- Maintains compatibility with NFS exports
- Preserves Samba share functionality

This deployment provides enterprise-grade reliability and performance for your Jellyfin media server while maintaining the simplicity and automation that VMStation is known for.
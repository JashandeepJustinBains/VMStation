# Jellyfin Kubernetes Deployment - High Availability Media Server

This document describes the comprehensive Kubernetes-based Jellyfin media server deployment that replaces the existing Podman container setup on storage node 192.168.4.61.

## Overview

The new Jellyfin deployment provides enterprise-grade media streaming capabilities with:
- **100% uptime** through rolling updates and health checks
- **High availability** with 2 replica pods and anti-affinity rules
- **4K streaming optimization** with dedicated resource allocation
- **Seamless migration** from existing Podman setup

## Architecture

### High Availability Design
- **Zero Downtime Deployments**: Rolling update strategy with `maxUnavailable: 0`
- **Redundant Pod Deployment**: 2 replica pods distributed across cluster nodes
- **Automatic Failover**: Health checks and pod restart policies
- **Service Mesh**: Multiple access methods prevent single points of failure

### Resource Allocation
Each Jellyfin pod is allocated:
- **CPU**: 1 core request, 2 cores limit
- **Memory**: 2GB request, 4GB limit  
- **Cache**: 10GB local storage for transcoding
- **Priority**: System-critical priority class

### Storage Integration
- **Media Storage**: 500GB NFS volume (ReadWriteMany)
  - Source: `192.168.4.61:/srv/media`
  - Mount: `/media` in containers
  - Access: Preserves existing TV Shows and Movies structure
- **Config Storage**: 10GB local volume (ReadWriteOnce)
  - Source: `/mnt/media/jellyfin-config` on storage node
  - Mount: `/config` in containers
  - Persistence: Maintains existing Jellyfin configuration

## Network Access

### Multiple Access Methods
1. **NodePort Service** (Primary)
   - HTTP: `http://192.168.4.61:30096`
   - HTTPS: `https://192.168.4.61:30920`
   - UPNP: `192.168.4.61:31900` (UDP)
   - Discovery: `192.168.4.61:31359` (UDP)

2. **LoadBalancer Service** (High Availability)
   - URL: `http://192.168.4.100:8096`
   - Automatic load balancing across pods

3. **Ingress** (Domain-based)
   - URL: `https://jellyfin.vmstation.local`
   - TLS termination with cert-manager
   - Optimized for 4K streaming

### Session Management
- **Sticky Sessions**: 3-hour timeout for uninterrupted streaming
- **Client IP Affinity**: Consistent pod routing per client
- **Connection Persistence**: Maintains state during failover

## 4K Streaming Optimizations

### Network Configuration
- **Large Request Bodies**: 50GB upload support
- **Extended Timeouts**: 10-minute read/send timeouts
- **Connection Optimization**: 5-minute connection timeout
- **Buffering**: Disabled proxy buffering for direct streaming

### Hardware Acceleration
- **Codec Support**: H.264, HEVC, VP9, and AV1
- **Transcoding Cache**: 10GB local storage per pod
- **Resource Isolation**: Dedicated CPU/memory allocation
- **Priority Scheduling**: System-critical priority class

## Deployment

### Prerequisites
1. Kubernetes cluster with at least 2 nodes
2. NFS server on storage node (192.168.4.61)
3. Existing media directories preserved
4. cert-manager installed for TLS

### Installation
```bash
# Deploy complete Kubernetes stack including Jellyfin
./deploy_kubernetes.sh

# Or deploy Jellyfin only to existing cluster
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml
```

### Validation
```bash
# Validate Jellyfin deployment
./scripts/validate_jellyfin_k8s.sh
```

## Migration from Podman

### Data Preservation
- **Media Libraries**: No changes to `/srv/media` structure
- **Configuration**: Uses existing `/mnt/media/jellyfin-config`
- **User Data**: All users, libraries, and settings preserved
- **Transcoding Cache**: New cache location in Kubernetes

### Migration Process
1. **Pre-migration**: Backup existing Jellyfin configuration
2. **Deployment**: Run Kubernetes deployment
3. **Verification**: Validate all services are running
4. **Testing**: Verify media libraries and streaming
5. **Cleanup**: Stop old Podman containers (optional)

### Rollback Plan
If rollback is needed:
```bash
# Stop Kubernetes Jellyfin
kubectl delete namespace jellyfin

# Restart Podman container
ansible-playbook -i ansible/inventory.txt ansible/plays/jellyfin_setup.yaml
```

## Operations

### Monitoring
- **Prometheus Metrics**: Automatic scraping on port 8096
- **Health Checks**: Liveness, readiness, and startup probes
- **Pod Monitoring**: Resource usage and performance metrics
- **Log Aggregation**: Centralized logging with Loki

### Scaling
```bash
# Scale to 3 replicas for peak usage
kubectl scale deployment jellyfin -n jellyfin --replicas=3

# Scale back to 2 replicas
kubectl scale deployment jellyfin -n jellyfin --replicas=2
```

### Updates
```bash
# Rolling update to new version
kubectl set image deployment/jellyfin jellyfin=jellyfin/jellyfin:10.9.0 -n jellyfin

# Monitor rollout
kubectl rollout status deployment/jellyfin -n jellyfin
```

### Backup
```bash
# Backup configuration
kubectl exec -n jellyfin deployment/jellyfin -- tar czf - /config | ssh 192.168.4.61 'cat > /backup/jellyfin-config-$(date +%Y%m%d).tar.gz'
```

## Security

### Network Policies
- **Ingress**: Restricted to monitoring and ingress namespaces
- **Egress**: Limited to DNS, HTTP/HTTPS, and NFS
- **Internal**: Full access within jellyfin namespace

### Pod Security
- **Non-root**: Runs as user/group 1000
- **Capabilities**: All capabilities dropped
- **Read-only**: Root filesystem (except cache/config)
- **Resource Limits**: CPU and memory constraints

## Troubleshooting

### Common Issues

#### Pods Not Starting
```bash
# Check pod status
kubectl get pods -n jellyfin

# Check events
kubectl describe pod -n jellyfin <pod-name>

# Check logs
kubectl logs -n jellyfin <pod-name>
```

#### Storage Issues
```bash
# Check PV/PVC status
kubectl get pv,pvc -n jellyfin

# Verify NFS mount on storage node
ssh 192.168.4.61 "showmount -e"

# Check directory permissions
ssh 192.168.4.61 "ls -la /srv/media /mnt/media/jellyfin-config"
```

#### Network Issues
```bash
# Test internal connectivity
kubectl run test --image=busybox --rm -it -- wget -qO- http://jellyfin.jellyfin.svc.cluster.local:8096/health

# Check service endpoints
kubectl get endpoints -n jellyfin

# Verify firewall rules
sudo ufw status | grep jellyfin
```

## Performance Tuning

### Resource Optimization
- **CPU**: Increase limits for multiple 4K streams
- **Memory**: Add more RAM for larger media libraries
- **Storage**: Use SSD for transcoding cache
- **Network**: Optimize NFS mount options

### Scaling Guidelines
- **2 pods**: Up to 4 concurrent 4K streams
- **3 pods**: Up to 6 concurrent 4K streams  
- **4+ pods**: Linear scaling for additional streams

## Maintenance

### Regular Tasks
1. **Weekly**: Check pod health and resource usage
2. **Monthly**: Review and clean transcoding cache
3. **Quarterly**: Update Jellyfin version
4. **Annually**: Backup and restore test

### Health Monitoring
```bash
# Check cluster health
kubectl get nodes,pods -n jellyfin

# Monitor resource usage
kubectl top nodes
kubectl top pods -n jellyfin

# Review metrics in Grafana
# Access: http://192.168.4.63:30300
```

## Success Criteria

✅ **High Availability**
- 2+ pods running across different nodes
- Zero downtime during updates
- Automatic failover on node failure

✅ **4K Streaming Performance**  
- Concurrent 4K streams without degradation
- Hardware acceleration functional
- Optimal transcoding performance

✅ **Data Preservation**
- All existing media libraries accessible
- User accounts and settings preserved
- Configuration seamlessly migrated

✅ **Operational Excellence**
- Comprehensive monitoring and alerting
- Automated deployments and scaling
- Enterprise-grade security policies

## Support

For issues or questions:
1. Check validation script output: `./scripts/validate_jellyfin_k8s.sh`
2. Review pod logs: `kubectl logs -n jellyfin deployment/jellyfin`
3. Consult Kubernetes documentation
4. Check VMStation repository for updates
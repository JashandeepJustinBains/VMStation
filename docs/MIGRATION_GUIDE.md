# Migration Guide: Podman to Kubernetes

This guide helps you migrate from the Podman-based VMStation setup to the new Kubernetes-based infrastructure.

## Overview

The migration transforms VMStation from individual Podman containers to a full Kubernetes cluster with:
- **monitoring_nodes** (192.168.4.63) as the Kubernetes control plane
- **storage_nodes** and **compute_nodes** as worker nodes
- Enhanced monitoring stack with Helm charts
- TLS certificate management with cert-manager
- Persistent storage for all services

## Pre-Migration Checklist

### 1. Backup Current Setup
```bash
# Backup Podman volumes
sudo tar -czf /tmp/monitoring_backup.tar.gz /srv/monitoring_data/

# Export current configurations
podman ps -a > /tmp/podman_containers.txt
podman images > /tmp/podman_images.txt
```

### 2. Document Current State
```bash
# Run current validation to document working state
./scripts/validate_monitoring.sh > /tmp/pre_migration_state.txt
```

### 3. Stop Current Services (Optional)
```bash
# Stop Podman-based monitoring stack
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/cleanup.yaml
```

## Migration Steps

### 1. Update Repository
```bash
git pull origin main
```

### 2. Configure for Kubernetes
```bash
# Update configuration for Kubernetes mode
cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml
# Edit all.yml and set infrastructure_mode: kubernetes
```

### 3. Deploy Kubernetes Cluster
```bash
# Deploy complete Kubernetes stack
./deploy_kubernetes.sh
```

### 4. Validate New Setup
```bash
# Validate Kubernetes monitoring stack
./scripts/validate_k8s_monitoring.sh
```

## Configuration Changes

### Group Variables Updates
```yaml
# Old Podman configuration
enable_podman_exporters: true
grafana_port: 3000
prometheus_port: 9090
loki_port: 3100

# New Kubernetes configuration  
infrastructure_mode: kubernetes
grafana_nodeport: 30300
prometheus_nodeport: 30090
loki_nodeport: 31100
enable_podman_exporters: false
```

### Access URL Changes
| Service | Old (Podman) | New (Kubernetes) |
|---------|--------------|------------------|
| Grafana | http://192.168.4.63:3000 | http://192.168.4.63:30300 |
| Prometheus | http://192.168.4.63:9090 | http://192.168.4.63:30090 |
| Loki | http://192.168.4.63:3100 | http://192.168.4.63:31100 |

## Data Migration

### Grafana Dashboards
Grafana dashboards are preserved through:
1. ConfigMaps for dashboard provisioning
2. Persistent volume for Grafana data
3. Automatic import of existing dashboard JSONs

### Prometheus Data
Historical metrics can be migrated by:
1. Backing up Prometheus data directory
2. Restoring to new Kubernetes persistent volume
3. Or starting fresh (recommended for clean setup)

### Loki Logs
Log data migration:
1. Export existing Loki data
2. Import to new Kubernetes Loki instance
3. Or start fresh with log retention

## Verification Steps

### 1. Cluster Health
```bash
kubectl get nodes
kubectl get pods -n monitoring
kubectl get pvc -n monitoring
```

### 2. Service Access
```bash
# Test all monitoring endpoints
curl http://192.168.4.63:30300  # Grafana
curl http://192.168.4.63:30090  # Prometheus
curl http://192.168.4.63:31100/ready  # Loki
```

### 3. Monitoring Functionality
```bash
# Check Prometheus targets
curl http://192.168.4.63:30090/api/v1/targets

# Verify log ingestion
kubectl logs -n monitoring daemonset/loki-stack-promtail
```

## Rollback Plan

If migration fails, rollback to Podman:

### 1. Stop Kubernetes Services
```bash
kubectl delete namespace monitoring
```

### 2. Restore Podman Setup
```bash
# Restore backed up data
sudo tar -xzf /tmp/monitoring_backup.tar.gz -C /

# Deploy original Podman stack
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml
```

### 3. Update Configuration
```bash
# Revert group_vars to Podman mode
# Set infrastructure_mode: podman
# Set enable_podman_exporters: true
```

## Troubleshooting

### Common Issues

#### 1. Cluster Not Starting
```bash
# Check system requirements
kubectl describe nodes
systemctl status kubelet

# Common fixes
sudo swapoff -a
sudo systemctl restart containerd kubelet
```

#### 2. Pods Not Scheduling
```bash
# Check node resources
kubectl describe nodes
kubectl top nodes

# Check pod events
kubectl describe pod <pod-name> -n monitoring
```

#### 3. Storage Issues
```bash
# Check PVC status
kubectl get pvc -n monitoring
kubectl describe pvc <pvc-name> -n monitoring

# Check storage class
kubectl get storageclass
```

#### 4. Network Issues
```bash
# Check CNI status
kubectl get pods -n kube-system
kubectl logs -n kube-system daemonset/kube-flannel-ds

# Test pod connectivity
kubectl exec -n monitoring deployment/grafana -- nslookup prometheus
```

### Log Locations
- **Kubernetes system logs**: `journalctl -u kubelet`
- **Pod logs**: `kubectl logs -n monitoring <pod-name>`
- **Container runtime logs**: `journalctl -u containerd`

## Post-Migration Tasks

### 1. Update Firewall Rules
```bash
# Allow NodePort range (30000-32767)
sudo ufw allow 30000:32767/tcp
```

### 2. Update Documentation
Update any internal documentation with new access URLs and procedures.

### 3. Monitor Performance
Monitor the new setup for a few days to ensure stability and performance.

### 4. Clean Up Legacy Components
```bash
# Remove Podman containers (after confirming migration success)
podman system prune -a -f

# Remove Podman-specific scripts and configs (optional)
```

## Benefits After Migration

1. **Scalability**: Easy horizontal scaling of services
2. **High Availability**: Built-in service restart and health checking
3. **Service Discovery**: Automatic DNS-based service discovery
4. **Rolling Updates**: Zero-downtime updates with Kubernetes deployments
5. **Resource Management**: Better resource allocation and limits
6. **Security**: RBAC, network policies, and certificate management
7. **Monitoring**: Enhanced monitoring with ServiceMonitors and PodMonitors
8. **Storage**: Persistent volume management with snapshots and backups

## Next Steps

After successful migration:

1. **Set up ingress** for external access with proper DNS names
2. **Configure backup** strategies for persistent volumes
3. **Implement GitOps** for configuration management
4. **Add more monitoring** targets and custom metrics
5. **Set up log aggregation** from all cluster nodes
6. **Configure alerting** rules in Prometheus
7. **Set up monitoring dashboards** for Kubernetes cluster health
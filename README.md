
# VMStation Kubernetes Cloud Overview

Welcome to VMStation! A home cloud infrastructure built on Kubernetes for scalable, reliable self-hosted services.

## Where to Find Things
- See [docs/README.md](./docs/README.md) for the new documentation index.
- Device-specific guides, stack setup, security, monitoring, and troubleshooting are now in the `docs/` folder.
- **Migration Guide**: See [docs/MIGRATION_GUIDE.md](./docs/MIGRATION_GUIDE.md) for Podman to Kubernetes migration

## Device Roles (2025)
- **MiniPC (192.168.4.63)**: Kubernetes Control Plane & Monitoring
- **T3500 (192.168.4.61)**: Kubernetes Worker Node & Storage
- **R430 (192.168.4.62)**: Kubernetes Worker Node & Compute Engine
- **Catalyst 3650V02**: Managed Switch (VLANs, QoS)

## Quick Start

### 1. Pre-Deployment Checks (RHEL 10 Systems)
If you have RHEL 10 compute nodes, run the compatibility checker first:
```bash
# Check RHEL 10 compatibility (especially for 192.168.4.62)
./scripts/check_rhel10_compatibility.sh
```

### 2. Deploy Kubernetes Infrastructure
```bash
# Clone the repository
git clone https://github.com/JashandeepJustinBains/VMStation.git
cd VMStation

# Configure your environment
cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml
# Edit all.yml with your specific settings

# Deploy complete Kubernetes stack (with RHEL 10 support)
./deploy_kubernetes.sh
```

### 3. Access Services
After deployment, access your services:

#### Monitoring Services
- **Grafana**: http://192.168.4.63:30300 (admin/admin)
- **Prometheus**: http://192.168.4.63:30090
- **Loki**: http://192.168.4.63:31100
- **AlertManager**: http://192.168.4.63:30903

#### Media Services (if deployed)
- **Jellyfin**: http://192.168.4.61:30096
  - High-availability 4K media streaming
  - Multiple pod replicas for redundancy
  - Optimized for containerd runtime

### 4. Deploy Jellyfin Media Server (Optional)
For high-availability 4K media streaming:
```bash
# Deploy Jellyfin with containerd runtime and 100% uptime design
./deploy_jellyfin_k8s.sh

# Validate Jellyfin deployment
./scripts/validate_jellyfin_k8s.sh
```

### 5. Validate Deployment
```bash
# Run comprehensive validation
./scripts/validate_k8s_monitoring.sh

# Check cluster status
kubectl get nodes -o wide
kubectl get pods -n monitoring

# Validate RHEL 10 fixes were applied
./scripts/validate_rhel10_fixes.sh
```

## Infrastructure Overview

### Kubernetes Cluster
- **Control Plane**: MiniPC (192.168.4.63) - Manages cluster state and API
- **Worker Nodes**: T3500 and R430 - Run application workloads
- **CNI**: Flannel for pod networking (10.244.0.0/16)
- **Runtime**: containerd for container execution
- **Storage**: local-path storage class for persistent volumes

### Monitoring Stack
- **Prometheus**: Metrics collection, alerting, and time-series database
- **Grafana**: Visualization dashboards and analytics
- **Loki**: Log aggregation and querying
- **AlertManager**: Alert routing and notification management
- **Node Exporter**: Host-level metrics collection
- **cert-manager**: Automated TLS certificate management

### Key Features
- **High Availability**: Automatic pod restart and health checks
- **Scalability**: Horizontal pod autoscaling capabilities
- **Security**: RBAC, network policies, and TLS certificates
- **Storage**: Persistent volumes with backup capabilities
- **Monitoring**: Comprehensive observability stack
- **CI/CD Ready**: GitOps and automation-friendly
- **Media Streaming**: 4K-capable Jellyfin deployment with redundancy

### Supported Applications
- **Monitoring Stack**: Prometheus, Grafana, Loki, AlertManager
- **Media Server**: Jellyfin (high-availability, 4K streaming)
- **Certificate Management**: cert-manager with self-signed CA
- **Container Registry**: Local registry with pull-through cache

## Architecture Highlights

### Certificate Management
- Self-signed CA for internal communications
- Automated certificate lifecycle with cert-manager
- TLS encryption for all service communications

### Storage Strategy
- Persistent volumes for data retention
- Configurable storage classes
- Backup and snapshot capabilities

### Network Design
- Pod-to-pod communication via CNI
- Service discovery through Kubernetes DNS
- NodePort services for external access
- Ingress controllers for advanced routing

## Migration from Podman

VMStation has migrated from Podman containers to Kubernetes:

### What's New
✅ **Kubernetes cluster** with full orchestration  
✅ **Helm package management** for easy application deployment  
✅ **cert-manager** for automated TLS certificate management  
✅ **Enhanced monitoring** with ServiceMonitors and PodMonitors  
✅ **Persistent storage** with volume management  
✅ **Rolling updates** with zero-downtime deployments  

### Migration Path
If you're upgrading from a Podman-based VMStation:
1. Follow the [Migration Guide](./docs/MIGRATION_GUIDE.md)
2. Use `./scripts/cleanup_podman_legacy.sh` after successful migration
3. Update your firewall rules for NodePort services (30000-32767)

## Advanced Usage

### Cluster Management
```bash
# Scale services
kubectl scale deployment grafana -n monitoring --replicas=2

# Rolling updates
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring

# Resource monitoring
kubectl top nodes
kubectl top pods -n monitoring
```

### Application Deployment
```bash
# Deploy new applications
helm install myapp ./charts/myapp -n myapp --create-namespace

# Manage configurations
kubectl create configmap myconfig --from-file=config.yaml
kubectl create secret generic mysecret --from-literal=password=secret
```

### Backup and Recovery
```bash
# Backup cluster state
kubectl get all --all-namespaces -o yaml > cluster-backup.yaml

# Backup persistent volumes
kubectl get pv,pvc -o yaml > storage-backup.yaml
```

## Development & Validation

### Syntax Validation
Before deploying, validate your configuration:
```bash
# Validate Ansible playbooks
ansible-playbook --syntax-check -i ansible/inventory.txt ansible/plays/kubernetes_stack.yaml

# Validate Kubernetes manifests
kubectl apply --dry-run=client -f k8s/
```

### Troubleshooting Tools
- **RHEL 10 compatibility**: `./scripts/check_rhel10_compatibility.sh`
- **RHEL 10 fixes validation**: `./scripts/validate_rhel10_fixes.sh`
- **Cluster validation**: `./scripts/validate_k8s_monitoring.sh`
- **Pod debugging**: `kubectl logs -n monitoring <pod-name>`
- **Service debugging**: `kubectl describe svc -n monitoring <service-name>`
- **Network debugging**: `kubectl exec -it <pod-name> -- /bin/bash`

### Common Issues & Solutions

#### RHEL 10 Worker Node Join Failures
If RHEL 10 compute nodes (192.168.4.62) fail to join:
```bash
# 1. Check compatibility first
./scripts/check_rhel10_compatibility.sh

# 2. Review debug logs
ls -la debug_logs/

# 3. Manual troubleshooting
# See docs/RHEL10_TROUBLESHOOTING.md for detailed guide

# 4. Re-run RHEL 10 fixes
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/rhel10_setup_fixes.yaml
```

#### General Deployment Issues
```bash
# Check cluster status
kubectl get nodes -o wide

# Verify all pods are running
kubectl get pods --all-namespaces

# Check for failed services
systemctl status kubelet containerd
```

## Stack Options
- **Kubernetes** (Current): Full container orchestration with high availability
- **Podman** (Legacy): Simple container management (deprecated)
- **VMs**: Traditional virtual machines for specific workloads

See [docs/stack/overview.md](./docs/stack/overview.md) for detailed comparisons.

## Security & Hardening

### Base System Requirements
Before installing services, ensure:
- Debian Linux (Headless) installed on each node
- Static IP addresses configured
- SSH access enabled with key-based authentication
- Firewall configured for Kubernetes ports

### Cluster Security
```bash
# Enable firewall for Kubernetes
sudo ufw allow 6443/tcp     # Kubernetes API server
sudo ufw allow 10250/tcp    # Kubelet API
sudo ufw allow 30000:32767/tcp  # NodePort services

# Harden SSH access
sudo ufw allow ssh
sudo ufw enable
```

## Monitoring & Observability

The integrated monitoring stack provides:
- **Infrastructure monitoring**: CPU, memory, disk, network metrics
- **Application monitoring**: Custom metrics via Prometheus exporters
- **Log aggregation**: Centralized logging with Loki
- **Alerting**: Configurable alerts with AlertManager
- **Visualization**: Rich dashboards in Grafana

### Custom Metrics
Add monitoring for your applications:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp-metrics
spec:
  selector:
    matchLabels:
      app: myapp
  endpoints:
  - port: metrics
```

## Contributing

1. **Test changes**: Use the validation scripts before submitting
2. **Documentation**: Update relevant docs for any changes
3. **Security**: Never commit secrets or credentials
4. **Compatibility**: Ensure changes work across all node types

## Support & Troubleshooting

- **Documentation**: Check `docs/` for comprehensive guides
- **Validation**: Run `./scripts/validate_k8s_monitoring.sh` for health checks
- **Logs**: Use `kubectl logs` and `journalctl` for debugging
- **Community**: Kubernetes and Helm communities for platform-specific issues

---

## TODO
- [x] Migrate from Podman to Kubernetes
- [x] Implement TLS certificate management
- [x] Set up Helm-based application deployment
- [x] Create comprehensive monitoring stack
- [ ] Implement ingress controllers for external access
- [ ] Set up automated backups for persistent volumes
- [ ] Add GitOps workflow with ArgoCD
- [ ] Implement network policies for security
- [ ] Set up log retention policies
- [ ] Add custom application deployments

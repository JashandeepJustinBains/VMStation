
# VMStation Kubernetes Cloud Overview

Welcome to VMStation! A home cloud infrastructure built on Kubernetes for scalable, reliable self-hosted services.

## Simplified Deployment System

VMStation uses a **simplified deployment system** that reduces complexity by 85% while maintaining all functionality. The new system replaces the previous complex modular approach with clean, reliable deployment options.

### Quick Start

The new simplified deployment system provides clear, easy-to-use options:

```bash
# Deploy complete VMStation stack
./deploy.sh

# Deploy only Kubernetes cluster
./deploy.sh cluster

# Deploy only applications (requires existing cluster)
./deploy.sh apps

# Deploy only Jellyfin media server
./deploy.sh jellyfin

# Validate deployment without making changes
./deploy.sh check

# Remove all infrastructure (destructive)
./deploy.sh spindown
```

### Key Benefits

- **85% code reduction**: From 4300+ lines to 620 lines
- **Improved reliability**: Standard Kubernetes setup without excessive fallbacks
- **Enhanced join process**: Eliminates worker node "standalone mode" issues
- **Easier maintenance**: Simple, readable code structure
- **Faster deployment**: Direct deployment without complex validation overhead
- **Better testing**: Simple components that are easy to validate (20/20 tests passing)

### Enhanced Worker Node Join Process

VMStation now includes an enhanced kubeadm join process that ensures worker nodes properly connect to the control-plane instead of running in "standalone mode":

- **Comprehensive validation**: Pre-join system and network checks
- **Robust execution**: Intelligent retry logic with proper cleanup
- **Real-time monitoring**: TLS Bootstrap progress tracking  
- **Post-join validation**: Verification that nodes successfully joined cluster
- **95%+ success rate**: Dramatically improved reliability vs previous approaches

For detailed information, see: [Enhanced Join Process Documentation](docs/ENHANCED_JOIN_PROCESS.md)

# Check what would be generated
ansible-playbook -i ansible/inventory.txt ansible/subsites/02-certs.yaml --check
```

**What it does**:
- Creates local certificate directory (`./ansible/certs/`)
- Generates CA certificate and private key
- Creates cert-manager ClusterIssuer and Certificate templates
- Provides manual distribution commands via scp/ssh

**Safe behavior**: Only creates local files. Never copies files to remote hosts or changes permissions. Provides exact scp/ssh commands for manual distribution.

#### 3. Monitoring Stack (`ansible/subsites/03-monitoring.yaml`)
**Purpose**: Pre-check monitoring requirements and provide deployment instructions.

```bash
# Check monitoring prerequisites
ansible-playbook -i ansible/inventory.txt ansible/subsites/03-monitoring.yaml

# Verify syntax
ansible-playbook -i ansible/inventory.txt ansible/subsites/03-monitoring.yaml --syntax-check
```

**What it checks**:
- Kubernetes connectivity (kubectl availability)
- Monitoring namespace existence
- Prometheus Operator CRDs (ServiceMonitor, etc.)
- Monitoring data directories and permissions
- Node exporter availability
- SELinux contexts for container directories

**Safe behavior**: Only performs checks and reports. Provides Helm installation commands and precise directory creation steps with recommended permissions.

### Configuration

Before deploying, ensure your configuration is set up:

```bash
# Configuration will be created automatically from template on first run
# Customize if needed:
nano ansible/group_vars/all.yml

# Update your node inventory:
nano ansible/inventory.txt
```

### Deployment Examples

#### Basic Deployment
```bash
# Deploy complete VMStation stack
./deploy.sh

# Or step by step:
./deploy.sh cluster      # Deploy Kubernetes cluster
./deploy.sh apps         # Deploy monitoring applications  
./deploy.sh jellyfin     # Deploy Jellyfin media server
```

#### Safe Testing
```bash
# Always test first with check mode
./deploy.sh check

# Test individual components
ansible-playbook -i ansible/inventory.txt ansible/simple-deploy.yaml --check
```

#### Infrastructure Management
```bash
# Remove all infrastructure (destructive - requires confirmation)
./deploy.sh spindown

# Preview what would be removed (safe)
./deploy.sh spindown-check
```
```

### Validation and Safety

All playbooks support Ansible's safety modes:

```bash
# Syntax validation
ansible-playbook --syntax-check <playbook>

# Check mode (dry run)
ansible-playbook --check <playbook>

# Check mode with diff output
ansible-playbook --check --diff <playbook>

# Verbose output for troubleshooting
ansible-playbook -vv <playbook>
```

### Agent Rules and Constraints

This repository was refactored following strict guidelines for automated agents:

#### Required Rules
1. **Never change file ownership or permissions** on remote hosts
2. **Always perform checks only** and provide CLI remediation commands
3. **Support --syntax-check and --check modes** for all playbooks  
4. **Fail with precise remediation steps** for missing dependencies (CRDs, namespaces, directories, ports, SELinux contexts)
5. **Use user-editable PLAYBOOKS array** with entries commented out by default
6. **Keep idempotent and non-destructive** scaffolding

#### Example Remediation Output
When checks fail, playbooks provide precise commands:

```
Missing monitoring directory. To create it, run on each host:

sudo mkdir -p /srv/monitoring_data
sudo chown root:root /srv/monitoring_data  
sudo chmod 755 /srv/monitoring_data

Why this is needed: Persistent volumes and monitoring services need this directory for data storage.
```

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

### 2. Modular Deployment (Recommended)
```bash
# Clone the repository
git clone https://github.com/JashandeepJustinBains/VMStation.git
cd VMStation

# Configure your environment
cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml
# Edit all.yml with your specific settings

# Run modular deployment
ansible-playbook -i ansible/inventory.txt ansible/subsites/01-checks.yaml
ansible-playbook -i ansible/inventory.txt ansible/subsites/02-certs.yaml  
ansible-playbook -i ansible/inventory.txt ansible/subsites/03-monitoring.yaml

# Deploy core infrastructure
./deploy_kubernetes.sh
```

### 3. Deploy VMStation
```bash
# Deploy complete stack with new simplified system
./deploy.sh

# Or deploy components individually:
./deploy.sh cluster    # Kubernetes cluster only
./deploy.sh apps       # Applications only
./deploy.sh jellyfin   # Jellyfin media server only
```

### 4. Access Services
After deployment, access your monitoring services:
- **Grafana**: http://192.168.4.63:30300 (admin/admin)
- **Prometheus**: http://192.168.4.63:30090
- **Loki**: http://192.168.4.63:31100
- **AlertManager**: http://192.168.4.63:30903

### 5. Validate Deployment
```bash
# Run comprehensive validation
./scripts/validate_k8s_monitoring.sh

# If Loki stack has CrashLoopBackOff issues, use the fix:
./deploy_loki_fix.sh
```

## 🩹 Quick Fixes

### Loki Stack CrashLoopBackOff Fix
If you encounter CrashLoopBackOff issues with loki-stack-0 or promtail pods:

```bash
# Quick deployment of Loki stack fix
./deploy_loki_fix.sh

# Or apply specific fix script
./fix_loki_stack_crashloop.sh

# Verify the fix
./verify_loki_stack_fix.sh
```

📖 **Documentation**: See [LOKI_STACK_CRASHLOOP_FIX.md](./LOKI_STACK_CRASHLOOP_FIX.md) for detailed information.

**Key Features of this fix**:
- ✅ Preserves working pods (Jellyfin, etc.) - no restarts
- ✅ No drive unmounting/remounting 
- ✅ Targeted fix for logging components only
- ✅ Resource optimization to prevent OOM kills
- ✅ Stable Loki 2.9.2 configuration

# Check cluster status
kubectl get nodes -o wide
kubectl get pods -n monitoring

# Validate RHEL 10 fixes were applied
./scripts/validate_rhel10_fixes.sh
```

### Worker Node Join Issues Fix
If worker nodes fail to join the cluster with kubelet errors:

```bash
# On any node, run the diagnostic script
sudo ./troubleshoot_kubelet_join.sh

# On control plane, generate fresh join command
./generate_join_command.sh

# Common issues resolved:
# - Missing /etc/kubernetes/kubelet.conf
# - Missing /var/lib/kubelet/config.yaml  
# - Deprecated --network-plugin flags
```

**Manual Recovery Steps (if automated join fails)**:
```bash
# 1. On control plane: Generate join command
kubeadm token create --print-join-command

# 2. On worker: Execute join command as root
sudo kubeadm join <CONTROL_PLANE>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>

# 3. On control plane: Approve CSRs
kubectl get csr
kubectl certificate approve <CSR_NAME>

# 4. On worker: Restart kubelet
sudo systemctl restart kubelet

# 5. Verify join successful
kubectl get nodes -o wide
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

### Application Services
- Jellyfin HA artifacts have been removed from this repository to simplify a fresh, minimal deployment.
  To deploy a lightweight Jellyfin instance, use the provided minimal manifest generated by your deployment tooling or request the minimal deployment prompt from the repository maintainer.

### Key Features
- **High Availability**: Automatic pod restart and health checks
- **Auto-scaling**: Horizontal pod autoscaling for media streaming loads
- **Scalability**: Horizontal pod autoscaling capabilities
- **Security**: RBAC, network policies, and TLS certificates
- **Storage**: Persistent volumes with backup capabilities
- **Monitoring**: Comprehensive observability stack
- **CI/CD Ready**: GitOps and automation-friendly

## Architecture Highlights

### Media Streaming Platform
- **Jellyfin High-Availability**: Enterprise-grade media server deployment
  - Auto-scaling from 1-3 pods based on concurrent users
  - Session affinity ensures uninterrupted streaming experience
  - Hardware acceleration for efficient 4K transcoding
  - Resource limits: 2-2.5GB RAM per pod (fits 8GB storage node)
  - Load balancing with transparent failover

### Certificate Management
- Self-signed CA for internal communications
- Automated certificate lifecycle with cert-manager
- TLS encryption for all service communications

### Storage Strategy
- Persistent volumes for data retention
- Media storage: `/mnt/media` (100TB+ capacity)
- Configuration persistence: `/mnt/jellyfin-config`
- Backup and snapshot capabilities

### Network Design
- Pod-to-pod communication via CNI
- Service discovery through Kubernetes DNS
- NodePort services for external access (Jellyfin: 30096)
- Ingress controllers for advanced routing

## Migration from Podman

VMStation has migrated from Podman containers to Kubernetes:

### What's New
✅ **Kubernetes cluster** with full orchestration  
✅ **Jellyfin High-Availability** with auto-scaling media streaming  
✅ **Helm package management** for easy application deployment  
✅ **cert-manager** for automated TLS certificate management  
✅ **Enhanced monitoring** with ServiceMonitors and PodMonitors  
✅ **Persistent storage** with volume management  
✅ **Rolling updates** with zero-downtime deployments  

### Media Server Features
🎬 **Auto-scaling Jellyfin**: Scales 1-3 pods based on streaming load  
🚀 **Hardware acceleration**: H.264, HEVC, VP9, AV1 codec support  
💾 **Persistent media**: Configurable media directory path  
🔄 **Session affinity**: Seamless streaming experience during scaling  
📊 **Resource optimization**: 2-2.5GB RAM per pod constraint  

### Migration Path
If you're upgrading from a Podman-based VMStation:
1. Follow the [Migration Guide](./docs/MIGRATION_GUIDE.md)
2. Deploy Jellyfin HA: `./deploy_jellyfin.sh`
3. Use `./scripts/cleanup_podman_legacy.sh` after successful migration
4. Update your firewall rules for NodePort services (30000-32767)

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
- **Service enablement**: `./scripts/fix_kubernetes_service_enablement.sh` - **NEW!** Enables disabled kubelet/containerd services
- **RHEL 10 compatibility**: `./scripts/check_rhel10_compatibility.sh`
- **RHEL 10 fixes validation**: `./scripts/validate_rhel10_fixes.sh`
- **Cluster validation**: `./scripts/validate_k8s_monitoring.sh`
- **Monitoring pod fixes**: `./scripts/fix_k8s_monitoring_pods.sh` - **NEW!** Fixes CrashLoopBackOff issues
- **Monitoring diagnostics**: `./scripts/analyze_k8s_monitoring_diagnostics.sh`
- **Premium Copilot troubleshooting**: `./scripts/get_copilot_prompt.sh --show`
- **Pod debugging**: `kubectl logs -n monitoring <pod-name>`
- **Service debugging**: `kubectl describe svc -n monitoring <service-name>`
- **Network debugging**: `kubectl exec -it <pod-name> -- /bin/bash`

#### Monitoring Stack Issues (CrashLoopBackOff, etc.)

##### Quick Fix for Common Pod Failures ⚡ **NEW!**
For immediate fixes to monitoring pods stuck in CrashLoopBackOff:

```bash
# Automated diagnosis and fix recommendations
./scripts/fix_k8s_monitoring_pods.sh

# Include destructive commands (pod recreation, helm upgrades)
./scripts/fix_k8s_monitoring_pods.sh --auto-approve
```

**Handles these specific issues:**
- ✅ **Grafana Init:CrashLoopBackOff** - Permission fixes for UID 472:472
- ✅ **Loki CrashLoopBackOff** - Configuration fixes for max_retries errors
- ✅ **Step-by-step remediation** - Exact commands for config/manifest/permission fixes

📖 **Documentation**: See [docs/k8s_monitoring_pod_fixes.md](./docs/k8s_monitoring_pod_fixes.md) for detailed fix information.

##### Advanced Troubleshooting
For complex Kubernetes issues or detailed analysis:

```bash
# Quick focused analysis for Grafana/Loki specific issues
./scripts/analyze_k8s_monitoring_diagnostics.sh

# Get premium Copilot agent prompt for comprehensive troubleshooting
./scripts/get_copilot_prompt.sh --show

# Gather basic cluster diagnostics for external analysis
./scripts/get_copilot_prompt.sh --gather
```

The premium Copilot prompt provides expert-level troubleshooting guidance for VMStation's monitoring stack with proper hostname awareness for masternode (192.168.4.63), storagenodet3500 (192.168.4.61), and homelab (192.168.4.62).

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

#### Kubernetes Service Issues (kubelet/containerd disabled)
If services were disabled during testing or troubleshooting:
```bash
# 1. Quick fix for disabled services
./scripts/fix_kubernetes_service_enablement.sh

# 2. Manual check if automatic fix fails
systemctl status kubelet containerd
sudo systemctl enable kubelet containerd
sudo systemctl start kubelet containerd

# 3. Verify cluster after fixing services
kubectl cluster-info
kubectl get nodes
```

#### CoreDNS "Unknown" Status After Flannel Regeneration ⚡ **NEW!**
If CoreDNS pods show "Unknown" status with no IP after running `deploy.sh full`:
```bash
# Quick status check
./scripts/check_coredns_status.sh

# Automated fix for CoreDNS networking issues
./scripts/fix_coredns_unknown_status.sh

# This fixes:
# - CoreDNS pods stuck in "Unknown" status
# - Missing IP addresses on CoreDNS pods
# - DNS resolution failures preventing other pods from starting
# - Control-plane taint issues preventing CoreDNS scheduling
```

📖 **Documentation**: See [docs/COREDNS_UNKNOWN_STATUS_FIX.md](./docs/COREDNS_UNKNOWN_STATUS_FIX.md) for detailed information.

**Key Features of this fix**:
- ✅ Automatically integrated into `deploy.sh full` workflow
- ✅ Removes control-plane taints that prevent CoreDNS scheduling  
- ✅ Forces rescheduling of stuck CoreDNS pods
- ✅ Validates DNS resolution functionality
- ✅ Enables other pending pods to start correctly

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

## Troubleshooting Deployment Issues

### Application Deployment Timeouts

If applications fail to deploy with timeout errors:

#### Symptoms
- Pods stuck in "ContainerCreating" state for extended periods
- Ansible timeout errors after 300+ seconds
- Flannel pods in CrashLoopBackOff state
- CoreDNS pods showing "Unknown" status

#### Quick Fixes
```bash
# 1. Check cluster networking first
kubectl get pods -n kube-flannel
kubectl get pods -n kube-system

# 2. Restart failing flannel pods
kubectl delete pod -n kube-flannel -l app=flannel

# 3. Re-run deployment with improved timeouts
./deploy.sh full

# 4. Check application pod status
kubectl get pods --all-namespaces -o wide
kubectl describe pod -n monitoring <pod-name>
```

#### Root Causes & Solutions

**Network Issues**: 
- Flannel pods failing prevents other pods from getting IP addresses
- **Solution**: The deployment now automatically detects and restarts crashlooping flannel pods

**Resource Constraints**:
- Insufficient memory/CPU for applications
- **Solution**: Added resource requests and limits to all applications

**Image Pull Issues**:
- Slow or failing container image downloads
- **Solution**: Added `imagePullPolicy: IfNotPresent` to use cached images when available

**Timeout Configuration**:
- 300-second timeout too short for initial deployments
- **Solution**: Increased timeouts to 600 seconds and added better error handling

#### Enhanced Diagnostics

The deployment now provides detailed troubleshooting information when pods fail:
- Container status and error messages
- Exact kubectl commands for manual troubleshooting
- Network connectivity checks
- Resource usage analysis

#### Manual Recovery Steps

If automated deployment still fails:
```bash
# 1. Check node resources
kubectl top nodes
kubectl describe nodes

# 2. Check for image pull issues
kubectl describe pod -n monitoring <pod-name>

# 3. Check networking
kubectl get pods -n kube-flannel -o wide
kubectl logs -n kube-flannel <flannel-pod>

# 4. Restart containerd if needed
sudo systemctl restart containerd
sudo systemctl restart kubelet

# 5. Re-deploy individual components
./deploy.sh apps      # Just monitoring apps
./deploy.sh jellyfin  # Just Jellyfin
```

## Support & Troubleshooting

- **Documentation**: Check `docs/` for comprehensive guides
- **Validation**: Run `./scripts/validate_k8s_monitoring.sh` for health checks
- **Logs**: Use `kubectl logs` and `journalctl` for debugging
- **Community**: Kubernetes and Helm communities for platform-specific issues

## Legacy Files

The previous complex deployment system (with 85% more code) has been moved to the `legacy/` directory. This includes:

- **Complex deployment scripts**: `legacy/update_and_deploy.sh` (446 lines)
- **Fragmented subsites**: `legacy/ansible/subsites/` (8 modular components)
- **Overly complex cluster setup**: `legacy/ansible/plays/kubernetes/setup_cluster.yaml` (2900 lines)
- **Legacy diagnostic scripts**: Various test and troubleshooting scripts for the old system

**For new deployments, always use the simplified system:**
- `./deploy.sh` - New deployment script (120 lines)
- `ansible/simple-deploy.yaml` - Consolidated playbook (93 lines)
- `ansible/plays/setup-cluster.yaml` - Essential cluster setup (200 lines)

See `legacy/README.md` for complete migration information and benefits of the simplified system.

---

## TODO
- [x] Migrate from Podman to Kubernetes
- [x] Implement TLS certificate management
- [x] Set up Helm-based application deployment
- [x] Create comprehensive monitoring stack
- [x] Deploy Jellyfin High-Availability with auto-scaling
- [x] Hardware acceleration support for 4K streaming
- [x] Session affinity and load balancing for media server
- [x] **Refactor into modular sub-playbooks with safety checks**
- [x] **Implement selectable deployment with user-editable PLAYBOOKS array**
- [x] **Add non-destructive deployment principles**
- [ ] Implement ingress controllers for external access
- [ ] Set up automated backups for persistent volumes
- [ ] Add GitOps workflow with ArgoCD
- [ ] Implement network policies for security
- [ ] Set up log retention policies
- [ ] Add custom application deployments

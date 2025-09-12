# VMStation Kubernetes Cluster Deployment Guide

This guide provides comprehensive instructions for deploying and managing a complete Kubernetes cluster using kubeadm and Ansible.

## Architecture Overview

### Cluster Topology
- **Control Plane**: 192.168.4.63 (masternode) - Debian
  - Runs Kubernetes control plane components
  - Hosts monitoring stack (Prometheus + Grafana)
  - Role: `monitoring_nodes`

- **Storage Node**: 192.168.4.61 (storagenodet3500) - Debian  
  - Runs Jellyfin media server
  - Provides media storage via /srv/media
  - Role: `storage_nodes`

- **Compute Node**: 192.168.4.62 (homelab) - RHEL 10
  - Runs general application workloads
  - Handles compute-intensive tasks
  - Role: `compute_nodes`

### Technical Specifications
- **Kubernetes Version**: 1.29
- **Container Runtime**: containerd
- **CNI Plugin**: Flannel (pod subnet: 10.244.0.0/16)
- **Service Subnet**: 10.96.0.0/12
- **Control Plane Endpoint**: 192.168.4.63:6443

## Prerequisites

### SSH Access Requirements
- **Root access** on control plane (192.168.4.63) - local connection
- **Key-based SSH** to worker nodes with sudo privileges
- SSH private key file: `~/.ssh/id_k3s`

### System Requirements
- **Operating Systems**: Debian (control plane, storage) and RHEL 10 (compute)
- **Resources**: Minimum 2 CPU cores, 4GB RAM per node
- **Network**: All nodes in same subnet with bidirectional connectivity
- **Storage**: 
  - `/srv/media` directory on storage node for Jellyfin
  - `/var/lib/jellyfin` for configuration persistence

### Ansible Requirements
```bash
# Install required Ansible collections
ansible-galaxy collection install kubernetes.core
ansible-galaxy collection install community.general
```

### Configuration Status
- ✅ **Runtime configuration ready**: `ansible/group_vars/all.yml` configured with production settings
- ✅ **Inventory configured**: Node groups and IP mappings verified
- ✅ **RHEL 10 support**: Compute node sudo authentication configured via vault
- ✅ **Secrets template**: Available at `ansible/group_vars/secrets.yml.example`

## Quick Start Deployment

### 1. Basic Cluster Deployment
```bash
# Deploy complete cluster with all components
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cluster-bootstrap.yml

# Verify deployment
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/verify-cluster.yml
```

### 2. Idempotent Re-deployment
```bash
# Safe to run multiple times - will skip already configured components
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cluster-bootstrap.yml --check --diff

# Actually apply changes
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cluster-bootstrap.yml
```

## Detailed Deployment Process

### Phase 1: System Preparation
The cluster bootstrap automatically includes the existing `setup-cluster.yaml` which handles:

**For Debian nodes (control plane, storage):**
- Package cache updates
- Installation of containerd, kubeadm, kubelet, kubectl
- Kubernetes repository configuration
- Package version holding

**For RHEL 10 nodes (compute):**
- DNF repository configuration
- Package installation with retry logic
- SELinux configuration (set to Permissive for Kubernetes compatibility)
- Specialized RHEL 10 compatibility fixes

**Common tasks for all nodes:**
- Swap disabled permanently
- Kernel module loading (br_netfilter, overlay)
- Sysctl configuration for Kubernetes
- Containerd service configuration with systemd cgroup driver
- Firewall configuration (if required)

### Phase 2: Control Plane Initialization
```bash
# Manual kubeadm init (if needed)
kubeadm init --config=/etc/kubernetes/kubeadm-config.yaml --upload-certs
```

The bootstrap process:
1. Generates kubeadm configuration from template
2. Initializes control plane with proper networking
3. Configures kubeconfig for root user
4. Generates join tokens for worker nodes
5. Deploys Flannel CNI plugin
6. Waits for CoreDNS to become operational

### Phase 3: Worker Node Joining
Workers join with enhanced retry logic:
1. Copy join command securely to worker nodes
2. Execute join with automatic retries
3. Handle failures with cleanup and retry
4. Verify successful kubelet startup

### Phase 4: Application Deployment
**Monitoring Stack (on control plane):**
- Prometheus with cluster-wide metrics collection
- Grafana with pre-configured Prometheus datasource
- NodePort services for external access

**Jellyfin (on storage node):**
- Media server with persistent storage
- Scheduled specifically on storage node
- NodePort service for web access

## Service Access

### Monitoring Services
- **Prometheus**: http://192.168.4.63:30090
  - Metrics collection and querying
  - Kubernetes cluster monitoring

- **Grafana**: http://192.168.4.63:30300
  - Username: admin
  - Password: admin (change immediately)
  - Pre-configured Prometheus datasource

### Media Services  
- **Jellyfin**: http://192.168.4.61:30096
  - Media streaming server
  - Initial setup wizard on first access

### Kubernetes Access
```bash
# Copy kubeconfig from control plane
scp root@192.168.4.63:/etc/kubernetes/admin.conf ~/.kube/config

# Test cluster access
kubectl get nodes
kubectl get pods --all-namespaces
```

## Configuration Management

### Inventory Configuration
Edit `ansible/inventory/hosts.yml` to customize:
- Node IP addresses
- SSH credentials and keys
- Node labels and roles
- Resource limits

### Cluster Variables
Modify `ansible/group_vars/all.yml.template`:
```yaml
# Kubernetes version
kubernetes_version: "1.29"

# Network configuration
pod_network_cidr: "10.244.0.0/16"
service_network_cidr: "10.96.0.0/12"

# Monitoring configuration
monitoring_scheduling_mode: flexible  # or strict/unrestricted
grafana_nodeport: 30300
prometheus_nodeport: 30090

# Jellyfin configuration
jellyfin_enabled: true
jellyfin_node_name: storagenodet3500
jellyfin_media_path: /srv/media
```

## Operating System Specific Notes

### RHEL 10 Considerations
RHEL 10 requires special handling due to newer system components:

**SELinux Configuration:**
```bash
# Check current SELinux status
getenforce

# Set to Permissive for Kubernetes (recommended)
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

**Package Management:**
- Uses DNF package manager
- May require subscription or repository configuration
- Enhanced error handling for package download issues

**System Services:**
- Different systemd unit locations
- Enhanced kubelet service detection
- Automatic service remediation

### Debian Differences
- APT package management with automatic cache updates
- Different package names and repository structures
- Standard SELinux handling (usually disabled)

## Troubleshooting

### Common Issues

#### 1. Worker Node Join Failures
```bash
# Check node status
kubectl get nodes

# Check kubelet logs on failing node
journalctl -u kubelet -f

# Manual reset and rejoin
kubeadm reset --force
# Re-run join command from control plane
```

#### 2. Pod Networking Issues  
```bash
# Check Flannel pod status
kubectl get pods -n kube-flannel

# Verify CNI configuration
cat /etc/cni/net.d/10-flannel.conflist

# Check node routing
ip route show
```

#### 3. RHEL 10 Specific Issues
```bash
# Run RHEL 10 compatibility checker
./scripts/check_rhel10_compatibility.sh

# Apply RHEL 10 specific fixes
ansible-playbook -i ansible/inventory/hosts.yml ansible/plays/kubernetes/rhel10_setup_fixes.yaml
```

#### 4. Monitoring Stack Issues
```bash
# Check monitoring pod status
kubectl get pods -n monitoring

# Verify node selector constraints
kubectl describe pod -n monitoring prometheus-xxx

# Test service connectivity
curl http://192.168.4.63:30090/api/v1/query?query=up
```

#### 5. Storage and Persistence Issues
```bash
# Check PV/PVC status
kubectl get pv,pvc -n jellyfin

# Verify storage paths on nodes
ansible storage_nodes -i ansible/inventory/hosts.yml -m shell -a "ls -la /srv/media /var/lib/jellyfin"

# Check Jellyfin pod logs
kubectl logs -n jellyfin deployment/jellyfin
```

### Diagnostic Commands

```bash
# Cluster health overview
kubectl get nodes -o wide
kubectl get pods --all-namespaces
kubectl top nodes

# Component status
kubectl get componentstatuses

# Event monitoring
kubectl get events --sort-by=.metadata.creationTimestamp

# Resource usage
kubectl describe node <node-name>
kubectl top pods --all-namespaces
```

### Reset Procedures

#### Soft Reset (Recommended)
```bash
# Reset specific node
kubeadm reset --force

# Clean up configuration
rm -rf /etc/kubernetes/kubelet.conf /var/lib/kubelet/pki

# Rejoin with fresh token
```

#### Hard Reset (Nuclear Option)
```bash
# Complete cluster teardown
ansible-playbook -i ansible/inventory/hosts.yml ansible/subsites/00-spindown.yaml

# Full re-deployment
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cluster-bootstrap.yml
```

#### Per-node Reset
```bash
# On the node to reset
kubeadm reset --force
systemctl stop kubelet containerd
rm -rf /etc/kubernetes/ /var/lib/kubelet/ /var/lib/containerd/
rm -rf /etc/cni/net.d/ /var/lib/cni/
systemctl start containerd kubelet

# Generate new join command on control plane
kubeadm token create --print-join-command
```

## Security Considerations

### File Permissions
All generated files have appropriate restrictive permissions:
- kubeadm config: 0600 (root only)
- join command files: 0700 (root executable only)  
- kubeconfig files: 0600 (root only)

### Network Security
- CNI provides pod-to-pod encryption via VXLAN
- Service-to-service communication within cluster
- NodePort services expose applications externally
- Consider implementing NetworkPolicies for production

### Secrets Management
```bash
# Create secrets.yml from template
cp ansible/group_vars/secrets.yml.example ansible/group_vars/secrets.yml

# Encrypt with ansible-vault
ansible-vault encrypt ansible/group_vars/secrets.yml

# Edit encrypted secrets
ansible-vault edit ansible/group_vars/secrets.yml
```

## Maintenance Operations

### Certificate Management
```bash
# Check certificate expiration
kubeadm certs check-expiration

# Renew certificates (before expiration)
kubeadm certs renew all

# Restart control plane components
systemctl restart kubelet
```

### Cluster Upgrades
```bash
# Plan upgrade
kubeadm upgrade plan

# Upgrade control plane
kubeadm upgrade apply v1.29.x

# Upgrade worker nodes (one at a time)
kubeadm upgrade node
systemctl restart kubelet
```

### Backup Procedures
```bash
# Backup etcd
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db

# Backup important configurations
tar -czf /backup/kubernetes-config.tar.gz /etc/kubernetes/

# Backup application data
rsync -av /srv/media/ /backup/jellyfin-media/
rsync -av /var/lib/jellyfin/ /backup/jellyfin-config/
```

### Monitoring Maintenance
```bash
# Restart monitoring stack
kubectl rollout restart deployment/prometheus -n monitoring  
kubectl rollout restart deployment/grafana -n monitoring

# Update Grafana admin password
kubectl exec -n monitoring deployment/grafana -- grafana-cli admin reset-admin-password <new-password>
```

## Integration with Existing Infrastructure

### Legacy Compatibility
This deployment works alongside existing infrastructure:
- Preserves existing `/srv/media` directories
- Maintains compatibility with existing SSH keys
- Uses existing monitoring data directories where possible

### Migration from Legacy Systems
```bash
# Check current system state
./scripts/validate_comprehensive_setup.sh

# Migrate from Podman-based systems
# See existing migration documentation in docs/
```

## Performance Tuning

### Resource Optimization
```yaml
# In group_vars/all.yml
prometheus_storage_size: 20Gi      # Increase for longer retention
grafana_storage_size: 10Gi         # Increase for more dashboards
jellyfin_resources:
  limits:
    cpu: 4000m                     # Increase for 4K transcoding
    memory: 4Gi                    # Increase for large libraries
```

### Network Optimization
```bash
# Optimize Flannel performance
kubectl patch daemonset kube-flannel-ds -n kube-flannel -p '{"spec":{"template":{"spec":{"containers":[{"name":"kube-flannel","resources":{"requests":{"cpu":"200m","memory":"100Mi"}}}]}}}}'
```

## Advanced Configuration

### Custom Node Labels
```bash
# Add custom labels to nodes
kubectl label node storagenodet3500 media-server=jellyfin
kubectl label node homelab workload-type=compute-intensive
```

### Additional Applications
```bash
# Deploy custom applications to specific nodes
kubectl apply -f manifests/custom-app.yaml
```

### Ingress Controllers
```bash
# Install NGINX Ingress for external access
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml
```

## Support and Documentation

### Additional Resources
- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [kubeadm Documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [Flannel CNI Documentation](https://github.com/flannel-io/flannel)

### VMStation Specific Documentation
- `docs/RHEL10_TROUBLESHOOTING.md` - RHEL 10 specific issues
- `docs/AGGRESSIVE_NODE_RESET.md` - Advanced reset procedures  
- `scripts/README.md` - Helper script documentation

### Getting Help
1. Check logs: `journalctl -u kubelet -f`
2. Run verification: `ansible-playbook verify-cluster.yml`
3. Review troubleshooting guides in `docs/`
4. Use diagnostic scripts in `scripts/`

---

*This guide covers deployment and management of a production-ready Kubernetes cluster optimized for the VMStation infrastructure. Regular updates and maintenance are essential for security and performance.*
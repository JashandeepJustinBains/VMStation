# VMStation Simplified Deployment

This document describes the new simplified deployment system for VMStation that replaces the complex previous system.

## Overview

The VMStation deployment has been significantly simplified from 3000+ lines of complex code to under 500 lines of clean, maintainable deployment logic.

### What Was Simplified

**Before:**
- Complex `update_and_deploy.sh` (447 lines) with extensive error handling
- Overly complex `setup_cluster.yaml` (2901 lines) with multiple fallbacks
- 8+ separate subsites requiring individual management
- Excessive CNI download fallbacks indicating brittleness
- Complex certificate and kubelet recovery logic

**After:**
- Simple `deploy.sh` (75 lines) with clear options
- Clean `setup-cluster.yaml` (200 lines) with essential functionality
- Consolidated `simple-deploy.yaml` combining essential features
- Standard Kubernetes and CNI setup
- Minimal error handling for robust operation

## Quick Start

1. **Deploy complete stack:**
   ```bash
   ./deploy.sh
   ```

2. **Deploy only Kubernetes cluster:**
   ```bash
   ./deploy.sh cluster
   ```

3. **Deploy only applications:**
   ```bash
   ./deploy.sh apps
   ```

4. **Check deployment (dry run):**
   ```bash
   ./deploy.sh check
   ```

## Architecture

### Infrastructure
- **Control Plane:** 192.168.4.63 (monitoring_nodes)
- **Storage Node:** 192.168.4.61 (storage_nodes) 
- **Compute Node:** 192.168.4.62 (compute_nodes)

### Applications Deployed
- **Monitoring Stack:** Prometheus, Grafana, Loki on control plane
- **Jellyfin:** Media server on storage node
- **Kubernetes Dashboard:** Web UI for cluster management

### Access URLs
- Grafana: http://192.168.4.63:30300 (admin/admin)
- Prometheus: http://192.168.4.63:30090
- Loki: http://192.168.4.63:31100
- Jellyfin: http://192.168.4.61:30096

## File Structure

```
deploy.sh                           # Main deployment script
ansible/
├── simple-deploy.yaml             # Main deployment playbook
├── plays/
│   ├── setup-cluster.yaml         # Kubernetes cluster setup
│   ├── deploy-apps.yaml           # Application deployment
│   └── jellyfin.yml               # Jellyfin deployment (existing)
├── inventory.txt                   # Node inventory
└── group_vars/
    ├── all.yml                     # Configuration
    └── all.yml.template            # Configuration template
```

## Configuration

The deployment uses `ansible/group_vars/all.yml` for configuration. If this file doesn't exist, it will be created automatically from the template with sensible defaults.

Key configuration options:
- `kubernetes_version`: Kubernetes version to install
- `jellyfin_enabled`: Enable/disable Jellyfin deployment
- `monitoring_namespace`: Namespace for monitoring apps
- Node ports for each service

## Deployment Options

### Full Deployment
```bash
./deploy.sh full    # or just ./deploy.sh
```
Deploys complete VMStation stack including Kubernetes cluster and all applications.

### Cluster Only
```bash
./deploy.sh cluster
```
Sets up Kubernetes cluster without applications. Useful for initial cluster setup or cluster-only updates.

### Applications Only
```bash
./deploy.sh apps
```
Deploys monitoring and dashboard applications to existing cluster. Requires cluster to already exist.

### Jellyfin Only
```bash
./deploy.sh jellyfin
```
Deploys only Jellyfin media server. Requires cluster to exist.

### Check Mode
```bash
./deploy.sh check
```
Runs deployment in check mode (dry run) to validate configuration without making changes.

### Infrastructure Removal (Spindown)

⚠️ **WARNING: Destructive operations that will completely remove Kubernetes infrastructure** ⚠️

#### Safe Preview (Recommended First)
```bash
./deploy.sh spindown-check
```
Shows what would be removed without making any changes. Always run this first to review the cleanup scope.

#### Complete Infrastructure Removal
```bash
./deploy.sh spindown
```
**DESTRUCTIVE**: Completely removes all VMStation and Kubernetes infrastructure including:

- **Services & Processes**: All Kubernetes services (kubelet, kube-apiserver, etcd, etc.)
- **Packages**: Kubernetes packages (kubeadm, kubectl, kubelet), container runtimes (docker, containerd, podman)
- **Data Directories**: `/etc/kubernetes`, `/var/lib/kubelet`, `/var/lib/etcd`, `/var/lib/containerd`, etc.
- **Network Configuration**: CNI interfaces (cni0, flannel.1), iptables rules, routing tables
- **System Configuration**: systemd services, drop-in directories, user configurations
- **Certificates & TLS**: All cluster certificates and TLS configurations
- **Storage**: Container images, volumes, local-path provisioner data
- **Monitoring Data**: Prometheus, Grafana, and Loki data
- **Temporary Files**: Caches, temporary files, build artifacts

The spindown process includes:
1. **Safety confirmation** - Requires typing 'yes' to proceed
2. **Comprehensive cleanup** - Removes all infrastructure components systematically
3. **Validation reporting** - Shows cleanup results and any remaining artifacts

#### Recovery After Spindown
After running spindown, the system is returned to a clean state. To redeploy:
```bash
./deploy.sh full    # Complete fresh deployment
```
Worker nodes will automatically rejoin the cluster with fresh certificates and tokens.

## Troubleshooting

### Common Issues

**SSH Connection Errors:**
- Ensure SSH keys are properly configured for all nodes
- Verify nodes are accessible: `ansible -i ansible/inventory.txt all -m ping`

**Network Connectivity:**
- Check firewall rules allow Kubernetes ports (6443, 10250, etc.)
- Ensure nodes can reach package repositories

**Application Access:**
- Verify NodePort services: `kubectl get svc -n monitoring`
- Check pod status: `kubectl get pods -n monitoring`

### Validation Commands

```bash
# Check cluster status
kubectl get nodes -o wide

# Check all pods
kubectl get pods --all-namespaces

# Check monitoring services
kubectl get svc -n monitoring

# Check Jellyfin
kubectl get pods -n jellyfin -o wide
```

## Migration from Complex System

If migrating from the previous complex deployment:

1. **Backup existing configuration:**
   ```bash
   cp ansible/group_vars/all.yml ansible/group_vars/all.yml.backup
   ```

2. **Test new deployment in check mode:**
   ```bash
   ./deploy.sh check
   ```

3. **Deploy incrementally:**
   ```bash
   ./deploy.sh cluster    # First ensure cluster is working
   ./deploy.sh apps       # Then deploy applications
   ./deploy.sh jellyfin   # Finally deploy Jellyfin
   ```

## Benefits of Simplification

1. **Reduced Complexity:** 85% reduction in lines of code
2. **Improved Reliability:** Less error handling = fewer edge cases
3. **Easier Maintenance:** Simple, readable code structure
4. **Faster Deployment:** No excessive fallbacks or recovery logic
5. **Better Testing:** Simple components are easier to test
6. **Clear Documentation:** Straightforward usage and troubleshooting

## Advanced Usage

### Custom Configuration
Edit `ansible/group_vars/all.yml` to customize:
- Kubernetes version
- Service ports
- Storage paths
- Application settings

### Individual Playbooks
Run specific playbooks directly:
```bash
cd ansible
ansible-playbook -i inventory.txt plays/setup-cluster.yaml
ansible-playbook -i inventory.txt plays/deploy-apps.yaml
```

### Ansible Commands
```bash
# Check inventory
ansible-inventory -i ansible/inventory.txt --list

# Ping all nodes
ansible -i ansible/inventory.txt all -m ping

# Run specific tasks
ansible -i ansible/inventory.txt monitoring_nodes -m command -a "kubectl get nodes"
```
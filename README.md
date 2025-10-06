
# VMStation Kubernetes Cloud Overview

Welcome to VMStation! A home cloud infrastructure with a **two-phase deployment model**: Debian nodes run kubeadm/Kubernetes, and RHEL10 runs a separate RKE2 cluster for isolation and monitoring federation.

## 🚀 Two-Phase Deployment Architecture

VMStation now uses a **simplified two-phase deployment**:

1. **Phase 1: Debian Cluster (kubeadm)** - Control plane and storage nodes
2. **Phase 2: RKE2 on RHEL10** - Separate cluster on homelab node with monitoring federation

This architecture provides:
- ✅ **Clean separation**: No more RHEL10 worker-node integration issues
- ✅ **Simplified deployment**: Each phase is independent and testable
- ✅ **Better monitoring**: RKE2 cluster runs Prometheus federation
- ✅ **Easy maintenance**: No complex network-fix roles for RHEL10

---

## Quick Start

### Option 1: Deploy Everything (Recommended)

```bash
cd /srv/monitoring_data/VMStation

# Deploy both Debian and RKE2 clusters
./deploy.sh all --with-rke2

# Or interactively (will prompt before RKE2)
./deploy.sh all
```

### Option 2: Deploy Phase by Phase

```bash
# Phase 1: Deploy Debian cluster (monitoring + storage nodes)
./deploy.sh debian

# Verify Debian cluster
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A

# Phase 2: Deploy RKE2 to homelab
./deploy.sh rke2

# Verify RKE2 cluster
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
kubectl get pods -A
```

### Reset Everything

```bash
# Reset both clusters (Debian + RKE2)
./deploy.sh reset

# After reset, you can redeploy immediately - binaries will be auto-installed
./deploy.sh all --with-rke2 --yes
```

> **Note**: After reset, Kubernetes binaries (kubeadm/kubelet/kubectl) are automatically installed if missing during the next deployment. No manual installation required! See [Post-Reset Deployment Fix](docs/POST_RESET_DEPLOYMENT_FIX.md) for details.

---

## Deployment Commands

### Main Commands

| Command | Description | Example |
|---------|-------------|---------|
| `debian` | Deploy kubeadm to Debian nodes only | `./deploy.sh debian` |
| `rke2` | Deploy RKE2 to homelab with pre-checks | `./deploy.sh rke2` |
| `all` | Deploy both phases (requires `--with-rke2`) | `./deploy.sh all --with-rke2` |
| `reset` | Reset both clusters completely | `./deploy.sh reset` |
| `setup` | Setup auto-sleep monitoring | `./deploy.sh setup` |
| `spindown` | Graceful shutdown (no power-off) | `./deploy.sh spindown` |

### Flags

| Flag | Description | Example |
|------|-------------|---------|
| `--yes` | Skip confirmations (for automation) | `./deploy.sh rke2 --yes` |
| `--check` | Dry-run mode (show planned actions) | `./deploy.sh debian --check` |
| `--with-rke2` | Auto-proceed with RKE2 in `all` | `./deploy.sh all --with-rke2` |
| `--log-dir` | Custom log directory | `./deploy.sh debian --log-dir=/tmp/logs` |

---

## Architecture Overview

### Debian Cluster (kubeadm)
- **Control Plane**: masternode (192.168.4.63)
- **Worker**: storagenodet3500 (192.168.4.61)
- **Kubernetes Version**: 1.29
- **CNI**: Flannel
- **Purpose**: Main workloads, Jellyfin, storage

### RKE2 Cluster (homelab)
- **Single Node**: homelab (192.168.4.62)
- **Kubernetes Version**: 1.29.x (RKE2)
- **CNI**: Canal (Flannel + Calico)
- **Purpose**: Monitoring, federation, RHEL10 workloads
- **Monitoring Stack**:
  - Node Exporter (port 9100)
  - Prometheus (port 30090)
  - Federation endpoint for central Prometheus

---

## Artifacts and Logs

All deployment artifacts are stored in `ansible/artifacts/`:

```
ansible/artifacts/
├── deploy-debian.log              # Debian deployment log
├── install-rke2-homelab.log       # RKE2 installation log
├── homelab-rke2-kubeconfig.yaml   # RKE2 cluster kubeconfig
├── reset-debian.log               # Reset logs
└── uninstall-rke2.log             # RKE2 uninstall logs
```

**Access RKE2 cluster:**
```bash
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
kubectl get pods -A
```

---

## Monitoring & Federation

### Prometheus Federation Setup

The RKE2 cluster exposes a Prometheus federation endpoint that the Debian cluster's Prometheus can scrape:

**Federation URL**: `http://192.168.4.62:30090/federate`

**Test federation:**
```bash
curl -s 'http://192.168.4.62:30090/federate?match[]={job=~".+"}' | head -20
```

**Add to central Prometheus** (`prometheus-config.yaml`):
```yaml
scrape_configs:
  - job_name: 'federate-rke2'
    scrape_interval: 30s
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job=~".+"}'
    static_configs:
      - targets:
        - '192.168.4.62:30090'
```

### Monitoring Endpoints

- **Node Exporter**: http://192.168.4.62:9100/metrics
- **Prometheus UI**: http://192.168.4.62:30090
- **Federation**: http://192.168.4.62:30090/federate

---

## Testing and Validation

VMStation includes comprehensive tests to verify the deployment:

### Pre-Deployment Tests

```bash
# Test deployment script behavior
./tests/test-deploy-limits.sh

# Validate environment
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/test-environment.yaml \
  --ask-vault-pass
```

### Post-Deployment Validation

```bash
# Verify Debian cluster
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A

# Verify RKE2 cluster
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
kubectl get pods -n monitoring-rke2

# Test federation
curl -s 'http://192.168.4.62:30090/federate?match[]={job=~".+"}' | head
```

---

## Troubleshooting

### Common Issues

**Issue**: Debian deployment fails
```bash
# Check logs
cat ansible/artifacts/deploy-debian.log

# Reset and retry
./deploy.sh reset
./deploy.sh debian
```

**Issue**: RKE2 pre-checks fail (old kubeadm artifacts)
```bash
# Run cleanup manually
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/cleanup-homelab.yml

# Then deploy RKE2
./deploy.sh rke2
```

**Issue**: Cannot reach homelab via SSH
```bash
# Test connectivity
ansible homelab -i ansible/inventory/hosts.yml -m ping

# Check SSH keys
ls ~/.ssh/id_k3s
```

---

## Documentation

- **[RKE2 Implementation](RKE2_COMPLETE_IMPLEMENTATION.md)** - Complete RKE2 setup details
- **[Test Environment Guide](TEST_ENVIRONMENT_GUIDE.md)** - Testing and validation
- **[Deployment Runbook](ansible/playbooks/RKE2_DEPLOYMENT_RUNBOOK.md)** - Step-by-step deployment
- **[Inventory Configuration](ansible/inventory/hosts.yml)** - Host definitions

---

## Migration from Old Worker-Node Approach

If you previously had homelab as a kubeadm worker node, you must:

1. **Reset the old setup**:
   ```bash
   ./deploy.sh reset
   ```

2. **Deploy the new two-phase model**:
   ```bash
   ./deploy.sh all --with-rke2
   ```

All old RHEL10 worker-node documentation and scripts have been removed. The new RKE2 approach is simpler and more reliable.

---
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

## Recovery workflow: homelab node fixes and deployment safety

When a RHEL worker (for example the homelab R430) shows Flannel or kube-proxy instability, use the included idempotent host-fix script to apply persistent and transient fixes. This section documents when to run it, how to run it non-interactively, and how to confirm the node is healthy.

When to run
- Run the script if kube-proxy or flannel pods on a RHEL node are in CrashLoopBackOff, Pending, or show repeated restarts.
- Run it when kubelet logs show errors about swap being enabled, xtables locks, or iptables failures.

Run the fix script (interactive or non-interactive)
- Interactive (recommended): the script will prompt for your sudo password if needed.

```powershell
# run from the repo root; you will be prompted for your sudo password
./scripts/fix_homelab_node_issues.sh
```

- Non-interactive (one-off): export SUDO_PASS in your shell session (temporary) so the script can run without prompting.

```powershell
# set for the session, run, then unset
$env:SUDO_PASS='your_sudo_password_here'; ./scripts/fix_homelab_node_issues.sh; Remove-Item Env:\SUDO_PASS
```

Vault-aware execution
- If you use Ansible Vault to store `ansible_become_pass` or `vault_r430_sudo_password`, the script can attempt to decrypt `ansible/inventory/group_vars/secrets.yml` if `ANSIBLE_VAULT_PASSWORD_FILE` is set in the environment and `ansible-vault` is available.

Integrate into deploy
- Quick (fast): call the script early in `deploy.sh` before kubeadm/kubelet startup to ensure host preflight state. This is safe because the script is idempotent.

```powershell
# inside deploy.sh (early step)
./scripts/fix_homelab_node_issues.sh || exit 1
```

- Recommended (production quality): convert the script's operations into an Ansible preflight role and run the role from `ansible/playbooks/deploy-cluster.yaml`. This integrates vault, become, and inventory management cleanly.

What the script enforces
- Disables swap and removes swap from `/etc/fstab` (persistent)
- Ensures `/run/xtables.lock` exists and required kernel modules are loaded
- Configures iptables alternatives and enables nftables where appropriate (RHEL)
- Cleans stale CNI interfaces and restarts kubelet/kube-proxy/flannel as needed

Quick verification commands

```powershell
# Check node and pod health
kubectl get nodes -o wide
kubectl get pods -A -o wide | grep -E "kube-proxy|flannel|coredns|kube-system"

# Check node-level state (run on the RHEL node or use ssh)
ssh user@r430 'sudo swapon --show || echo no-active-swap; sudo grep -E "^[^#].*swap" /etc/fstab || echo no-swap-in-fstab'
ssh user@r430 'sudo getenforce || echo selinux-not-available; sudo grep ^SELINUX= /etc/selinux/config'
ssh user@r430 'test -f /run/xtables.lock && echo xtables-lock-present || echo xtables-lock-missing'
ssh user@r430 'sudo iptables --version || echo iptables-missing'
```

## Resetting pod restart counts (view and reset)

Kubernetes tracks restart counts per container inside a Pod. There is no API to zero an existing Pod's restart counter; the counter resets when a new Pod object (new UID) is created. Use one of the following safe options depending on your controller type:

- View restart counts across all namespaces:

```powershell
kubectl get pods -A --no-headers -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount' | column -t
```

- Reset restart count for a Pod managed by a controller (Deployment/DaemonSet/StatefulSet): delete the Pod and the controller will recreate it with restartCount=0.

```powershell
kubectl delete pod <pod-name> -n <namespace>
```

- Restart a controller (preferred for DaemonSet/Deployment):

```powershell
kubectl rollout restart deployment/<name> -n <namespace>
kubectl rollout restart daemonset/<name> -n <namespace>
```

- Restart all pods in a namespace (careful — disruptive):

```powershell
kubectl delete pod --all -n <namespace>
```

Notes and tips
- Always inspect pod events and previous logs before deleting to understand root cause:

```powershell
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
```

- For kube-system DaemonSets (kube-proxy, flannel) prefer `rollout restart` on the DaemonSet instead of deleting all pods at once.

- Add these steps to your runbook and consider turning the script into an Ansible preflight role to avoid manual execution.


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
- **Pod health validation**: `./scripts/validate_pod_health.sh` - **NEW!** Quick validation of all pod health status
- **Jellyfin readiness fix**: `./fix_jellyfin_readiness.sh` - **NEW!** Fixes jellyfin probe configuration and readiness issues
- **Jellyfin network fix**: `./fix_jellyfin_network_issue.sh` - **NEW!** Fixes "no route to host" network connectivity issues
- **Jellyfin network test**: `./test_jellyfin_network.sh` - **NEW!** Tests network connectivity and CNI bridge configuration
- **Jellyfin config test**: `./test_jellyfin_config.sh` - **NEW!** Validates jellyfin pod configuration
- **Remaining pod fixes**: `./scripts/fix_remaining_pod_issues.sh` - **NEW!** Fixes jellyfin readiness and kube-proxy crashloop issues
- **Pod diagnostics**: `./scripts/diagnose_remaining_pod_issues.sh` - **NEW!** Detailed analysis of pod failures
- **Service enablement**: `./scripts/fix_kubernetes_service_enablement.sh` - **NEW!** Enables disabled kubelet/containerd services
- **CNI bridge conflicts**: `./scripts/fix_cni_bridge_conflict.sh` - **NEW!** Fixes CNI bridge IP conflicts causing ContainerCreating errors
- **CNI bridge reset**: `sudo ./scripts/reset_cni_bridge.sh` - **NEW!** Quick reset for "cni0 already has IP address different from 10.244.x.x" errors
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
For immediate fixes to pods stuck in CrashLoopBackOff or not ready:

```bash
# Validate current pod health status
./scripts/validate_pod_health.sh

# Diagnose specific pod failures
./scripts/diagnose_remaining_pod_issues.sh

# Fix remaining pod issues (jellyfin readiness, kube-proxy crashloop, etc.)
./scripts/fix_remaining_pod_issues.sh

# For monitoring pods specifically
./scripts/fix_k8s_monitoring_pods.sh
```

**Common fixes include**:
- ✅ **Jellyfin 0/1 Ready** - Health check endpoint fixes and volume permission corrections
- ✅ **kube-proxy CrashLoopBackOff** - Network configuration fixes for worker nodes
- ✅ **ContainerCreating pods** - CNI bridge IP conflict resolution
- ✅ **Grafana Init:CrashLoopBackOff** - Permission fixes for UID 472:472
- ✅ **Loki CrashLoopBackOff** - Configuration fixes for max_retries errors
- ✅ **Step-by-step remediation** - Exact commands for config/manifest/permission fixes

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

#### CoreDNS Scheduling to Worker Nodes ⚡ **NEW!**
If CoreDNS pods are being scheduled to worker nodes like "homelab" instead of staying on the masternode:
```bash
# Check current CoreDNS pod placement
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# Test CoreDNS scheduling configuration
./scripts/test_coredns_masternode_scheduling.sh

# Fix CoreDNS to require masternode scheduling  
./scripts/fix_homelab_node_issues.sh

# This ensures:
# - CoreDNS will ONLY run on control-plane nodes (masternode)
# - CoreDNS will NEVER be scheduled to worker nodes (homelab, storage)
# - Uses required node affinity instead of preferred
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
```

#### Flannel CNI Timing Issues ⚡ **NEW!**
If you encounter errors during deployment like:
- `failed to find plugin "flannel" in path [/opt/cni/bin]`
- `failed to load flannel 'subnet.env' file`
- Flannel pods in CrashLoopBackOff
- CoreDNS/kube-proxy failing to create pod sandbox

```bash
# Check flannel pod status
kubectl -n kube-flannel get pods -o wide

# Check for subnet.env file on each node
ssh root@masternode 'ls -l /run/flannel/subnet.env'
ssh jashandeepjustinbains@192.168.4.62 'sudo ls -l /run/flannel/subnet.env'

# Emergency fix for RHEL node
./scripts/fix-flannel-homelab.sh
```

**Root Cause:** Pods were being scheduled before flannel daemon fully initialized.

**Automated Fix:** The deployment playbook now includes proper readiness checks to ensure flannel is fully ready (subnet.env created) before proceeding. See [docs/FLANNEL_TIMING_ISSUE_FIX.md](docs/FLANNEL_TIMING_ISSUE_FIX.md) for details.
# - Control-plane taint issues preventing CoreDNS scheduling
```

#### CNI Bridge IP Conflicts ⚡ **NEW!**
If pods are stuck in ContainerCreating due to CNI bridge IP conflicts:
```bash
# Quick validation to detect CNI bridge conflicts
./scripts/validate_network_prerequisites.sh

# Quick reset for CNI bridge IP conflicts (recommended)
sudo ./scripts/reset_cni_bridge.sh

# Alternative comprehensive fix 
./scripts/fix_cni_bridge_conflict.sh

# This fixes:
# - Pods stuck in "ContainerCreating" state
# - "cni0 already has an IP address different from 10.244.x.x" errors
# - CNI bridge (cni0) IP address conflicts with Flannel subnet
# - "failed to set bridge addr" errors in pod events
# - Automatic integration with existing fix scripts
```

📖 **Documentation**: 
- **Quick CNI reset**: [docs/CNI_BRIDGE_RESET.md](./docs/CNI_BRIDGE_RESET.md) - Fast targeted fix
- CoreDNS scheduling fixes: [docs/COREDNS_MASTERNODE_ENFORCEMENT.md](./docs/COREDNS_MASTERNODE_ENFORCEMENT.md)
- CoreDNS unknown status: [docs/COREDNS_UNKNOWN_STATUS_FIX.md](./docs/COREDNS_UNKNOWN_STATUS_FIX.md)

**Key Features of this fix**:
- ✅ Automatically integrated into `deploy.sh full` workflow
- ✅ Removes control-plane taints that prevent CoreDNS scheduling  
- ✅ Forces rescheduling of stuck CoreDNS pods
- ✅ Validates DNS resolution functionality
- ✅ Enables other pending pods to start correctly

#### Jellyfin Pod Readiness Issues ⚡ **NEW!**
If Jellyfin shows 0/1 Ready status with probe failures:

```bash
# Quick fix for Jellyfin readiness issues
./fix_jellyfin_readiness.sh

# Test configuration after fix
./test_jellyfin_config.sh

# Check jellyfin status
kubectl get pods -n jellyfin -o wide
kubectl describe pod -n jellyfin jellyfin
```

**Common fixes include**:
- ✅ **Incorrect probe paths** - Updates health check endpoints from `/web/index.html` to `/`
- ✅ **Volume permission issues** - Ensures host directories have correct permissions for UID 1000
- ✅ **Configuration inconsistencies** - Applies consistent security context and resource limits
- ✅ **Network connectivity** - Validates pod networking and service configuration

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

## Troubleshooting

### Common Issues and Fixes

#### 1. Cluster Networking Problems
If you experience Flannel CrashLoopBackOff, CoreDNS issues, or pods stuck in ContainerCreating:

```bash
# Check overall cluster status
./scripts/vmstation_status.sh

# Fix homelab node networking issues  
./scripts/fix_homelab_node_issues.sh

# Fix CoreDNS-specific issues
./scripts/fix_coredns_unknown_status.sh
```

#### 2. Application Deployment Hanging
If `deploy.sh full` hangs on "wait for applications to be ready":

```bash
# Check cluster networking first
./scripts/check_coredns_status.sh

# Apply fixes and redeploy applications
./scripts/fix_homelab_node_issues.sh

# If jellyfin shows 0/1 Ready or CrashLoopBackOff
./scripts/fix_remaining_pod_issues.sh

# For Jellyfin "no route to host" network issues specifically
./fix_jellyfin_network_issue.sh

# Check overall pod health
./scripts/validate_pod_health.sh
./deploy.sh apps
```

#### 3. Jellyfin Not Deploying
If Jellyfin doesn't appear in the cluster:

```bash
# Check storage node readiness
kubectl get nodes storagenodet3500 -o wide

# Deploy Jellyfin specifically
./deploy.sh jellyfin

# Check deployment status
kubectl get pods -n jellyfin -o wide
```

#### 4. Jellyfin Pod Network Connectivity Issues
If Jellyfin pod shows 0/1 Ready with "no route to host" probe failures:

```bash
# Quick test to identify the issue
./test_jellyfin_network.sh

# Apply network connectivity fix
./fix_jellyfin_network_issue.sh

# Verify the fix worked
kubectl get pods -n jellyfin
```

#### 5. Pods on Wrong Nodes
If CoreDNS runs on homelab instead of masternode:

```bash
# Apply CoreDNS scheduling fix
./scripts/fix_homelab_node_issues.sh

# Verify CoreDNS is on control-plane
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
```

### Comprehensive Status Check

For a complete overview of cluster health and recommendations:

```bash
./scripts/vmstation_status.sh
```

### Emergency Recovery

If the cluster is completely broken:

```bash
# Reset and rebuild cluster
./deploy.sh spindown  # Remove all infrastructure
./deploy.sh full      # Fresh deployment with fixes
```

For detailed troubleshooting information, see:
- [docs/HOMELAB_NODE_FIXES.md](./docs/HOMELAB_NODE_FIXES.md) - General cluster issues
- [docs/jellyfin-cni-bridge-fix.md](./docs/jellyfin-cni-bridge-fix.md) - Jellyfin CNI bridge conflicts
- [README-CNI-FIX.md](./README-CNI-FIX.md) - CNI networking issues

## Legacy Files

The previous complex deployment system (with 85% more code) has been moved to the `legacy/` directory. This includes:

- **Complex deployment scripts**: `legacy/update_and_deploy.sh` (446 lines)
- **Fragmented subsites**: `legacy/ansible/subsites/` (8 modular components)
- **Overly complex cluster setup**: `legacy/ansible/plays/kubernetes/setup_cluster.yaml` (2900 lines)
- **Legacy diagnostic scripts**: Various test and troubleshooting scripts for the old system

**For new deployments, always use the current system:**
- `./deploy-cluster.sh` - Main deployment script (967 lines)
- `scripts/enhanced_kubeadm_join.sh` - Enhanced join process (1388 lines)
- `ansible/plays/setup-cluster.yaml` - Essential cluster setup

See `scripts/README.md` for complete script documentation and usage information.

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

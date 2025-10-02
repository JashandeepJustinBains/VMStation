# README Update - Cluster Reset Section

## Suggested Addition to Main README.md

Add this section after the "Deployment" section:

---

## 🔄 Cluster Reset

### Quick Reset

Safely wipe your Kubernetes cluster and start fresh:

```bash
./deploy.sh reset
```

This will:
- ✅ Gracefully drain all nodes
- ✅ Remove Kubernetes configurations
- ✅ Clean K8s network interfaces (flannel*, cni*, calico*, etc.)
- ✅ Flush iptables rules
- ✅ Stop and disable kubelet
- ✅ **Preserve SSH keys** (verified)
- ✅ **Preserve physical ethernet interfaces** (verified)

### Safety Features

The reset operation includes multiple safety checks:

- **User Confirmation**: Must type 'yes' to proceed
- **SSH Verification**: Checks SSH keys before and after reset
- **Interface Protection**: Physical ethernet interfaces (eth*, ens*, eno*, enp*) are never touched
- **Graceful Drain**: 120-second timeout for pod eviction
- **Serial Execution**: One node at a time for reliability

### When to Use Reset

Use cluster reset when you need to:

1. **Clean Slate**: Start completely fresh after configuration changes
2. **Fix Networking**: Resolve persistent CNI or networking issues
3. **Config Changes**: Apply major kubeadm configuration changes
4. **Development**: Rapid iteration during development/testing
5. **Recovery**: Nuclear option when troubleshooting fails

### Reset Workflow

```bash
# 1. Reset cluster
./deploy.sh reset

# 2. Confirm (type: yes)
Please type 'yes' to confirm cluster reset: yes

# 3. Wait for completion (~3-4 minutes)
[... reset progress ...]
CLUSTER RESET COMPLETED SUCCESSFULLY

# 4. Verify clean state
ls /etc/kubernetes     # Should not exist
ip link | grep cni     # Should return nothing
ssh root@192.168.4.61 uptime  # SSH should work

# 5. Deploy fresh cluster
./deploy.sh

# 6. Validate
kubectl get nodes      # All Ready
kubectl get pods -A    # All Running
```

### Advanced Usage

#### Dry Run (Check Mode)

Test what would be reset without making changes:

```bash
ansible-playbook --check \
  -i ansible/inventory/hosts \
  ansible/playbooks/reset-cluster.yaml
```

#### Targeted Reset

Reset only worker nodes:

```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/reset-cluster.yaml \
  --limit compute_nodes:storage_nodes
```

Reset specific node:

```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/reset-cluster.yaml \
  --limit homelab
```

#### Skip Confirmation

For automation (use with caution):

```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/reset-cluster.yaml \
  --extra-vars "reset_confirmed=yes"
```

### Documentation

- **Quick Start**: [QUICKSTART_RESET.md](QUICKSTART_RESET.md)
- **User Guide**: [docs/CLUSTER_RESET_GUIDE.md](docs/CLUSTER_RESET_GUIDE.md)
- **Role Docs**: [ansible/roles/cluster-reset/README.md](ansible/roles/cluster-reset/README.md)
- **Testing**: [VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md)

### Performance

- **Reset Time**: ~3-4 minutes (3-node cluster)
- **Deploy Time**: ~10-15 minutes (full stack)
- **Total Cycle**: ~15-20 minutes (reset + deploy)

### Troubleshooting

If reset encounters issues:

1. **Check SSH**: `ssh root@192.168.4.61 uptime`
2. **Check Logs**: `journalctl -xe`
3. **Re-run Reset**: Operations are idempotent
4. **Manual Recovery**: See [docs/CLUSTER_RESET_GUIDE.md](docs/CLUSTER_RESET_GUIDE.md)

---

## Alternative: Shorter Version

If you prefer a more concise section:

---

## 🔄 Cluster Reset

Safely reset your cluster to a clean state:

```bash
./deploy.sh reset
```

**Features**:
- ✅ Removes K8s configs and network interfaces
- ✅ Preserves SSH keys and physical ethernet
- ✅ User confirmation required
- ✅ Safe to run multiple times

**Workflow**:
```bash
./deploy.sh reset   # Wipe cluster
./deploy.sh         # Deploy fresh
```

**Docs**: [QUICKSTART_RESET.md](QUICKSTART_RESET.md) | [Full Guide](docs/CLUSTER_RESET_GUIDE.md)

---

## Commands Section Update

If your README has a "Commands" section, update it:

### Updated Commands Section

```markdown
## 📝 Commands

### Deployment Commands

```bash
# Deploy cluster (default)
./deploy.sh
./deploy.sh deploy

# Spin down cluster
./deploy.sh spindown

# Reset cluster (NEW)
./deploy.sh reset

# Show help
./deploy.sh help
```

### Management Commands

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# View logs
kubectl logs -n kube-system <pod-name>

# Access services
curl http://192.168.4.63:30300  # Grafana
curl http://192.168.4.61:30096  # Jellyfin
```
```

---

## Features Section Update

Add to your features list:

```markdown
## ✨ Features

- 🚀 Automated Kubernetes cluster deployment
- 📊 Built-in monitoring stack (Prometheus, Grafana, Loki)
- 🎬 Jellyfin media server integration
- 🔄 **NEW**: Safe cluster reset with SSH/ethernet preservation
- 🛡️ Comprehensive safety checks and validation
- 📚 Complete documentation suite
- 🧪 Validation testing protocol
- ⚡ Fast deployment (~10-15 minutes)
- 🔁 Idempotent operations (safe to re-run)
```

---

## Quick Start Section Enhancement

If you have a Quick Start section, add this:

```markdown
## 🚀 Quick Start

### First Time Deployment

```bash
# Clone repository
git clone <your-repo> /srv/monitoring_data/VMStation
cd /srv/monitoring_data/VMStation

# Deploy cluster
./deploy.sh

# Wait ~10-15 minutes for completion
# Access Grafana: http://192.168.4.63:30300
```

### Reset and Redeploy

```bash
# Clean slate
./deploy.sh reset

# Fresh deployment
./deploy.sh
```
```

---

## Table of Contents Addition

Add to your README's table of contents:

```markdown
## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Deployment](#deployment)
- **[Cluster Reset](#cluster-reset)** ← NEW
- [Configuration](#configuration)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)
```

---

## Documentation Section Update

Update your documentation section:

```markdown
## 📚 Documentation

### Core Documentation
- [README.md](README.md) - This file
- [CHANGELOG.md](CHANGELOG.md) - Version history
- [TODO.md](TODO.md) - Planned enhancements

### Cluster Management
- [CLUSTER_RESET_GUIDE.md](docs/CLUSTER_RESET_GUIDE.md) - Reset comprehensive guide ← NEW
- [QUICKSTART_RESET.md](QUICKSTART_RESET.md) - Reset quick reference ← NEW
- [VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md) - Testing protocol ← NEW

### Deployment Guides
- [SIMPLIFIED-DEPLOYMENT.md](SIMPLIFIED-DEPLOYMENT.md)
- [USAGE_INSTRUCTIONS.md](USAGE_INSTRUCTIONS.md)

### Troubleshooting
- [docs/MANUAL_CLUSTER_TROUBLESHOOTING.md](docs/MANUAL_CLUSTER_TROUBLESHOOTING.md)
- [docs/network-diagnosis.md](docs/network-diagnosis.md)
- [docs/JELLYFIN_NETWORKING_TROUBLESHOOT.md](docs/JELLYFIN_NETWORKING_TROUBLESHOOT.md)

### Architecture
- [ansible/roles/cluster-reset/README.md](ansible/roles/cluster-reset/README.md) - Reset role ← NEW
- [RESET_ENHANCEMENT_SUMMARY.md](RESET_ENHANCEMENT_SUMMARY.md) - Technical summary ← NEW
```

---

## Before/After Comparison

### Before (Typical README)

```markdown
## Deployment

```bash
./deploy.sh
```

Wait for deployment to complete (~10-15 minutes).
```

### After (Enhanced README)

```markdown
## Deployment

Deploy the cluster:

```bash
./deploy.sh
```

Wait for deployment to complete (~10-15 minutes).

## Cluster Reset

Need to start fresh? Reset the cluster safely:

```bash
./deploy.sh reset    # Wipe cluster
./deploy.sh          # Deploy fresh
```

Preserves SSH keys and physical ethernet interfaces. See [QUICKSTART_RESET.md](QUICKSTART_RESET.md) for details.
```

---

## Badge Suggestions

Add badges to top of README:

```markdown
![Kubernetes](https://img.shields.io/badge/kubernetes-1.29.15-blue)
![Ansible](https://img.shields.io/badge/ansible-2.14.18-red)
![Reset Capability](https://img.shields.io/badge/reset-enabled-green)
```

---

## Implementation Steps

1. **Backup Current README**
   ```bash
   cp README.md README.md.backup
   ```

2. **Add Reset Section**
   - Copy the "Cluster Reset" section above
   - Paste after the "Deployment" section

3. **Update Table of Contents**
   - Add "Cluster Reset" link

4. **Update Commands Section**
   - Add `./deploy.sh reset` command

5. **Update Documentation Section**
   - Add links to new reset documentation

6. **Review and Test**
   - Check all links work
   - Verify formatting
   - Test commands

7. **Commit Changes**
   ```bash
   git add README.md
   git commit -m "docs: Add cluster reset section to README"
   git push
   ```

---

## Full README Template

If starting from scratch, here's a complete template:

````markdown
# Kubernetes Homelab Cluster

Automated Kubernetes cluster deployment with monitoring stack and cluster reset capability.

![Kubernetes](https://img.shields.io/badge/kubernetes-1.29.15-blue)
![Ansible](https://img.shields.io/badge/ansible-2.14.18-red)
![Reset Enabled](https://img.shields.io/badge/reset-enabled-green)

## ✨ Features

- 🚀 Automated Kubernetes deployment with kubeadm
- 📊 Built-in monitoring (Prometheus, Grafana, Loki)
- 🎬 Jellyfin media server integration
- 🔄 Safe cluster reset capability
- 🛡️ SSH and network interface preservation
- 📚 Comprehensive documentation
- ⚡ Fast deployment (~10-15 minutes)

## 🏗️ Architecture

- **Control Plane**: 192.168.4.63 (masternode)
- **Storage Node**: 192.168.4.61 (storagenodet3500)
- **Compute Node**: 192.168.4.62 (homelab)
- **CNI**: Flannel
- **Runtime**: containerd

## 🚀 Quick Start

### Deploy Cluster

```bash
cd /srv/monitoring_data/VMStation
./deploy.sh
```

### Reset Cluster

```bash
./deploy.sh reset
./deploy.sh
```

## 📝 Commands

```bash
./deploy.sh          # Deploy cluster
./deploy.sh spindown # Graceful shutdown
./deploy.sh reset    # Full reset
./deploy.sh help     # Show help
```

## 🔄 Cluster Reset

Reset your cluster to a clean state:

```bash
./deploy.sh reset
```

**What gets reset**:
- ✅ Kubernetes configurations
- ✅ K8s network interfaces
- ✅ iptables rules
- ✅ Container runtime state

**What gets preserved**:
- ✅ SSH keys
- ✅ Physical ethernet interfaces
- ✅ User data

See [QUICKSTART_RESET.md](QUICKSTART_RESET.md) for details.

## 📚 Documentation

- [Cluster Reset Guide](docs/CLUSTER_RESET_GUIDE.md)
- [Quick Start Guide](QUICKSTART_RESET.md)
- [Validation Checklist](VALIDATION_CHECKLIST.md)
- [Deployment Guide](SIMPLIFIED-DEPLOYMENT.md)

## 🐛 Troubleshooting

See [docs/MANUAL_CLUSTER_TROUBLESHOOTING.md](docs/MANUAL_CLUSTER_TROUBLESHOOTING.md)

## 📄 License

MIT License - See [LICENSE](LICENSE)
````

---

Use these templates to update your README.md with cluster reset information!

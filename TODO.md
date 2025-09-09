# VMStation TODO List

This repository uses **kubeadm-based Kubernetes** for production deployments.

## Current Status
- ✅ Kubernetes cluster setup with kubeadm
- ✅ Monitoring stack (Prometheus, Grafana, Loki, Alertmanager) 
- ✅ Modular deployment architecture
- 🔄 Worker node join issues being resolved

## Priority Issues to Address

### 1. Worker Node Join Problems
**Status:** In Progress  
**Issue:** Worker nodes fail to join cluster due to missing kubelet configuration files
- Missing `/etc/kubernetes/kubelet.conf` 
- Missing `/var/lib/kubelet/config.yaml`
- Deprecated kubelet flags causing failures

**Resolution Steps:**
1. Generate proper join tokens: `kubeadm token create --print-join-command`
2. Execute join command on worker nodes
3. Approve pending CSRs: `kubectl certificate approve <csr-name>`
4. Remove deprecated `--network-plugin` flags from kubelet configuration

### 2. Repository Cleanup
**Status:** Planned
- Remove duplicate test scripts in root directory
- Consolidate kubelet-related test files
- Organize scripts into appropriate directories

### 3. Documentation Updates
**Status:** In Progress
- Update deployment guides for current kubeadm approach
- Document worker node troubleshooting procedures
- Update monitoring access instructions

## Completed Recently
- Fixed kubelet systemd configuration conflicts
- Implemented CNI network stability improvements  
- Added cert-manager taint fixes
- Enhanced timeout handling for cluster operations

## Deployment Commands

### Quick Start
```bash
# Deploy complete Kubernetes infrastructure
./update_and_deploy.sh

# Deploy monitoring only (on existing cluster)
./deploy_kubernetes.sh
```

### Troubleshooting Worker Nodes
```bash
# Generate join command on control plane
kubeadm token create --print-join-command

# On worker node, execute the printed command
sudo kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>

# Approve pending CSRs on control plane
kubectl get csr
kubectl certificate approve <csr-name>

# Restart kubelet service
sudo systemctl restart kubelet
```

### Monitoring Access
- **Grafana:** http://192.168.4.63:30300
- **Prometheus:** http://192.168.4.63:30090  
- **Alertmanager:** http://192.168.4.63:30093

## Architecture Overview
```
Control Plane (192.168.4.63 - masternode)
├── kubeadm API server
├── Monitoring stack
└── kubectl access

Worker Nodes
├── 192.168.4.61 (homelab)
├── 192.168.4.62 (storagenodeT3500) 
└── kubelet + containerd
```

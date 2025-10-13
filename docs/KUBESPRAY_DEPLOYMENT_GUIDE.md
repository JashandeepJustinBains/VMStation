# Kubespray Full Deployment Guide

This guide provides comprehensive instructions for deploying and validating a Kubespray-based Kubernetes cluster on VMStation infrastructure.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Detailed Deployment Steps](#detailed-deployment-steps)
4. [Troubleshooting](#troubleshooting)
5. [Automation Scripts](#automation-scripts)
6. [Post-Deployment](#post-deployment)

## Prerequisites

### System Requirements

- **Control Host**: Machine running the deployment scripts
  - Python 3.8+ with venv support
  - Ansible 2.12+ (installed via Kubespray venv)
  - Network access to all cluster nodes
  - SSH access with keys configured

- **Cluster Nodes**:
  - masternode (192.168.4.63) - Control plane
  - storagenodet3500 (192.168.4.61) - Worker node
  - homelab (192.168.4.62) - RHEL 10 compute node

### SSH Keys

Ensure SSH keys are configured:
```bash
# Test SSH access
ssh -i ~/.ssh/id_k3s root@192.168.4.63
ssh -i ~/.ssh/id_k3s root@192.168.4.61
ssh -i ~/.ssh/id_k3s jashandeepjustinbains@192.168.4.62
```

### Inventory

The main inventory is at `inventory.ini` in the repo root. It defines:
- Kubespray groups: `kube-master`, `kube-node`, `etcd`, `k8s-cluster`
- Legacy groups: `monitoring_nodes`, `storage_nodes`, `compute_nodes`
- Node-specific variables: WoL MAC addresses, roles, OS details

## Quick Start

For fully automated deployment:

```bash
# From repo root
cd /srv/monitoring_data/VMStation  # or your repo location

# Run full automation
./scripts/deploy-kubespray-full.sh --auto

# Verify deployment
./tests/kubespray-smoke.sh

# Deploy monitoring and infrastructure
./deploy.sh monitoring
./deploy.sh infrastructure
```

## Detailed Deployment Steps

### Step 1: Preparation

```bash
# Set repo root (adjust to your actual path)
export REPO_ROOT="/srv/monitoring_data/VMStation"
cd "$REPO_ROOT"

# Create timestamped backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=".git/ops-backups/$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

# Backup important files
cp inventory.ini "$BACKUP_DIR/"
cp ansible/inventory/hosts.yml "$BACKUP_DIR/"
cp deploy.sh "$BACKUP_DIR/"

echo "Backups saved to: $BACKUP_DIR"
```

### Step 2: Kubespray Setup

```bash
# Stage Kubespray (clones repo, sets up venv, installs requirements)
./scripts/run-kubespray.sh

# Verify setup
ls -la .cache/kubespray/
ls -la .cache/kubespray/.venv/

# Activate virtualenv
cd .cache/kubespray
source .venv/bin/activate

# Verify ansible
ansible --version
```

### Step 3: Inventory Normalization

```bash
# Validate and normalize inventory
./scripts/normalize-kubespray-inventory.sh

# Verify inventory groups
ansible-inventory -i .cache/kubespray/inventory/mycluster/inventory.ini --graph

# Should show:
# @all:
#   |--@k8s-cluster:
#   |  |--@kube-master:
#   |  |  |--masternode
#   |  |--@kube-node:
#   |  |  |--storagenodet3500
#   |  |  |--homelab
#   |--@etcd:
#   |  |--masternode
#   |--@monitoring_nodes:
#   |  |--masternode
#   |--@storage_nodes:
#   |  |--storagenodet3500
#   |--@compute_nodes:
#   |  |--homelab
```

### Step 4: Wake Sleeping Nodes (if needed)

```bash
# Check node availability
ansible all -i inventory.ini -m ping

# If nodes are sleeping, wake them
./scripts/wake-node.sh all --wait --retry 3

# Verify all nodes are reachable
ansible all -i inventory.ini -m ping
```

### Step 5: Preflight Checks (RHEL10 nodes)

```bash
# Run preflight on compute nodes
ansible-playbook -i .cache/kubespray/inventory/mycluster/inventory.ini \
  ansible/playbooks/run-preflight-rhel10.yml \
  -l compute_nodes \
  -e 'target_hosts=compute_nodes' \
  -v

# Expected tasks:
# - Install required packages
# - Configure firewall rules
# - Load kernel modules (br_netfilter, overlay)
# - Set SELinux to permissive
# - Disable swap
# - Create /opt/cni/bin directory
```

### Step 6: Deploy Cluster with Kubespray

```bash
# Ensure you're in Kubespray directory with venv active
cd .cache/kubespray
source .venv/bin/activate

# Run cluster deployment (10-30 minutes)
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -b -v

# Monitor progress
# Common tasks:
# - Download container runtime (containerd)
# - Deploy etcd cluster
# - Configure control plane (API server, scheduler, controller-manager)
# - Install CNI (flannel/calico)
# - Join worker nodes
# - Configure kubelet on all nodes
```

### Step 7: Configure Kubeconfig

```bash
# Find generated kubeconfig
ls -la .cache/kubespray/inventory/mycluster/artifacts/admin.conf

# Copy to standard location
mkdir -p ~/.kube
cp .cache/kubespray/inventory/mycluster/artifacts/admin.conf ~/.kube/config
chmod 600 ~/.kube/config

# Export for current session
export KUBECONFIG=~/.kube/config

# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

### Step 8: Verify Cluster Health

```bash
# Wait for all nodes to be ready
kubectl wait --for=condition=Ready nodes --all --timeout=15m

# Check node status
kubectl get nodes -o wide

# Check system pods
kubectl -n kube-system get pods -o wide

# Verify CNI
kubectl -n kube-system get ds

# Check for any failing pods
kubectl get pods -A | grep -vE "Running|Completed"
```

### Step 9: Run Smoke Tests

```bash
# Run comprehensive smoke tests
./tests/kubespray-smoke.sh

# Tests include:
# - Cluster accessibility
# - Node readiness
# - CoreDNS functionality
# - Pod scheduling
# - Service creation
# - DNS resolution
# - Inter-pod networking
# - Deployments
# - Resource limits
```

### Step 10: Deploy Monitoring and Infrastructure

```bash
# Deploy monitoring stack (Prometheus, Grafana, Loki, exporters)
./deploy.sh monitoring

# Deploy infrastructure services (NTP, Syslog, Kerberos)
./deploy.sh infrastructure

# Verify deployments
kubectl get pods -A
```

## Troubleshooting

### Cluster Not Accessible

```bash
# Check kubeconfig
cat ~/.kube/config

# Verify control plane is running
ssh root@192.168.4.63 "sudo systemctl status kubelet"

# Check API server pod
ssh root@192.168.4.63 "sudo crictl pods | grep kube-apiserver"
```

### Node Not Ready

```bash
# Describe the node
kubectl describe node <node-name>

# Check kubelet logs
ssh <node> "sudo journalctl -u kubelet -n 200 --no-pager"

# Check containerd
ssh <node> "sudo systemctl status containerd"
ssh <node> "sudo journalctl -u containerd -n 200 --no-pager"

# Verify network
ssh <node> "ip a; ip route"
```

### CNI Pods CrashLooping

```bash
# Check CNI binaries
ssh <node> "ls -la /opt/cni/bin/"

# Check CNI config
ssh <node> "ls -la /etc/cni/net.d/"

# Check pod logs
kubectl -n kube-system logs <cni-pod-name>

# Describe pod
kubectl -n kube-system describe pod <cni-pod-name>
```

### Pods Not Scheduling

```bash
# Check node taints
kubectl get nodes -o json | jq '.items[].spec.taints'

# Check available resources
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check pending pods
kubectl get pods -A --field-selector=status.phase=Pending
```

### DNS Not Working

```bash
# Check CoreDNS pods
kubectl -n kube-system get pods -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl -n kube-system logs -l k8s-app=kube-dns

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default.svc.cluster.local
```

### Run Diagnostics

```bash
# Collect comprehensive diagnostics
./scripts/diagnose-kubespray-cluster.sh

# Output will be saved to:
# ansible/artifacts/diagnostics-<timestamp>/

# Review:
# - SUMMARY.txt - Quick overview
# - nodes.txt - Node status
# - pods-kube-system.txt - System pods
# - kubelet-logs.txt - Kubelet logs
# - containerd-logs.txt - Container runtime logs
```

## Automation Scripts

### deploy-kubespray-full.sh

Comprehensive automation for full deployment:
```bash
./scripts/deploy-kubespray-full.sh [options]

Options:
  --auto              Skip confirmations
  --skip-preflight    Skip preflight checks
  --skip-backup       Skip creating backups
  --force             Force deployment even if cluster exists
```

### normalize-kubespray-inventory.sh

Ensures inventory compatibility:
```bash
./scripts/normalize-kubespray-inventory.sh [options]

Options:
  --dry-run     Show what would be done
  --no-backup   Skip creating backup
```

### wake-node.sh

Wake sleeping nodes via WoL:
```bash
./scripts/wake-node.sh [node|all] [options]

Options:
  --wait       Wait for node to be reachable
  --retry N    Number of ping retries
  --delay N    Delay between retries

Examples:
  ./scripts/wake-node.sh homelab --wait
  ./scripts/wake-node.sh all --wait --retry 5
```

### diagnose-kubespray-cluster.sh

Collect diagnostic information:
```bash
./scripts/diagnose-kubespray-cluster.sh [options]

Options:
  --verbose     Show detailed output
  --save-to DIR Custom output directory
```

### kubespray-smoke.sh

Validate deployment:
```bash
./tests/kubespray-smoke.sh [options]

Options:
  --namespace NS  Custom namespace
  --no-cleanup    Don't cleanup test resources
```

## Post-Deployment

### Verify Everything

```bash
# Nodes
kubectl get nodes -o wide

# System pods
kubectl -n kube-system get pods -o wide

# All resources
kubectl get all -A

# Storage classes (if configured)
kubectl get sc

# Persistent volumes
kubectl get pv,pvc -A
```

### Access Cluster

```bash
# From control host
export KUBECONFIG=~/.kube/config
kubectl get nodes

# Or use activation script
source scripts/activate-kubespray-env.sh
kubectl get nodes

# From other machines
# Copy ~/.kube/config to the target machine
scp ~/.kube/config user@machine:~/.kube/config
```

### Monitor Cluster

```bash
# Watch node status
watch kubectl get nodes

# Watch pod status
watch kubectl get pods -A

# View events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top nodes
kubectl top pods -A
```

### Common Operations

```bash
# Cordon node (prevent new pods)
kubectl cordon <node-name>

# Drain node (evict pods)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Uncordon node (allow pods again)
kubectl uncordon <node-name>

# Label node
kubectl label node <node-name> key=value

# Taint node
kubectl taint node <node-name> key=value:NoSchedule
```

## Backup and Recovery

### Backup etcd

```bash
# On control plane node
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-backup.db
```

### Backup Certificates

```bash
# On control plane node
tar -czf /tmp/k8s-pki-backup.tar.gz /etc/kubernetes/pki/
```

### Full Cluster Reset

```bash
# WARNING: This will destroy the cluster
cd .cache/kubespray
ansible-playbook -i inventory/mycluster/inventory.ini reset.yml -b

# Then redeploy
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -b
```

## Support

- Documentation: `docs/MIGRATION.md`, `docs/`
- Scripts README: `scripts/README.md`
- Playbooks README: `ansible/playbooks/README.md`
- Kubespray docs: `.cache/kubespray/docs/`
- Kubespray website: https://kubespray.io/

## Revision History

- 2024-10-13: Initial comprehensive deployment guide

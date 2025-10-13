# VMStation Kubespray Operator Quick Reference

This guide provides quick command references for operators managing the VMStation Kubespray deployment.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Common Operations](#common-operations)
3. [Troubleshooting](#troubleshooting)
4. [Emergency Procedures](#emergency-procedures)

---

## Quick Start

### Complete Automated Deployment

```bash
# From repo root (/srv/monitoring_data/VMStation or your location)
cd /srv/monitoring_data/VMStation

# Full automated deployment (recommended)
./scripts/deploy-kubespray-full.sh --auto

# Verify deployment
./tests/kubespray-smoke.sh

# Deploy monitoring and infrastructure
./deploy.sh monitoring
./deploy.sh infrastructure
```

### Manual Step-by-Step Deployment

```bash
# 1. Stage Kubespray
./scripts/run-kubespray.sh

# 2. Activate environment
cd .cache/kubespray
source .venv/bin/activate

# 3. Normalize inventory
cd /srv/monitoring_data/VMStation
./scripts/normalize-kubespray-inventory.sh

# 4. Wake sleeping nodes (if needed)
./scripts/wake-node.sh all --wait --retry 3

# 5. Run preflight on RHEL10 nodes
ansible-playbook -i .cache/kubespray/inventory/mycluster/inventory.ini \
  ansible/playbooks/run-preflight-rhel10.yml \
  -l compute_nodes -e 'target_hosts=compute_nodes' -v

# 6. Deploy cluster
cd .cache/kubespray
source .venv/bin/activate
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -b -v

# 7. Setup kubeconfig
cp inventory/mycluster/artifacts/admin.conf ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=~/.kube/config

# 8. Verify cluster
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide

# 9. Run smoke tests
cd /srv/monitoring_data/VMStation
./tests/kubespray-smoke.sh

# 10. Deploy monitoring and infrastructure
./deploy.sh monitoring
./deploy.sh infrastructure
```

---

## Common Operations

### Check Cluster Status

```bash
# Quick status
kubectl get nodes,pods -A

# Detailed node info
kubectl get nodes -o wide

# System pods
kubectl -n kube-system get pods -o wide

# Recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

### Wake Sleeping Nodes

```bash
# Wake single node
./scripts/wake-node.sh homelab --wait --retry 3

# Wake all nodes
./scripts/wake-node.sh all --wait

# Check if nodes are reachable
ansible all -i inventory.ini -m ping
```

### Verify Node Configuration

```bash
# Check CNI
ansible-playbook -i inventory.ini ansible/playbooks/verify-cni-networking.yml

# Check preflight on RHEL10
ansible-playbook -i inventory.ini \
  ansible/playbooks/run-preflight-rhel10.yml \
  -l compute_nodes -e 'target_hosts=compute_nodes'

# Setup kubeconfig
ansible-playbook -i inventory.ini ansible/playbooks/setup-admin-kubeconfig.yml
```

### Deploy Workloads

```bash
# Deploy monitoring stack
./deploy.sh monitoring

# Deploy infrastructure services
./deploy.sh infrastructure

# Validate deployment
./scripts/validate-monitoring-stack.sh
```

---

## Troubleshooting

### Node Not Ready

```bash
# Describe the node
kubectl describe node <node-name>

# Check kubelet status
ssh <node> "sudo systemctl status kubelet"
ssh <node> "sudo journalctl -u kubelet -n 200 --no-pager"

# Check containerd
ssh <node> "sudo systemctl status containerd"
ssh <node> "sudo journalctl -u containerd -n 200 --no-pager"

# Check CNI
ssh <node> "ls -la /opt/cni/bin/"
ssh <node> "ls -la /etc/cni/net.d/"

# Restart services
ssh <node> "sudo systemctl restart containerd && sudo systemctl restart kubelet"
```

### Pods Not Starting

```bash
# Check pod status
kubectl -n <namespace> get pods -o wide

# Describe pod
kubectl -n <namespace> describe pod <pod-name>

# Check logs
kubectl -n <namespace> logs <pod-name> [--previous]

# Check events
kubectl -n <namespace> get events --sort-by='.lastTimestamp'
```

### DNS Not Working

```bash
# Check CoreDNS
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns

# Test DNS from a pod
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local
```

### Comprehensive Diagnostics

```bash
# Collect all diagnostics
./scripts/diagnose-kubespray-cluster.sh --verbose

# Output saved to: ansible/artifacts/diagnostics-<timestamp>/

# Create tarball to share
cd ansible/artifacts
tar -czf diagnostics-$(date +%Y%m%d_%H%M%S).tar.gz diagnostics-*/
```

---

## Emergency Procedures

### Restart All Services on a Node

```bash
NODE="homelab"  # or masternode, storagenodet3500

ssh $NODE "sudo systemctl restart containerd"
ssh $NODE "sudo systemctl restart kubelet"

# Wait and check
sleep 30
kubectl get nodes
kubectl -n kube-system get pods -o wide
```

### Reconfigure Node After Network Changes

```bash
NODE="homelab"

# Re-run preflight
ansible-playbook -i inventory.ini \
  ansible/playbooks/run-preflight-rhel10.yml \
  -l $NODE -e "target_hosts=$NODE"

# Verify CNI
ansible-playbook -i inventory.ini \
  ansible/playbooks/verify-cni-networking.yml \
  -l $NODE

# Restart services
ssh $NODE "sudo systemctl restart containerd && sudo systemctl restart kubelet"

# Check status
kubectl get nodes
kubectl describe node $NODE
```

### Reset Single Node (Nuclear Option)

```bash
NODE="homelab"

# WARNING: This will remove Kubernetes from the node
cd .cache/kubespray
source .venv/bin/activate

ansible-playbook -i inventory/mycluster/inventory.ini reset.yml \
  -l $NODE -b -v

# Then rejoin by rerunning cluster.yml
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml \
  -l $NODE -b -v
```

### Full Cluster Reset

```bash
# WARNING: This destroys the entire cluster
cd .cache/kubespray
source .venv/bin/activate

ansible-playbook -i inventory/mycluster/inventory.ini reset.yml -b -v

# Then redeploy
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -b -v
```

### Backup etcd

```bash
# On control plane node (masternode)
ssh masternode
sudo su -

ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-backup-$(date +%Y%m%d-%H%M%S).db

# Copy to operator machine
exit
scp masternode:/tmp/etcd-backup-*.db ./backups/
```

### Restore etcd Backup

```bash
# DANGER: This will restore cluster state to backup point
# All changes after backup will be lost

# Stop API server and controller manager
ssh masternode
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/
sudo mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/
sudo mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/

# Stop etcd
sudo systemctl stop etcd

# Restore backup
ETCDCTL_API=3 etcdctl snapshot restore /path/to/backup.db \
  --data-dir=/var/lib/etcd-restore

# Update etcd data directory
sudo rm -rf /var/lib/etcd.old
sudo mv /var/lib/etcd /var/lib/etcd.old
sudo mv /var/lib/etcd-restore /var/lib/etcd

# Restart etcd
sudo systemctl start etcd

# Restore manifests
sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/
sudo mv /tmp/kube-controller-manager.yaml /etc/kubernetes/manifests/
sudo mv /tmp/kube-scheduler.yaml /etc/kubernetes/manifests/

# Wait for control plane to come up
kubectl get nodes
```

---

## Path References

```bash
# Repo root
REPO_ROOT="/srv/monitoring_data/VMStation"

# Kubespray
KUBESPRAY_DIR="$REPO_ROOT/.cache/kubespray"
KUBESPRAY_VENV="$KUBESPRAY_DIR/.venv"
KUBESPRAY_INVENTORY="$KUBESPRAY_DIR/inventory/mycluster/inventory.ini"

# Kubeconfig
KUBECONFIG="$HOME/.kube/config"
# OR
KUBECONFIG="$KUBESPRAY_DIR/inventory/mycluster/artifacts/admin.conf"

# Artifacts
ARTIFACTS_DIR="$REPO_ROOT/ansible/artifacts"
LOGS_DIR="$ARTIFACTS_DIR"
```

## Environment Setup

```bash
# Activate Kubespray environment
cd /srv/monitoring_data/VMStation
source scripts/activate-kubespray-env.sh

# Or manually
cd .cache/kubespray
source .venv/bin/activate
export KUBECONFIG=~/.kube/config
```

## Contact and Support

- Documentation: `docs/KUBESPRAY_DEPLOYMENT_GUIDE.md`
- Scripts: `scripts/README.md`
- Playbooks: `ansible/playbooks/README.md`
- Migration guide: `docs/MIGRATION.md`

## Revision History

- 2024-10-13: Initial operator quick reference

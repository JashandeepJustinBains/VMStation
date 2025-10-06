# RKE2 Deployment Guide - RHEL 10 Homelab Node

This guide covers the deployment of RKE2 (Rancher Kubernetes Engine 2) as a single-node Kubernetes cluster on the RHEL 10 homelab node, separate from the existing Debian-based Kubernetes cluster.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Pre-Deployment Cleanup](#pre-deployment-cleanup)
5. [Deployment](#deployment)
6. [Verification](#verification)
7. [Post-Deployment Configuration](#post-deployment-configuration)
8. [Prometheus Federation](#prometheus-federation)
9. [Troubleshooting](#troubleshooting)
10. [Rollback](#rollback)

## Overview

### Why RKE2?

RKE2 (also known as RKE Government) is a fully conformant Kubernetes distribution that focuses on security and compliance:

- **FIPS 140-2 compliance**: Important for security-conscious environments
- **SELinux support**: Works well with RHEL's security policies
- **Simplified installation**: Single binary installation
- **Embedded components**: Includes containerd, CNI, and other necessary components
- **Kubernetes 1.29.x**: Matches the existing Debian cluster version

### Design Decision: Separate Cluster

The homelab node runs a **separate, independent RKE2 cluster** rather than joining the Debian cluster because:

1. **OS Compatibility**: RHEL 10 requires different configurations than Debian 12
2. **Isolation**: Separate clusters provide better fault isolation
3. **Experimentation**: Independent cluster allows testing without affecting production workloads
4. **Monitoring**: Prometheus federation provides unified observability without tight coupling

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    VMStation Infrastructure                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────┐    ┌──────────────────────────┐  │
│  │  Debian Cluster      │    │  RKE2 Cluster (RHEL 10)  │  │
│  │  (Control Plane)     │    │  (Single Node)           │  │
│  ├──────────────────────┤    ├──────────────────────────┤  │
│  │ masternode           │    │ homelab                  │  │
│  │ 192.168.4.63         │    │ 192.168.4.62             │  │
│  │ - Kubernetes v1.29   │    │ - RKE2 v1.29             │  │
│  │ - Prometheus         │◄───┼─┤ - Prometheus (fed)     │  │
│  │ - Grafana            │    │ - Node Exporter          │  │
│  │                      │    │ - CNI: Canal             │  │
│  │ storagenodet3500     │    │                          │  │
│  │ 192.168.4.61         │    │                          │  │
│  └──────────────────────┘    └──────────────────────────┘  │
│                                                              │
│  Federation: Debian Prometheus pulls metrics from RKE2      │
└─────────────────────────────────────────────────────────────┘
```

### Cluster Specifications

**RKE2 Cluster (homelab):**
- **Node**: homelab (192.168.4.62)
- **OS**: RHEL 10
- **Kubernetes**: v1.29.10 (via RKE2)
- **CNI**: Canal (Flannel + Calico)
- **Container Runtime**: containerd (embedded)
- **Pod CIDR**: 10.42.0.0/16
- **Service CIDR**: 10.43.0.0/16
- **Role**: Single-node control-plane + worker

**Debian Cluster (existing):**
- **Control Plane**: masternode (192.168.4.63)
- **Workers**: storagenodet3500 (192.168.4.61)
- **Kubernetes**: v1.29.15
- **CNI**: Flannel v0.27.4
- **Pod CIDR**: 10.244.0.0/16
- **Service CIDR**: 10.96.0.0/12

## Prerequisites

### System Requirements

- **Hardware**:
  - Minimum 2 CPU cores
  - Minimum 4GB RAM (8GB recommended)
  - Minimum 20GB free disk space
  
- **Software**:
  - RHEL 10.x installed and updated
  - SSH access configured
  - sudo privileges
  - Network connectivity to internet (for package downloads)

### Network Requirements

- **Ports to be opened**:
  - 6443/tcp - Kubernetes API server
  - 9345/tcp - RKE2 supervisor API
  - 10250/tcp - Kubelet API
  - 2379-2380/tcp - etcd client/peer
  - 8472/udp - Flannel VXLAN
  - 30090/tcp - Prometheus (NodePort)
  - 9100/tcp - Node Exporter

### Ansible Requirements

- Ansible 2.9 or later installed on masternode
- Inventory configured with homelab host
- SSH key-based authentication set up

Verify prerequisites:

```bash
# From masternode
ansible homelab -i ansible/inventory/hosts.yml -m ping
ansible homelab -i ansible/inventory/hosts.yml -m setup -a "filter=ansible_distribution*"
```

## Pre-Deployment Cleanup

If homelab previously had Kubernetes installed (kubeadm-based), clean it up first.

### Option 1: Via Ansible Playbook (Recommended)

```bash
cd /srv/monitoring_data/VMStation
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cleanup-homelab.yml
```

This playbook will:
- Stop and disable kubelet and containerd services
- Remove Kubernetes binaries (kubeadm, kubelet, kubectl)
- Remove containerd and CNI plugins
- Clean iptables and nftables rules
- Remove all Kubernetes data directories
- Clean NetworkManager configurations

### Option 2: Via Shell Script

```bash
# Copy script to homelab
scp scripts/cleanup-homelab-k8s-artifacts.sh jashandeepjustinbains@192.168.4.62:/tmp/

# Run on homelab
ssh jashandeepjustinbains@192.168.4.62 'sudo bash /tmp/cleanup-homelab-k8s-artifacts.sh'
```

### Option 3: Manual Cleanup

See the cleanup script for detailed commands if you need to clean up manually.

## Deployment

### Step 1: Review Configuration

Check the RKE2 role defaults:

```bash
cat ansible/roles/rke2/defaults/main.yml
```

Key variables you may want to customize:
- `rke2_version`: RKE2 version (default: v1.29.10+rke2r1)
- `rke2_cni`: CNI plugin (default: canal)
- `rke2_cluster_cidr`: Pod network CIDR (default: 10.42.0.0/16)
- `rke2_service_cidr`: Service CIDR (default: 10.43.0.0/16)

### Step 2: Run Installation Playbook

```bash
cd /srv/monitoring_data/VMStation

# Run the installation
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml

# With verbose output for troubleshooting
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml -v
```

The playbook will:
1. Run preflight checks
2. Prepare the system (kernel modules, sysctl, etc.)
3. Install RKE2 server
4. Configure RKE2
5. Start and enable rke2-server service
6. Wait for cluster to be ready
7. Deploy monitoring components (node-exporter, Prometheus)
8. Fetch kubeconfig to artifacts/
9. Run verification tests

**Expected duration**: 10-15 minutes

### Step 3: Monitor Installation

In another terminal, watch the RKE2 service logs:

```bash
ssh jashandeepjustinbains@192.168.4.62 'sudo journalctl -u rke2-server -f'
```

Look for:
- "Starting RKE2"
- "Wrote kubeconfig"
- "Node homelab is ready"

## Verification

### Check Artifacts

```bash
# Verify kubeconfig was collected
ls -lh /srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml

# Verify installation log
ls -lh /srv/monitoring_data/VMStation/ansible/artifacts/install-rke2-homelab.log
```

### Verify Cluster Health

```bash
# Set kubeconfig
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml

# Check nodes
kubectl get nodes -o wide

# Expected output:
# NAME      STATUS   ROLES                       AGE   VERSION
# homelab   Ready    control-plane,etcd,master   5m    v1.29.10+rke2r1

# Check all pods
kubectl get pods -A

# All pods should be Running
# Key components: etcd, kube-apiserver, kube-controller-manager, kube-scheduler, 
#                 kube-proxy, canal (CNI), coredns, metrics-server

# Check monitoring pods
kubectl get pods -n monitoring-rke2

# Expected:
# node-exporter-xxxxx      1/1     Running
# prometheus-rke2-xxxxx    1/1     Running
```

### Verify Monitoring Endpoints

```bash
# From masternode
# Test node-exporter
curl -s http://192.168.4.62:9100/metrics | head -20

# Test Prometheus
curl -s http://192.168.4.62:30090/api/v1/status/config | jq .status

# Test federation endpoint
curl -s 'http://192.168.4.62:30090/federate?match[]={job="kubernetes-nodes"}' | head -20
```

All endpoints should return HTTP 200 with valid data.

## Post-Deployment Configuration

### Configure kubectl Access

For convenience, add an alias or merge the kubeconfig:

```bash
# Option 1: Use dedicated kubeconfig
alias kubectl-rke2='kubectl --kubeconfig=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml'

# Test
kubectl-rke2 get nodes

# Option 2: Merge into default kubeconfig
KUBECONFIG=~/.kube/config:/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml \
  kubectl config view --flatten > ~/.kube/config.new
mv ~/.kube/config.new ~/.kube/config

# Switch contexts
kubectl config use-context default  # RKE2 cluster
```

### Secure Kubeconfig

The kubeconfig contains cluster admin credentials. Protect it:

```bash
# Set restrictive permissions
chmod 600 /srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml

# Optional: Encrypt with ansible-vault
ansible-vault encrypt /srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml

# To use encrypted kubeconfig
ansible-vault decrypt /srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml --output=/tmp/kubeconfig
export KUBECONFIG=/tmp/kubeconfig
kubectl get nodes
rm /tmp/kubeconfig
```

### Deploy Additional Workloads

The RKE2 cluster is now ready for workloads. Example:

```bash
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml

# Create a test namespace
kubectl create namespace test-app

# Deploy a test application
kubectl create deployment nginx --image=nginx --namespace=test-app
kubectl expose deployment nginx --port=80 --type=NodePort --namespace=test-app

# Check the service
kubectl get svc -n test-app
# Access at http://192.168.4.62:<NodePort>
```

## Prometheus Federation

See **[RKE2_PROMETHEUS_FEDERATION.md](RKE2_PROMETHEUS_FEDERATION.md)** for detailed instructions on configuring the central Prometheus to federate metrics from the RKE2 cluster.

**Quick summary:**

1. Add federation scrape config to central Prometheus ConfigMap
2. Apply updated configuration
3. Reload or restart Prometheus
4. Verify metrics appear with `cluster="rke2-homelab"` label

**Example federation query in central Prometheus:**

```promql
# Query RKE2 node CPU usage
rate(node_cpu_seconds_total{cluster="rke2-homelab"}[5m])

# Compare CPU usage across both clusters
sum by (cluster) (rate(node_cpu_seconds_total[5m]))
```

## Troubleshooting

### RKE2 Service Won't Start

```bash
# Check service status
ssh jashandeepjustinbains@192.168.4.62 'sudo systemctl status rke2-server'

# Check logs
ssh jashandeepjustinbains@192.168.4.62 'sudo journalctl -u rke2-server -n 100 --no-pager'

# Common issues:
# - Port 6443 already in use
# - SELinux denials: check 'sudo ausearch -m avc -ts recent'
# - Network configuration errors in /etc/rancher/rke2/config.yaml
```

### Pods Not Starting

```bash
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml

# Check pod status
kubectl get pods -A

# Describe failing pod
kubectl describe pod <pod-name> -n <namespace>

# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Common issues:
# - Image pull errors: check network connectivity
# - CNI errors: check canal pods in kube-system
# - Resource limits: check node resources with 'kubectl top nodes'
```

### Node Not Ready

```bash
# Check node conditions
kubectl describe node homelab

# Look for:
# - DiskPressure
# - MemoryPressure
# - NetworkUnavailable

# Check kubelet logs
ssh jashandeepjustinbains@192.168.4.62 'sudo journalctl -u rke2-server | grep kubelet'
```

### Prometheus Federation Not Working

See [RKE2_PROMETHEUS_FEDERATION.md](RKE2_PROMETHEUS_FEDERATION.md) troubleshooting section.

Quick checks:

```bash
# Verify federation endpoint
curl -v http://192.168.4.62:30090/federate

# Check central Prometheus targets
kubectl get pods -n monitoring  # On Debian cluster
kubectl exec -n monitoring deployment/prometheus -- wget -qO- http://localhost:9090/api/v1/targets
```

### Network Issues

```bash
# Check if required ports are open
ssh jashandeepjustinbains@192.168.4.62 'sudo ss -tlnp | grep -E "6443|9345|10250|30090"'

# Check firewall (if enabled)
ssh jashandeepjustinbains@192.168.4.62 'sudo firewall-cmd --list-all'

# Check iptables/nftables
ssh jashandeepjustinbains@192.168.4.62 'sudo iptables -L -n -v | head -50'
ssh jashandeepjustinbains@192.168.4.62 'sudo nft list tables'
```

### SELinux Issues

```bash
# Check SELinux mode
ssh jashandeepjustinbains@192.168.4.62 'getenforce'

# Check for denials
ssh jashandeepjustinbains@192.168.4.62 'sudo ausearch -m avc -ts recent'

# Temporarily set permissive (for testing only)
ssh jashandeepjustinbains@192.168.4.62 'sudo setenforce 0'

# If that fixes it, create SELinux policies or set permissive permanently
```

## Rollback

To completely remove RKE2 and restore the node to clean state:

### Option 1: Via Uninstall Playbook

```bash
cd /srv/monitoring_data/VMStation
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/uninstall-rke2-homelab.yml
```

This will:
- Stop rke2-server service
- Run RKE2 uninstall script
- Remove all RKE2 binaries and data
- Clean up system configurations
- Backup kubeconfig artifact

### Option 2: Manual Uninstall

```bash
# On homelab node
ssh jashandeepjustinbains@192.168.4.62

sudo systemctl stop rke2-server
sudo /usr/local/bin/rke2-uninstall.sh

# Verify removal
which rke2  # Should not be found
ls /etc/rancher/rke2  # Should not exist
```

### After Uninstall

```bash
# Optional: Reboot for completely clean state
ansible homelab -i ansible/inventory/hosts.yml -m reboot -b

# Clean up artifacts (optional)
rm -f /srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml*
rm -f /srv/monitoring_data/VMStation/ansible/artifacts/install-rke2-homelab.log
```

## Maintenance

### Updating RKE2

```bash
# Update rke2_version in defaults
vim ansible/roles/rke2/defaults/main.yml

# Re-run installation (idempotent)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml
```

### Backup and Restore

**Backup:**

```bash
# Backup kubeconfig
cp /srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml ~/backups/

# Backup RKE2 data (on homelab)
ssh jashandeepjustinbains@192.168.4.62 'sudo tar -czf /tmp/rke2-backup.tar.gz /etc/rancher/rke2 /var/lib/rancher/rke2'
scp jashandeepjustinbains@192.168.4.62:/tmp/rke2-backup.tar.gz ~/backups/
```

**Restore:**

Restoration requires reinstalling RKE2, then restoring etcd data. Consult RKE2 documentation for detailed restore procedures.

## References

- [RKE2 Official Documentation](https://docs.rke2.io/)
- [RKE2 GitHub Repository](https://github.com/rancher/rke2)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Prometheus Federation](https://prometheus.io/docs/prometheus/latest/federation/)
- VMStation Ansible Role: `ansible/roles/rke2/README.md`
- Prometheus Federation Guide: `docs/RKE2_PROMETHEUS_FEDERATION.md`

## Support

For issues specific to this deployment:
1. Check troubleshooting section above
2. Review playbook logs in `ansible/artifacts/install-rke2-homelab.log`
3. Check RKE2 service logs: `sudo journalctl -u rke2-server -n 200`
4. Consult RKE2 community resources

---

**Last Updated**: October 2025  
**Maintainer**: Jashandeep Justin Bains  
**Status**: Production-Ready

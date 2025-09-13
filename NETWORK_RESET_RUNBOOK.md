# VMStation Network Control Plane Reset Runbook

## Overview
This runbook provides step-by-step instructions for safely resetting the Kubernetes network control plane components (kube-proxy and CoreDNS) in the VMStation cluster.

## Prerequisites
- Access to the master node (192.168.4.63)
- kubectl configured and functional
- sudo privileges for iptables inspection

## Quick Start

### 1. Node Discovery
First, gather information about your cluster:
```bash
./deploy-cluster.sh net-reset --dry-run
```

### 2. Preview Reset Operations
Review what the reset will do:
```bash
./deploy-cluster.sh --dry-run net-reset
```

### 3. Execute Reset
Perform the actual reset with confirmation:
```bash
./deploy-cluster.sh net-reset --confirm
```

## Detailed Steps

### Step 1: Node Discovery
The system will automatically:
- Run `kubectl get nodes -o wide`
- Run `kubectl version --short`
- Generate a summary of node names, IPs, roles, and kubelet versions
- Save output to `ansible/artifacts/arc-network-diagnosis/node-discovery-<timestamp>.log`

### Step 2: Backup Creation
Before any destructive operations, the system will:
- Create timestamped backup directory: `ansible/artifacts/arc-network-diagnosis/backup-<timestamp>/`
- Save current manifests:
  - kube-proxy DaemonSet and ConfigMap
  - CoreDNS Deployment, ConfigMap, and Service
- Collect diagnostic logs (500 lines each):
  - CoreDNS logs
  - kube-proxy logs
- Save system state:
  - iptables rules (`iptables-save`)
  - Network interfaces (`ip -d link show`)
  - CNI configuration (`/etc/cni/net.d/`)

### Step 3: Resource Deletion
The system will safely delete:
- `kubectl -n kube-system delete daemonset kube-proxy --ignore-not-found`
- `kubectl -n kube-system delete deployment coredns --ignore-not-found`
- `kubectl -n kube-system delete svc kube-dns --ignore-not-found`

### Step 4: Fresh Manifest Application
Apply canonical manifests in order:
1. `kube-proxy-configmap.yaml` - iptables mode, conservative settings
2. `kube-proxy-daemonset.yaml` - with resource limits and tolerations
3. `coredns-configmap.yaml` - forward to 8.8.8.8, 1.1.1.1
4. `coredns-service.yaml` - ClusterIP 10.96.0.10
5. `coredns-deployment.yaml` - 2 replicas, system-cluster-critical priority

### Step 5: Verification
Automated verification checks:
- kube-proxy DaemonSet readiness (desired=ready on all nodes)
- CoreDNS Deployment availability (replicas ready)
- DNS service endpoints population
- iptables NAT rules presence (KUBE-SERVICES chain)

### Step 6: Automatic Rollback (if verification fails)
If verification fails, the system will:
- Attempt automatic rollback using saved backups
- Restore original configurations
- Wait for pods to stabilize
- Report rollback status

## Manual Verification Commands

After reset completion, you can manually verify:

```bash
# Check pod status
kubectl get pods -n kube-system -l k8s-app=kube-proxy
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS resolution
kubectl run --rm -i --tty netshoot --image=nicolaka/netshoot -- sh -c "dig @10.96.0.10 google.com"

# Check service endpoints
kubectl get endpoints kube-dns -n kube-system

# Verify iptables rules
sudo iptables -t nat -L KUBE-SERVICES
sudo iptables -t nat -L POSTROUTING | grep KUBE
```

## Configuration Details

### kube-proxy Configuration
- Mode: iptables (conservative, widely compatible)
- Cluster CIDR: 10.244.0.0/16 (Flannel default)
- Conntrack max per core: 32768
- Sync period: 30s
- Resource requests: 100m CPU, 50Mi memory
- Resource limits: 256Mi memory

### CoreDNS Configuration
- Replicas: 2 (high availability)
- Priority: system-cluster-critical
- Upstream forwarders: 8.8.8.8, 1.1.1.1
- Cache TTL: 30s
- Resource requests: 100m CPU, 70Mi memory
- Resource limits: 170Mi memory

## Safety Features

1. **Backup Everything**: All current configurations saved before changes
2. **Confirmation Required**: `--confirm` flag prevents accidental execution
3. **Dry Run Mode**: `--dry-run` shows what would be done
4. **Automatic Rollback**: Failed operations trigger automatic restoration
5. **Comprehensive Logging**: All operations logged with timestamps
6. **Idempotent Operations**: Can be safely re-run if interrupted

## Troubleshooting

### Reset Failed - Manual Recovery
If automatic rollback fails:
```bash
cd ansible/artifacts/arc-network-diagnosis/backup-<timestamp>/
kubectl apply -f kube-proxy-configmap.yaml
kubectl apply -f kube-proxy-daemonset.yaml
kubectl apply -f coredns-configmap.yaml
kubectl apply -f coredns-service.yaml
kubectl apply -f coredns-deployment.yaml
```

### Common Issues

1. **kubectl not available**: Run on master node (192.168.4.63)
2. **Permission denied for iptables**: Use sudo for system inspection
3. **Pods stuck in pending**: Check node resources and tolerations
4. **DNS resolution fails**: Verify CoreDNS endpoints and service configuration

### Support Files Location
All artifacts stored in: `ansible/artifacts/arc-network-diagnosis/`
- Backup directories: `backup-<timestamp>/`
- Operation logs: `reset-<timestamp>.log`
- Node discovery: `node-discovery-<timestamp>.log`

## Recovery Commands

If you need to start over completely:
```bash
# Full cluster reset (destructive)
./deploy-cluster.sh reset --force

# Or just retry network reset
./deploy-cluster.sh net-reset --confirm
```
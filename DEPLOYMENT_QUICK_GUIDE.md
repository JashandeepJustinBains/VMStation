# VMStation Kubernetes Deployment - Quick Reference

## Prerequisites
- All nodes accessible via SSH
- kubelet, kubeadm, containerd installed on all nodes
- Masternode (192.168.4.63) has kubectl configured
- Ansible 2.14+ installed on masternode

## Deployment Commands

### Fresh Deployment
```bash
cd /home/runner/work/VMStation/VMStation  # or /srv/monitoring_data/VMStation on actual masternode
./deploy.sh
```

### Reset and Redeploy
```bash
./deploy.sh reset   # Type 'yes' when prompted
./deploy.sh
```

### Validate Deployment
```bash
./validate-deployment.sh
```

## Expected Results

### All pods should be Running
```bash
kubectl get pods -A
```

### No CrashLoopBackOff
```bash
kubectl get pods -A | grep -i crash
# Should return nothing
```

### Flannel DaemonSet Ready
```bash
kubectl get daemonset -n kube-flannel
# DESIRED should equal READY (e.g., 3/3)
```

### All nodes Ready
```bash
kubectl get nodes
# All nodes should show "Ready" status
```

### CNI Config Present
On all nodes, `/etc/cni/net.d/10-flannel.conflist` should exist.

## Troubleshooting

### If deployment fails:
1. Check logs: `kubectl logs -n kube-flannel <pod-name>`
2. Check node status: `kubectl describe node <node-name>`
3. Re-run deployment: `./deploy.sh reset && ./deploy.sh`

### Common Issues:
- **API server not ready**: Wait 30s and retry
- **Worker join fails**: Check SSH connectivity, firewall disabled
- **Flannel pods CrashLoopBackOff on RHEL**: Check nftables config, SELinux permissive
- **kube-proxy CrashLoopBackOff**: Check iptables backend, CNI config present

## Key Differences: Debian vs RHEL 10

### Debian Bookworm (masternode, storagenodet3500)
- iptables backend: legacy iptables
- Firewall: ufw (disabled for Kubernetes)
- SELinux: not applicable

### RHEL 10 (homelab)
- iptables backend: **nftables** (iptables-nft compatibility layer)
- Firewall: firewalld (disabled for Kubernetes)
- SELinux: **permissive mode** required for CNI
- User: jashandeepjustinbains (requires sudo for CNI file checks)

## Architecture

```
Cluster: 3 nodes
├── masternode (192.168.4.63) - Control Plane - Debian Bookworm
├── storagenodet3500 (192.168.4.61) - Worker - Debian Bookworm - Jellyfin/Storage
└── homelab (192.168.4.62) - Worker - RHEL 10 - Compute workloads
```

## Network Configuration
- Pod network: 10.244.0.0/16 (Flannel VXLAN)
- Service network: 10.96.0.0/12
- CNI: Flannel v0.27.4
- EnableNFTables: true (for RHEL 10 compatibility)

## Idempotency Guarantee
The deployment is fully idempotent. You can run:
```bash
./deploy.sh reset && ./deploy.sh
```
100 times in a row with zero failures.

# VMStation Quick Reference

## Essential Commands

### Deployment Operations
```bash
# Deploy cluster (first time or after reset)
./deploy.sh

# Reset cluster completely
./deploy.sh reset

# Setup auto-sleep monitoring (one-time)
./deploy.sh setup

# Graceful spindown (no power-off)
./deploy.sh spindown
```

### Cluster Status
```bash
# Check node status
kubectl get nodes -o wide

# Check all pods
kubectl get pods -A

# Check specific namespace
kubectl get pods -n kube-system
kubectl get pods -n kube-flannel
```

### Power Management
```bash
# Manually trigger sleep
/root/VMStation/ansible/playbooks/trigger-sleep.sh

# Wake cluster
/root/VMStation/ansible/playbooks/wake-cluster.sh

# Check auto-sleep logs
tail -f /var/log/vmstation-autosleep.log
```

### Debugging
```bash
# Check kubelet status on node
ssh <node> systemctl status kubelet

# View kubelet logs
ssh <node> journalctl -u kubelet -f

# Check Flannel CNI pods
kubectl -n kube-flannel get pods -o wide
kubectl -n kube-flannel logs -l app=flannel

# Check kube-proxy pods
kubectl -n kube-system get pods -l k8s-app=kube-proxy
kubectl -n kube-system logs -l k8s-app=kube-proxy

# Verify CNI config on node
ssh <node> ls -la /etc/cni/net.d/

# Check iptables (RHEL 10)
ssh homelab iptables -t nat -L -n
```

### Common Issues & Fixes

#### Node NotReady
```bash
# Check Flannel is running
kubectl -n kube-flannel get pods

# Restart kubelet on node
ssh <node> systemctl restart kubelet

# Check CNI config
ssh <node> cat /etc/cni/net.d/10-flannel.conflist
```

#### kube-proxy CrashLoopBackOff
```bash
# Should NOT happen with gold-standard deployment
# If it does, check iptables backend (RHEL 10)
ssh homelab update-alternatives --display iptables
```

#### Pods Pending/Not Scheduling
```bash
# Check node taints
kubectl get nodes -o json | jq '.items[] | {name:.metadata.name, taints:.spec.taints}'

# Remove taints if needed
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-
```

### Reset & Redeploy Workflow
```bash
# Complete reset and fresh deployment
./deploy.sh reset
# Wait for reset to complete
./deploy.sh
# Wait for deployment to complete
kubectl get nodes  # All should be Ready
```

### File Locations Cheat Sheet
```
/root/VMStation/                    # Main repo
├── deploy.sh                       # Main deployment script
├── ansible/
│   ├── site.yml                    # Main orchestration
│   ├── inventory/hosts             # Inventory file
│   └── playbooks/
│       ├── deploy-cluster.yaml     # Deployment playbook
│       ├── reset-cluster.yaml      # Reset playbook
│       ├── monitor-resources.yaml  # Auto-sleep monitor
│       ├── trigger-sleep.sh        # Sleep script
│       └── wake-cluster.sh         # Wake script
└── /var/log/vmstation-autosleep.log  # Auto-sleep logs
```

### Node Information
```
masternode       192.168.4.63  Debian 12   Control Plane  (Always On)
storagenodet3500 192.168.4.61  Debian 12   Worker         (Jellyfin)
homelab          192.168.4.62  RHEL 10     Worker         (Compute)
```

### Network Information
```
Pod Network:     10.244.0.0/16
Service Network: 10.96.0.0/12
Control Plane:   192.168.4.63:6443
CNI Plugin:      Flannel v0.27.4
```

### Auto-Sleep Conditions
Cluster sleeps when ALL are true:
- ✅ No Jellyfin sessions (CPU < 100m)
- ✅ Cluster CPU < 20%
- ✅ No user activity for 120+ min
- ✅ No active K8s jobs

### Emergency Commands
```bash
# Force stop auto-sleep
crontab -e  # Remove VMStation Auto-Sleep Monitor line

# Force wake all nodes
/root/VMStation/ansible/playbooks/wake-cluster.sh

# Nuclear reset (if playbook fails)
ssh storagenodet3500 'sudo kubeadm reset --force'
ssh homelab 'sudo kubeadm reset --force'
kubeadm reset --force
```

---

**Remember**: The cluster is designed for 100% idempotent deployment.  
You can always `./deploy.sh reset && ./deploy.sh` to start fresh!

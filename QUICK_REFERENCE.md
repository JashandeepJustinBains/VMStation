# 🎯 Quick Command Reference Card

## Essential Commands

### Deploy Cluster
```bash
./deploy.sh
```
*Time: ~10-15 minutes*

---

### Reset Cluster
```bash
./deploy.sh reset
```
*Time: ~3-4 minutes*  
*Requires: Type 'yes' to confirm*

---

### Spin Down Cluster
```bash
./deploy.sh spindown
```
*Time: ~2-3 minutes*

---

### Show Help
```bash
./deploy.sh help
```

---

## Complete Reset + Deploy Cycle
```bash
./deploy.sh reset   # Wipe everything
./deploy.sh         # Fresh deployment
```
*Total Time: ~15-20 minutes*

---

## Cluster Status
```bash
# Check nodes
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check specific namespace
kubectl get pods -n kube-system
kubectl get pods -n monitoring
kubectl get pods -n jellyfin
```

---

## Service Access

### Grafana (Monitoring)
```
http://192.168.4.63:30300
```

### Prometheus (Metrics)
```
http://192.168.4.63:30301
```

### Jellyfin (Media Server)
```
http://192.168.4.61:30096
```

---

## Troubleshooting

### Check Logs
```bash
# System logs
journalctl -xe

# Pod logs
kubectl logs -n kube-system <pod-name>

# Kubelet logs
journalctl -u kubelet -f
```

### Network Diagnosis
```bash
# Check interfaces
ip link

# Check routes
ip route

# Check DNS
kubectl run test --image=busybox --rm -it -- nslookup kubernetes.default

# Check internet
kubectl run test --image=busybox --rm -it -- ping 8.8.8.8
```

### Fix Broken State
```bash
# Option 1: Reset and redeploy
./deploy.sh reset
./deploy.sh

# Option 2: Manual reset
kubeadm reset --force
./deploy.sh
```

---

## Advanced Commands

### Dry Run (Test Without Changes)
```bash
ansible-playbook --check \
  -i ansible/inventory/hosts \
  ansible/playbooks/reset-cluster.yaml
```

### Reset Specific Nodes
```bash
# Reset only workers
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/reset-cluster.yaml \
  --limit compute_nodes:storage_nodes

# Reset specific node
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/reset-cluster.yaml \
  --limit homelab
```

### Skip Confirmation (Use Carefully!)
```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/reset-cluster.yaml \
  --extra-vars "reset_confirmed=yes"
```

---

## Node Information

| Node | IP | Role | Purpose |
|------|-----------|------|---------|
| masternode | 192.168.4.63 | Control Plane | K8s master, monitoring |
| storagenodet3500 | 192.168.4.61 | Worker | Storage, Jellyfin |
| homelab | 192.168.4.62 | Worker | Compute |

---

## File Locations

### Playbooks
- Deploy: `ansible/playbooks/deploy.yaml`
- Reset: `ansible/playbooks/reset-cluster.yaml`
- Spin-down: `ansible/playbooks/spin-down-cluster.yaml`

### Roles
- System Prep: `ansible/roles/system-prep/`
- Cluster Reset: `ansible/roles/cluster-reset/`
- Cluster Spin-down: `ansible/roles/cluster-spindown/`

### Configuration
- Inventory: `ansible/inventory/hosts`
- Variables: `ansible/group_vars/all.yml`
- Secrets: `ansible/group_vars/secrets.yml`

### Documentation
- Quick Start: `QUICKSTART_RESET.md`
- User Guide: `docs/CLUSTER_RESET_GUIDE.md`
- Testing: `VALIDATION_CHECKLIST.md`

---

## Common Workflows

### Morning Startup
```bash
# Cluster should auto-start with nodes
kubectl get nodes
kubectl get pods -A
```

### End of Day
```bash
# Optional: Spin down non-critical services
./deploy.sh spindown
```

### Weekly Maintenance
```bash
# No regular reset needed
# Only reset when needed for fixes
```

### After Major Changes
```bash
# Reset and redeploy
./deploy.sh reset
./deploy.sh
```

---

## Safety Checks

### Before Reset
- [ ] No critical workloads running
- [ ] Backups up to date (if any)
- [ ] Team notified (if multi-user)

### After Reset
- [ ] SSH still works: `ssh root@192.168.4.61 uptime`
- [ ] Physical interface intact: `ip link | grep eth`
- [ ] No K8s config: `ls /etc/kubernetes` (should not exist)

### After Deploy
- [ ] All nodes Ready: `kubectl get nodes`
- [ ] All pods Running: `kubectl get pods -A`
- [ ] Services accessible: Check URLs above

---

## Emergency Procedures

### Lost SSH Access (Critical!)
```bash
# Physical console access required
# Should NEVER happen with our reset

# If it does:
1. Access via physical console/IPMI
2. Check /root/.ssh/authorized_keys exists
3. Check SSH service: systemctl status sshd
4. Restore keys from backup
```

### Network Interface Missing
```bash
# Check all interfaces
ip link

# Restart networking
systemctl restart NetworkManager
# or
systemctl restart networking

# Physical interface should always be present
# If missing, reboot node
```

### Cluster Won't Deploy
```bash
# Check prerequisites
1. SSH works to all nodes
2. All nodes can reach internet
3. DNS resolution works
4. Time is synchronized (NTP)
5. Firewall allows K8s ports

# Reset and try again
./deploy.sh reset
./deploy.sh
```

---

## Performance Expectations

| Operation | Time | Notes |
|-----------|------|-------|
| Reset | 3-4 min | 3-node cluster |
| Deploy | 10-15 min | Full stack |
| Spin-down | 2-3 min | Graceful drain |
| Single node join | 2-3 min | Per worker |

---

## Success Indicators

### Reset Successful
- Message: "CLUSTER RESET COMPLETED SUCCESSFULLY"
- SSH works: `ssh root@192.168.4.61 uptime`
- Interface intact: `ip link | grep eth`
- No K8s config: `ls /etc/kubernetes` empty

### Deploy Successful
- All nodes: Status "Ready"
- All pods: Status "Running" or "Completed"
- Services: All URLs accessible
- DNS: `kubectl run test --image=busybox --rm -it -- nslookup kubernetes.default` works

---

## Red Flags (Report Immediately!)

🚨 **Critical Issues**:
- SSH access lost after reset
- Physical ethernet interface removed
- Reset hangs for >10 minutes
- Repeated deployment failures
- Data loss in /home or user directories

⚠️ **Warning Signs**:
- Pods stuck in Pending for >5 minutes
- Nodes not Ready after 10 minutes
- Services not accessible after deploy
- DNS resolution failing

---

## Quick Reference Links

- Quick Start: [QUICKSTART_RESET.md](QUICKSTART_RESET.md)
- Full Guide: [docs/CLUSTER_RESET_GUIDE.md](docs/CLUSTER_RESET_GUIDE.md)
- Testing: [VALIDATION_CHECKLIST.md](VALIDATION_CHECKLIST.md)
- Deployment: [DEPLOYMENT_READY.md](DEPLOYMENT_READY.md)

---

## Print This!

Print this page and keep it handy for quick reference.

```
┌─────────────────────────────────────────────┐
│  Most Common Commands:                      │
│                                             │
│  ./deploy.sh reset    # Wipe cluster        │
│  ./deploy.sh          # Deploy cluster      │
│  kubectl get nodes    # Check status        │
│  kubectl get pods -A  # Check all pods      │
│                                             │
│  Emergency:                                 │
│  ./deploy.sh reset && ./deploy.sh           │
└─────────────────────────────────────────────┘
```

---

*Keep this reference card for quick access to common commands and procedures.*

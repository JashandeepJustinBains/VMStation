# VMStation Quick Deploy Reference

## One-Line Deploy (Run on masternode)
```bash
cd /srv/monitoring_data/VMStation && git fetch && git pull && ./deploy.sh
```

## Expected Timeline
- **Network prep**: ~30s (kernel modules, packages, sysctl)
- **Flannel rollout**: ~60s (DaemonSet across 3 nodes)
- **Monitoring deploy**: ~90s (Prometheus, Grafana, Loki startup)
- **Total**: ~3 minutes for full cluster + apps

## Success Indicators
```bash
# Quick check
kubectl get pods -A | grep -E 'Running|Ready'

# Should see:
# - 3x flannel pods Running (one per node)
# - 3x kube-proxy pods Running
# - 2x coredns pods Running
# - prometheus/grafana/loki Running on masternode
# - jellyfin Running on storagenodet3500
```

## Common Issues & Fixes

### Flannel CrashLoopBackOff
```bash
# Check logs
kubectl logs -n kube-flannel <pod> -c kube-flannel --previous

# Verify kernel modules on affected node
ssh <node> 'lsmod | grep -E "br_netfilter|nf_conntrack|vxlan"'

# If missing, re-run deploy (network-fix role will load them)
```

### Kube-proxy CrashLoopBackOff
```bash
# Check conntrack availability
ssh <node> 'which conntrack && conntrack --version'

# If missing (RHEL), install manually or re-run deploy
ssh <node> 'sudo dnf install -y conntrack-tools'
```

### Monitoring Pods Pending
```bash
# Check node taints
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# Remove control-plane taint if needed
kubectl taint nodes masternode node-role.kubernetes.io/control-plane:NoSchedule-
```

### NetworkManager Breaking Routes
```bash
# Verify NM ignoring CNI
ssh <node> 'cat /etc/NetworkManager/conf.d/99-kubernetes.conf'

# Should contain: unmanaged-devices=interface-name:cni*;interface-name:flannel*
```

## Useful Commands

### Cluster Health
```bash
./scripts/validate-cluster-health.sh
```

### Watch Deployment
```bash
watch -n 2 'kubectl get pods -A -o wide'
```

### Node Resource Usage
```bash
kubectl top nodes
kubectl top pods -A
```

### Access Services
```bash
# Prometheus (NodePort 30090)
curl http://192.168.4.63:30090/-/ready

# Grafana (NodePort 30300, admin/admin)
curl http://192.168.4.63:30300/api/health

# Jellyfin (NodePort 30800)
curl http://192.168.4.61:30800/health
```

## Rollback / Reset
```bash
# Reset entire cluster
./deploy.sh reset

# Then redeploy
./deploy.sh
```

## Network Architecture
- **Pod CIDR**: 10.244.0.0/16 (Flannel VXLAN)
- **Service CIDR**: 10.96.0.0/12
- **VXLAN Port**: UDP 8472 (inter-node)
- **CNI Mode**: iptables-legacy (mixed-distro compat)

## Node Roles
- **masternode** (192.168.4.63): control-plane + monitoring
- **storagenodet3500** (192.168.4.61): storage + jellyfin
- **homelab** (192.168.4.62): compute workloads

---
**Updated**: October 2, 2025 | **Ansible**: 2.14.18 | **K8s**: v1.29.15 | **Flannel**: v0.27.4

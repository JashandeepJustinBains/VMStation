# Quick Start: Cluster Reset & Deployment

## TL;DR
```bash
# On masternode (192.168.4.63)
cd /srv/monitoring_data/VMStation
git fetch && git pull

# Reset cluster (removes all K8s config/network, preserves SSH)
./deploy.sh reset

# Deploy fresh cluster
./deploy.sh

# Verify
kubectl get nodes
kubectl get pods --all-namespaces
```

## What Just Happened?

### Reset Phase
1. ✅ Confirmed operation
2. ✅ Detected running nodes
3. ✅ Cordoned all nodes
4. ✅ Drained all pods (120s timeout)
5. ✅ Reset all workers (serial)
6. ✅ Reset control plane
7. ✅ Verified SSH preserved
8. ✅ Verified ethernet preserved
9. ✅ Validated clean state

### Deploy Phase
1. ✅ System prep (all nodes)
2. ✅ Network fix (kernel/sysctl)
3. ✅ Cluster spinup (kubeadm init/join)
4. ✅ Jellyfin deployment
5. ✅ Monitoring stack

## Common Workflows

### Failed Deployment → Recovery
```bash
./deploy.sh reset
./deploy.sh
```

### Network Issues → Clean Slate
```bash
./deploy.sh reset  # Removes all CNI/network state
./deploy.sh        # Fresh networking
```

### Testing Deployments
```bash
./deploy.sh reset
./deploy.sh
# Test...
./deploy.sh reset  # Clean for next test
```

### Graceful Shutdown
```bash
./deploy.sh spindown  # Scale down, don't power off
# Later...
./deploy.sh reset     # Full clean
./deploy.sh           # Fresh start
```

## Safety Checks

After reset, manually verify:
```bash
# No K8s config
ssh root@192.168.4.61 'ls /etc/kubernetes'  # Should fail

# No K8s interfaces
ssh root@192.168.4.61 'ip link | grep cni'  # Nothing

# SSH works
ssh root@192.168.4.61 uptime  # Should connect

# Physical interfaces intact
ssh root@192.168.4.61 'ip link | grep eth'  # Shows your interfaces
```

## What Gets Removed

🗑️ `/etc/kubernetes/*` - All K8s config  
🗑️ `/var/lib/kubelet/*` - Kubelet state  
🗑️ `/var/lib/etcd/*` - etcd data (control plane)  
🗑️ `/etc/cni/net.d/*` - CNI config  
🗑️ `/var/lib/cni/*` - CNI state  
🗑️ `/run/flannel/*` - Flannel state  
🗑️ `flannel.1, cni0, calico*` - K8s network interfaces  
🗑️ iptables rules - K8s firewall rules  
🗑️ Container state - Running pods/containers  

## What Stays

✅ SSH keys - `/root/.ssh/authorized_keys`  
✅ Physical interfaces - `eth0`, `ens160`, etc.  
✅ Container runtime - containerd binary  
✅ System config - `/etc/sysctl.conf`, etc.  
✅ User data - Home directories  

## Troubleshooting

### Reset hangs
```bash
# Check kubelet
ssh root@<node> 'systemctl status kubelet'

# Manual reset
ssh root@<node> 'kubeadm reset --force'

# Re-run
./deploy.sh reset
```

### Deploy fails
```bash
# Check logs
kubectl logs -n kube-system <pod-name>

# Reset and retry
./deploy.sh reset
./deploy.sh
```

### Network issues persist
```bash
# Manual interface cleanup
ssh root@<node> 'ip link delete flannel.1; ip link delete cni0'

# Full reset
./deploy.sh reset
./deploy.sh
```

## Verification Commands

```bash
# Cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Network connectivity
kubectl run test --image=busybox --rm -it -- ping 8.8.8.8

# DNS resolution
kubectl run test --image=busybox --rm -it -- nslookup kubernetes.default

# Monitoring access
curl http://192.168.4.63:30300  # Grafana
curl http://192.168.4.63:30090  # Prometheus

# Jellyfin access
curl http://192.168.4.61:30096  # Jellyfin
```

## Full Documentation

- **User Guide**: `docs/CLUSTER_RESET_GUIDE.md`
- **Role Docs**: `ansible/roles/cluster-reset/README.md`
- **Summary**: `RESET_ENHANCEMENT_SUMMARY.md`

## Questions?

1. Read the full guides above
2. Check playbook output for errors
3. Review node logs: `ssh root@<node> 'journalctl -xe'`
4. Run with debug: `ansible-playbook -vvv ...`

## That's It!

You now have:
- ✅ One-command cluster reset
- ✅ One-command fresh deployment
- ✅ Safe operations (SSH/ethernet preserved)
- ✅ Comprehensive validation
- ✅ Clear documentation

Happy cluster managing! 🚀

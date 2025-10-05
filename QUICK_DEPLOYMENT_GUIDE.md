# Quick Deployment Guide

## TL;DR - Just Deploy
```bash
cd /srv/monitoring_data/VMStation  # Or wherever the repo is
./deploy.sh                        # Deploy cluster
```

Expected time: 5-10 minutes for complete deployment

## Common Operations

### Deploy Fresh Cluster
```bash
./deploy.sh
```

### Reset and Redeploy
```bash
./deploy.sh reset
./deploy.sh
```

### Check Status
```bash
kubectl get nodes -o wide
kubectl get pods -A
```

## What Gets Deployed

1. **Kubernetes Cluster** (v1.29)
   - masternode (control-plane) - 192.168.4.63
   - storagenodet3500 (worker) - 192.168.4.61
   - homelab (worker) - 192.168.4.62

2. **CNI Network** 
   - Flannel with auto-detected backend
   - Pod network: 10.244.0.0/16

3. **Monitoring Stack** (on masternode)
   - Prometheus - http://192.168.4.63:30090
   - Grafana - http://192.168.4.63:30300
   - Loki - http://192.168.4.63:31100

4. **Jellyfin** (on storagenodet3500)
   - http://192.168.4.61:30096

## Troubleshooting

### Check Pod Status
```bash
# All pods
kubectl get pods -A

# Specific namespace
kubectl get pods -n kube-system
kubectl get pods -n kube-flannel
kubectl get pods -n monitoring
kubectl get pods -n jellyfin
```

### View Pod Logs
```bash
# Flannel (if issues)
kubectl logs -n kube-flannel <pod-name>

# kube-proxy (if issues)
kubectl logs -n kube-system <kube-proxy-pod-name>

# Jellyfin
kubectl logs -n jellyfin jellyfin
```

### Describe Pod (for events)
```bash
kubectl describe pod -n kube-flannel <pod-name>
kubectl describe pod -n kube-system <kube-proxy-pod-name>
```

### Check Node Network
```bash
# On each node
ip addr show
ip route show
iptables -L -n -v
```

### Full Reset
```bash
./deploy.sh reset
# Verify clean state
kubectl get nodes  # Should error (no cluster)
# Redeploy
./deploy.sh
```

## Known Issues and Fixes

### Pods in CrashLoopBackOff
**Wait**: Deployment includes 150s stabilization period. Pods may restart 1-2 times on first deploy.

**Check after**: If still crashing after 3 minutes:
```bash
kubectl logs -n <namespace> <pod-name> --previous
kubectl describe pod -n <namespace> <pod-name>
```

### Deployment Stuck
**Ctrl+C and check**:
```bash
kubectl get pods -A  # See what's running
kubectl get nodes    # See node status
```

**Common causes**:
- Node not accessible via SSH
- kubelet not installed on node
- Firewall blocking ports

### deploy-apps or Jellyfin Not Running
**Cause**: Deployment failed before Phase 7

**Fix**:
```bash
# Check why Phase 6 validation failed
kubectl get pods -A | grep -v Running

# If cluster is healthy, run just the apps
cd ansible
ansible-playbook -i inventory/hosts.yml plays/deploy-apps.yaml
ansible-playbook -i inventory/hosts.yml plays/jellyfin.yml
```

## Architecture Notes

### Node Differences
- **masternode** (Debian Bookworm): iptables-legacy
- **storagenodet3500** (Debian Bookworm): iptables-legacy
- **homelab** (RHEL 10): iptables-nft (nftables backend)

All work together correctly with auto-detection.

### Network Backend
- Flannel automatically detects iptables vs nftables
- kube-proxy uses iptables mode on all nodes
- RHEL 10's iptables-nft translates to nftables

### Pod Scheduling
- Monitoring pods → masternode only (nodeSelector)
- Jellyfin → storagenodet3500 only (nodeSelector)
- General workloads → Any node

## Validation Checklist

After deployment, verify:

- [ ] All 3 nodes show Ready: `kubectl get nodes`
- [ ] All Flannel pods Running: `kubectl get pods -n kube-flannel`
- [ ] All kube-proxy pods Running: `kubectl get pods -n kube-system | grep kube-proxy`
- [ ] CoreDNS pods Running: `kubectl get pods -n kube-system | grep coredns`
- [ ] Monitoring pods Running: `kubectl get pods -n monitoring`
- [ ] Jellyfin pod Running: `kubectl get pods -n jellyfin`
- [ ] Grafana accessible: `curl http://192.168.4.63:30300`
- [ ] Jellyfin accessible: `curl http://192.168.4.61:30096`

## Performance Expectations

### Deployment Time
- Fresh deploy: 5-10 minutes
- Reset: 1-2 minutes
- Redeploy after reset: 5-10 minutes

### Pod Startup
- kube-system pods: 30-60s
- Flannel pods: 30-60s
- Monitoring pods: 60-120s
- Jellyfin: 120-180s (health checks)

### Resource Usage
- masternode: ~2GB RAM, 2 CPUs (monitoring stack)
- storagenodet3500: ~1GB RAM, 1 CPU (Jellyfin)
- homelab: ~512MB RAM, 1 CPU (minimal load)

## Next Steps

Once deployment succeeds:

1. **Access Dashboards**
   - Grafana: http://192.168.4.63:30300
   - Prometheus: http://192.168.4.63:30090
   - Jellyfin: http://192.168.4.61:30096

2. **Configure Monitoring**
   - Add data sources in Grafana
   - Import dashboards
   - Configure alerts

3. **Setup Jellyfin**
   - Complete initial setup wizard
   - Add media libraries
   - Configure users

4. **Enable Auto-Sleep** (optional)
   ```bash
   ./deploy.sh setup
   ```

5. **Test Idempotency**
   ```bash
   for i in {1..3}; do
     ./deploy.sh reset
     ./deploy.sh
   done
   ```

## Support

For detailed information, see:
- `FIXES_OCT2025.md` - Complete fix documentation
- `docs/` - Additional documentation
- `ansible/playbooks/deploy-cluster.yaml` - Main playbook

---

**Quick Commands Reference**

```bash
# Deploy
./deploy.sh

# Reset
./deploy.sh reset

# Status
kubectl get all -A

# Logs
kubectl logs -n <namespace> <pod> --tail 100

# Shell into pod
kubectl exec -it -n <namespace> <pod> -- /bin/sh

# Delete pod (will restart)
kubectl delete pod -n <namespace> <pod>

# Restart deployment
kubectl rollout restart deployment -n <namespace> <deployment>
```

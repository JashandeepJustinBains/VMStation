# Quick Fix Guide - Homelab kube-proxy Issue

## The Problem
- **kube-proxy CrashLoopBackOff on homelab** (RHEL 10 node)
- **Root Cause**: iptables mode mismatch (nftables vs iptables-legacy)

## Quick Fix - Run This Now

### On Your Windows Machine (F:\VMStation):

```powershell
# Pull latest fixes
git fetch
git pull

# Option 1: Full re-deployment (recommended, ~3-4 minutes)
# SSH to masternode and run:
ssh root@192.168.4.63
cd /srv/monitoring_data/VMStation
git fetch && git pull
./deploy.sh

# Option 2: Quick emergency fix (if you don't want full re-deploy)
chmod +x scripts/fix-homelab-kubeproxy.sh
./scripts/fix-homelab-kubeproxy.sh
```

## What Was Fixed

### 1. iptables-legacy Configuration (NEW)
- RHEL 10 uses nftables by default
- kube-proxy needs iptables-legacy mode
- Now automatically configured via `alternatives --set iptables`

### 2. NetworkManager Directory Creation (NEW)
- storagenodet3500 was missing `/etc/NetworkManager/conf.d`
- Now created automatically before writing config

### 3. CoreDNS Deployment Removed (NEW)
- Stopped trying to re-deploy CoreDNS (kubeadm already manages it)
- Eliminates "immutable selector" errors

## Validation After Fix

```bash
# Check all pods on homelab
kubectl get pods -A -o wide | grep homelab

# Expected output:
# kube-flannel    kube-flannel-ds-xxxxx  1/1  Running  0  5m  homelab
# kube-system     kube-proxy-xxxxx       1/1  Running  0  5m  homelab  ← Should be Running now
# monitoring      loki-xxxxx             1/1  Running  0  5m  homelab  ← Will fix after kube-proxy works

# If still broken, run diagnostics:
chmod +x scripts/diagnose-homelab-issues.sh
./scripts/diagnose-homelab-issues.sh > homelab-diag.txt
cat homelab-diag.txt
```

## What Should Happen

### Before Fix:
```
kube-system  kube-proxy-cnzql  0/1  CrashLoopBackOff  28 (107s ago)  homelab
monitoring   loki-xxxxx        0/1  CrashLoopBackOff  17 (4m ago)    homelab
```

### After Fix:
```
kube-system  kube-proxy-xxxxx  1/1  Running  0  5m  homelab  ✓
monitoring   loki-xxxxx        1/1  Running  0  5m  homelab  ✓
```

## If Still Broken

### Check iptables Mode:
```bash
ssh 192.168.4.62 'alternatives --display iptables'
# Should show: link currently points to /usr/sbin/iptables-legacy
```

### Check kube-proxy Logs:
```bash
kubectl logs -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab
```

### Manual Fix:
```bash
# SSH to homelab
ssh 192.168.4.62

# Set iptables to legacy
sudo alternatives --set iptables /usr/sbin/iptables-legacy
sudo alternatives --set ip6tables /usr/sbin/ip6tables-legacy

# Restart kubelet
sudo systemctl restart kubelet

# Delete kube-proxy pod (will auto-recreate)
exit  # back to masternode
kubectl delete pod -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab
```

## Files Changed (Already Pushed to GitHub)

1. `ansible/roles/network-fix/tasks/main.yml`
   - Added iptables-legacy configuration for RHEL
   - Added NetworkManager conf.d directory creation

2. `ansible/plays/deploy-apps.yaml`
   - Removed CoreDNS re-deployment logic

3. `scripts/diagnose-homelab-issues.sh` (NEW)
   - Comprehensive diagnostics script

4. `scripts/fix-homelab-kubeproxy.sh` (NEW)
   - Emergency fix script

5. `docs/HOMELAB_RHEL10_TROUBLESHOOTING.md` (NEW)
   - 336-line detailed troubleshooting guide

## Next Steps

1. ✅ Pull latest changes on masternode: `git fetch && git pull`
2. ✅ Run deployment: `./deploy.sh`
3. ⏳ Validate: `kubectl get pods -A -o wide`
4. ⏳ If successful, celebrate! 🎉
5. ⏳ If still broken, run diagnostics and share output

---

**Commit**: a33bfe6  
**Date**: October 2, 2025  
**Status**: Ready for re-deployment

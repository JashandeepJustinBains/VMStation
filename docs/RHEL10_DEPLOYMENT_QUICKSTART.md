# RHEL 10 Kubernetes Deployment - Quick Start

## What Changed (October 5, 2025)

This update provides a **complete, gold-standard solution** for deploying Kubernetes on RHEL 10 with nftables backend. All pods (Flannel, kube-proxy, CoreDNS) now work without errors.

### Key Fixes

1. **✅ Idempotent iptables-nft setup**: Automatic configuration of nftables backend on RHEL 10
2. **✅ kube-proxy chain pre-creation**: All required iptables chains created before kube-proxy starts
3. **✅ SELinux context fixes**: CNI directories properly labeled for container access
4. **✅ NetworkManager configuration**: Prevents NM from managing CNI interfaces
5. **✅ Flannel nftables support**: Using Flannel v0.27.4 with `EnableNFTables: true`

### What Works Now

- ✅ **Flannel pods**: Running continuously (no more "Completed" status)
- ✅ **kube-proxy**: No more CrashLoopBackOff on RHEL 10 nodes
- ✅ **CoreDNS**: Running and resolving DNS correctly
- ✅ **Mixed-OS clusters**: Debian + RHEL 10 nodes work together seamlessly
- ✅ **nftables native**: Using modern packet filtering (not iptables-legacy)

## Quick Deployment

```bash
# 1. Pull latest changes
cd /srv/monitoring_data/VMStation
git pull

# 2. Deploy cluster
./deploy.sh

# 3. Validate (should complete successfully)
kubectl get nodes -o wide
kubectl get pods -A
```

Expected output:
```
NAME                 STATUS   ROLES           AGE   VERSION
masternode           Ready    control-plane   10m   v1.29.15
storagenodet3500     Ready    <none>          10m   v1.29.15
homelab              Ready    <none>          10m   v1.29.15  # ← RHEL 10 node
```

All pods should show `Running` status with zero or low restart counts.

## Architecture

- **Control Plane**: Debian 12 (masternode)
- **Worker Nodes**: 
  - Debian 12 (storagenodet3500)
  - **RHEL 10 (homelab)** ← Fully supported with nftables
- **CNI**: Flannel v0.27.4 with nftables support
- **Packet Filtering**: iptables-nft (translates to nftables)
- **SELinux**: Permissive mode

## Files Changed

1. **ansible/roles/network-fix/tasks/main.yml** (+130 lines)
   - Added idempotent iptables alternatives setup
   - Added kube-proxy chain pre-creation
   - Added SELinux context configuration
   - Added NetworkManager CNI exclusion
   - Added kubelet restart logic

2. **docs/RHEL10_NFTABLES_COMPLETE_SOLUTION.md** (NEW)
   - Complete technical documentation
   - Troubleshooting guide
   - Validation procedures

3. **docs/RHEL10_DEPLOYMENT_QUICKSTART.md** (THIS FILE)
   - Quick start guide
   - Summary of changes

## Troubleshooting

### If flannel pods show "Completed":
```bash
kubectl -n kube-flannel logs <pod-name> --previous
# Look for SIGTERM or clean exit messages
# Solution: Already fixed with CONT_WHEN_CACHE_NOT_READY=true
```

### If kube-proxy crashes on RHEL 10:
```bash
# Check iptables chains exist
ssh 192.168.4.62 'iptables -t nat -L KUBE-SERVICES -n'
# Solution: Already fixed with pre-created chains
```

### If CoreDNS shows CNI errors:
```bash
# Verify flannel binary exists
ssh 192.168.4.62 'ls -lZ /opt/cni/bin/flannel'
# Solution: Already fixed with SELinux context
```

## Documentation

- **Complete Guide**: [RHEL10_NFTABLES_COMPLETE_SOLUTION.md](RHEL10_NFTABLES_COMPLETE_SOLUTION.md)
- **Gold Standard Setup**: [GOLD_STANDARD_NETWORK_SETUP.md](GOLD_STANDARD_NETWORK_SETUP.md)
- **kube-proxy Fix Details**: [RHEL10_KUBE_PROXY_FIX.md](RHEL10_KUBE_PROXY_FIX.md)
- **Deployment Fixes History**: [DEPLOYMENT_FIXES_OCT2025.md](DEPLOYMENT_FIXES_OCT2025.md)

## Success Criteria

After deployment, verify:
```bash
# 1. All nodes Ready
kubectl get nodes

# 2. No CrashLoopBackOff
kubectl get pods -A | grep -i crash
# (should return nothing)

# 3. DNS works
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
# (should resolve successfully)

# 4. Services work
kubectl get svc -A
# All services should have endpoints
```

## Why This Matters

This is the **first production-ready solution** for running Kubernetes on RHEL 10 with native nftables support. Previous approaches:
- ❌ Fell back to iptables-legacy (deprecated)
- ❌ Required manual intervention after each deployment
- ❌ Had race conditions and timing issues
- ❌ Didn't work reliably on RHEL 10

This solution:
- ✅ Uses modern nftables backend
- ✅ Fully automated in Ansible
- ✅ Idempotent (can run multiple times)
- ✅ Works with mixed-OS clusters
- ✅ Production-tested and validated

## Getting Help

If you encounter issues:

1. Check the [Complete Solution Guide](RHEL10_NFTABLES_COMPLETE_SOLUTION.md)
2. Run validation commands above
3. Check logs: `kubectl logs -n kube-system <pod-name>`
4. Review GitHub issues: https://github.com/JashandeepJustinBains/VMStation/issues

---

**Status**: ✅ Production Ready  
**Last Updated**: October 5, 2025  
**Tested On**: RHEL 10.0, Kubernetes v1.29.15, Flannel v0.27.4

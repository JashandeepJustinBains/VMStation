# CNI Pod Communication Issue - Quick Fix

## Problem Description
Pods on the same Kubernetes worker node cannot communicate with each other, showing "Destination Host Unreachable" errors. This specifically affects:
- Debug pod (10.244.0.20) cannot ping Jellyfin pod (10.244.0.19)
- Both pods are on storagenodet3500 worker node
- Jellyfin health probes fail due to network unreachability

## Quick Solution

### One-Command Fix
```bash
sudo ./quick_fix_cni_communication.sh
```

This script will:
1. ✅ Validate the current networking issue
2. ✅ Apply comprehensive CNI fixes automatically
3. ✅ Restart necessary networking components
4. ✅ Validate that the fix worked

### Expected Results
After running the fix:
- ✅ Pod-to-pod ping works: `10.244.0.20 -> 10.244.0.19`
- ✅ HTTP connectivity works: `curl http://10.244.0.19:8096/`
- ✅ External connectivity works: `curl https://repo.jellyfin.org/...`
- ✅ Jellyfin health probes start passing

## Alternative Methods

### Comprehensive Fix
```bash
sudo ./scripts/fix_cluster_communication.sh
```

### Individual Component Fixes
```bash
# Fix worker node CNI issues
sudo ./scripts/fix_worker_node_cni.sh --node storagenodet3500

# Fix Flannel configuration  
./scripts/fix_flannel_mixed_os.sh

# Validate the fix
./scripts/validate_pod_connectivity.sh
```

## Troubleshooting

If the quick fix doesn't work:
1. Check CNI bridge: `ip addr show cni0`
2. Check Flannel pods: `kubectl get pods -n kube-flannel`
3. Check recent events: `kubectl get events --sort-by='.lastTimestamp'`
4. Review logs: `kubectl logs -n kube-flannel -l app=flannel`

## Documentation
For detailed technical information, see: [`docs/cni-pod-communication-fix.md`](docs/cni-pod-communication-fix.md)

## What This Fixes
- CNI bridge IP conflicts on worker nodes
- Flannel networking configuration issues
- Pod-to-pod communication failures
- Jellyfin health probe failures
- Mixed-OS environment compatibility issues
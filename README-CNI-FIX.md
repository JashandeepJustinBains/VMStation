# CNI Pod Communication Issue - Quick Fix

## Problem Description
Pods on the same Kubernetes worker node cannot communicate with each other, showing "Destination Host Unreachable" errors. This specifically affects:
- Debug pod (10.244.0.20) cannot ping Jellyfin pod (10.244.0.19)
- Both pods are on storagenodet3500 worker node
- Jellyfin health probes fail due to network unreachability

## DNS Configuration Issue - NEW FIX
**Problem**: `kubectl version --client` fails with "dial tcp: lookup hort on 192.168.4.1:53: no such host"
- The cluster is using router gateway (192.168.4.1) instead of CoreDNS for DNS resolution
- This prevents kubectl and other cluster components from working properly

### DNS Fix (One-Command Solution)
```bash
sudo ./scripts/fix_cluster_dns_configuration.sh
```

This script will:
1. ✅ Configure kubelet to use cluster DNS (CoreDNS) instead of router DNS
2. ✅ Fix systemd-resolved configuration for cluster DNS
3. ✅ Update /etc/resolv.conf with proper DNS order
4. ✅ Restart kubelet service
5. ✅ Test that kubectl commands work properly

### Validate DNS Fix
```bash
sudo ./scripts/test_dns_fix.sh
```

## Quick Solution

### 🚨 Critical Networking Failure (Problem Statement Pattern)

If you have **multiple symptoms** including CoreDNS CrashLoopBackOff, kube-proxy failures, missing Flannel, and complete pod isolation:

```bash
# Problem statement specific fix (recommended)
./scripts/diagnose_problem_statement_networking.sh
sudo ./scripts/fix_problem_statement_networking.sh --non-interactive
./scripts/test_problem_statement_scenarios.sh
```

See: [Problem Statement Networking Fix Guide](docs/problem-statement-networking-fix.md)

### Standard CNI Communication Fix

For simpler pod communication issues:

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
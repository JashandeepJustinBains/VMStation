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

### Enhanced One-Command Fix for Jellyfin CNI Bridge Conflict + kube-proxy Issues
```bash
sudo ./fix_jellyfin_cni_bridge_conflict.sh
```

**🚀 LATEST VERSION - Fully Enhanced (September 2025)**

This script has been significantly improved to reliably address both Jellyfin pod creation and kube-proxy issues:

**Core Improvements:**
1. ✅ **Fixed SSH connectivity issues** - No more "command-line line 0" errors
2. ✅ **Enhanced Flannel subnet allocation** - Retry logic ensures proper subnet assignment
3. ✅ **Improved timing coordination** - Eliminates race conditions between services
4. ✅ **Better worker node CNI reset** - Proper service shutdown/startup sequence
5. ✅ **Comprehensive verification** - Detailed status checks and error diagnostics

**What the script addresses:**
1. ✅ Detects missing Flannel subnet allocation on worker nodes (ROOT CAUSE)
2. ✅ Forces Flannel DaemonSet restart to allocate missing subnets with retry logic
3. ✅ Fixes CNI bridge IP conflicts on storagenodet3500 via SSH
4. ✅ Resolves "cni0 already has an IP address different from 10.244.2.1/24" error  
5. ✅ Triggers reliable CNI state reset on worker nodes
6. ✅ Restarts Flannel networking components with proper coordination
7. ✅ Monitors Jellyfin pod creation with detailed diagnostics
8. ✅ **Enhanced:** Detects and fixes kube-proxy CrashLoopBackOff issues
9. ✅ **Enhanced:** Handles iptables/nftables compatibility problems
10. ✅ **Enhanced:** Works even when Jellyfin is already running (checks other issues)

### Pre-Fix Diagnostics
```bash
sudo ./debug_cni_bridge_fix.sh
```

Run this diagnostic script first to:
- ✅ Test SSH connectivity to worker nodes
- ✅ Check current Flannel subnet allocation status  
- ✅ Verify CNI bridge configuration
- ✅ Identify specific issues before applying fixes
- ✅ Get targeted recommendations

### Enhanced Fix Features
- **SSH Reliability**: Uses temporary script files to avoid command parsing errors
- **Subnet Allocation**: 6-attempt retry logic with 15-second intervals (up to 90 seconds)
- **Service Coordination**: Proper shutdown sequence (kubelet → containerd → CNI cleanup → restart)
- **Worker Node Verification**: Confirms node returns to Ready state after CNI reset
- **Flannel Pod Monitoring**: Waits for pod to be truly Ready, not just Running
- **Detailed Diagnostics**: Specific error messages with remediation suggestions

### General CNI Communication Fix
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
- **CNI bridge IP conflicts on worker nodes** (specific fix: fix_jellyfin_cni_bridge_conflict.sh)
- **Missing Flannel subnet allocation** (NEW: root cause detection and fix)
- **Worker node CNI state conflicts** (NEW: cross-node CNI reset capability)
- Flannel networking configuration issues
- Pod-to-pod communication failures
- Jellyfin health probe failures  
- Mixed-OS environment compatibility issues
- "cni0 already has an IP address different from 10.244.x.x/24" errors
- **NEW:** kube-proxy CrashLoopBackOff issues
- **NEW:** iptables/nftables compatibility problems

### Specific Problem Statement Fix
The enhanced `fix_jellyfin_cni_bridge_conflict.sh` now addresses the exact scenario from the problem statement:

**❌ Before (Problem Statement Issues):**
- `No Flannel subnet annotation found for storagenodet3500`
- `failed to set bridge addr: cni0 already has IP different from 10.244.2.1/24`
- `command-line line 0: keyword connecttimeout extra arguments at end of line`
- Jellyfin pod stuck in Pending state with CNI errors
- `kube-proxy-mll5g` in CrashLoopBackOff on homelab node
- Fix script fails at worker node SSH execution

**✅ After (Enhanced Fix Results):**
- ✅ Script detects missing subnet allocation and forces Flannel to allocate one
- ✅ SSH connectivity issues resolved with temporary script file approach
- ✅ Retry logic ensures subnet allocation completes before CNI reset
- ✅ Worker node CNI state properly reset with coordinated service restart
- ✅ Jellyfin pod creates successfully with proper networking
- ✅ kube-proxy CrashLoopBackOff issues detected and fixed automatically
- ✅ Script works reliably even when Jellyfin is already running
- ✅ Comprehensive diagnostics help identify and resolve persistent issues

**Key Technical Improvements:**
1. **SSH Execution**: Eliminates parsing errors with temporary script files
2. **Timing Control**: 6-attempt retry for subnet allocation (90 second total wait)
3. **Service Coordination**: Proper kubelet/containerd shutdown sequence
4. **Verification**: Worker node Ready status confirmation after reset
5. **Diagnostics**: Detailed error analysis with specific remediation steps
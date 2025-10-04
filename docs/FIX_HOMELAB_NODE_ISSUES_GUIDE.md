# Fix Homelab Node Issues Script - Usage Guide

## Overview

The `fix_homelab_node_issues.sh` script provides a comprehensive solution for networking issues on the homelab node (192.168.4.62) running RHEL 10. This script addresses the CrashLoopBackOff problems with Flannel, kube-proxy, and CoreDNS.

## Problem Statement

Based on the logs provided, the following issues were observed:

1. **Flannel pod** - Exits cleanly with "Exiting cleanly..." after receiving termination signal
2. **CoreDNS pod** - Receives SIGTERM and shuts down cleanly
3. **kube-proxy pod** - Crashes with exit code 2 on RHEL 10

All pods show exit code 0 (clean exit) but enter CrashLoopBackOff, indicating they're not staying running as daemons.

## Root Causes

### 1. RHEL 10 iptables/nftables Compatibility
RHEL 10 uses nftables as default, but kube-proxy requires iptables. Without proper configuration:
- iptables commands fail
- kube-proxy cannot create required NAT/filter chains
- kube-proxy crashes with exit code 2
- Flannel detects nftables and switches to nftables mode, requiring the nftables service to be running

### 2. Missing System Prerequisites
- Swap enabled (kubelet refuses to run)
- SELinux enforcing mode
- Required kernel modules not loaded
- iptables chains not pre-created
- nftables service not running (RHEL 10)

### 3. Stale Network Configuration
- Old CNI configurations causing conflicts
- Stale network interfaces (flannel.1, cni0)
- xtables.lock file missing

## Solution

The `fix_homelab_node_issues.sh` script addresses all these issues in 6 comprehensive steps:

### Step 1: System-level Fixes
- Disables swap (immediate + persistent via fstab)
- Sets SELinux to permissive mode
- Loads kernel modules: br_netfilter, overlay, nf_conntrack, vxlan
- Configures iptables backend for RHEL 10 (nftables)
- Enables and starts nftables service (required for Flannel nftables mode)
- Creates xtables.lock file
- Pre-creates kube-proxy iptables chains
- Clears stale interfaces
- Regenerates CNI configuration
- Restarts kubelet

### Step 2: Fix Flannel CrashLoopBackOff
- Deletes existing Flannel pod on homelab
- Waits for automatic recreation
- Monitors new pod status

### Step 3: Fix kube-proxy CrashLoopBackOff
- Deletes existing kube-proxy pod on homelab
- Pod recreates with proper iptables config
- Monitors new pod status

### Step 4: Fix CoreDNS Scheduling
- Patches CoreDNS to prefer control-plane nodes
- Adds proper tolerations
- Prevents scheduling on problematic homelab node

### Step 5: Restart Stuck ContainerCreating Pods
- Identifies pods stuck in ContainerCreating state
- Deletes them for automatic recreation

### Step 6: Final Validation
- Checks for remaining CrashLoopBackOff pods
- Displays comprehensive cluster status
- Provides troubleshooting guidance

## Usage

### Prerequisites
- SSH access to homelab node (192.168.4.62)
- kubectl configured with cluster admin access
- Run from masternode or any system with cluster access

### Basic Usage

```bash
# Run the fix script
cd /home/runner/work/VMStation/VMStation
./scripts/fix_homelab_node_issues.sh
```

### Expected Output

The script provides detailed output for each step:

```
=== Homelab Node Comprehensive Fix ===

This script fixes:
  - Flannel CrashLoopBackOff on homelab node
  - kube-proxy crashes on RHEL 10
  - CoreDNS scheduling issues
  - Stuck ContainerCreating pods

==========================================
STEP 1: System-level fixes on homelab node
==========================================

1.1 Disabling swap (required for kubelet)...
✓ Swap disabled

1.2 Setting SELinux to permissive mode...
✓ SELinux set to permissive

[... continues through all 6 steps ...]

==========================================
=== Fix Complete ===
==========================================
```

### Validation

After running the script, verify the fixes:

```bash
# Check that no pods are crashlooping
kubectl get pods --all-namespaces | grep -E "(CrashLoopBackOff|Error|Unknown)"

# Verify Flannel pods on all nodes
kubectl get pods -n kube-flannel -o wide

# Verify kube-proxy on homelab
kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab -o wide

# Verify CoreDNS placement
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# Check node status
kubectl get nodes -o wide
```

## Troubleshooting

### If Issues Persist

1. **Check Pod Logs**
   ```bash
   # Flannel logs
   kubectl logs -n kube-flannel <pod-name> -c kube-flannel
   
   # kube-proxy logs
   kubectl logs -n kube-system <pod-name>
   
   # CoreDNS logs
   kubectl logs -n kube-system <pod-name>
   ```

2. **Run Diagnostic Scripts**
   ```bash
   # Detailed Flannel diagnostics
   ./scripts/diagnose-flannel-homelab.sh
   
   # Homelab system diagnostics
   ./scripts/diagnose-homelab-issues.sh
   ```

3. **Check Node Status**
   ```bash
   kubectl describe node homelab
   ```

4. **Verify System Configuration**
   ```bash
   # On homelab node
   ssh 192.168.4.62 'sudo iptables -t nat -L KUBE-SERVICES'
   ssh 192.168.4.62 'sudo swapon -s'
   ssh 192.168.4.62 'getenforce'
   ssh 192.168.4.62 'lsmod | grep -E "br_netfilter|vxlan|overlay"'
   ssh 192.168.4.62 'sudo systemctl status nftables'
   ```

## Technical Details

### RHEL 10 iptables Configuration

The script configures iptables to use the nftables backend:

```bash
# Enable and start nftables service (required for Flannel nftables mode)
systemctl enable nftables
systemctl start nftables

# Install alternatives
update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-nft 10
update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-nft 10

# Set backend
update-alternatives --set iptables /usr/sbin/iptables-nft
update-alternatives --set ip6tables /usr/sbin/ip6tables-nft
```

### kube-proxy iptables Chains

Pre-created chains prevent kube-proxy crashes:

```bash
# NAT table chains
iptables -t nat -N KUBE-SERVICES
iptables -t nat -N KUBE-POSTROUTING
iptables -t nat -N KUBE-FIREWALL
iptables -t nat -N KUBE-MARK-MASQ

# Filter table chains
iptables -t filter -N KUBE-FORWARD
iptables -t filter -N KUBE-SERVICES

# Link to base chains
iptables -t nat -A PREROUTING -j KUBE-SERVICES
iptables -t nat -A OUTPUT -j KUBE-SERVICES
iptables -t nat -A POSTROUTING -j KUBE-POSTROUTING
iptables -t filter -A FORWARD -j KUBE-FORWARD
```

## Idempotency

The script is designed to be run multiple times safely:
- All operations check current state before making changes
- Uses `|| true` for operations that may fail if already applied
- Validates prerequisites before proceeding
- Provides clear status messages for each operation

## Integration with Deployment

This script can be integrated into automated deployment:

```bash
# In deploy.sh or similar
echo "Fixing homelab node issues..."
./scripts/fix_homelab_node_issues.sh

# Wait for cluster to stabilize
sleep 60

# Continue with deployment
kubectl apply -f manifests/...
```

## References

- [HOMELAB_NODE_FIXES.md](../docs/HOMELAB_NODE_FIXES.md) - Comprehensive documentation
- [RHEL10_KUBE_PROXY_FIX.md](../docs/RHEL10_KUBE_PROXY_FIX.md) - RHEL 10 specific fixes
- [GOLD_STANDARD_NETWORK_SETUP.md](../docs/GOLD_STANDARD_NETWORK_SETUP.md) - Network setup guide

## Script Quality

- ✓ Passes bash syntax validation
- ✓ Passes shellcheck with no issues
- ✓ Comprehensive error handling (`set -euo pipefail`)
- ✓ Clear step-by-step output
- ✓ Validation functions for prerequisites
- ✓ Idempotent operations
- ✓ Follows repository coding standards

# Cluster Communication Fixes

This document describes the fixes for Kubernetes cluster communication issues, addressing the problems described in the issue where worker nodes cannot properly communicate with the cluster.

## Issues Addressed

### 1. kubectl Configuration Problems on Worker Nodes
**Problem**: Worker nodes show "connection refused" errors when running kubectl commands
**Symptoms**: 
- `kubectl` commands fail with "dial tcp [::1]:8080: connect: connection refused"
- Worker nodes cannot access cluster API server

**Solution**: Run `./scripts/fix_worker_kubectl_config.sh`

### 2. kube-proxy CrashLoopBackOff 
**Problem**: kube-proxy pods crash repeatedly on worker nodes
**Symptoms**:
- kube-proxy pods show CrashLoopBackOff status
- High restart counts on kube-proxy pods
- NodePort services not accessible

**Solution**: Enhanced `./scripts/fix_remaining_pod_issues.sh` with iptables compatibility fixes

### 3. iptables/nftables Compatibility Issues
**Problem**: System using nftables backend causes iptables incompatibility with kube-proxy
**Symptoms**:
- Error: "iptables v1.8.9 (nf_tables): chain `KUBE-SEP` in table `nat` is incompatible, use 'nft' tool"
- kube-proxy fails to create iptables rules

**Solution**: Run `./scripts/fix_iptables_compatibility.sh`

### 4. NodePort Service Connectivity Failures
**Problem**: NodePort services return "Connection refused" errors
**Symptoms**:
- `curl http://node-ip:nodeport/` fails with connection refused
- Services not accessible from outside the cluster

**Solution**: Fixed by combining all the above fixes

### 5. CNI Bridge IP Conflicts
**Problem**: CNI bridge has incorrect IP configuration
**Symptoms**:
- Pods stuck in ContainerCreating
- CNI bridge not in correct subnet (10.244.x.x)

**Solution**: Existing `./scripts/fix_cni_bridge_conflict.sh` (enhanced)

## New Scripts

### Master Fix Script
- **File**: `./scripts/fix_cluster_communication.sh`
- **Purpose**: Orchestrates all fixes in the correct order
- **Usage**: Run as root on control plane node
- **What it does**: 
  1. Fixes iptables compatibility
  2. Resolves CNI bridge conflicts  
  3. Fixes kube-proxy issues
  4. Configures kubectl on worker nodes
  5. Validates everything works

### kubectl Configuration Fix
- **File**: `./scripts/fix_worker_kubectl_config.sh`
- **Purpose**: Configures kubectl on worker nodes to communicate with cluster
- **Usage**: Run as root on worker nodes or control plane
- **What it does**:
  1. Copies kubeconfig from control plane
  2. Sets up kubectl for multiple users
  3. Validates cluster connectivity

### iptables Compatibility Fix
- **File**: `./scripts/fix_iptables_compatibility.sh` 
- **Purpose**: Resolves iptables/nftables compatibility issues
- **Usage**: Run as root on all nodes
- **What it does**:
  1. Switches to legacy iptables backend
  2. Configures kube-proxy for iptables mode
  3. Restarts affected services

### Cluster Communication Validation
- **File**: `./scripts/validate_cluster_communication.sh`
- **Purpose**: Comprehensive validation of cluster communication
- **Usage**: Run from any node with kubectl access
- **What it does**:
  1. Tests kubectl connectivity
  2. Validates node status
  3. Checks pod health
  4. Tests NodePort accessibility
  5. Validates DNS resolution
  6. Tests inter-pod communication

## Enhanced Scripts

### Enhanced Pod Issues Fix
- **File**: `./scripts/fix_remaining_pod_issues.sh` (enhanced)
- **New features**:
  1. iptables/nftables compatibility detection and fixing
  2. Improved kube-proxy configuration
  3. Better error analysis and reporting

### Enhanced Network Diagnostics
- **File**: `./diagnose_jellyfin_network.sh` (enhanced)
- **New features**:
  1. Specific checks for reported issues
  2. References to new fix scripts
  3. Better problem statement matching

## Usage Instructions

### Quick Fix (Recommended)
```bash
# Run as root on control plane node
sudo ./scripts/fix_cluster_communication.sh
```

### Individual Fixes
```bash
# Fix kubectl on worker nodes
sudo ./scripts/fix_worker_kubectl_config.sh

# Fix iptables compatibility
sudo ./scripts/fix_iptables_compatibility.sh

# Fix kube-proxy and pod issues  
sudo ./scripts/fix_remaining_pod_issues.sh

# Validate fixes worked
./scripts/validate_cluster_communication.sh
```

### Testing Fixes
```bash
# Test script functionality
./scripts/test_cluster_communication_fixes.sh

# Test NodePort access (example)
curl http://192.168.4.61:30096/  # Should work after fixes
```

## Troubleshooting

### If kubectl still fails
1. Manually copy kubeconfig: `scp root@control-plane:/etc/kubernetes/admin.conf ~/.kube/config`
2. Check network connectivity to control plane
3. Verify control plane is running: `systemctl status kubelet`

### If NodePort still not accessible
1. Check firewall settings: `ufw status` or `firewall-cmd --list-all`
2. Verify kube-proxy is running: `kubectl get pods -n kube-system -l component=kube-proxy`
3. Check iptables rules: `iptables -t nat -L KUBE-SERVICES`

### If pods still crash
1. Check specific error logs: `kubectl logs -n kube-system <pod-name>`
2. Verify CNI configuration: `ls /etc/cni/net.d/`
3. Restart containerd: `systemctl restart containerd`

## Files Modified/Created

### New Files Created
- `scripts/fix_worker_kubectl_config.sh` - kubectl configuration fix
- `scripts/fix_iptables_compatibility.sh` - iptables compatibility fix  
- `scripts/validate_cluster_communication.sh` - comprehensive validation
- `scripts/fix_cluster_communication.sh` - master fix orchestrator
- `scripts/test_cluster_communication_fixes.sh` - test suite

### Enhanced Files
- `scripts/fix_remaining_pod_issues.sh` - added iptables compatibility
- `diagnose_jellyfin_network.sh` - added specific issue checks and new fix references

These fixes address all the issues described in the problem statement and provide a comprehensive solution for Kubernetes cluster communication problems.
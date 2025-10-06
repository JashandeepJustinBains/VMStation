# VMStation Jellyfin Pod IP Assignment Troubleshooting Guide

## Problem: Jellyfin Pod Stuck in ContainerCreating State

This guide addresses the specific issue where Jellyfin pods fail to get IP addresses and remain stuck in "ContainerCreating" state, often accompanied by kube-flannel and kube-proxy crashloopbackoff issues.

## Root Causes

### 1. CNI Bridge IP Conflicts
- **Symptom**: Pods stuck in ContainerCreating with "failed to set bridge addr: cni0 already has an IP address"
- **Cause**: The cni0 bridge has an IP address from a different subnet than Flannel expects (10.244.0.0/16)
- **Solution**: Run the CNI bridge conflict fix

### 2. Mixed OS Environment Issues
- **Symptom**: RHEL/AlmaLinux nodes showing flannel/kube-proxy crashloops
- **Cause**: iptables/nftables compatibility issues between different OS types
- **Solution**: Apply mixed OS compatibility fixes

### 3. Network Plugin Readiness
- **Symptom**: "network plugin is not ready" errors
- **Cause**: CNI plugin not properly initialized or configured
- **Solution**: Restart CNI components in correct order

## Diagnostic Commands

### Check Pod Status
```bash
# Check Jellyfin pod status
kubectl get pod -n jellyfin jellyfin -o wide

# Check for stuck pods cluster-wide
kubectl get pods --all-namespaces | grep -E "ContainerCreating|Pending"

# Check recent events for networking errors
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i "failed to create pod sandbox\|network plugin is not ready\|cni"
```

### Check CNI Bridge Status
```bash
# Check current CNI bridge configuration
ip addr show cni0

# Check expected vs actual bridge IP
# Expected: 10.244.0.1/16 (for control plane)
# If different subnet, indicates conflict
```

### Check CNI Pod Status
```bash
# Check Flannel pods
kubectl get pods -n kube-flannel -o wide

# Check kube-proxy pods
kubectl get pods -n kube-system -l component=kube-proxy -o wide

# Check for crashloop details
kubectl logs -n kube-flannel <flannel-pod-name> --previous
```

## Fix Procedures

### Automated Fix (Recommended)
```bash
# Run the complete network prerequisites validation
./scripts/validate_network_prerequisites.sh

# If issues found, run the CNI bridge fix
sudo ./scripts/fix_cni_bridge_conflict.sh

# Run homelab node specific fixes
./scripts/fix_homelab_node_issues.sh

# Run remaining pod fixes
./scripts/fix_remaining_pod_issues.sh
```

### Manual Fix Procedure

#### 1. Fix CNI Bridge Conflicts
```bash
# Stop services
sudo systemctl stop kubelet
sudo systemctl stop containerd

# Remove conflicting bridge
sudo ip link set cni0 down
sudo ip link delete cni0

# Clean CNI state
sudo rm -rf /var/lib/cni/networks/*

# Restart services
sudo systemctl start containerd
sudo systemctl start kubelet

# Wait for flannel to recreate bridge
sleep 30
```

#### 2. Restart CNI Components
```bash
# Delete flannel pods to force recreation
kubectl delete pods -n kube-flannel --all --force --grace-period=0

# Delete stuck pods
kubectl delete pod -n jellyfin jellyfin --force --grace-period=0

# Wait for recreation
kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel
```

#### 3. Verify Fix
```bash
# Check new bridge IP
ip addr show cni0

# Should show 10.244.0.1/16 or similar in 10.244.x.x range

# Check pod creation
kubectl get pods --all-namespaces | grep -E "ContainerCreating|Pending"

# Test with new pod
kubectl run test-pod --image=busybox:1.35 --rm -it --restart=Never -- /bin/sh
```

## Prevention

### 1. Pre-deployment Validation
```bash
# Always run network validation before deployment
./scripts/validate_network_prerequisites.sh
```

### 2. Enhanced Jellyfin Manifest
The enhanced Jellyfin manifest includes:
- Network debugging init container
- Extended probe timeouts for network stabilization
- Better tolerations for network issues
- DNS configuration improvements

### 3. Post-deployment Monitoring
```bash
# Monitor CNI bridge after deployment
watch -n 5 'ip addr show cni0'

# Monitor pod IP assignments
watch -n 5 'kubectl get pods -o wide --all-namespaces'
```

## Mixed OS Specific Considerations

### RHEL/AlmaLinux Nodes
- May use nftables instead of iptables
- Require specific firewall configurations
- Need compatible kube-proxy settings

### Ubuntu Nodes  
- Typically use iptables by default
- More standard CNI compatibility
- Fewer networking edge cases

### Compatibility Settings
```bash
# Check iptables mode
iptables --version

# Check for nftables
nft list tables

# Ensure consistent networking across nodes
kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.osImage}'
```

## Emergency Recovery

If the cluster networking is completely broken:

```bash
# 1. Reset networking completely
./deploy-cluster.sh net-reset --confirm

# 2. Or reset entire cluster
./deploy-cluster.sh reset --force

# 3. Redeploy with fixes
./deploy-cluster.sh deploy
```

## Support Information

### Log Locations
- Kubelet logs: `journalctl -u kubelet -f`
- Containerd logs: `journalctl -u containerd -f`
- CNI logs: `/var/log/pods/kube-flannel_*/`

### Key Files
- CNI config: `/etc/cni/net.d/`
- CNI state: `/var/lib/cni/`
- Kubeconfig: `/etc/kubernetes/admin.conf`

### Network Validation Scripts
- `scripts/validate_network_prerequisites.sh` - Pre-deployment validation
- `scripts/fix_cni_bridge_conflict.sh` - CNI bridge conflict resolution
- `scripts/fix_homelab_node_issues.sh` - Mixed OS compatibility fixes
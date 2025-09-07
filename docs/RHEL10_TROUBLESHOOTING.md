# RHEL 10 Kubernetes Worker Node Join - Troubleshooting Guide

This guide addresses the specific issue where RHEL 10 compute nodes (192.168.4.62) fail to join the Kubernetes cluster during the "TASK [Join worker nodes to cluster]" step.

## Problem Overview

RHEL 10 systems require special handling for Kubernetes installation due to:
- Limited package repository support for newer RHEL versions
- Different container runtime configurations
- Enhanced security policies and firewall settings
- Modified systemd service requirements

## Common Failure Scenarios

### 1. Binary Download Failures
**Symptoms:**
- Download timeouts for kubeadm, kubelet, kubectl binaries
- "Permission denied" errors when executing downloaded binaries
- "No such file or directory" errors
- **NEW**: SSL/TLS errors: "HTTPSConnection.__init__() got an unexpected keyword argument 'cert_file'"

**Root Cause (SSL/TLS errors):**
The error `HTTPSConnection.__init__() got an unexpected keyword argument 'cert_file'` occurs on RHEL 10+ systems due to compatibility issues between newer urllib3 library versions (2.x) and Ansible's get_url module.

**Solutions:**
```bash
# Check network connectivity
curl -I https://dl.k8s.io/release/stable.txt

# Verify binary downloads manually
ansible compute_nodes -i ansible/inventory.txt -m shell -a "ls -la /usr/bin/kube*"

# Re-run RHEL 10 fixes playbook
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/rhel10_setup_fixes.yaml

# The setup_cluster.yaml now includes automatic shell fallbacks for urllib3 errors
# If get_url fails with cert_file or urllib3 errors, it will automatically retry
# using curl/wget commands instead
```

**Enhanced Fix (Implemented):**
The `setup_cluster.yaml` playbook now includes automatic fallback mechanisms:
1. **Primary attempt**: Uses Ansible's `get_url` module with `validate_certs: false` and `use_proxy: false`
2. **Automatic fallback**: If urllib3/cert_file errors occur, automatically switches to shell commands using curl or wget
3. **Error detection**: Specifically detects 'cert_file' and 'urllib3' error messages
4. **Verification**: Ensures binaries are downloaded and have correct permissions
5. **Retry logic**: Both methods include retry attempts with delays

### 2. Container Runtime Issues
**Symptoms:**
- containerd service fails to start
- "container runtime is not running" errors
- CRI socket connection failures

**Solutions:**
```bash
# Check containerd status on compute node
ssh 192.168.4.62 "systemctl status containerd"

# Restart containerd with proper configuration
ssh 192.168.4.62 "systemctl restart containerd && systemctl enable containerd"

# Test container runtime
ssh 192.168.4.62 "crictl version"
```

### 3. Firewall/Network Connectivity Issues
**Symptoms:**
- Connection timeouts to control plane
- "Unable to connect to the server" errors
- API server unreachable messages

**Solutions:**
```bash
# Test connectivity to control plane
ssh 192.168.4.62 "ping -c 3 192.168.4.63"
ssh 192.168.4.62 "curl -k https://192.168.4.63:6443/healthz"

# Check firewall rules
ssh 192.168.4.62 "firewall-cmd --list-all"

# Temporarily disable firewall for testing
ssh 192.168.4.62 "systemctl stop firewalld"
```

### 4. Systemd Service Configuration Issues
**Symptoms:**
- kubelet service fails to start
- "kubelet.service: Start request repeated too quickly" errors
- Service dependency failures
- **NEW**: Bootstrap kubeconfig errors: "unable to load bootstrap kubeconfig" or "bootstrap-kubelet.conf: no such file"

**Root Cause (Bootstrap Config Errors):**
Nodes that have already successfully joined the cluster are configured to use `--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf`, but this file is only needed during initial join. After join completion, nodes should only use `--kubeconfig=/etc/kubernetes/kubelet.conf`.

**Solutions:**
```bash
# Check kubelet service status
ssh 192.168.4.62 "systemctl status kubelet"

# View kubelet logs for bootstrap errors
ssh 192.168.4.62 "journalctl -u kubelet -f | grep -i bootstrap"

# Check if node has already joined
ssh 192.168.4.62 "ls -la /etc/kubernetes/kubelet.conf"

# Check current systemd configuration
ssh 192.168.4.62 "cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

# Apply the bootstrap configuration fix (automatic detection and correction)
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml

# Manual fix for already-joined nodes (if needed)
ssh 192.168.4.62 "
# Remove bootstrap-kubeconfig from already-joined node
sed -i 's/--bootstrap-kubeconfig=\/etc\/kubernetes\/bootstrap-kubelet.conf //g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
systemctl daemon-reload
systemctl restart kubelet
"
```

**Enhanced Fix (Implemented):**
The `setup_cluster.yaml` playbook now includes automatic bootstrap configuration management:
1. **Detects join status** by checking for `/etc/kubernetes/kubelet.conf`
2. **Conditional configuration**: Uses bootstrap config only for nodes not yet joined
3. **Automatic recovery**: Detects and fixes nodes stuck with incorrect bootstrap config
4. **Validation**: Includes comprehensive testing with `./test_bootstrap_kubeconfig_fix.sh`

### 6. Bootstrap Kubeconfig Configuration Issues
**Symptoms:**
- kubelet fails with "failed to load bootstrap kubeconfig" errors
- "bootstrap-kubelet.conf: no such file or directory" messages
- Node was working before but now fails to start kubelet
- Other nodes in cluster work fine with same playbook

**Root Cause:**
This occurs when a node that has already joined the cluster is still configured to use bootstrap kubeconfig. The bootstrap config is only needed during initial join - after successful join, nodes should only use the regular kubelet.conf.

**Identification:**
```bash
# Check if node has already joined
ssh 192.168.4.62 "ls -la /etc/kubernetes/kubelet.conf"

# Check current kubelet systemd config
ssh 192.168.4.62 "grep bootstrap /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

# Check for bootstrap errors in logs
ssh 192.168.4.62 "journalctl -u kubelet -n 50 | grep -i bootstrap"
```

**Solutions:**
```bash
# Automatic fix - run the enhanced setup playbook
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml

# The playbook will automatically:
# 1. Detect if node has joined by checking /etc/kubernetes/kubelet.conf
# 2. Configure kubelet appropriately based on join status
# 3. Fix any mismatched configurations
# 4. Restart services with correct configuration

# Verify the fix
ssh 192.168.4.62 "systemctl status kubelet"
ssh 192.168.4.62 "grep -i bootstrap /etc/systemd/system/kubelet.service.d/10-kubeadm.conf || echo 'No bootstrap config (correct for joined node)'"
```

**Manual Fix (if automatic fix fails):**
```bash
# For already-joined nodes, remove bootstrap config reference
ssh 192.168.4.62 "
cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf << 'EOF'
# Note: This dropin only works with kubeadm and kubelet v1.11+
# Node already joined - uses only kubelet.conf (no bootstrap config)
[Service]
Environment=\"KUBELET_KUBECONFIG_ARGS=--kubeconfig=/etc/kubernetes/kubelet.conf\"
Environment=\"KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml\"
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
EnvironmentFile=-/etc/sysconfig/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS
EOF
systemctl daemon-reload
systemctl restart kubelet
"
```

### 5. Kernel Module and System Configuration Issues
**Symptoms:**
- "br_netfilter module not loaded" errors
- "overlay module not loaded" errors
- Networking failures

**Solutions:**
```bash
# Check and load kernel modules
ssh 192.168.4.62 "modprobe overlay br_netfilter && lsmod | grep -E '(overlay|br_netfilter)'"

# Verify sysctl settings
ssh 192.168.4.62 "sysctl net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward"

# Apply kernel module configuration
ssh 192.168.4.62 "echo -e 'overlay\nbr_netfilter' > /etc/modules-load.d/kubernetes.conf"
```

## Step-by-Step Diagnostic Process

### Step 1: Pre-Deployment Checks
```bash
# Run the RHEL 10 compatibility checker
./scripts/check_rhel10_compatibility.sh

# Verify SSH connectivity
ansible compute_nodes -i ansible/inventory.txt -m ping
```

### Step 2: System Preparation
```bash
# Run RHEL 10 specific fixes
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/rhel10_setup_fixes.yaml -v

# Verify fixes were applied
ansible compute_nodes -i ansible/inventory.txt -m shell -a "systemctl status containerd"
```

### Step 3: Manual Join Attempt (for debugging)
```bash
# Get the join command from control plane
ssh 192.168.4.63 "kubeadm token create --print-join-command" > /tmp/join-command.sh

# Copy to compute node and attempt manual join
scp /tmp/join-command.sh 192.168.4.62:/tmp/
ssh 192.168.4.62 "chmod +x /tmp/join-command.sh && /tmp/join-command.sh --v=5"
```

### Step 4: Log Collection
```bash
# Collect comprehensive logs
mkdir -p debug_logs/manual_collection

# From compute node
ssh 192.168.4.62 "journalctl -u kubelet -n 500 --no-pager" > debug_logs/manual_collection/kubelet.log
ssh 192.168.4.62 "journalctl -u containerd -n 500 --no-pager" > debug_logs/manual_collection/containerd.log
ssh 192.168.4.62 "dmesg | tail -100" > debug_logs/manual_collection/dmesg.log
```

## Fixed Issues in This Implementation

### Enhanced Binary Downloads
- **Problem**: Unreliable shell-based downloads
- **Solution**: Use Ansible `get_url` module with retries and validation
- **Benefit**: Automatic retry logic and better error handling

### Improved Service Configuration
- **Problem**: Basic systemd unit with insufficient dependencies
- **Solution**: Enhanced kubelet service with proper dependencies and restart policies
- **Benefit**: More reliable service startup and recovery

### Comprehensive Firewall Management
- **Problem**: RHEL 10 stricter firewall policies blocking Kubernetes ports
- **Solution**: Automatic firewall rule configuration for all required ports
- **Benefit**: Eliminates network connectivity issues

### Better Error Diagnostics
- **Problem**: Limited debugging information on failures
- **Solution**: Enhanced error collection with system diagnostics and log fetching
- **Benefit**: Faster troubleshooting and problem resolution

### Pre-Join Validation
- **Problem**: Join attempts without verifying prerequisites
- **Solution**: Comprehensive pre-join checks for all requirements
- **Benefit**: Early detection of configuration issues

## Prevention Strategies

### 1. Use the Enhanced Deployment Process
```bash
# Always run the full enhanced deployment
./deploy_kubernetes.sh
```

### 2. Regular System Updates
```bash
# Keep RHEL 10 systems updated
ansible compute_nodes -i ansible/inventory.txt -m shell -a "dnf update -y"
```

### 3. Monitor System Health
```bash
# Regular health checks
ansible compute_nodes -i ansible/inventory.txt -m shell -a "systemctl status kubelet containerd"
```

### 4. Backup Configuration
```bash
# Backup working configurations
ansible compute_nodes -i ansible/inventory.txt -m fetch -a "src=/etc/containerd/config.toml dest=./backups/"
```

## Emergency Recovery

### If Node Fails to Join After Multiple Attempts
```bash
# Complete reset and retry
ssh 192.168.4.62 "kubeadm reset -f"
ssh 192.168.4.62 "systemctl stop kubelet containerd"
ssh 192.168.4.62 "rm -rf /etc/kubernetes /var/lib/kubelet"
ssh 192.168.4.62 "systemctl start containerd"

# Re-run setup
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/rhel10_setup_fixes.yaml
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml
```

### If All Else Fails
```bash
# Check for RHEL 10 specific packages or compatibility issues
ssh 192.168.4.62 "dnf list installed | grep -i container"
ssh 192.168.4.62 "rpm -qa | grep -i kube"

# Consider using alternative container runtime or Kubernetes distribution
# that specifically supports RHEL 10
```

## Success Verification

After successful join, verify with:
```bash
# From control plane
kubectl get nodes -o wide

# Check node status
kubectl describe node 192.168.4.62

# Verify pods can be scheduled
kubectl get pods --all-namespaces -o wide
```

## Support Resources

1. **Debug Logs**: Check `debug_logs/` directory for detailed failure information
2. **Compatibility Checker**: Run `./scripts/check_rhel10_compatibility.sh` before deployment
3. **System Status**: Use enhanced diagnostics in the playbook for real-time status
4. **Community**: Check Kubernetes and RHEL community forums for RHEL 10 specific issues
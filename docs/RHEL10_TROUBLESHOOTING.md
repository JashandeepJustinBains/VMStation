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
The `setup_cluster.yaml` playbook now includes automatic fallback mechanisms for both main CNI installation and worker node CNI installation:
1. **Primary attempt**: Uses Ansible's `get_url` module with `validate_certs: false` and `use_proxy: false`
2. **Automatic fallback**: If urllib3/cert_file errors occur, automatically switches to shell commands using curl or wget
3. **Error detection**: Specifically detects 'cert_file' and 'urllib3' error messages
4. **Verification**: Ensures binaries are downloaded and have correct permissions
5. **Retry logic**: Both methods include retry attempts with delays
6. **Worker node consistency**: Worker nodes now have the same robust fallback mechanisms as control plane nodes

### 3. CNI Plugin Verification Shell Syntax Errors
**Symptoms:**
- Shell script syntax errors during CNI plugin verification
- Error: "Syntax error: '(' unexpected"
- Failed CNI plugin installation check

**Root Cause:**
The CNI plugin verification script uses bash arrays but runs with `/bin/sh` (dash) which doesn't support bash array syntax.

**Solutions:**
```bash
# Check if CNI plugins are properly installed
ls -la /opt/cni/bin/
ls -la /etc/cni/net.d/

# Manual verification if needed
for plugin in bridge host-local loopback flannel; do
  if [ -f "/opt/cni/bin/$plugin" ] && [ -x "/opt/cni/bin/$plugin" ]; then
    echo "✓ $plugin plugin installed and executable"
  else
    echo "✗ $plugin plugin missing or not executable"
  fi
done
```

**Enhanced Fix (Implemented):**
The `setup_cluster.yaml` playbook now explicitly uses bash shell for CNI verification:
1. **Explicit bash shell**: Uses `args: executable: /bin/bash` for array support
2. **POSIX compliance**: Fallback to POSIX-compliant shell commands if needed
3. **Enhanced verification**: More robust plugin checking with detailed output

### 4. Service Unit File Location Issues
**Symptoms:**
- "kubelet.service unit file not found in expected locations"
- "containerd.service unit file not found"
- Service enable failures

**Root Cause:**
Different Linux distributions place systemd service files in different locations, and package managers may install to non-standard paths.

**Solutions:**
```bash
# Search for service unit files manually
find /lib/systemd/system /usr/lib/systemd/system /etc/systemd/system -name "kubelet.service" 2>/dev/null
find /lib/systemd/system /usr/lib/systemd/system /etc/systemd/system -name "containerd.service" 2>/dev/null

# Check if packages are properly installed
rpm -ql kubelet | grep "\.service$"
rpm -ql containerd | grep "\.service$"

# Verify systemd can see the services
systemctl list-unit-files | grep -E "(kubelet|containerd)"
```

**Enhanced Fix (Implemented):**
The `setup_cluster.yaml` playbook now includes comprehensive service file location detection:
1. **Multiple search paths**: Checks `/lib/systemd/system`, `/usr/lib/systemd/system`, and `/etc/systemd/system`
2. **Dynamic search**: Uses `find` command to locate service files in any systemd directory
3. **Detailed error reporting**: Provides specific paths checked and found
4. **Better diagnostics**: Shows exact location where service files are found

### 5. Container Runtime Issues
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

### 6. Systemd Service Configuration Issues
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

# Apply the standard kubelet configuration
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
The `setup_cluster.yaml` playbook now uses a simplified, consistent kubelet configuration:
1. **Standard configuration**: Uses only `/etc/kubernetes/kubelet.conf` (no bootstrap dependency)
2. **Automatic recovery**: Includes fallback mechanisms for various failure scenarios  
3. **Retry logic**: Enhanced error handling and automatic retry attempts


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

## Critical Worker Node Join Failures - Advanced Diagnostics

### Why Joins Still Fail After Basic Fixes

The most common persistent join failures are caused by:

1. **CNI Configuration Missing**: containerd reports "no network config found in /etc/cni/net.d" 
   - The playbook may have failed to install a binary, so per-node CNI files were not created
   - Flannel DaemonSet only populates CNI on nodes after they join (chicken-and-egg problem)
   
2. **kubelet Standalone Mode Conflict**: kubelet running in "standalone mode" blocks kubeadm join
   - systemd started kubelet which listens on port 10250
   - kubeadm join cannot proceed while port is occupied
   
3. **Image Filesystem Issues**: kubelet and containerd report "invalid capacity 0 on image filesystem"
   - containerd's image filesystem (/var/lib/containerd) missing, unmounted or zero capacity
   - PLEG becomes unhealthy, causing node registration failures

### Immediate Read-Only Diagnostic Commands

Run these commands on the failing worker node and paste results for analysis:

#### 1. CNI and Kubernetes Configuration Check
```bash
# Check CNI directory and files
ls -la /etc/cni/net.d/
find /etc/cni -type f -exec ls -la {} \; 2>/dev/null
cat /etc/cni/net.d/* 2>/dev/null || echo "No CNI config files found"

# Check Kubernetes configs
ls -la /etc/kubernetes/ 2>/dev/null || echo "No kubernetes config directory"
ls -la /var/lib/kubelet/ 2>/dev/null || echo "No kubelet data directory"

# Check kubeadm-flags and bootstrap configs
cat /var/lib/kubelet/kubeadm-flags.env 2>/dev/null || echo "No kubeadm-flags.env"
ls -la /etc/kubernetes/bootstrap-kubelet.conf 2>/dev/null || echo "No bootstrap config"
```

#### 2. Image Filesystem and Mounts Check
```bash
# Check containerd image filesystem
df -h /var/lib/containerd
ls -la /var/lib/containerd/
du -sh /var/lib/containerd/* 2>/dev/null

# Check mount points and filesystem capacity
mount | grep -E "(containerd|kubelet|var/lib)"
df -h | grep -E "(Filesystem|/var|tmpfs)"

# Verify filesystem not read-only
touch /var/lib/containerd/test_write 2>/dev/null && rm /var/lib/containerd/test_write && echo "Filesystem writable" || echo "Filesystem read-only or permission issue"
```

#### 3. Container Runtime Interface (CRI) Socket Check
```bash
# Check containerd socket
ls -la /run/containerd/containerd.sock
systemctl status containerd --no-pager -l

# Test CRI connectivity (if crictl available)
which crictl && crictl version 2>/dev/null || echo "crictl not available"
which ctr && ctr version 2>/dev/null || echo "ctr not available"

# Check containerd config for CNI
grep -n cni /etc/containerd/config.toml 2>/dev/null || echo "No CNI config in containerd.toml"
```

#### 4. kubelet Service Status and Port Check
```bash
# Check kubelet service status
systemctl status kubelet --no-pager -l
systemctl is-active kubelet
systemctl is-enabled kubelet

# Check port 10250 usage
netstat -tulpn | grep :10250 || ss -tulpn | grep :10250
lsof -i :10250 2>/dev/null || echo "lsof not available, port check incomplete"

# Check kubelet logs for errors
journalctl -u kubelet --no-pager -l --since="5 minutes ago" | tail -20
```

### Exact Remediation Sequence

When diagnostics confirm the issues above, follow this precise sequence:

#### Phase 1: Stop Services and Clean State
```bash
# Stop kubelet to release port 10250
systemctl stop kubelet
systemctl mask kubelet

# Verify port is released
sleep 2
netstat -tulpn | grep :10250 && echo "ERROR: Port still in use" || echo "OK: Port 10250 released"

# Stop containerd if filesystem issues detected
systemctl stop containerd
sleep 2
```

#### Phase 2: Fix Runtime and Filesystem Issues
```bash
# Fix containerd image filesystem if capacity was 0
if [ ! -d /var/lib/containerd ]; then
    mkdir -p /var/lib/containerd
    chown root:root /var/lib/containerd
    chmod 755 /var/lib/containerd
fi

# Clear any corrupted containerd state (ONLY if capacity was 0)
if [ "$(df -BG /var/lib/containerd | tail -1 | awk '{print $2}' | sed 's/G//')" = "0" ]; then
    echo "WARNING: Containerd filesystem shows 0 capacity, clearing state"
    rm -rf /var/lib/containerd/*
fi

# Start containerd and verify health
systemctl start containerd
sleep 3
systemctl status containerd --no-pager | grep Active

# Test containerd functionality
ctr version >/dev/null 2>&1 && echo "OK: containerd responding" || echo "ERROR: containerd not responding"
```

#### Phase 3: Reset Kubernetes State (Safe)
```bash
# Reset kubeadm state (preserves /mnt/media and other data)
kubeadm reset -f --cert-dir=/etc/kubernetes/pki

# Clean kubernetes directories (avoiding /mnt/media)
rm -rf /etc/kubernetes/*
rm -rf /var/lib/kubelet/*
rm -rf /etc/cni/net.d/*

# Clean temporary kubeadm flags
rm -f /var/lib/kubelet/kubeadm-flags.env
```

#### Phase 4: Prepare for Join
```bash
# Unmask kubelet (but don't start it - let kubeadm handle this)
systemctl unmask kubelet
systemctl daemon-reload

# Verify prerequisites
systemctl status containerd --no-pager | grep "Active: active"
test ! -f /etc/kubernetes/kubelet.conf && echo "OK: No existing kubelet.conf"
test ! -d /etc/cni/net.d/*.conflist && echo "OK: No existing CNI config"
```

#### Phase 5: Execute Join
```bash
# Generate and execute join command (replace with actual values)
# Example: kubeadm join 192.168.4.63:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>

# Add specific flags for the identified issues:
kubeadm join <CONTROL_PLANE_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash <HASH> \
  --ignore-preflight-errors=Port-10250,FileAvailable--etc-kubernetes-pki-ca.crt \
  --v=5

# Monitor join progress
echo "Join initiated. Monitor with: journalctl -u kubelet -f"
```

#### Phase 6: Post-Join Verification
```bash
# Wait for kubelet to stabilize
sleep 30

# Verify node registration (run from control plane)
kubectl get nodes -o wide

# Check CNI configuration was populated by Flannel
ls -la /etc/cni/net.d/
cat /etc/cni/net.d/10-flannel.conflist 2>/dev/null || echo "CNI config still missing"

# Verify kubelet health
systemctl status kubelet --no-pager
journalctl -u kubelet --no-pager -l --since="2 minutes ago" | grep -E "(ERROR|FATAL)" || echo "No critical kubelet errors"
```

### Troubleshooting Notes

- **Never modify `/mnt/media`** - This sequence carefully avoids any interaction with mounted media storage
- **Port 10250 conflicts** - Always mask kubelet before join attempts if it's already running
- **CNI chicken-and-egg** - Flannel DaemonSet can't populate CNI configs until node joins, but join may fail without CNI
- **Filesystem capacity** - containerd image filesystem showing 0 capacity indicates mount or permissions issues
- **PLEG health** - Pod Lifecycle Event Generator becomes unhealthy when containerd filesystem is problematic

## Support Resources

1. **Debug Logs**: Check `debug_logs/` directory for detailed failure information
2. **Compatibility Checker**: Run `./scripts/check_rhel10_compatibility.sh` before deployment
3. **System Status**: Use enhanced diagnostics in the playbook for real-time status
4. **Community**: Check Kubernetes and RHEL community forums for RHEL 10 specific issues
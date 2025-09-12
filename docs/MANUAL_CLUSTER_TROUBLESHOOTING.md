# Enhanced Kubernetes Worker Node Troubleshooting Guide

This guide provides comprehensive troubleshooting steps for worker node join failures, focusing on the enhanced remediation capabilities added to VMStation.

## Quick Diagnostic Commands

Before applying fixes, run these diagnostic commands to identify the root cause:

```bash
# Quick diagnostic scan
sudo ./scripts/quick_join_diagnostics.sh

# Comprehensive diagnostic gathering (for complex issues)
sudo ./scripts/gather_worker_diagnostics.sh
```

## Common Issues and Solutions

### 1. crictl ↔ containerd Communication Failures

**Symptoms:**
- crictl commands fail with "connection refused" or socket permission errors
- Error: `connect: permission denied` when running crictl
- Warning: `runtime connect using default endpoints`

**Root Causes:**
- Missing or incorrect `/etc/crictl.yaml` configuration
- Incorrect containerd socket permissions
- Missing containerd group or user not in containerd group

**Enhanced Fix (Automatic):**
The Ansible playbook now automatically handles crictl configuration and socket permissions during cluster setup.

**Manual Fix:**
```bash
# 1. Create/fix crictl configuration
sudo mkdir -p /etc
sudo cat > /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# 2. Fix containerd socket permissions
sudo groupadd containerd 2>/dev/null || true
sudo usermod -a -G containerd root
sudo chgrp containerd /run/containerd/containerd.sock
sudo chmod 660 /run/containerd/containerd.sock

# 3. Test crictl communication
sudo crictl version
sudo crictl info
```

**Verification:**
```bash
# Should return version information without errors
sudo crictl version

# Should show imageFilesystem with non-zero capacity
sudo crictl info | grep -A5 imageFilesystem
```

### 2. Missing kubelet config.yaml After Join Attempts

**Symptoms:**
- kubelet service fails to start with: `failed to load Kubelet config file /var/lib/kubelet/config.yaml: no such file or directory`
- kubeadm join appears to succeed but kubelet remains in failed state
- Node does not appear in `kubectl get nodes` on control plane

**Root Causes:**
- kubeadm join failed to complete the TLS Bootstrap process
- Join token expired during the join process
- containerd filesystem capacity issues preventing kubelet startup
- Network connectivity issues during certificate exchange

**Enhanced Fix (Automatic Token Refresh):**
```bash
# The enhanced join script now automatically handles token refresh
export MASTER_IP="192.168.4.63"  # Your control plane IP
export TOKEN_REFRESH_RETRIES=2
sudo ./scripts/enhanced_kubeadm_join.sh "<your-original-join-command>"
```

**Manual Fix (Generate Fresh Token):**
```bash
# 1. On control plane, generate fresh join token
kubeadm token create --ttl=2h --print-join-command

# 2. On worker node, use the new join command with enhanced script
sudo ./scripts/enhanced_kubeadm_join.sh "<new-join-command>"
```

**Pre-Join Validation:**
The system now automatically validates kubelet configuration before attempting join:
- Checks if kubelet config already exists and is valid
- Validates that kubelet.conf points to correct control plane
- Skips join if kubelet is already properly connected to cluster

### 3. containerd "invalid capacity 0 on image filesystem" Error

**Symptoms:**
- kubelet logs show: `"invalid capacity 0 on image filesystem"`
- TLS Bootstrap fails with filesystem-related errors
- crictl commands work but kubelet cannot start

**Root Causes:**
- containerd image filesystem not properly initialized
- Filesystem capacity detection issues after containerd restart
- Corrupted containerd metadata

**Enhanced Fix (Automatic Detection and Repair):**
The enhanced join script now automatically detects and fixes this issue during join:

```bash
# Manual fix for stubborn cases
sudo ./scripts/manual_containerd_filesystem_fix.sh
```

**Manual Fix Steps:**
```bash
# 1. Stop containerd and kubelet
sudo systemctl stop kubelet containerd

# 2. Clear containerd state
sudo rm -rf /var/lib/containerd/io.containerd.*

# 3. Restart containerd and initialize filesystem
sudo systemctl start containerd
sleep 10

# 4. Initialize image filesystem
sudo ctr namespace create k8s.io
sudo ctr --namespace k8s.io images ls
sudo crictl info

# 5. Verify filesystem shows capacity
sudo crictl info | grep -A10 imageFilesystem
```

### 4. Token Expiry During Join Process

**Symptoms:**
- Join fails with authentication errors: `401 Unauthorized` or `403 Forbidden`
- Error messages about invalid or expired tokens
- TLS Bootstrap timeouts

**Enhanced Solution:**
The enhanced join script now automatically detects token expiry and refreshes tokens:

**Automatic Handling:**
- Script detects token expiry patterns in join output
- Automatically connects to control plane via SSH
- Generates fresh join token with 2-hour TTL
- Retries join with new token

**Manual Token Refresh:**
```bash
# On control plane
kubeadm token list  # Check existing tokens
kubeadm token create --ttl=2h --print-join-command

# On worker
sudo ./scripts/enhanced_kubeadm_join.sh "<new-join-command>"
```

## Enhanced Ansible Integration

### Automatic Pre-Join Validation

The Ansible playbook now includes comprehensive pre-join validation:

```yaml
- name: "Pre-join kubelet config validation and remediation"
  # Automatically checks and fixes kubelet configuration issues
  # Skips join if kubelet already properly connected
  # Backs up and resets invalid configurations
```

### Improved Error Reporting

Join failures now provide comprehensive diagnostic information:
- Complete join log contents
- Recent kubelet and containerd logs
- Configuration file contents
- Socket permission status
- Specific remediation steps

### Enhanced Failure Recovery

The playbook now includes:
- Automatic backup of invalid configurations
- Comprehensive cleanup on join failures
- Detailed failure diagnostics collection
- Specific remediation guidance

## Diagnostic Tools

### Quick Diagnostics
```bash
# Fast diagnostic scan
sudo ./scripts/quick_join_diagnostics.sh [CONTROL_PLANE_IP]
```

### Comprehensive Diagnostics
```bash
# Gather all diagnostic information
sudo ./scripts/gather_worker_diagnostics.sh [CONTROL_PLANE_IP] [WORKER_IPS] [OUTPUT_DIR]

# Example
sudo ./scripts/gather_worker_diagnostics.sh 192.168.4.63 "192.168.4.61,192.168.4.62"
```

This creates a comprehensive diagnostic package including:
- Service status and logs from all nodes
- Configuration files
- Network and runtime status
- Join attempt logs
- Summary report with analysis guidance

### Enhanced Join Process
```bash
# Use enhanced join with automatic error recovery
sudo ./scripts/enhanced_kubeadm_join.sh "<join-command>"
```

Features:
- Automatic crictl configuration and socket permission fixes
- containerd filesystem issue detection and repair
- Token expiry detection and automatic refresh
- Comprehensive retry logic with cleanup between attempts
- Post-wipe worker state detection
- Enhanced monitoring and validation

## Troubleshooting Workflow

1. **Quick Assessment:**
   ```bash
   sudo ./scripts/quick_join_diagnostics.sh
   ```

2. **Apply Automatic Fixes:**
   ```bash
   sudo ./scripts/enhanced_kubeadm_join.sh "<join-command>"
   ```

3. **For Persistent Issues:**
   ```bash
   sudo ./scripts/gather_worker_diagnostics.sh
   # Review the generated DIAGNOSTIC_SUMMARY.txt
   ```

4. **Manual Intervention (if needed):**
   - Check specific log files mentioned in diagnostics
   - Apply targeted fixes based on root cause
   - Use manual scripts for specific issues

## Prevention

To prevent these issues in future deployments:

1. **Use Enhanced Ansible Playbook:**
   - Includes automatic crictl configuration
   - Handles socket permissions properly
   - Validates configurations before join

2. **Monitor containerd Health:**
   - Verify crictl communication after containerd restarts
   - Check filesystem capacity regularly

3. **Token Management:**
   - Use longer TTL tokens for complex deployments
   - Implement automatic token refresh for retry scenarios

## Related Documentation

- [Enhanced Join Process Details](./ENHANCED_JOIN_PROCESS.md)
- [Post-Wipe Worker Join Process](./POST_WIPE_WORKER_JOIN.md)
- [containerd Timeout Fix Guide](./containerd-timeout-fix.md)

## Legacy Issues (Now Fixed)

### 1. crictl Connection Failures

**Symptoms:**
```bash
$ sudo crictl ps -a
WARN[0000] runtime connect using default endpoints: [unix:///var/run/dockershim.sock unix:///run/containerd/containerd.sock unix:///run/crio/crio.sock unix:///var/run/cri-dockerd.sock]. As the default settings are now deprecated, you should set the endpoint instead.
ERRO[0000] validate service connection: validate CRI v1 runtime API for endpoint "unix:///var/run/dockershim.sock": rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial unix /var/run/dockershim.sock: connect: no such file or directory"
```

**Root Cause:** 
crictl is trying to use deprecated dockershim endpoints instead of the proper containerd endpoint.

**Fix:**
```bash
sudo ./scripts/fix_manual_cluster_setup.sh
```

### 2. Kubelet in Standalone Mode

**Symptoms:**
```bash
$ sudo journalctl -u kubelet -xe
Sep 09 14:37:19 masternode kubelet[3098388]: I0909 14:37:19.274583 3098388 server.go:655] "Standalone mode, no API client"
Sep 09 14:37:19 masternode kubelet[3098388]: I0909 14:37:19.281165 3098388 server.go:543] "No api server defined - no events will be sent to API server"
```

**Root Cause:**
kubelet is not properly configured to connect to the Kubernetes API server, often due to failed or incomplete kubeadm join process.

**Enhanced Fix (Recommended):**
```bash
# Use the enhanced join process for comprehensive resolution
sudo ./scripts/enhanced_kubeadm_join.sh <join-command>
```

**Legacy Fix (if enhanced process unavailable):**
```bash
sudo ./scripts/fix_kubelet_cluster_connection.sh
```

**For complete resolution, see:** [Enhanced Join Process Documentation](./ENHANCED_JOIN_PROCESS.md)

### 3. Container Runtime Issues

**Symptoms:**
```bash
ERRO[0000] validate service connection: validate CRI v1 image API for endpoint "unix:///var/run/dockershim.sock": rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial unix /var/run/dockershim.sock: connect: no such file or directory"
```

**Root Cause:**
containerd service is not running or properly configured.

**Fix:**
```bash
sudo ./scripts/fix_manual_cluster_setup.sh
```

## Automated Deployment

For automated deployment without manual intervention:

```bash
# Deploy complete cluster
./deploy.sh cluster

# Deploy only applications (requires existing cluster)
./deploy.sh apps

# Check deployment status
./deploy.sh check
```

## Manual Troubleshooting Steps

### Step 1: Verify Container Runtime
```bash
# Check containerd service
sudo systemctl status containerd

# If not running, start it
sudo systemctl enable containerd
sudo systemctl start containerd

# Test container runtime
sudo crictl version
```

### Step 2: Configure crictl
```bash
# Create crictl configuration
sudo tee /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# Test crictl
sudo crictl ps -a
```

### Step 3: Check Kubelet Configuration
```bash
# Check if node is joined to cluster
ls -la /etc/kubernetes/kubelet.conf

# Check kubelet service
sudo systemctl status kubelet

# View recent kubelet logs
sudo journalctl -u kubelet -f
```

### Step 4: Node Join Status

**Master Node:**
- Should have `/etc/kubernetes/admin.conf`
- Should be able to run `kubectl get nodes`

**Worker Node:**
- Should have `/etc/kubernetes/kubelet.conf` after joining
- Should show in `kubectl get nodes` from master

## Detailed Diagnostics

### Container Runtime Diagnostics
```bash
# Check containerd socket
ls -la /var/run/containerd/containerd.sock

# Test containerd directly
sudo ctr version

# Check containerd configuration
sudo cat /etc/containerd/config.toml | head -20
```

### Kubelet Diagnostics
```bash
# Check kubelet systemd configuration
sudo cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Check kubelet cluster configuration (if joined)
sudo cat /etc/kubernetes/kubelet.conf | head -10

# Check kubelet logs for errors
sudo journalctl -u kubelet --no-pager -n 50 | grep -E "(ERROR|WARN|Failed)"
```

### Network Connectivity (Worker to Master)
```bash
# Test connectivity to master API server
curl -k https://192.168.4.63:6443/healthz

# Check if firewall is blocking
sudo firewall-cmd --list-all

# Test DNS resolution
nslookup kubernetes.default.svc.cluster.local
```

## Fix Scripts Usage

### General Manual Setup Issues
```bash
# Run comprehensive manual setup fix
sudo ./scripts/fix_manual_cluster_setup.sh

# This script:
# - Configures crictl for containerd
# - Verifies and starts containerd service
# - Checks kubelet configuration
# - Provides diagnostic information
```

### Kubelet Standalone Mode Issues
```bash
# Run kubelet cluster connection fix
sudo ./scripts/fix_kubelet_cluster_connection.sh

# This script:
# - Detects standalone vs cluster mode
# - Fixes kubelet systemd configuration
# - Handles pre-join vs post-join scenarios
# - Provides cluster join guidance
```

## Prevention

### Use Enhanced Deployment
The VMStation deployment system includes RHEL 10+ compatibility fixes:

```bash
# Run RHEL 10 specific pre-setup (if needed)
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/rhel10_setup_fixes.yaml

# Then run normal cluster setup
./deploy.sh cluster
```

### Regular Health Checks
```bash
# Validate cluster health
./scripts/validate_k8s_monitoring.sh

# Check node status
kubectl get nodes -o wide

# Check system services
sudo systemctl status kubelet containerd
```

## Expected Results After Fixes

### Working crictl:
```bash
$ sudo crictl ps -a
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID              POD
<containers listed without warnings>
```

### Working kubelet (cluster mode):
```bash
$ sudo journalctl -u kubelet -n 5
Sep 09 15:00:00 node kubelet[12345]: I0909 15:00:00.123456 12345 kubelet.go:xxx] "Successfully registered node"
Sep 09 15:00:00 node kubelet[12345]: I0909 15:00:00.123456 12345 kubelet.go:xxx] "Node ready"
```

### Working cluster connection:
```bash
$ kubectl get nodes
NAME         STATUS   ROLES           AGE   VERSION
masternode   Ready    control-plane   1h    v1.29.15
workernode   Ready    <none>          1h    v1.29.15
```

## Support

If issues persist after running the fix scripts:

1. Check the [RHEL 10 Troubleshooting Guide](RHEL10_TROUBLESHOOTING.md) for OS-specific issues
2. Verify network connectivity between nodes
3. Ensure all required ports are open in firewall
4. Check system resources (disk space, memory)
5. Review the full deployment logs for additional context

For automated deployment, prefer using `./deploy.sh cluster` which includes all necessary fixes and configurations.
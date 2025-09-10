#!/bin/bash

# Worker Node Join Diagnostics Script - Enhanced
# Provides immediate read-only checks for troubleshooting join failures
# Updated to work with enhanced join retry logic

echo "=== Worker Node Join Diagnostics Script (Enhanced) ==="
echo "Timestamp: $(date)"
echo "Hostname: $(hostname)"
echo "IP Address: $(hostname -I | awk '{print $1}')"
echo ""

echo "This script provides safe, read-only diagnostic commands to identify:"
echo "  1. CNI configuration issues (no network config found in /etc/cni/net.d)"
echo "  2. kubelet standalone mode conflicts (port 10250 in use)"  
echo "  3. containerd image filesystem capacity issues (invalid capacity 0)"
echo "  4. PLEG health problems affecting node registration"
echo "  5. Network connectivity issues to control plane"
echo "  6. Certificate and token validation problems"
echo ""

# Function to run command safely and capture output
run_check() {
    local description="$1"
    local command="$2"
    
    echo "=== $description ==="
    echo "Command: $command"
    echo "Output:"
    eval "$command" 2>&1 || echo "Command failed or returned non-zero exit code"
    echo ""
}

# 1. Network Connectivity Checks (NEW)
echo "### 1. NETWORK CONNECTIVITY CHECKS ###"
echo ""

# Check if control plane IP is provided as argument
CONTROL_PLANE_IP="${1:-}"
if [ -n "$CONTROL_PLANE_IP" ]; then
    run_check "Control Plane API Server Connectivity" "timeout 10 nc -z -w 5 $CONTROL_PLANE_IP 6443 && echo 'API server reachable' || echo 'API server NOT reachable'"
    run_check "Control Plane DNS Resolution" "nslookup $CONTROL_PLANE_IP || echo 'DNS resolution failed'"
    run_check "Control Plane ICMP Ping" "ping -c 3 -W 3 $CONTROL_PLANE_IP || echo 'ICMP ping failed'"
else
    echo "No control plane IP provided. Use: $0 <control-plane-ip> for connectivity tests"
    echo ""
fi

run_check "Default Route" "ip route show default"
run_check "Network Interfaces" "ip addr show | grep -E '^[0-9]+:|inet '"

# 2. Join Output Analysis (NEW)
echo "### 2. JOIN OUTPUT ANALYSIS ###"
echo ""

run_check "Previous Join Attempts Log" "[ -f /tmp/join-output.log ] && echo 'Found join output:' && tail -20 /tmp/join-output.log || echo 'No previous join output found'"
run_check "Previous Join Errors" "[ -f /tmp/join-output.log ] && echo 'Join errors found:' && grep -E '(error|ERROR|failed|FAILED|timeout|TIMEOUT)' /tmp/join-output.log | tail -10 || echo 'No join errors logged'"
run_check "Previous Reset Output" "[ -f /tmp/reset-output.log ] && echo 'Found reset output:' && tail -10 /tmp/reset-output.log || echo 'No previous reset output found'"

# 3. CNI and Kubernetes Configuration Checks
echo "### 3. CNI AND KUBERNETES CONFIGURATION CHECKS ###"
echo ""

run_check "CNI Directory Structure" "ls -la /etc/cni/net.d/ 2>/dev/null || echo 'CNI directory does not exist'"

run_check "CNI Configuration Files Content" "find /etc/cni -type f -exec echo 'File: {}' \; -exec cat {} \; 2>/dev/null || echo 'No CNI configuration files found'"

run_check "CNI Binary Directory" "ls -la /opt/cni/bin/ 2>/dev/null || echo 'CNI binary directory missing'"

run_check "Kubernetes Configuration Directory" "ls -la /etc/kubernetes/ 2>/dev/null || echo 'Kubernetes config directory missing'"

run_check "Kubelet Data Directory" "ls -la /var/lib/kubelet/ 2>/dev/null || echo 'Kubelet data directory missing'" 

run_check "kubeadm Flags Environment" "cat /var/lib/kubelet/kubeadm-flags.env 2>/dev/null || echo 'kubeadm-flags.env not found'"

run_check "Bootstrap Kubelet Configuration" "ls -la /etc/kubernetes/bootstrap-kubelet.conf 2>/dev/null || echo 'Bootstrap kubelet config not found'"

run_check "Kubelet Configuration" "ls -la /etc/kubernetes/kubelet.conf 2>/dev/null || echo 'Kubelet config not found (expected if not joined)'"

# 4. Image Filesystem and Mount Checks  
echo "### 4. IMAGE FILESYSTEM AND MOUNT CHECKS ###"
echo ""

run_check "Containerd Filesystem Capacity" "df -h /var/lib/containerd 2>/dev/null || echo 'Cannot check containerd filesystem'"

run_check "Containerd Directory Contents" "ls -la /var/lib/containerd/ 2>/dev/null || echo 'Containerd directory missing'"

run_check "Containerd Subdirectory Sizes" "du -sh /var/lib/containerd/* 2>/dev/null || echo 'Cannot determine containerd directory sizes'"

run_check "Relevant Mount Points" "mount | grep -E '(containerd|kubelet|var/lib)' || echo 'No relevant mount points found'"

run_check "Filesystem Capacity Overview" "df -h | grep -E '(Filesystem|/var|tmpfs)'"

run_check "Containerd Filesystem Write Test" "touch /var/lib/containerd/diagnostic_test 2>/dev/null && rm -f /var/lib/containerd/diagnostic_test && echo 'Filesystem is writable' || echo 'Filesystem is read-only or has permission issues'"

# 5. Container Runtime Interface (CRI) Checks
echo "### 5. CONTAINER RUNTIME INTERFACE (CRI) CHECKS ###"  
echo ""

run_check "Containerd Socket Status" "ls -la /run/containerd/containerd.sock 2>/dev/null || echo 'Containerd socket missing'"

run_check "Containerd Service Status" "systemctl status containerd --no-pager -l 2>/dev/null || echo 'Cannot check containerd service status'"

run_check "Containerd Health Check" "timeout 10 ctr version 2>/dev/null && echo 'Containerd is responding' || echo 'Containerd not responding or timed out'"

run_check "CRI Tool Version Check" "which crictl >/dev/null 2>&1 && crictl version 2>/dev/null || echo 'crictl not available or not working'"

run_check "Container Tool Version Check" "which ctr >/dev/null 2>&1 && ctr version 2>/dev/null || echo 'ctr not available or not working'"

run_check "Containerd CNI Configuration" "grep -n cni /etc/containerd/config.toml 2>/dev/null || echo 'No CNI configuration found in containerd.toml'"

# 6. kubelet Service and Port Status
echo "### 6. KUBELET SERVICE AND PORT STATUS ###"
echo ""

run_check "kubelet Service Status" "systemctl status kubelet --no-pager -l 2>/dev/null || echo 'Cannot check kubelet service status'"

run_check "kubelet Active State" "systemctl is-active kubelet 2>/dev/null || echo 'kubelet service state unknown'"

run_check "kubelet Enabled State" "systemctl is-enabled kubelet 2>/dev/null || echo 'kubelet service enabled state unknown'"

run_check "Port 10250 Usage (ss)" "ss -tulpn 2>/dev/null | grep :10250 || echo 'Port 10250 not in use (ss)'"

run_check "Port 10250 Usage (netstat)" "netstat -tulpn 2>/dev/null | grep :10250 || echo 'Port 10250 not in use (netstat)'"

run_check "Port 10250 Process Info" "lsof -i :10250 2>/dev/null || echo 'lsof not available or port 10250 not in use'"

run_check "Recent kubelet Logs" "journalctl -u kubelet --no-pager -l --since='10 minutes ago' 2>/dev/null | tail -30 || echo 'Cannot retrieve kubelet logs'"

# 7. System Resource Checks (ENHANCED)
echo "### 7. SYSTEM RESOURCE AND HEALTH CHECKS ###"
echo ""

run_check "System Load and Memory" "uptime && free -h"

run_check "CPU Information" "lscpu | grep -E '(CPU|MHz|Architecture)' | head -5"

run_check "Disk Space Overview" "df -h | head -10"

run_check "Network Interface Status" "ip addr show | grep -E '^[0-9]+:|inet ' | head -10"

run_check "Systemd Failed Services" "systemctl list-units --failed --no-pager || echo 'No failed systemd services found'"

run_check "Process Count" "ps aux | wc -l && echo 'Total processes running'"

run_check "Memory Pressure Check" "free | awk 'NR==2{printf \"Memory Usage: %.2f%%\n\", $3*100/$2}'"

# 8. Certificate and Token Analysis (NEW)
echo "### 8. CERTIFICATE AND TOKEN ANALYSIS ###"
echo ""

run_check "Join Command Availability" "[ -f /tmp/kubeadm-join.sh ] && echo 'Join command found:' && cat /tmp/kubeadm-join.sh || echo 'No join command file found'"

run_check "Kubernetes CA Certificate" "[ -f /etc/kubernetes/pki/ca.crt ] && echo 'CA certificate exists' && openssl x509 -in /etc/kubernetes/pki/ca.crt -text -noout | grep -A2 'Validity' || echo 'CA certificate not found or invalid'"

run_check "System Clock" "date && echo 'System timezone:' && timedatectl status | grep 'Time zone' || echo 'timedatectl not available'"

echo "=== ENHANCED DIAGNOSTIC SUMMARY ==="
echo ""
echo "Review the output above for common issues:"
echo "  ❌ NETWORK: API server unreachable, DNS resolution failed, routing issues"
echo "  ❌ CNI: Missing /etc/cni/net.d/ directory or configurations"
echo "  ❌ PORTS: Port 10250 conflicts from existing kubelet instances"  
echo "  ❌ STORAGE: Containerd filesystem capacity 0, read-only filesystems"
echo "  ❌ RUNTIME: Containerd not responding, missing socket"
echo "  ❌ SERVICES: Failed systemd services, kubelet issues"
echo "  ❌ RESOURCES: High memory usage, insufficient CPU/memory"
echo "  ❌ CERTIFICATES: Missing CA certificates, clock skew issues"
echo ""
echo "NEXT STEPS:"
if [ -n "$CONTROL_PLANE_IP" ]; then
    echo "  1. If network issues found, check firewall and routing"
    echo "  2. If ready for join, run: worker_node_join_remediation.sh"
    echo "  3. Then run the enhanced deploy.sh which includes improved retry logic"
else
    echo "  1. Re-run with control plane IP: $0 <control-plane-ip>"
    echo "  2. Address any issues found above"
    echo "  3. Run worker_node_join_remediation.sh if needed"
fi
echo ""
echo "The enhanced join logic now includes:"
echo "  ✓ Better connectivity testing"
echo "  ✓ Longer timeouts (15 minutes vs 10 minutes)" 
echo "  ✓ More retry attempts (5 vs 3)"
echo "  ✓ Comprehensive cleanup between retries"
echo "  ✓ Enhanced error diagnostics"
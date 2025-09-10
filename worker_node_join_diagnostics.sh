#!/bin/bash

# Worker Node Join Diagnostics Script
# Provides immediate read-only checks for troubleshooting join failures
# Based on problem statement requirements for quick diagnosis

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "=== Worker Node Join Diagnostics Script ==="
echo "Timestamp: $(date)"
echo "Hostname: $(hostname)"
echo "IP Address: $(hostname -I | awk '{print $1}')"
echo ""

# Validate execution context
log_warn "IMPORTANT: This script should be run on the WORKER NODE having join issues"
log_warn "Running on the control plane provides limited diagnostic value for worker problems"
echo ""

# Check if this appears to be a control plane node
if kubectl get nodes >/dev/null 2>&1; then
    log_error "WARNING: kubectl is accessible - this appears to be a CONTROL PLANE node"
    log_error "For worker node join issues, run this script on the WORKER NODE instead"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Script cancelled. Please run on the worker node having join issues."
        exit 0
    fi
fi

echo ""
echo "This script provides safe, read-only diagnostic commands to identify:"
echo "  1. CNI configuration issues (no network config found in /etc/cni/net.d)"
echo "  2. kubelet standalone mode conflicts (port 10250 in use)"  
echo "  3. containerd image filesystem capacity issues (invalid capacity 0)"
echo "  4. PLEG health problems affecting node registration"
echo "  5. Network connectivity and system health issues"
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

# 1. CNI and Kubernetes Configuration Checks
echo "### 1. CNI AND KUBERNETES CONFIGURATION CHECKS ###"
echo ""

run_check "CNI Directory Structure" "ls -la /etc/cni/net.d/ 2>/dev/null || echo 'CNI directory does not exist'"

run_check "CNI Configuration Files Content" "find /etc/cni -type f -exec echo 'File: {}' \; -exec cat {} \; 2>/dev/null || echo 'No CNI configuration files found'"

run_check "CNI Binary Directory" "ls -la /opt/cni/bin/ 2>/dev/null || echo 'CNI binary directory missing'"

run_check "Kubernetes Configuration Directory" "ls -la /etc/kubernetes/ 2>/dev/null || echo 'Kubernetes config directory missing'"

run_check "Kubelet Data Directory" "ls -la /var/lib/kubelet/ 2>/dev/null || echo 'Kubelet data directory missing'" 

run_check "kubeadm Flags Environment" "cat /var/lib/kubelet/kubeadm-flags.env 2>/dev/null || echo 'kubeadm-flags.env not found'"

run_check "Bootstrap Kubelet Configuration" "ls -la /etc/kubernetes/bootstrap-kubelet.conf 2>/dev/null || echo 'Bootstrap kubelet config not found'"

# 2. Image Filesystem and Mount Checks  
echo "### 2. IMAGE FILESYSTEM AND MOUNT CHECKS ###"
echo ""

run_check "Containerd Filesystem Capacity" "df -h /var/lib/containerd 2>/dev/null || echo 'Cannot check containerd filesystem'"

run_check "Containerd Directory Contents" "ls -la /var/lib/containerd/ 2>/dev/null || echo 'Containerd directory missing'"

run_check "Containerd Subdirectory Sizes" "du -sh /var/lib/containerd/* 2>/dev/null || echo 'Cannot determine containerd directory sizes'"

run_check "Relevant Mount Points" "mount | grep -E '(containerd|kubelet|var/lib)' || echo 'No relevant mount points found'"

run_check "Filesystem Capacity Overview" "df -h | grep -E '(Filesystem|/var|tmpfs)'"

run_check "Containerd Filesystem Write Test" "touch /var/lib/containerd/diagnostic_test 2>/dev/null && rm -f /var/lib/containerd/diagnostic_test && echo 'Filesystem is writable' || echo 'Filesystem is read-only or has permission issues'"

# 3. Container Runtime Interface (CRI) Checks
echo "### 3. CONTAINER RUNTIME INTERFACE (CRI) CHECKS ###"  
echo ""

run_check "Containerd Socket Status" "ls -la /run/containerd/containerd.sock 2>/dev/null || echo 'Containerd socket missing'"

run_check "Containerd Service Status" "systemctl status containerd --no-pager -l 2>/dev/null || echo 'Cannot check containerd service status'"

run_check "CRI Tool Version Check" "which crictl >/dev/null 2>&1 && crictl version 2>/dev/null || echo 'crictl not available or not working'"

run_check "Container Tool Version Check" "which ctr >/dev/null 2>&1 && ctr version 2>/dev/null || echo 'ctr not available or not working'"

run_check "Containerd CNI Configuration" "grep -n cni /etc/containerd/config.toml 2>/dev/null || echo 'No CNI configuration found in containerd.toml'"

# 4. kubelet Service and Port Status
echo "### 4. KUBELET SERVICE AND PORT STATUS ###"
echo ""

run_check "kubelet Service Status" "systemctl status kubelet --no-pager -l 2>/dev/null || echo 'Cannot check kubelet service status'"

run_check "kubelet Active State" "systemctl is-active kubelet 2>/dev/null || echo 'kubelet service state unknown'"

run_check "kubelet Enabled State" "systemctl is-enabled kubelet 2>/dev/null || echo 'kubelet service enabled state unknown'"

run_check "Port 10250 Usage (netstat)" "netstat -tulpn 2>/dev/null | grep :10250 || echo 'Port 10250 not in use (netstat)'"

run_check "Port 10250 Usage (ss)" "ss -tulpn 2>/dev/null | grep :10250 || echo 'Port 10250 not in use (ss)'"

run_check "Port 10250 Process Info" "lsof -i :10250 2>/dev/null || echo 'lsof not available or port 10250 not in use'"

run_check "Recent kubelet Logs" "journalctl -u kubelet --no-pager -l --since='5 minutes ago' 2>/dev/null | tail -20 || echo 'Cannot retrieve kubelet logs'"

# 5. Additional System Health Checks
echo "### 5. ADDITIONAL SYSTEM HEALTH CHECKS ###"
echo ""

run_check "System Load and Memory" "uptime && free -h"

run_check "Disk Space Overview" "df -h | head -10"

run_check "Network Interface Status" "ip addr show | grep -E '^[0-9]+:|inet ' | head -10"

run_check "Systemd Failed Services" "systemctl list-units --failed --no-pager || echo 'No failed systemd services found'"

echo "=== DIAGNOSTIC SUMMARY ==="
echo ""
echo "Review the output above for:"
echo "  ❌ CNI configuration missing: Look for 'CNI directory does not exist' or empty /etc/cni/net.d/"
echo "  ❌ Port 10250 conflicts: Look for kubelet or other processes using port 10250"  
echo "  ❌ Filesystem capacity 0: Look for 0G, 0B, or 'No space' in containerd filesystem checks"
echo "  ❌ Containerd socket issues: Look for missing /run/containerd/containerd.sock"
echo "  ❌ Service health problems: Look for failed/inactive states in systemctl status"
echo ""
echo "=== NEXT STEPS ==="
echo ""
log_info "Based on diagnostic results, choose appropriate action:"
echo ""
echo "1. IF ISSUES FOUND: Address specific problems before attempting join"
echo "   - Fix CNI configuration issues"
echo "   - Resolve port conflicts"
echo "   - Fix containerd problems"
echo "   - Address network connectivity issues"
echo ""
echo "2. IF SYSTEM APPEARS HEALTHY: Proceed with join attempt"
echo "   - Get fresh join command: kubeadm token create --print-join-command"
echo "   - Run join with verbose logging: kubeadm join ... --v=5"
echo "   - Monitor logs: journalctl -u kubelet -f"
echo ""
echo "3. IF JOIN FAILS: Capture and analyze logs"
echo "   - Save join command output"
echo "   - Save kubelet logs during join attempt"
echo "   - Use analyze_worker_join_logs.sh for detailed analysis"
echo ""
echo "4. FOR PERSISTENT ISSUES: Run remediation"
echo "   - Use worker_node_join_remediation.sh for complete cleanup"
echo "   - Re-run diagnostics after remediation"
echo ""
log_warn "REMEMBER: Always run diagnostics on the actual WORKER NODE having problems"
log_info "For comprehensive analysis, use enhanced_worker_join_troubleshooter.sh"
echo ""
echo "Copy the relevant sections above and provide them for analysis."
echo "This diagnostic information will help determine the exact remediation steps needed."
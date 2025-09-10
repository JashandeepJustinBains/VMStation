#!/bin/bash

# Enhanced Worker Node Join Troubleshooter
# Comprehensive diagnostic and analysis script for worker node join issues
# This script should be run on the WORKER NODE that is having join problems

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_section() {
    echo -e "\n${MAGENTA}=== $1 ===${NC}"
}

log_subsection() {
    echo -e "\n${CYAN}--- $1 ---${NC}"
}

# Function to run command safely and capture output
run_diagnostic() {
    local description="$1"
    local command="$2"
    
    echo ""
    log_subsection "$description"
    echo "Command: $command"
    echo "Output:"
    
    if eval "$command" 2>&1; then
        echo "Exit Code: 0 (Success)"
    else
        local exit_code=$?
        echo "Exit Code: $exit_code (Failed)"
    fi
    echo ""
}

# Detect node type and validate execution context
detect_node_type() {
    log_section "NODE TYPE DETECTION AND VALIDATION"
    
    local hostname=$(hostname)
    local ip=$(hostname -I | awk '{print $1}')
    
    log_info "Hostname: $hostname"
    log_info "Primary IP: $ip"
    
    # Check if this appears to be a control plane node
    if kubectl get nodes >/dev/null 2>&1; then
        log_warn "kubectl is accessible - this appears to be a control plane node"
        log_warn "This script should typically be run on the WORKER NODE having join issues"
        echo ""
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Script cancelled by user"
            exit 0
        fi
    else
        log_success "No direct kubectl access - this appears to be a worker node (expected)"
    fi
    
    # Check if kubeadm is available
    if command -v kubeadm >/dev/null 2>&1; then
        log_success "kubeadm is available"
    else
        log_error "kubeadm not found - Kubernetes tools may not be installed"
    fi
}

# Enhanced CNI and Kubernetes diagnostics
enhanced_cni_diagnostics() {
    log_section "ENHANCED CNI AND KUBERNETES DIAGNOSTICS"
    
    run_diagnostic "CNI Directory Structure" "ls -la /etc/cni/net.d/ 2>/dev/null || echo 'CNI directory does not exist'"
    
    run_diagnostic "CNI Configuration Files Content" "find /etc/cni -type f -exec echo 'File: {}' \\; -exec cat {} \\; 2>/dev/null || echo 'No CNI configuration files found'"
    
    run_diagnostic "CNI Binary Directory" "ls -la /opt/cni/bin/ 2>/dev/null || echo 'CNI binary directory missing'"
    
    run_diagnostic "Kubernetes Configuration Directory" "ls -la /etc/kubernetes/ 2>/dev/null || echo 'Kubernetes config directory missing'"
    
    run_diagnostic "Kubelet Data Directory" "ls -la /var/lib/kubelet/ 2>/dev/null || echo 'Kubelet data directory missing'"
    
    # Check for previous join attempts
    run_diagnostic "Previous Join Artifacts" "find /etc/kubernetes /var/lib/kubelet -name '*bootstrap*' -o -name '*join*' 2>/dev/null || echo 'No previous join artifacts found'"
    
    # Check kubeadm flags
    run_diagnostic "kubeadm Flags Environment" "cat /var/lib/kubelet/kubeadm-flags.env 2>/dev/null || echo 'kubeadm-flags.env not found'"
}

# Enhanced container runtime diagnostics
enhanced_runtime_diagnostics() {
    log_section "ENHANCED CONTAINER RUNTIME DIAGNOSTICS"
    
    run_diagnostic "Containerd Service Status" "systemctl status containerd --no-pager -l"
    
    run_diagnostic "Containerd Socket Status" "ls -la /run/containerd/containerd.sock 2>/dev/null || echo 'Containerd socket missing'"
    
    run_diagnostic "Containerd Filesystem Capacity" "df -h /var/lib/containerd 2>/dev/null || echo 'Cannot check containerd filesystem'"
    
    run_diagnostic "Containerd Directory Structure" "find /var/lib/containerd -maxdepth 2 -type d 2>/dev/null | head -20 || echo 'Cannot access containerd directory'"
    
    run_diagnostic "Containerd Configuration" "grep -n cni /etc/containerd/config.toml 2>/dev/null || echo 'No CNI configuration found in containerd.toml'"
    
    # Test containerd functionality
    run_diagnostic "Containerd API Test" "ctr version 2>/dev/null || echo 'Containerd API not accessible'"
    
    run_diagnostic "Containerd Image List" "ctr images list 2>/dev/null | head -10 || echo 'Cannot list containerd images'"
}

# Enhanced kubelet diagnostics
enhanced_kubelet_diagnostics() {
    log_section "ENHANCED KUBELET DIAGNOSTICS"
    
    run_diagnostic "kubelet Service Status" "systemctl status kubelet --no-pager -l"
    
    run_diagnostic "kubelet Service State" "systemctl is-active kubelet && systemctl is-enabled kubelet"
    
    # Check for port conflicts
    run_diagnostic "Port 10250 Usage (Detailed)" "netstat -tulpn 2>/dev/null | grep :10250; ss -tulpn 2>/dev/null | grep :10250; lsof -i :10250 2>/dev/null || echo 'Port 10250 checks completed'"
    
    # Get recent kubelet logs
    run_diagnostic "Recent kubelet Logs (Last 50 lines)" "journalctl -u kubelet --no-pager -l -n 50"
    
    # Check for kubelet configuration issues
    run_diagnostic "kubelet Configuration" "cat /var/lib/kubelet/config.yaml 2>/dev/null || echo 'kubelet config.yaml not found'"
    
    # Check systemd drop-in files
    run_diagnostic "kubelet Systemd Drop-ins" "find /etc/systemd/system/kubelet.service.d/ -name '*.conf' -exec echo 'File: {}' \\; -exec cat {} \\; 2>/dev/null || echo 'No kubelet systemd drop-ins found'"
}

# Network connectivity diagnostics
network_connectivity_diagnostics() {
    log_section "NETWORK CONNECTIVITY DIAGNOSTICS"
    
    # Try to detect control plane IP from previous attempts
    local control_plane_ip=""
    if [ -f /var/lib/kubelet/kubeadm-flags.env ]; then
        # This won't work for initial join, but might help for debugging
        control_plane_ip=$(grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' /var/lib/kubelet/kubeadm-flags.env 2>/dev/null | head -1 || echo "")
    fi
    
    # Also check common control plane IPs in the network
    local network_base=$(ip route | grep -E '^default|0\.0\.0\.0' | awk '{print $3}' | head -1 | sed 's/\.[0-9]*$//')
    
    run_diagnostic "Network Interface Status" "ip addr show | grep -E '^[0-9]+:|inet '"
    
    run_diagnostic "Routing Table" "ip route show"
    
    run_diagnostic "DNS Resolution Test" "nslookup kubernetes.default.svc.cluster.local 2>/dev/null || nslookup google.com || echo 'DNS resolution issues detected'"
    
    if [ -n "$control_plane_ip" ]; then
        run_diagnostic "Control Plane Connectivity (Previous IP: $control_plane_ip)" "ping -c 3 $control_plane_ip 2>/dev/null || echo 'Cannot reach previous control plane IP'"
        
        run_diagnostic "Control Plane API Server Test (Port 6443)" "nc -z -w 5 $control_plane_ip 6443 && echo 'Port 6443 accessible' || echo 'Port 6443 not accessible'"
    else
        log_warn "No previous control plane IP detected, skipping specific connectivity tests"
        log_info "Common control plane ports to check: 6443 (API server), 2379-2380 (etcd)"
    fi
}

# System health diagnostics
system_health_diagnostics() {
    log_section "SYSTEM HEALTH DIAGNOSTICS"
    
    run_diagnostic "System Resources" "uptime && free -h && df -h | head -10"
    
    run_diagnostic "Failed System Services" "systemctl list-units --failed --no-pager"
    
    run_diagnostic "System Journal Errors (Last 100 lines)" "journalctl -p err -n 100 --no-pager"
    
    run_diagnostic "Firewall Status" "systemctl status firewalld --no-pager || systemctl status ufw --no-pager || iptables -L -n | head -20"
    
    run_diagnostic "SELinux Status" "getenforce 2>/dev/null || echo 'SELinux not available'"
}

# Join failure pattern analysis
analyze_join_failure_patterns() {
    log_section "JOIN FAILURE PATTERN ANALYSIS"
    
    local patterns_found=()
    
    log_info "Analyzing common join failure patterns..."
    
    # Pattern 1: CNI configuration missing
    if [ ! -d /etc/cni/net.d ] || [ -z "$(ls -A /etc/cni/net.d/ 2>/dev/null)" ]; then
        patterns_found+=("CNI_CONFIG_MISSING")
        log_warn "❌ PATTERN: CNI configuration directory missing or empty"
    else
        log_success "✓ CNI configuration directory exists and has files"
    fi
    
    # Pattern 2: Port 10250 conflict
    if netstat -tulpn 2>/dev/null | grep -q :10250; then
        if systemctl is-active --quiet kubelet; then
            log_success "✓ Port 10250 in use by kubelet (normal)"
        else
            patterns_found+=("PORT_10250_CONFLICT")
            log_warn "❌ PATTERN: Port 10250 in use by non-kubelet process"
        fi
    else
        log_success "✓ Port 10250 available"
    fi
    
    # Pattern 3: Containerd filesystem issues
    local containerd_capacity=$(df -h /var/lib/containerd 2>/dev/null | awk 'NR==2 {print $2}' || echo "unknown")
    if [ "$containerd_capacity" = "0" ] || [ "$containerd_capacity" = "0B" ] || [ "$containerd_capacity" = "0G" ]; then
        patterns_found+=("CONTAINERD_FILESYSTEM_INVALID")
        log_warn "❌ PATTERN: Containerd filesystem shows invalid capacity: $containerd_capacity"
    else
        log_success "✓ Containerd filesystem capacity normal: $containerd_capacity"
    fi
    
    # Pattern 4: Containerd socket issues
    if [ ! -S /run/containerd/containerd.sock ]; then
        patterns_found+=("CONTAINERD_SOCKET_MISSING")
        log_warn "❌ PATTERN: Containerd socket missing"
    else
        log_success "✓ Containerd socket exists"
    fi
    
    # Pattern 5: Kubelet configuration file conflicts
    if [ -f /etc/kubernetes/kubelet.conf ] && ! systemctl is-active --quiet kubelet; then
        patterns_found+=("KUBELET_CONFIG_CONFLICT")
        log_warn "❌ PATTERN: kubelet.conf exists but kubelet not running (may indicate failed previous join)"
    fi
    
    # Pattern 6: Bootstrap configuration issues
    if [ -f /etc/kubernetes/bootstrap-kubelet.conf ]; then
        patterns_found+=("BOOTSTRAP_CONFIG_EXISTS")
        log_warn "❌ PATTERN: Bootstrap kubelet config exists (may indicate interrupted join)"
    fi
    
    # Summary of patterns
    if [ ${#patterns_found[@]} -eq 0 ]; then
        log_success "✓ No common join failure patterns detected"
    else
        log_warn "Found ${#patterns_found[@]} potential issue pattern(s):"
        for pattern in "${patterns_found[@]}"; do
            log_warn "  - $pattern"
        done
    fi
    
    return ${#patterns_found[@]}
}

# Generate recommendations
generate_recommendations() {
    log_section "TROUBLESHOOTING RECOMMENDATIONS"
    
    log_info "Based on the diagnostic results, here are recommended next steps:"
    echo ""
    
    # Check if we detected any patterns and provide specific recommendations
    if [ ! -d /etc/cni/net.d ] || [ -z "$(ls -A /etc/cni/net.d/ 2>/dev/null)" ]; then
        log_warn "CNI Configuration Issue:"
        echo "  1. Ensure Flannel is deployed on the control plane:"
        echo "     kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"
        echo "  2. Verify CNI plugins are installed: ls -la /opt/cni/bin/"
        echo ""
    fi
    
    if [ -f /etc/kubernetes/kubelet.conf ] || [ -f /etc/kubernetes/bootstrap-kubelet.conf ]; then
        log_warn "Previous Join Artifacts Detected:"
        echo "  1. Consider running the remediation script to clean up previous join attempts"
        echo "  2. Or manually clean: rm -f /etc/kubernetes/{kubelet.conf,bootstrap-kubelet.conf}"
        echo ""
    fi
    
    log_info "General Recommendations:"
    echo "  1. Ensure control plane is accessible and healthy"
    echo "  2. Get a fresh join command: kubeadm token create --print-join-command"
    echo "  3. Run the join command with verbose logging: kubeadm join ... --v=5"
    echo "  4. Monitor join progress: journalctl -u kubelet -f"
    echo ""
    
    log_info "For persistent issues:"
    echo "  1. Run the worker_node_join_remediation.sh script"
    echo "  2. Check control plane logs: kubectl logs -n kube-system <pod-name>"
    echo "  3. Verify network connectivity between nodes"
    echo ""
}

# Main execution
main() {
    echo "========================================================================"
    echo "           Enhanced Worker Node Join Troubleshooter"
    echo "========================================================================"
    echo "Timestamp: $(date)"
    echo "Script should be run on the WORKER NODE having join issues"
    echo "========================================================================"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    # Detect and validate node type
    detect_node_type
    
    # Run comprehensive diagnostics
    enhanced_cni_diagnostics
    enhanced_runtime_diagnostics
    enhanced_kubelet_diagnostics
    network_connectivity_diagnostics
    system_health_diagnostics
    
    # Analyze patterns
    analyze_join_failure_patterns
    local issues_found=$?
    
    # Generate recommendations
    generate_recommendations
    
    echo ""
    log_section "DIAGNOSTIC COMPLETE"
    
    if [ $issues_found -eq 0 ]; then
        log_success "System appears healthy for kubeadm join operation"
    else
        log_warn "Found $issues_found potential issue(s) - see recommendations above"
    fi
    
    log_info "Save this output for analysis and share with the troubleshooting team"
    log_info "Next step: Address any issues found, then attempt kubeadm join with --v=5 for detailed logging"
}

# Execute main function
main "$@"
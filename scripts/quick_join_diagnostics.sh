#!/bin/bash

# VMStation Quick Join Diagnostics
# Rapid diagnostic script for kubeadm join issues

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

MASTER_IP="${1:-192.168.4.63}"

echo "=== VMStation Quick Join Diagnostics ==="
echo "Timestamp: $(date)"
echo "Master IP: $MASTER_IP"
echo ""

# Function to check service status
check_service_status() {
    local service="$1"
    info "Checking $service service..."
    
    if systemctl is-active "$service" >/dev/null 2>&1; then
        info "✓ $service is active"
        
        # Show brief status
        systemctl status "$service" --no-pager -l | head -5
    else
        warn "✗ $service is not active"
        systemctl status "$service" --no-pager -l | head -10
    fi
    echo ""
}

# Function to check connectivity
check_connectivity() {
    info "Checking connectivity to master node..."
    
    # Test ping
    if ping -c 2 "$MASTER_IP" >/dev/null 2>&1; then
        info "✓ Can ping master node at $MASTER_IP"
    else
        error "✗ Cannot ping master node at $MASTER_IP"
    fi
    
    # Test API server port
    if timeout 5 bash -c "echo >/dev/tcp/$MASTER_IP/6443" 2>/dev/null; then
        info "✓ API server port 6443 is reachable"
    else
        error "✗ Cannot connect to API server at $MASTER_IP:6443"
    fi
    
    echo ""
}

# Function to check containerd status
check_containerd_status() {
    info "Checking containerd status and configuration..."
    
    # Service status
    check_service_status containerd
    
    # Socket availability
    if [ -S /run/containerd/containerd.sock ]; then
        info "✓ Containerd socket exists"
    else
        error "✗ Containerd socket missing"
    fi
    
    # Client connectivity
    if ctr version >/dev/null 2>&1; then
        info "✓ Containerd client connectivity works"
        ctr version | head -3
    else
        warn "✗ Containerd client connectivity failed"
    fi
    
    # CRI status
    if crictl version >/dev/null 2>&1; then
        info "✓ CRI (crictl) connectivity works"
        
        # Check for image filesystem
        if crictl info 2>/dev/null | grep -q "\"imageFilesystem\""; then
            local capacity=$(crictl info 2>/dev/null | grep -A10 "imageFilesystem" | grep "capacityBytes" | head -1 | grep -oE '[0-9]+' || echo "0")
            if [ "$capacity" != "0" ] && [ -n "$capacity" ]; then
                info "✓ Image filesystem detected with capacity: $capacity bytes"
            else
                error "✗ Image filesystem shows zero capacity"
            fi
        else
            error "✗ Image filesystem not detected in CRI status"
        fi
    else
        warn "✗ CRI (crictl) connectivity failed"
    fi
    
    echo ""
}

# Function to check kubelet status
check_kubelet_status() {
    info "Checking kubelet status..."
    
    check_service_status kubelet
    
    # Check for common kubelet issues
    info "Checking for common kubelet issues..."
    
    # Check for standalone mode
    if pgrep kubelet >/dev/null && journalctl -u kubelet --no-pager --since "10 minutes ago" | grep -q "standalone"; then
        warn "✗ Kubelet is running in standalone mode"
        warn "This indicates the join process failed or kubelet cannot connect to API server"
    elif pgrep kubelet >/dev/null; then
        info "✓ Kubelet is running and not in standalone mode"
    else
        info "• Kubelet is not currently running (normal before join)"
    fi
    
    # Check for existing kubelet configuration
    if [ -f /etc/kubernetes/kubelet.conf ]; then
        info "✓ Kubelet configuration exists (node may already be joined)"
        
        # Extract server info
        local server=$(grep "server:" /etc/kubernetes/kubelet.conf 2>/dev/null | awk '{print $2}' || echo "unknown")
        info "Configured API server: $server"
    else
        info "• No kubelet configuration (normal before join)"
    fi
    
    echo ""
}

# Function to check filesystem status
check_filesystem_status() {
    info "Checking filesystem status..."
    
    # Check key directories
    for dir in "/var/lib/kubelet" "/var/lib/containerd" "/etc/kubernetes"; do
        if [ -d "$dir" ]; then
            local usage=$(df -h "$dir" 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
            if [ "$usage" -gt 90 ] 2>/dev/null; then
                warn "High disk usage in $dir: ${usage}%"
            else
                info "✓ Disk usage OK for $dir: ${usage}%"
            fi
        else
            info "• Directory $dir does not exist (will be created during join)"
        fi
    done
    
    # Check containerd filesystem capacity
    local containerd_capacity=$(df -BG /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo "0")
    if [ "$containerd_capacity" = "0" ] || [ -z "$containerd_capacity" ]; then
        error "✗ Containerd filesystem shows 0 capacity - this will cause join failures"
    else
        info "✓ Containerd filesystem capacity: ${containerd_capacity}G"
    fi
    
    echo ""
}

# Function to check network configuration
check_network_config() {
    info "Checking network configuration..."
    
    # Check required kernel modules
    for module in br_netfilter overlay; do
        if lsmod | grep -q "$module"; then
            info "✓ $module module loaded"
        else
            warn "✗ $module module not loaded"
        fi
    done
    
    # Check sysctl parameters
    local params=(
        "net.bridge.bridge-nf-call-iptables"
        "net.bridge.bridge-nf-call-ip6tables"
        "net.ipv4.ip_forward"
    )
    
    for param in "${params[@]}"; do
        local value=$(sysctl -n "$param" 2>/dev/null || echo "0")
        if [ "$value" = "1" ]; then
            info "✓ $param = $value"
        else
            warn "✗ $param = $value (should be 1)"
        fi
    done
    
    echo ""
}

# Function to show recent logs
show_recent_logs() {
    info "Recent logs (last 20 lines from key services)..."
    
    echo ""
    info "=== Recent kubelet logs ==="
    journalctl -u kubelet --no-pager -n 20 --since "1 hour ago" 2>/dev/null | tail -10 || echo "No kubelet logs available"
    
    echo ""
    info "=== Recent containerd logs ==="
    journalctl -u containerd --no-pager -n 20 --since "1 hour ago" 2>/dev/null | tail -10 || echo "No containerd logs available"
    
    echo ""
}

# Function to provide recommendations
provide_recommendations() {
    info "=== Diagnostic Summary and Recommendations ==="
    echo ""
    
    # Check if containerd filesystem issue is likely
    local containerd_capacity=$(df -BG /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo "0")
    local has_image_fs=false
    
    if crictl info 2>/dev/null | grep -q "\"imageFilesystem\""; then
        local cri_capacity=$(crictl info 2>/dev/null | grep -A10 "imageFilesystem" | grep "capacityBytes" | head -1 | grep -oE '[0-9]+' || echo "0")
        if [ "$cri_capacity" != "0" ] && [ -n "$cri_capacity" ]; then
            has_image_fs=true
        fi
    fi
    
    if [ "$containerd_capacity" = "0" ] || [ "$has_image_fs" = "false" ]; then
        error "PRIMARY ISSUE DETECTED: Containerd image filesystem initialization problem"
        error ""
        error "Recommended fix:"
        error "   sudo ./scripts/manual_containerd_filesystem_fix.sh"
        error ""
        error "This script will completely reset and reinitialize containerd to fix"
        error "the 'invalid capacity 0 on image filesystem' error."
        echo ""
    fi
    
    # Check for service issues
    if ! systemctl is-active containerd >/dev/null 2>&1; then
        warn "SECONDARY ISSUE: Containerd service not running"
        warn "Fix: sudo systemctl start containerd"
        echo ""
    fi
    
    if ! systemctl is-active kubelet >/dev/null 2>&1 && [ -f /etc/kubernetes/kubelet.conf ]; then
        warn "SECONDARY ISSUE: Kubelet service not running but config exists"
        warn "Fix: sudo systemctl start kubelet"
        echo ""
    fi
    
    # Check for connectivity issues
    if ! timeout 5 bash -c "echo >/dev/tcp/$MASTER_IP/6443" 2>/dev/null; then
        warn "NETWORK ISSUE: Cannot connect to API server"
        warn "Check: Network connectivity, firewall rules, master node status"
        echo ""
    fi
    
    info "After addressing issues above, retry join with:"
    info "   sudo ./scripts/enhanced_kubeadm_join.sh \"<your-join-command>\""
    echo ""
}

# Main execution
main() {
    # Check if running with appropriate permissions
    if [[ $EUID -eq 0 ]]; then
        info "Running as root - full diagnostics available"
    else
        warn "Running as non-root - some checks may be limited"
        warn "For complete diagnostics, run: sudo $0"
    fi
    echo ""
    
    check_connectivity
    check_filesystem_status
    check_containerd_status
    check_kubelet_status
    check_network_config
    show_recent_logs
    provide_recommendations
    
    echo ""
    info "Diagnostic scan completed. Review recommendations above."
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
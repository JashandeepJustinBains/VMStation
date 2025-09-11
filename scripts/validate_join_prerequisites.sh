#!/bin/bash

# VMStation Kubernetes Join Prerequisites Validator
# Comprehensive validation before attempting kubeadm join to prevent standalone mode

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
VALIDATION_FAILED=0

echo "=== VMStation Join Prerequisites Validator ==="
echo "Timestamp: $(date)"
echo "Validating prerequisites for joining master: $MASTER_IP"
echo ""

# Function to increment failure counter
fail_check() {
    ((VALIDATION_FAILED++))
}

# Check 1: Basic system requirements
check_system_requirements() {
    info "Checking system requirements..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "Must run as root for proper validation"
        fail_check
        return 1
    fi
    
    # Check available memory
    local mem_gb=$(free -g | awk 'NR==2{print $2}')
    if [ "$mem_gb" -lt 1 ]; then
        warn "Low memory: ${mem_gb}GB (recommended: >=2GB)"
    else
        info "✓ Memory: ${mem_gb}GB"
    fi
    
    # Check disk space in key directories
    for dir in "/var/lib/kubelet" "/var/lib/containerd" "/etc/kubernetes"; do
        if df -h "$dir" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); if($5 > 90) exit 1}'; then
            info "✓ Disk space OK for $dir"
        else
            warn "High disk usage in $dir"
        fi
    done
    
    # Check swap is disabled
    if swapon -s | grep -q "/"; then
        error "Swap is enabled - Kubernetes requires swap to be disabled"
        fail_check
    else
        info "✓ Swap is disabled"
    fi
}

# Check 2: Network connectivity to master
check_master_connectivity() {
    info "Checking connectivity to master node..."
    
    # Test basic network connectivity
    if ping -c 2 "$MASTER_IP" >/dev/null 2>&1; then
        info "✓ Basic ping to master successful"
    else
        error "Cannot ping master node at $MASTER_IP"
        fail_check
        return 1
    fi
    
    # Test API server port
    if timeout 10 bash -c "echo >/dev/tcp/$MASTER_IP/6443" 2>/dev/null; then
        info "✓ API server port 6443 is reachable"
    else
        error "Cannot connect to API server at $MASTER_IP:6443"
        fail_check
    fi
    
    # Test API server health endpoint
    if curl -k -s --connect-timeout 5 "https://$MASTER_IP:6443/healthz" | grep -q "ok"; then
        info "✓ API server health endpoint responds"
    else
        warn "API server health endpoint not responding (may be normal)"
    fi
}

# Check 3: Container runtime
check_container_runtime() {
    info "Checking container runtime..."
    
    # Check containerd service
    if systemctl is-active containerd >/dev/null 2>&1; then
        info "✓ containerd service is active"
    else
        error "containerd service is not active"
        fail_check
        return 1
    fi
    
    # Check containerd socket
    if [ -S /run/containerd/containerd.sock ]; then
        info "✓ containerd socket exists"
    else
        error "containerd socket not found"
        fail_check
    fi
    
    # Test containerd connectivity
    if ctr version >/dev/null 2>&1; then
        info "✓ containerd client connection works"
    else
        warn "containerd client connection failed"
    fi
    
    # Check crictl configuration with proper permissions
    info "Checking crictl runtime connection..."
    
    # Ensure crictl config exists with correct settings
    mkdir -p /etc
    cat > /etc/crictl.yaml << EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
    info "✓ crictl configuration updated"
    
    # Check containerd socket permissions and fix if needed
    if [ -S /run/containerd/containerd.sock ]; then
        local socket_perms=$(stat -c "%a" /run/containerd/containerd.sock 2>/dev/null)
        local socket_owner=$(stat -c "%U:%G" /run/containerd/containerd.sock 2>/dev/null)
        info "Containerd socket permissions: ${socket_perms} (${socket_owner})"
        
        # If socket is restrictive (660) and we're not root, ensure we can access it
        if [ "$socket_perms" = "660" ] && [ "$(id -u)" != "0" ]; then
            warn "Socket has restrictive permissions and current user is not root"
            info "Attempting to add current user to appropriate group for containerd access..."
            
            # Try to create containerd group if it doesn't exist
            if ! getent group containerd >/dev/null 2>&1; then
                info "Creating containerd group..."
                groupadd containerd 2>/dev/null || true
            fi
            
            # Add current user to containerd group
            usermod -a -G containerd $(whoami) 2>/dev/null || true
            
            # Change socket group to containerd for access
            chgrp containerd /run/containerd/containerd.sock 2>/dev/null || true
        fi
    else
        error "Containerd socket not found at /run/containerd/containerd.sock"
        fail_check
        return
    fi
    
    # Test crictl connection - use appropriate execution context
    local crictl_test_failed=false
    if [ "$(id -u)" = "0" ]; then
        # Running as root - direct execution
        if crictl version >/dev/null 2>&1; then
            info "✓ crictl can connect to runtime (as root)"
        else
            crictl_test_failed=true
        fi
    else
        # Running as non-root - try with current permissions first, then with sudo
        if crictl version >/dev/null 2>&1; then
            info "✓ crictl can connect to runtime (current user)"
        elif command -v sudo >/dev/null 2>&1 && sudo -n crictl version >/dev/null 2>&1; then
            info "✓ crictl can connect to runtime (with sudo)"
        else
            crictl_test_failed=true
        fi
    fi
    
    if [ "$crictl_test_failed" = "true" ]; then
        error "Failed to establish crictl connection to containerd"
        error "This indicates a permissions or configuration issue with the containerd socket"
        
        # Provide diagnostic information
        if [ -S /run/containerd/containerd.sock ]; then
            error "Socket exists but is not accessible:"
            ls -la /run/containerd/containerd.sock
            error "Current user: $(whoami) (UID: $(id -u))"
            error "Current groups: $(groups)"
        fi
        
        error "Possible fixes:"
        error "1. Run this script as root: sudo $0"
        error "2. Add user to containerd group and restart containerd"
        error "3. Check containerd service status and logs"
        
        fail_check
    fi
}

# Check 4: Kubernetes packages and services
check_kubernetes_packages() {
    info "Checking Kubernetes packages..."
    
    # Check required packages are installed
    for package in kubelet kubeadm kubectl; do
        if command -v "$package" >/dev/null 2>&1; then
            local version=$($package --version 2>/dev/null | head -1)
            info "✓ $package installed: $version"
        else
            error "$package is not installed or not in PATH"
            fail_check
        fi
    done
    
    # Check kubelet service exists
    if systemctl list-unit-files | grep -q "kubelet.service"; then
        info "✓ kubelet service unit exists"
    else
        error "kubelet service unit not found"
        fail_check
    fi
}

# Check 5: Network configuration
check_network_config() {
    info "Checking network configuration..."
    
    # Check required kernel modules
    for module in br_netfilter overlay; do
        if lsmod | grep -q "$module"; then
            info "✓ $module module loaded"
        else
            warn "$module module not loaded - loading now"
            modprobe "$module" || fail_check
        fi
    done
    
    # Check sysctl parameters
    for param in "net.bridge.bridge-nf-call-iptables=1" "net.bridge.bridge-nf-call-ip6tables=1" "net.ipv4.ip_forward=1"; do
        local key=$(echo "$param" | cut -d'=' -f1)
        local expected=$(echo "$param" | cut -d'=' -f2)
        local actual=$(sysctl -n "$key" 2>/dev/null || echo "0")
        
        if [ "$actual" = "$expected" ]; then
            info "✓ $key = $actual"
        else
            warn "$key = $actual (expected: $expected) - fixing"
            sysctl -w "$key=$expected" >/dev/null || fail_check
        fi
    done
    
    # Check firewall status
    if command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state >/dev/null 2>&1; then
            info "✓ Firewall is running"
            # Check required ports
            for port in "6443/tcp" "10250/tcp"; do
                if firewall-cmd --query-port="$port" >/dev/null 2>&1; then
                    info "✓ Port $port is open"
                else
                    warn "Port $port is not open - may cause issues"
                fi
            done
        else
            info "✓ Firewall is disabled"
        fi
    fi
}

# Check 6: Existing kubelet configuration
check_existing_config() {
    info "Checking existing Kubernetes configuration..."
    
    # Check if node is already joined
    if [ -f /etc/kubernetes/kubelet.conf ]; then
        warn "Node appears to already be joined (kubelet.conf exists)"
        info "Existing kubelet config found - this may indicate partial join"
        
        # Check if it's a valid config
        if grep -q "server:" /etc/kubernetes/kubelet.conf; then
            local server=$(grep "server:" /etc/kubernetes/kubelet.conf | awk '{print $2}')
            info "Configured API server: $server"
        fi
    else
        info "✓ No existing kubelet.conf (clean state)"
    fi
    
    # Check for bootstrap config
    if [ -f /etc/kubernetes/bootstrap-kubelet.conf ]; then
        warn "Bootstrap config exists - may indicate failed previous join"
    fi
    
    # Check kubelet systemd configuration
    if [ -f /etc/systemd/system/kubelet.service.d/10-kubeadm.conf ]; then
        info "✓ kubelet systemd configuration exists"
        
        # Check for problematic bootstrap references
        if grep -q "bootstrap-kubeconfig" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf; then
            if [ -f /etc/kubernetes/kubelet.conf ]; then
                warn "kubelet systemd still references bootstrap config but cluster config exists"
                warn "This may cause standalone mode - will fix"
                
                # Remove bootstrap reference for already joined nodes
                sed -i 's/--bootstrap-kubeconfig=[^ ]* //g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
                systemctl daemon-reload
                info "✓ Removed bootstrap config reference"
            fi
        fi
    fi
}

# Check 7: Resource availability
check_system_resources() {
    info "Checking system resources..."
    
    # Check CPU
    local cpu_count=$(nproc)
    if [ "$cpu_count" -ge 2 ]; then
        info "✓ CPU cores: $cpu_count"
    else
        warn "Low CPU count: $cpu_count (recommended: >=2)"
    fi
    
    # Check load average
    local load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    # Convert load to integer for comparison (multiply by 100 to handle decimals)
    local load_int=$(echo "$load" | awk '{printf "%.0f", $1 * 100}')
    if (( load_int < 200 )); then  # 200 = 2.0 * 100
        info "✓ System load: $load"
    else
        warn "High system load: $load"
    fi
    
    # Check if kubelet is consuming excessive resources
    if pgrep kubelet >/dev/null; then
        local kubelet_cpu=$(ps -p $(pgrep kubelet) -o %cpu --no-headers 2>/dev/null || echo "0")
        # Convert CPU percentage to integer for comparison (remove decimal point)
        local kubelet_cpu_int=$(echo "$kubelet_cpu" | awk '{printf "%.0f", $1}')
        if (( kubelet_cpu_int < 50 )); then
            info "✓ kubelet CPU usage: ${kubelet_cpu}%"
        else
            warn "High kubelet CPU usage: ${kubelet_cpu}%"
        fi
    fi
}

# Summary and recommendations
show_summary() {
    echo ""
    echo "=== Validation Summary ==="
    
    if [ "$VALIDATION_FAILED" -eq 0 ]; then
        info "✅ All prerequisites validated successfully!"
        info "System is ready for kubeadm join"
        echo ""
        info "Recommended next steps:"
        info "1. Ensure master node has a valid join token"
        info "2. Run kubeadm join with appropriate parameters"
        info "3. Monitor kubelet logs during join process"
        return 0
    else
        error "❌ $VALIDATION_FAILED validation check(s) failed"
        error "System is NOT ready for kubeadm join"
        echo ""
        error "Required fixes:"
        error "1. Address the failed checks above"
        error "2. Re-run this validation script"
        error "3. Only attempt join after all checks pass"
        return 1
    fi
}

# Main execution
main() {
    check_system_requirements
    check_master_connectivity
    check_container_runtime
    check_kubernetes_packages
    check_network_config
    check_existing_config
    check_system_resources
    
    show_summary
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
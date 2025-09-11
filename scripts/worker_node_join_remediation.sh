#!/bin/bash

# VMStation Worker Node Join Remediation
# General purpose remediation script for worker node join issues

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

echo "=== VMStation Worker Node Join Remediation ==="
echo "Timestamp: $(date)"
echo "Master IP: $MASTER_IP"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

# Function to run diagnostics first
run_diagnostics() {
    info "Running quick diagnostics first..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local diag_script="$script_dir/quick_join_diagnostics.sh"
    
    if [ -f "$diag_script" ]; then
        bash "$diag_script" "$MASTER_IP"
    else
        warn "Quick diagnostics script not found, proceeding with remediation"
    fi
    
    echo ""
    info "Press Enter to continue with remediation, or Ctrl+C to abort..."
    read -r
}

# Function to stop services
stop_services() {
    info "Stopping Kubernetes and container services..."
    
    systemctl stop kubelet 2>/dev/null || true
    systemctl stop containerd 2>/dev/null || true
    
    # Kill any remaining processes
    pkill -f kubelet 2>/dev/null || true
    pkill -f containerd 2>/dev/null || true
    
    sleep 5
    info "✓ Services stopped"
}

# Function to clean up existing state
cleanup_existing_state() {
    info "Cleaning up existing Kubernetes state..."
    
    # Reset kubeadm configuration
    kubeadm reset --force 2>/dev/null || true
    
    # Clean up iptables rules
    iptables -F 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    iptables -t mangle -F 2>/dev/null || true
    iptables -X 2>/dev/null || true
    
    # Remove Kubernetes directories
    rm -rf /etc/kubernetes/* 2>/dev/null || true
    rm -rf /var/lib/kubelet/* 2>/dev/null || true
    rm -rf /var/lib/etcd/* 2>/dev/null || true
    rm -rf /etc/cni/net.d/* 2>/dev/null || true
    rm -rf /var/lib/cni/* 2>/dev/null || true
    rm -rf /run/flannel/* 2>/dev/null || true
    
    # Clean up network interfaces
    ip link set cni0 down 2>/dev/null || true
    ip link delete cni0 2>/dev/null || true
    ip link set flannel.1 down 2>/dev/null || true
    ip link delete flannel.1 2>/dev/null || true
    
    # Reset systemd
    systemctl daemon-reload
    systemctl reset-failed kubelet 2>/dev/null || true
    systemctl reset-failed containerd 2>/dev/null || true
    
    info "✓ Existing state cleaned up"
}

# Function to fix containerd
fix_containerd() {
    info "Checking if containerd needs fixing..."
    
    # Start containerd if it's not running
    if ! systemctl is-active containerd >/dev/null 2>&1; then
        systemctl start containerd
        sleep 10
    fi
    
    # Configure crictl for containerd before checking CRI interface
    info "Configuring crictl for containerd communication..."
    mkdir -p /etc
    cat > /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
    info "✓ crictl configuration created"
    
    # Ensure proper permissions for containerd socket access
    if [ -S /run/containerd/containerd.sock ]; then
        # Create containerd group if it doesn't exist
        if ! getent group containerd >/dev/null 2>&1; then
            info "Creating containerd group for socket access..."
            groupadd containerd 2>/dev/null || true
        fi
        # Set appropriate group ownership for socket access
        chgrp containerd /run/containerd/containerd.sock 2>/dev/null || true
        info "✓ containerd socket permissions configured"
    fi
    
    # Check if containerd filesystem initialization is needed
    local needs_fix=false
    
    # Check filesystem capacity
    local capacity=$(df -BG /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo "0")
    if [ "$capacity" = "0" ]; then
        needs_fix=true
        warn "Containerd filesystem shows zero capacity"
    fi
    
    # Check CRI image filesystem
    if ! crictl info 2>/dev/null | grep -q "\"imageFilesystem\""; then
        needs_fix=true
        warn "CRI imageFilesystem not detected"
    else
        local cri_capacity=$(crictl info 2>/dev/null | grep -A10 "imageFilesystem" | grep "capacityBytes" | head -1 | grep -oE '[0-9]+' || echo "0")
        if [ "$cri_capacity" = "0" ]; then
            needs_fix=true
            warn "CRI imageFilesystem shows zero capacity"
        fi
    fi
    
    if [ "$needs_fix" = "true" ]; then
        warn "Containerd filesystem initialization issues detected"
        warn "Running manual containerd filesystem fix..."
        
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local manual_fix="$script_dir/manual_containerd_filesystem_fix.sh"
        
        if [ -f "$manual_fix" ]; then
            bash "$manual_fix"
        else
            error "Manual containerd fix script not found at $manual_fix"
            error "Please run the manual fix separately before retrying join"
            return 1
        fi
    else
        info "✓ Containerd filesystem appears healthy"
    fi
}

# Function to prepare system for join
prepare_system() {
    info "Preparing system for Kubernetes join..."
    
    # Ensure required kernel modules are loaded
    modprobe overlay || true
    modprobe br_netfilter || true
    
    # Set required sysctl parameters
    sysctl -w net.bridge.bridge-nf-call-iptables=1 2>/dev/null || true
    sysctl -w net.bridge.bridge-nf-call-ip6tables=1 2>/dev/null || true
    sysctl -w net.ipv4.ip_forward=1 2>/dev/null || true
    
    # Ensure swap is disabled
    swapoff -a 2>/dev/null || true
    
    # Recreate CNI directories
    mkdir -p /etc/cni/net.d
    mkdir -p /opt/cni/bin
    mkdir -p /var/lib/cni/networks
    mkdir -p /run/flannel
    
    chmod 755 /etc/cni/net.d /opt/cni/bin /var/lib/cni/networks /run/flannel
    
    # Enable services
    systemctl enable kubelet
    systemctl enable containerd
    
    info "✓ System prepared for join"
}

# Function to test connectivity
test_connectivity() {
    info "Testing connectivity to master node..."
    
    # Test ping
    if ! ping -c 2 "$MASTER_IP" >/dev/null 2>&1; then
        error "Cannot ping master node at $MASTER_IP"
        return 1
    fi
    
    # Test API server port
    if ! timeout 10 bash -c "echo >/dev/tcp/$MASTER_IP/6443" 2>/dev/null; then
        error "Cannot connect to API server at $MASTER_IP:6443"
        return 1
    fi
    
    info "✓ Connectivity to master node verified"
}

# Function to provide final instructions
provide_instructions() {
    echo ""
    info "=== Remediation Complete ==="
    echo ""
    info "The worker node has been prepared for joining the cluster."
    echo ""
    info "Next steps:"
    info "1. On the master node, generate a fresh join command:"
    info "   sudo kubeadm token create --print-join-command"
    echo ""
    info "2. On this worker node, run the enhanced join process:"
    info "   sudo ./scripts/enhanced_kubeadm_join.sh \"<join-command-from-step-1>\""
    echo ""
    info "3. Monitor the join process:"
    info "   sudo journalctl -u kubelet -f"
    echo ""
    info "4. Verify the node joined successfully (run on master):"
    info "   kubectl get nodes -o wide"
    echo ""
    
    if [ -f /tmp/containerd-backup-location.txt ]; then
        local backup_location=$(cat /tmp/containerd-backup-location.txt)
        info "Note: Configuration backups saved at: $backup_location"
    fi
}

# Main execution
main() {
    info "Starting worker node join remediation process..."
    echo ""
    
    # Step 1: Run diagnostics
    run_diagnostics
    
    # Step 2: Stop services
    stop_services
    
    # Step 3: Clean up existing state
    cleanup_existing_state
    
    # Step 4: Fix containerd if needed
    if ! fix_containerd; then
        error "Failed to fix containerd - manual intervention required"
        exit 1
    fi
    
    # Step 5: Prepare system
    prepare_system
    
    # Step 6: Test connectivity
    if ! test_connectivity; then
        error "Connectivity test failed - check network configuration"
        exit 1
    fi
    
    # Step 7: Provide instructions
    provide_instructions
    
    echo ""
    info "✅ Worker node remediation completed successfully!"
    info "You can now proceed with the kubeadm join process."
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
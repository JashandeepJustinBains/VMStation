#!/bin/bash

# VMStation Manual Cluster Setup Troubleshooting Script
# Fixes crictl and kubelet configuration issues for manual cluster setup

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

echo "=== VMStation Manual Cluster Setup Fixes ==="
echo "Timestamp: $(date)"
echo ""

info "Fixing crictl and kubelet configuration issues..."

# Function to configure crictl properly
configure_crictl() {
    info "Configuring crictl to use containerd..."
    
    # Create crictl configuration
    cat > /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF
    
    chmod 644 /etc/crictl.yaml
    
    info "✓ crictl configuration updated"
    
    # Test crictl configuration
    if crictl version >/dev/null 2>&1; then
        info "✓ crictl can connect to containerd"
        crictl version
    else
        warn "crictl still cannot connect to containerd - checking containerd service..."
        return 1
    fi
}

# Function to check and fix containerd service
fix_containerd_service() {
    info "Checking containerd service status..."
    
    # Check if containerd is installed
    if ! command -v containerd >/dev/null 2>&1; then
        error "containerd is not installed. Please install containerd first."
        return 1
    fi
    
    # Check containerd service status
    if ! systemctl is-active containerd >/dev/null 2>&1; then
        warn "containerd service is not running. Attempting to start..."
        
        # Ensure containerd config directory exists
        mkdir -p /etc/containerd
        
        # Generate default containerd config if missing
        if [ ! -f /etc/containerd/config.toml ]; then
            info "Generating containerd configuration..."
            containerd config default > /etc/containerd/config.toml
            
            # Configure systemd cgroup driver
            sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
            
            info "✓ containerd configuration generated"
        fi
        
        # Start containerd service
        systemctl daemon-reload
        systemctl enable containerd
        systemctl start containerd
        
        # Wait for containerd to be ready
        sleep 5
        
        if systemctl is-active containerd >/dev/null 2>&1; then
            info "✓ containerd service started successfully"
        else
            error "Failed to start containerd service"
            systemctl status containerd
            return 1
        fi
    else
        info "✓ containerd service is running"
    fi
    
    # Test containerd socket
    if [ -S /var/run/containerd/containerd.sock ]; then
        info "✓ containerd socket exists"
    else
        error "containerd socket not found at /var/run/containerd/containerd.sock"
        ls -la /var/run/containerd/ || true
        return 1
    fi
}

# Function to check kubelet configuration
check_kubelet_config() {
    info "Checking kubelet configuration..."
    
    # Check if kubelet is installed
    if ! command -v kubelet >/dev/null 2>&1; then
        error "kubelet is not installed. Please install kubelet first."
        return 1
    fi
    
    # Check kubelet service status
    if systemctl is-active kubelet >/dev/null 2>&1; then
        info "✓ kubelet service is running"
    else
        warn "kubelet service is not running"
    fi
    
    # Check kubelet configuration files
    if [ -f /etc/kubernetes/kubelet.conf ]; then
        info "✓ kubelet cluster configuration exists"
        # Check if it's properly configured
        if grep -q "server:" /etc/kubernetes/kubelet.conf; then
            local api_server
            api_server=$(grep "server:" /etc/kubernetes/kubelet.conf | awk '{print $2}')
            info "✓ kubelet configured to connect to API server: $api_server"
        else
            warn "kubelet configuration exists but may be incomplete"
        fi
    else
        warn "kubelet cluster configuration not found at /etc/kubernetes/kubelet.conf"
        warn "This indicates the node may not be properly joined to the cluster"
    fi
    
    # Check kubelet service configuration
    if [ -f /etc/systemd/system/kubelet.service.d/10-kubeadm.conf ]; then
        info "✓ kubelet systemd configuration exists"
        debug "Current kubelet systemd configuration:"
        head -10 /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    else
        warn "kubelet systemd configuration not found"
    fi
}

# Function to display cluster status
check_cluster_status() {
    info "Checking cluster connection status..."
    
    # Check if we can connect to the API server
    if kubectl cluster-info >/dev/null 2>&1; then
        info "✓ kubectl can connect to cluster"
        kubectl get nodes --no-headers 2>/dev/null | while read -r node status; do
            if [[ "$status" == "Ready" ]]; then
                info "✓ Node $node is Ready"
            else
                warn "Node $node status: $status"
            fi
        done
    else
        warn "kubectl cannot connect to cluster API server"
        warn "This is expected if running on a worker node that hasn't joined yet"
    fi
    
    # Check if running on master node
    if [ -f /etc/kubernetes/admin.conf ]; then
        info "✓ This appears to be a master node (admin.conf exists)"
        export KUBECONFIG=/etc/kubernetes/admin.conf
        kubectl get nodes -o wide 2>/dev/null || warn "Cannot list nodes even with admin.conf"
    else
        info "This appears to be a worker node (no admin.conf)"
    fi
}

# Function to show current status
show_current_status() {
    info "Current system status:"
    echo ""
    
    debug "Container runtime status:"
    systemctl status containerd --no-pager -l | head -10 || true
    echo ""
    
    debug "Kubelet service status:"
    systemctl status kubelet --no-pager -l | head -10 || true
    echo ""
    
    debug "crictl version and info:"
    crictl version 2>&1 || true
    echo ""
    
    debug "Container runtime info:"
    crictl info 2>&1 | head -20 || true
    echo ""
    
    debug "Current pods (if any):"
    crictl ps -a 2>&1 || true
}

# Main execution
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (try: sudo $0)"
        exit 1
    fi
    
    info "Starting manual cluster setup troubleshooting..."
    
    # Show current status first
    show_current_status
    
    echo ""
    info "Applying fixes..."
    
    # Apply fixes in order
    if fix_containerd_service; then
        info "✓ containerd service check passed"
    else
        error "Failed to fix containerd service"
        exit 1
    fi
    
    if configure_crictl; then
        info "✓ crictl configuration passed"
    else
        error "Failed to configure crictl"
        exit 1
    fi
    
    check_kubelet_config
    check_cluster_status
    
    echo ""
    info "Manual cluster setup fixes completed!"
    
    echo ""
    info "Next steps:"
    info "1. If this is a worker node, ensure it has been joined to the cluster:"
    info "   kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>"
    info ""
    info "2. If this is a master node, ensure the cluster is initialized:"
    info "   kubeadm init --pod-network-cidr=10.244.0.0/16"
    info ""
    info "3. Test crictl functionality:"
    info "   crictl ps -a"
    info "   crictl images"
    echo ""
}

# Run main function
main "$@"
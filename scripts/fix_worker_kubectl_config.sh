#!/bin/bash

# Fix kubectl Configuration on Worker Nodes
# Addresses the "connection refused" errors when running kubectl on worker nodes
# This script configures kubectl to communicate with the cluster API server

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Default control plane IP - can be overridden
CONTROL_PLANE_IP="${1:-192.168.4.63}"
KUBECONFIG_SOURCE="/etc/kubernetes/admin.conf"

echo "=== Worker Node kubectl Configuration Fix ==="
echo "Timestamp: $(date)"
echo "Control Plane IP: $CONTROL_PLANE_IP"
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

# Function to detect node role
detect_node_role() {
    local hostname=$(hostname)
    
    # Check if this is the control plane node
    if [ -f "$KUBECONFIG_SOURCE" ]; then
        info "Detected control plane node (found $KUBECONFIG_SOURCE)"
        return 0  # Control plane
    else
        info "Detected worker node (no $KUBECONFIG_SOURCE found)"
        return 1  # Worker node
    fi
}

# Function to copy kubeconfig from control plane
setup_worker_kubeconfig() {
    info "Setting up kubectl configuration for worker node"
    
    # Create .kube directory for root user
    mkdir -p /root/.kube
    
    # Try to copy kubeconfig from control plane
    info "Attempting to copy kubeconfig from control plane ($CONTROL_PLANE_IP)"
    
    # Use scp to copy the admin.conf from control plane
    if scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
           "root@${CONTROL_PLANE_IP}:${KUBECONFIG_SOURCE}" \
           "/root/.kube/config" 2>/dev/null; then
        info "✓ Successfully copied kubeconfig from control plane"
    else
        warn "Failed to copy kubeconfig via scp, trying alternative method"
        
        # Alternative: create a basic kubeconfig manually
        create_manual_kubeconfig
    fi
    
    # Set proper permissions
    chmod 600 /root/.kube/config
    chown root:root /root/.kube/config
    
    # Also set up for current user if not root
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        local user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        if [ -n "$user_home" ] && [ -d "$user_home" ]; then
            mkdir -p "$user_home/.kube"
            cp /root/.kube/config "$user_home/.kube/config"
            chown "$SUDO_USER:$SUDO_USER" "$user_home/.kube/config"
            chmod 600 "$user_home/.kube/config"
            info "✓ Also configured kubectl for user $SUDO_USER"
        fi
    fi
}

# Function to create manual kubeconfig
create_manual_kubeconfig() {
    warn "Creating manual kubeconfig configuration"
    
    # Get cluster CA certificate and token from the existing kubelet config if available
    local kubelet_config="/var/lib/kubelet/config.yaml"
    local ca_file="/var/lib/kubelet/pki/kubelet-client-ca.crt"
    
    if [ ! -f "$ca_file" ]; then
        ca_file="/etc/kubernetes/pki/ca.crt"
    fi
    
    if [ -f "$ca_file" ]; then
        # Read CA data
        local ca_data=$(base64 -w 0 "$ca_file")
        
        # Create basic kubeconfig
        cat > /root/.kube/config << EOF
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $ca_data
    server: https://${CONTROL_PLANE_IP}:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubernetes-admin
  name: kubernetes-admin@kubernetes
current-context: kubernetes-admin@kubernetes
kind: Config
preferences: {}
users:
- name: kubernetes-admin
  user:
    client-certificate-data: 
    client-key-data: 
EOF
        warn "Created basic kubeconfig - you may need to add client certificates"
        warn "For full functionality, copy the complete admin.conf from the control plane"
    else
        error "Cannot find CA certificate file to create kubeconfig"
        return 1
    fi
}

# Function to validate kubectl configuration
validate_kubectl_config() {
    info "Validating kubectl configuration"
    
    # Set KUBECONFIG environment variable
    export KUBECONFIG=/root/.kube/config
    
    # Test basic connectivity
    if timeout 10 kubectl version --client >/dev/null 2>&1; then
        info "✓ kubectl client is working"
    else
        error "✗ kubectl client test failed"
        return 1
    fi
    
    # Test cluster connectivity
    if timeout 15 kubectl get nodes >/dev/null 2>&1; then
        info "✓ kubectl can connect to cluster"
        
        # Show current node information
        echo "Current cluster nodes:"
        kubectl get nodes -o wide 2>/dev/null || true
        
        return 0
    else
        warn "✗ kubectl cannot connect to cluster"
        echo "This may be due to:"
        echo "  1. Network connectivity issues to control plane"
        echo "  2. Missing client certificates in kubeconfig"
        echo "  3. Control plane API server not accessible"
        
        # Show what's in the kubeconfig for debugging
        if [ -f /root/.kube/config ]; then
            echo "Current kubeconfig server:"
            grep "server:" /root/.kube/config || true
        fi
        
        return 1
    fi
}

# Function to fix kubectl for multiple users
setup_kubectl_for_all_users() {
    info "Setting up kubectl for all relevant users"
    
    # List of common users that might need kubectl access
    local users=("ubuntu" "centos" "ec2-user" "admin")
    
    for user in "${users[@]}"; do
        if id "$user" >/dev/null 2>&1; then
            local user_home=$(getent passwd "$user" | cut -d: -f6)
            if [ -d "$user_home" ]; then
                info "Setting up kubectl for user: $user"
                
                sudo -u "$user" mkdir -p "$user_home/.kube"
                cp /root/.kube/config "$user_home/.kube/config"
                chown "$user:$user" "$user_home/.kube/config"
                chmod 600 "$user_home/.kube/config"
                
                debug "✓ kubectl configured for $user"
            fi
        fi
    done
}

# Main execution
main() {
    # Detect if this is control plane or worker node
    if detect_node_role; then
        info "Running on control plane node - kubectl should already be configured"
        
        # Validate existing configuration
        export KUBECONFIG="$KUBECONFIG_SOURCE"
        if validate_kubectl_config; then
            info "✓ Control plane kubectl configuration is working"
        else
            warn "Control plane kubectl configuration has issues"
        fi
        
        # Still set up for other users
        if [ -f "$KUBECONFIG_SOURCE" ]; then
            mkdir -p /root/.kube
            cp "$KUBECONFIG_SOURCE" /root/.kube/config
            chmod 600 /root/.kube/config
            setup_kubectl_for_all_users
        fi
    else
        info "Running on worker node - setting up kubectl configuration"
        
        # Setup kubectl for worker node
        setup_worker_kubeconfig
        
        # Validate the configuration
        if validate_kubectl_config; then
            info "✓ Worker node kubectl configuration successful"
            setup_kubectl_for_all_users
        else
            error "Worker node kubectl configuration failed"
            
            echo
            echo "Manual setup required:"
            echo "1. Copy /etc/kubernetes/admin.conf from control plane to /root/.kube/config"
            echo "2. Or run: scp root@${CONTROL_PLANE_IP}:/etc/kubernetes/admin.conf /root/.kube/config"
            echo "3. Set permissions: chmod 600 /root/.kube/config"
            
            exit 1
        fi
    fi
    
    echo
    info "kubectl configuration setup complete!"
    echo
    echo "To use kubectl, ensure your KUBECONFIG is set:"
    echo "  export KUBECONFIG=/root/.kube/config"
    echo "  # or for regular users:"
    echo "  export KUBECONFIG=\$HOME/.kube/config"
}

# Run main function
main "$@"
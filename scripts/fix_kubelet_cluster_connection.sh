#!/bin/bash

# VMStation Kubelet Cluster Connection Fix
# Addresses kubelet running in standalone mode instead of cluster mode

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

echo "=== VMStation Kubelet Cluster Connection Fix ==="
echo "Timestamp: $(date)"
echo ""

# Function to check if kubelet is in standalone mode
check_kubelet_mode() {
    info "Checking kubelet operational mode..."
    
    # Check kubelet logs for standalone mode indicators
    if journalctl -u kubelet --no-pager -n 50 | grep -q "Standalone mode"; then
        warn "kubelet is running in standalone mode"
        warn "This means it's not connected to a Kubernetes cluster API server"
        return 1
    elif journalctl -u kubelet --no-pager -n 50 | grep -q "Started kubelet"; then
        if journalctl -u kubelet --no-pager -n 50 | grep -q "No API server defined"; then
            warn "kubelet started but no API server connection configured"
            return 1
        else
            info "✓ kubelet appears to be in cluster mode"
            return 0
        fi
    else
        warn "kubelet status unclear from logs"
        return 1
    fi
}

# Function to check for proper cluster configuration files
check_cluster_config_files() {
    info "Checking cluster configuration files..."
    
    local config_issues=0
    
    # Check for kubelet cluster configuration
    if [ -f /etc/kubernetes/kubelet.conf ]; then
        info "✓ kubelet cluster config exists: /etc/kubernetes/kubelet.conf"
        
        # Verify it has proper API server configuration
        if grep -q "server:" /etc/kubernetes/kubelet.conf; then
            local api_server
            api_server=$(grep "server:" /etc/kubernetes/kubelet.conf | awk '{print $2}')
            info "✓ API server configured: $api_server"
        else
            warn "kubelet.conf exists but missing API server configuration"
            ((config_issues++))
        fi
    else
        warn "Missing kubelet cluster config: /etc/kubernetes/kubelet.conf"
        warn "This indicates the node has not been properly joined to the cluster"
        ((config_issues++))
    fi
    
    # Check for kubelet systemd configuration
    if [ -f /etc/systemd/system/kubelet.service.d/10-kubeadm.conf ]; then
        info "✓ kubelet systemd config exists"
        
        # Check if it's trying to use bootstrap config (which shouldn't be there after join)
        if grep -q "bootstrap-kubeconfig" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf; then
            if [ -f /etc/kubernetes/kubelet.conf ]; then
                warn "kubelet systemd config still references bootstrap config but cluster config exists"
                warn "This may cause the standalone mode issue"
                ((config_issues++))
            fi
        fi
    else
        warn "Missing kubelet systemd config: /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"
        ((config_issues++))
    fi
    
    return $config_issues
}

# Function to fix kubelet systemd configuration
fix_kubelet_systemd_config() {
    info "Fixing kubelet systemd configuration..."
    
    # Create kubelet systemd directory if it doesn't exist
    mkdir -p /etc/systemd/system/kubelet.service.d
    
    # Check if node has been joined (kubelet.conf exists)
    if [ -f /etc/kubernetes/kubelet.conf ]; then
        info "Node appears to be joined - creating post-join kubelet config"
        
        # Create a clean kubelet systemd config for joined nodes
        cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf << 'EOF'
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF
        
        info "✓ Created post-join kubelet systemd configuration"
        
    else
        info "Node not joined yet - creating pre-join kubelet config"
        
        # Create a basic kubelet systemd config for nodes that haven't joined yet
        cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf << 'EOF'
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF
        
        info "✓ Created pre-join kubelet systemd configuration"
        warn "Note: kubelet will still be in standalone mode until the node is joined to a cluster"
    fi
    
    # Reload systemd and restart kubelet
    systemctl daemon-reload
    
    info "Restarting kubelet service..."
    systemctl restart kubelet
    
    # Wait for kubelet to start
    sleep 5
    
    if systemctl is-active kubelet >/dev/null 2>&1; then
        info "✓ kubelet service restarted successfully"
    else
        error "Failed to restart kubelet service"
        systemctl status kubelet --no-pager
        return 1
    fi
}

# Function to check master node vs worker node
check_node_type() {
    info "Determining node type..."
    
    if [ -f /etc/kubernetes/admin.conf ]; then
        info "✓ This is a MASTER node (admin.conf exists)"
        
        # Check if cluster is initialized
        export KUBECONFIG=/etc/kubernetes/admin.conf
        if kubectl get nodes >/dev/null 2>&1; then
            info "✓ Cluster is initialized and accessible"
            kubectl get nodes -o wide
        else
            warn "admin.conf exists but cluster is not accessible"
        fi
        
        return 0
    elif [ -f /etc/kubernetes/kubelet.conf ]; then
        info "✓ This is a WORKER node (kubelet.conf exists, no admin.conf)"
        
        # Check if we can reach the API server
        local api_server
        api_server=$(grep "server:" /etc/kubernetes/kubelet.conf | awk '{print $2}')
        info "Configured API server: $api_server"
        
        if curl -k --connect-timeout 5 "$api_server/healthz" >/dev/null 2>&1; then
            info "✓ Can reach API server"
        else
            warn "Cannot reach API server - network or firewall issue?"
        fi
        
        return 0
    else
        warn "This node is NOT JOINED to any cluster (no kubelet.conf or admin.conf)"
        warn "To join this node to a cluster, run:"
        warn "  kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>"
        return 1
    fi
}

# Function to show diagnostics
show_diagnostics() {
    info "Kubelet diagnostics:"
    echo ""
    
    debug "Recent kubelet logs:"
    journalctl -u kubelet --no-pager -n 20 2>/dev/null || true
    echo ""
    
    debug "Kubelet systemd configuration:"
    if [ -f /etc/systemd/system/kubelet.service.d/10-kubeadm.conf ]; then
        cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    else
        echo "No kubelet systemd configuration found"
    fi
    echo ""
    
    debug "Container runtime connection test:"
    crictl version 2>&1 || true
    echo ""
}

# Main execution
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (try: sudo $0)"
        exit 1
    fi
    
    info "Analyzing kubelet cluster connection..."
    
    # Show current diagnostics
    show_diagnostics
    
    # Check current kubelet mode
    if check_kubelet_mode; then
        info "✓ kubelet is already in cluster mode"
    else
        info "kubelet is in standalone mode - analyzing configuration..."
        
        # Check configuration files
        if check_cluster_config_files; then
            info "Configuration files appear correct"
        else
            warn "Found configuration issues"
        fi
        
        # Determine node type and status
        check_node_type
        
        # Attempt to fix kubelet configuration
        info "Attempting to fix kubelet systemd configuration..."
        if fix_kubelet_systemd_config; then
            info "✓ kubelet configuration fixed"
            
            # Check if kubelet mode improved
            sleep 10
            if check_kubelet_mode; then
                info "✓ SUCCESS: kubelet is now in cluster mode!"
            else
                warn "kubelet still in standalone mode - may need cluster join"
            fi
        else
            error "Failed to fix kubelet configuration"
            exit 1
        fi
    fi
    
    echo ""
    info "Kubelet cluster connection fix completed!"
    
    echo ""
    info "Current status:"
    systemctl status kubelet --no-pager -l | head -5 || true
    
    echo ""
    info "If kubelet is still in standalone mode, the node may need to be joined to a cluster:"
    info "1. On master node, generate join command: kubeadm token create --print-join-command"
    info "2. Run the join command on this worker node"
    info "3. Restart kubelet: systemctl restart kubelet"
}

# Run main function
main "$@"
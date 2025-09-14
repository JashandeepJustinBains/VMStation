#!/bin/bash

# VMStation CNI Bridge Reset Script
# Fixes CNI bridge IP conflicts that prevent pod creation

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "=== VMStation CNI Bridge Reset ==="
echo "Timestamp: $(date)"
echo "Purpose: Fix CNI bridge IP conflicts preventing pod creation"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
    exit 1
fi

# Function to reset CNI bridge on a node
reset_cni_bridge() {
    local node_ip="$1"
    local node_name="$2"
    
    info "Resetting CNI bridge on $node_name ($node_ip)..."
    
    # Check if we're running locally or need SSH
    local current_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1 | awk '{print $7; exit}')
    
    if [[ "$current_ip" == "$node_ip"* ]] || [ "$node_ip" = "127.0.0.1" ] || [ "$node_ip" = "localhost" ]; then
        info "Resetting CNI bridge locally on $node_name"
        reset_local_cni_bridge
    else
        info "Resetting CNI bridge remotely on $node_name ($node_ip)"
        reset_remote_cni_bridge "$node_ip"
    fi
}

# Function to reset CNI bridge locally
reset_local_cni_bridge() {
    info "Stopping kubelet to safely reset CNI bridge..."
    systemctl stop kubelet || warn "Failed to stop kubelet (may not be running)"
    
    # Kill any lingering container processes that might hold the bridge
    info "Stopping container processes..."
    pkill -f containerd-shim || true
    pkill -f runc || true
    
    sleep 5
    
    # Check current CNI bridge status
    if ip link show cni0 >/dev/null 2>&1; then
        local current_ip=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
        info "Current CNI bridge IP: ${current_ip:-none}"
        
        # Check if it's in the wrong subnet
        if [ -n "$current_ip" ] && ! echo "$current_ip" | grep -q "10.244."; then
            warn "CNI bridge has wrong IP ($current_ip), needs reset"
            
            # Delete the bridge completely
            info "Deleting existing CNI bridge..."
            ip link delete cni0 || warn "Failed to delete cni0 (may not exist)"
        else
            info "CNI bridge IP looks correct: $current_ip"
        fi
    else
        info "No existing CNI bridge found"
    fi
    
    # Clean up any conflicting CNI configuration
    info "Cleaning CNI configuration..."
    rm -f /etc/cni/net.d/100-crio-bridge.conf || true
    rm -f /etc/cni/net.d/200-loopback.conf || true
    rm -f /etc/cni/net.d/87-podman-bridge.conflist || true
    
    # Ensure flannel config exists
    if [ ! -f /etc/cni/net.d/10-flannel.conflist ]; then
        warn "Flannel CNI config missing, will be restored by flannel pod"
    fi
    
    # Clear iptables NAT rules that might conflict
    info "Clearing potential conflicting iptables rules..."
    iptables -t nat -F POSTROUTING || true
    iptables -t nat -F PREROUTING || true
    iptables -t filter -F FORWARD || true
    
    # Restart containerd to clear any cached network state
    info "Restarting containerd..."
    systemctl restart containerd
    sleep 5
    
    # Start kubelet
    info "Starting kubelet..."
    systemctl start kubelet
    
    # Wait for kubelet to be ready
    info "Waiting for kubelet to be ready..."
    sleep 10
    
    success "CNI bridge reset completed on local node"
}

# Function to reset CNI bridge on remote node
reset_remote_cni_bridge() {
    local node_ip="$1"
    
    # Determine SSH user based on node IP
    local ssh_user="root"
    case "$node_ip" in
        "192.168.4.62")  # homelab node
            ssh_user="jashandeepjustinbains"
            ;;
        "192.168.4.61"|"192.168.4.63")  # storage/master nodes
            ssh_user="root"
            ;;
    esac
    
    info "Connecting to $ssh_user@$node_ip..."
    
    # Copy this script to remote node and execute
    local remote_script="/tmp/reset_cni_bridge_local.sh"
    
    # Create a simplified version for remote execution
    cat > /tmp/reset_cni_bridge_remote.sh << 'EOF'
#!/bin/bash
echo "=== Remote CNI Bridge Reset ==="
systemctl stop kubelet || true
pkill -f containerd-shim || true
pkill -f runc || true
sleep 5

if ip link show cni0 >/dev/null 2>&1; then
    current_ip=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
    echo "Current CNI bridge IP: ${current_ip:-none}"
    
    if [ -n "$current_ip" ] && ! echo "$current_ip" | grep -q "10.244."; then
        echo "Deleting CNI bridge with wrong IP: $current_ip"
        ip link delete cni0 || true
    fi
else
    echo "No existing CNI bridge found"
fi

# Clean up CNI configs
rm -f /etc/cni/net.d/100-crio-bridge.conf || true
rm -f /etc/cni/net.d/200-loopback.conf || true
rm -f /etc/cni/net.d/87-podman-bridge.conflist || true

# Clear iptables
iptables -t nat -F POSTROUTING || true
iptables -t nat -F PREROUTING || true
iptables -t filter -F FORWARD || true

# Restart services
systemctl restart containerd
sleep 5
systemctl start kubelet
sleep 10

echo "Remote CNI bridge reset completed"
EOF
    
    chmod +x /tmp/reset_cni_bridge_remote.sh
    
    if scp /tmp/reset_cni_bridge_remote.sh $ssh_user@$node_ip:$remote_script; then
        ssh $ssh_user@$node_ip "chmod +x $remote_script && sudo $remote_script"
        ssh $ssh_user@$node_ip "rm -f $remote_script" || true
        success "CNI bridge reset completed on $node_ip"
    else
        error "Failed to copy reset script to $node_ip"
        return 1
    fi
    
    rm -f /tmp/reset_cni_bridge_remote.sh
}

# Main execution
main() {
    # Define node information
    local nodes=(
        "192.168.4.63:masternode"
        "192.168.4.61:storagenodet3500" 
        "192.168.4.62:homelab"
    )
    
    info "Will reset CNI bridge on ${#nodes[@]} nodes..."
    
    for node_entry in "${nodes[@]}"; do
        IFS=':' read -r node_ip node_name <<< "$node_entry"
        echo ""
        reset_cni_bridge "$node_ip" "$node_name"
    done
    
    echo ""
    success "=== CNI Bridge Reset Complete ==="
    info "All nodes have been processed"
    info "Flannel pods should now be able to create proper CNI bridges"
    info "Wait 30-60 seconds for flannel pods to restart and configure bridges"
    
    # Wait a bit and check the results
    sleep 30
    
    info "Checking CNI bridge status after reset..."
    if command -v kubectl >/dev/null 2>&1; then
        info "Checking flannel pod status..."
        kubectl get pods -n kube-flannel || warn "Could not check flannel pods"
        
        info "Checking for recent CNI bridge errors..."
        recent_errors=$(kubectl get events --all-namespaces --field-selector reason=FailedCreatePodSandBox 2>/dev/null | grep "failed to set bridge addr.*already has an IP address different" | wc -l || echo "0")
        
        if [ "$recent_errors" -eq 0 ]; then
            success "No recent CNI bridge errors detected!"
        else
            warn "Still seeing $recent_errors recent CNI bridge errors - may need additional time"
        fi
    fi
}

# Run main function
main "$@"
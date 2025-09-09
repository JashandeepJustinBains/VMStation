#!/bin/bash

# VMStation Kubeadm Join Command Generator
# Generates the exact join command for worker nodes as recommended in problem statement

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=== VMStation Kubeadm Join Command Generator ==="
echo "Timestamp: $(date)"
echo ""

# Check if running on control plane
if [ ! -f "/etc/kubernetes/admin.conf" ]; then
    error "This script must be run on the Kubernetes control plane node"
    error "Expected file: /etc/kubernetes/admin.conf"
    exit 1
fi

info "Running on control plane node - generating join command..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl not found. Please ensure kubectl is installed and configured."
    exit 1
fi

if ! command -v kubeadm &> /dev/null; then
    error "kubeadm not found. Please ensure kubeadm is installed."
    exit 1
fi

echo ""
info "Generating fresh join token and command..."

# Generate the join command
JOIN_COMMAND=$(kubeadm token create --print-join-command 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$JOIN_COMMAND" ]; then
    success "Join command generated successfully!"
    echo ""
    echo "=== WORKER NODE JOIN COMMAND ==="
    echo "Run this command on each worker node as root:"
    echo ""
    echo -e "${GREEN}sudo $JOIN_COMMAND${NC}"
    echo ""
    
    # Extract the control plane IP for reference
    CONTROL_PLANE_IP=$(echo "$JOIN_COMMAND" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
    
    info "Control plane IP: $CONTROL_PLANE_IP"
    info "Worker nodes should be able to reach this IP on port 6443"
    echo ""
    
    echo "=== STEP-BY-STEP PROCEDURE ==="
    echo ""
    echo "1. ON WORKER NODE: Run the join command above as root"
    echo ""
    echo "2. ON CONTROL PLANE: Check for pending CSRs and approve them"
    echo "   kubectl get csr"
    echo "   kubectl certificate approve <CSR_NAME>"
    echo ""
    echo "3. ON WORKER NODE: Restart kubelet service"
    echo "   sudo systemctl restart kubelet"
    echo ""
    echo "4. ON CONTROL PLANE: Verify node joined successfully"
    echo "   kubectl get nodes -o wide"
    echo ""
    
    # Check current cluster status
    echo "=== CURRENT CLUSTER STATUS ==="
    kubectl get nodes -o wide 2>/dev/null || echo "Could not retrieve node status"
    echo ""
    
    # Check for pending CSRs
    echo "=== PENDING CERTIFICATE SIGNING REQUESTS ==="
    PENDING_CSRS=$(kubectl get csr --no-headers 2>/dev/null | grep "Pending" || true)
    if [ -n "$PENDING_CSRS" ]; then
        warn "Found pending CSRs - approve them after worker joins:"
        echo "$PENDING_CSRS"
        echo ""
        echo "To approve all pending CSRs:"
        echo "kubectl certificate approve \$(kubectl get csr -o name --no-headers | grep -E 'Pending')"
    else
        info "No pending CSRs currently"
    fi
    
    echo ""
    echo "=== TROUBLESHOOTING ==="
    echo "If worker node join fails, run the troubleshooting script:"
    echo "sudo ./troubleshoot_kubelet_join.sh"
    echo ""
    echo "Common issues:"
    echo "- Missing /etc/kubernetes/kubelet.conf (resolved by proper join)"
    echo "- Missing /var/lib/kubelet/config.yaml (resolved by proper join)" 
    echo "- Deprecated --network-plugin flags (remove from /var/lib/kubelet/kubeadm-flags.env)"
    echo "- Network connectivity (ensure port 6443 is accessible)"
    
else
    error "Failed to generate join command"
    error "Please check that:"
    error "1. This is a properly initialized control plane node"
    error "2. kubeadm is working correctly"
    error "3. The cluster is in a healthy state"
    exit 1
fi
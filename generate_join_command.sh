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

# Validate certificates before generating join command
info "Validating control plane certificates..."

# Check API server certificate
if [ ! -f "/etc/kubernetes/pki/apiserver.crt" ]; then
    error "API server certificate not found at /etc/kubernetes/pki/apiserver.crt"
    exit 1
fi

if ! openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -checkend 86400 >/dev/null 2>&1; then
    error "API server certificate expires within 24 hours"
    error "Run: kubeadm certs renew apiserver"
    exit 1
fi

# Check CA certificate
if [ ! -f "/etc/kubernetes/pki/ca.crt" ]; then
    error "CA certificate not found at /etc/kubernetes/pki/ca.crt"
    exit 1
fi

if ! openssl x509 -in /etc/kubernetes/pki/ca.crt -noout -checkend 86400 >/dev/null 2>&1; then
    error "CA certificate expires within 24 hours"
    error "This requires cluster recovery - consult Kubernetes documentation"
    exit 1
fi

success "✓ Certificates are valid and ready for worker joins"

# Generate the join command
JOIN_COMMAND=$(kubeadm token create --print-join-command 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$JOIN_COMMAND" ]; then
    success "Join command generated successfully!"
    
    # Validate the generated join command contains proper certificate hash
    CA_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //')
    if [[ "$JOIN_COMMAND" == *"sha256:$CA_HASH"* ]]; then
        success "✓ Join command contains correct CA certificate hash"
    else
        warn "⚠ Join command CA hash may not match current CA certificate"
        warn "Expected: sha256:$CA_HASH"
        warn "Generated: $(echo "$JOIN_COMMAND" | grep -o 'sha256:[a-f0-9]\{64\}')"
    fi
    
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
    
    # Test API server accessibility
    info "Testing API server accessibility..."
    if timeout 5 bash -c "</dev/tcp/$CONTROL_PLANE_IP/6443" 2>/dev/null; then
        success "✓ API server port 6443 is accessible"
    else
        warn "⚠ API server port 6443 may not be accessible from this host"
        warn "Ensure firewall allows access to port 6443"
    fi
    
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
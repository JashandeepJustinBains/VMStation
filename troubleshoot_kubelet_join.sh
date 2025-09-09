#!/bin/bash

# VMStation Kubelet Join Troubleshooting Script
# Helps diagnose and fix worker node join issues per problem statement

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo "=== VMStation Kubelet Join Troubleshooting ==="
echo "Timestamp: $(date)"
echo ""

info "This script addresses the key kubelet join issues identified:"
info "- Missing /etc/kubernetes/kubelet.conf"
info "- Missing /var/lib/kubelet/config.yaml"
info "- Deprecated kubelet flags"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "This script must be run as root for kubelet configuration access"
    echo "Usage: sudo $0"
    exit 1
fi

# Detect node role
if [ -f "/etc/kubernetes/admin.conf" ]; then
    NODE_ROLE="control-plane"
    info "Detected control plane node"
else
    NODE_ROLE="worker"
    info "Detected worker node"
fi

echo ""
echo "=== Diagnostic Checks ==="

# 1. Check kubelet status
info "1. Checking kubelet service status..."
if systemctl is-active --quiet kubelet; then
    success "kubelet service is running"
else
    warn "kubelet service is not running"
    systemctl status kubelet --no-pager || true
fi

# 2. Check for missing kubelet.conf
info "2. Checking for kubelet.conf..."
if [ -f "/etc/kubernetes/kubelet.conf" ]; then
    success "kubelet.conf exists"
else
    error "kubelet.conf is missing - this is the primary issue!"
    echo "  Location: /etc/kubernetes/kubelet.conf"
fi

# 3. Check for missing config.yaml
info "3. Checking for kubelet config.yaml..."
if [ -f "/var/lib/kubelet/config.yaml" ]; then
    success "kubelet config.yaml exists"
else
    error "kubelet config.yaml is missing"
    echo "  Location: /var/lib/kubelet/config.yaml"
fi

# 4. Check containerd
info "4. Checking containerd status..."
if systemctl is-active --quiet containerd; then
    success "containerd is running"
else
    error "containerd is not running"
    systemctl status containerd --no-pager || true
fi

# 5. Check for deprecated flags
info "5. Checking for deprecated kubelet flags..."
DEPRECATED_FLAGS=false

if [ -f "/var/lib/kubelet/kubeadm-flags.env" ]; then
    if grep -q "network-plugin" "/var/lib/kubelet/kubeadm-flags.env"; then
        error "Found deprecated --network-plugin flag in kubeadm-flags.env"
        DEPRECATED_FLAGS=true
    fi
fi

if [ -f "/etc/sysconfig/kubelet" ]; then
    if grep -q "network-plugin" "/etc/sysconfig/kubelet"; then
        error "Found deprecated --network-plugin flag in /etc/sysconfig/kubelet"
        DEPRECATED_FLAGS=true
    fi
fi

if [ "$DEPRECATED_FLAGS" = false ]; then
    success "No deprecated flags detected"
fi

echo ""
echo "=== Recommended Fixes ==="

if [ "$NODE_ROLE" = "control-plane" ]; then
    info "Control plane node - Generate join command for worker nodes:"
    echo ""
    echo "  kubeadm token create --print-join-command"
    echo ""
    
    info "Check and approve pending CSRs:"
    echo ""
    echo "  kubectl get csr"
    echo "  kubectl certificate approve <CSR_NAME>"
    echo ""
    
else
    # Worker node fixes
    if [ ! -f "/etc/kubernetes/kubelet.conf" ] || [ ! -f "/var/lib/kubelet/config.yaml" ]; then
        warn "Worker node missing kubelet configuration - rejoin required"
        echo ""
        info "RECOMMENDED FIX 1: Proper kubeadm join (preferred method)"
        echo "1. On control plane, run: kubeadm token create --print-join-command"
        echo "2. On this worker node, run the join command as root:"
        echo "   sudo kubeadm join <CONTROL_PLANE>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>"
        echo "3. Back on control plane, check for and approve CSRs:"
        echo "   kubectl get csr"
        echo "   kubectl certificate approve <CSR_NAME>"
        echo "4. Restart kubelet: sudo systemctl restart kubelet"
        echo ""
        
        info "ALTERNATIVE FIX 2: Quick bootstrap (temporary)"
        echo "1. Copy bootstrap config from control plane:"
        echo "   sudo mkdir -p /etc/kubernetes"
        echo "   sudo scp root@<CONTROL_PLANE>:/etc/kubernetes/bootstrap-kubelet.conf /etc/kubernetes/"
        echo "   sudo chown root:root /etc/kubernetes/bootstrap-kubelet.conf"
        echo "   sudo chmod 600 /etc/kubernetes/bootstrap-kubelet.conf"
        echo "2. Restart kubelet: sudo systemctl restart kubelet"
        echo "3. On control plane, approve the CSR when it appears"
        echo ""
        
        warn "EMERGENCY FIX 3: Copy kubelet.conf (NOT RECOMMENDED - security risk)"
        echo "Only for testing - revert to proper join later:"
        echo "   sudo scp root@<CONTROL_PLANE>:/etc/kubernetes/kubelet.conf /etc/kubernetes/"
        echo "   sudo chown root:root /etc/kubernetes/kubelet.conf"
        echo "   sudo chmod 600 /etc/kubernetes/kubelet.conf"
        echo "   sudo systemctl restart kubelet"
        echo ""
    fi
    
    if [ "$DEPRECATED_FLAGS" = true ]; then
        info "Fix deprecated flags:"
        echo "1. Backup current configuration:"
        echo "   sudo cp /var/lib/kubelet/kubeadm-flags.env{,.bak}"
        echo "2. Remove deprecated --network-plugin flag:"
        echo "   sudo sed -i -E 's/(^| )--network-plugin(=[^ ]+)?( |\$)/ /g' /var/lib/kubelet/kubeadm-flags.env"
        echo "3. Restart kubelet:"
        echo "   sudo systemctl daemon-reload && sudo systemctl restart kubelet"
        echo ""
    fi
fi

# 6. Show current kubelet logs
echo ""
info "Recent kubelet logs (last 20 lines):"
journalctl -u kubelet -n 20 --no-pager || true

echo ""
echo "=== Verification Commands ==="
info "Run these after applying fixes:"
echo "  sudo systemctl status kubelet"
echo "  sudo journalctl -u kubelet -f"
echo "  ls -l /run/containerd/containerd.sock"

if [ "$NODE_ROLE" = "control-plane" ]; then
    echo "  kubectl get nodes -o wide"
    echo "  kubectl get csr"
fi

echo ""
info "For more details, see: TODO.md section 'Troubleshooting Worker Nodes'"
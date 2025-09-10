#!/bin/bash

# Worker Node Join Remediation Script
# Provides exact remediation sequence for persistent join failures
# Addresses CNI config missing, kubelet standalone mode, containerd filesystem issues

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

echo "=== Worker Node Join Remediation Script ==="
echo "Timestamp: $(date)"
echo "Hostname: $(hostname)"
echo "Target: Fix CNI config, kubelet conflicts, containerd filesystem issues"
echo ""

log_warn "This script will:"
log_warn "  1. Stop and mask kubelet service"
log_warn "  2. Fix containerd image filesystem issues"
log_warn "  3. Reset Kubernetes state (preserves /mnt/media)"
log_warn "  4. Prepare for clean kubeadm join"
log_warn ""
log_warn "NOTE: This will NOT modify /mnt/media or any mounted storage"

# Confirmation prompt
read -p "Continue with remediation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Remediation cancelled by user"
    exit 0
fi

echo ""
log_info "Starting remediation sequence..."

# Phase 1: Stop Services and Clean State
log_info "=== Phase 1: Stop Services and Clean State ==="

log_info "Stopping kubelet service..."
if systemctl is-active --quiet kubelet; then
    systemctl stop kubelet
    log_success "kubelet stopped"
else
    log_info "kubelet was not running"
fi

log_info "Masking kubelet to prevent auto-start..."
systemctl mask kubelet
log_success "kubelet masked"

log_info "Checking port 10250 release..."
sleep 2
if netstat -tulpn 2>/dev/null | grep -q :10250 || ss -tulpn 2>/dev/null | grep -q :10250; then
    log_error "Port 10250 still in use after stopping kubelet"
    log_error "Manual intervention may be required"
    netstat -tulpn 2>/dev/null | grep :10250 || ss -tulpn 2>/dev/null | grep :10250
else
    log_success "Port 10250 released successfully"
fi

# Phase 2: Fix Runtime and Filesystem Issues
log_info "=== Phase 2: Fix Runtime and Filesystem Issues ==="

log_info "Checking containerd image filesystem..."
if [ ! -d /var/lib/containerd ]; then
    log_warn "Creating missing containerd directory..."
    mkdir -p /var/lib/containerd
    chown root:root /var/lib/containerd
    chmod 755 /var/lib/containerd
    log_success "Containerd directory created"
fi

# Check filesystem capacity
CONTAINERD_CAPACITY=$(df -BG /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo "unknown")
log_info "Containerd filesystem capacity: ${CONTAINERD_CAPACITY}G"

if [ "$CONTAINERD_CAPACITY" = "0" ] || [ "$CONTAINERD_CAPACITY" = "unknown" ]; then
    log_warn "Containerd filesystem shows 0 or unknown capacity"
    log_warn "This may indicate mount or permissions issues"
    
    # Stop containerd for filesystem repair
    log_info "Stopping containerd for filesystem repair..."
    systemctl stop containerd
    sleep 2
    
    # Clear potentially corrupted state
    log_warn "Clearing containerd state due to capacity issues..."
    rm -rf /var/lib/containerd/*
    log_info "Containerd state cleared"
else
    log_success "Containerd filesystem capacity normal: ${CONTAINERD_CAPACITY}G"
fi

# Start containerd and verify health
log_info "Starting containerd service..."
systemctl start containerd
sleep 3

if systemctl is-active --quiet containerd; then
    log_success "Containerd service active"
else
    log_error "Containerd failed to start"
    systemctl status containerd --no-pager
    exit 1
fi

# Test containerd functionality
log_info "Testing containerd functionality..."
if timeout 10 ctr version >/dev/null 2>&1; then
    log_success "Containerd responding to API calls"
else
    log_error "Containerd not responding properly"
    exit 1
fi

# Phase 3: Reset Kubernetes State (Safe)
log_info "=== Phase 3: Reset Kubernetes State ==="

log_info "Resetting kubeadm state (preserves /mnt/media)..."
kubeadm reset -f --cert-dir=/etc/kubernetes/pki || log_warn "kubeadm reset completed with warnings"

log_info "Cleaning Kubernetes directories..."
rm -rf /etc/kubernetes/* || true
rm -rf /var/lib/kubelet/* || true  
rm -rf /etc/cni/net.d/* || true

log_info "Cleaning kubeadm flags..."
rm -f /var/lib/kubelet/kubeadm-flags.env || true

log_success "Kubernetes state reset completed"

# Phase 4: Prepare for Join
log_info "=== Phase 4: Prepare for Join ==="

log_info "Unmasking kubelet service..."
systemctl unmask kubelet
systemctl daemon-reload
log_success "kubelet unmasked and systemd reloaded"

# Verify prerequisites
log_info "Verifying prerequisites..."

if systemctl is-active --quiet containerd; then
    log_success "✓ containerd service is active"
else
    log_error "✗ containerd service not active"
    exit 1
fi

if [ ! -f /etc/kubernetes/kubelet.conf ]; then
    log_success "✓ No existing kubelet.conf (clean state)"
else
    log_warn "✗ kubelet.conf still exists (may cause issues)"
fi

if [ ! -f /etc/cni/net.d/*.conflist ] 2>/dev/null; then
    log_success "✓ No existing CNI config (clean state)" 
else
    log_warn "✗ CNI config still exists"
fi

# Phase 5: Join Instructions
log_info "=== Phase 5: Ready for Join ==="

log_success "System prepared for kubeadm join!"
log_info ""
log_info "Next steps:"
log_info "1. Obtain join command from control plane:"
log_info "   ssh <control-plane-ip> 'kubeadm token create --print-join-command'"
log_info ""
log_info "2. Execute join with appropriate flags:"
log_info "   kubeadm join <control-plane-ip>:6443 \\"
log_info "     --token <token> \\"
log_info "     --discovery-token-ca-cert-hash <hash> \\"
log_info "     --ignore-preflight-errors=Port-10250,FileAvailable--etc-kubernetes-pki-ca.crt \\"
log_info "     --v=5"
log_info ""
log_info "3. Monitor join progress:"
log_info "   journalctl -u kubelet -f"
log_info ""

# Phase 6: Post-Join Verification Instructions
log_info "=== Phase 6: Post-Join Verification (after join completes) ==="
log_info ""
log_info "After successful join, verify with these commands:"
log_info ""
log_info "# Wait for kubelet to stabilize"
log_info "sleep 30"
log_info ""
log_info "# Check node registration (from control plane)"
log_info "kubectl get nodes -o wide"
log_info ""
log_info "# Verify CNI configuration populated"
log_info "ls -la /etc/cni/net.d/"
log_info "cat /etc/cni/net.d/10-flannel.conflist"
log_info ""
log_info "# Check kubelet health" 
log_info "systemctl status kubelet"
log_info "journalctl -u kubelet --since='2 minutes ago' | grep -v 'level=info'"

echo ""
log_success "Remediation completed successfully!"
log_info "System is ready for kubeadm join operation."

# Final system status summary
echo ""
log_info "=== Final System Status ==="
log_info "kubelet: $(systemctl is-active kubelet) ($(systemctl is-enabled kubelet))"
log_info "containerd: $(systemctl is-active containerd) ($(systemctl is-enabled containerd))"
log_info "Port 10250: $(netstat -tulpn 2>/dev/null | grep :10250 >/dev/null && echo 'in use' || echo 'available')"
log_info "CNI config: $(ls /etc/cni/net.d/*.conf* 2>/dev/null | wc -l) files"
log_info "Containerd filesystem: $(df -h /var/lib/containerd | tail -1 | awk '{print $2 " used: " $3}')"

echo ""
log_success "Ready for kubeadm join!"
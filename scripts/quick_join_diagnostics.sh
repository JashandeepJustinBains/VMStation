#!/bin/bash

# Quick Join Diagnostics Script
# Rapidly identifies common causes of kubelet TLS Bootstrap failures

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

echo "=== Quick Kubernetes Join Diagnostics ==="
echo "Timestamp: $(date)"
echo "Hostname: $(hostname)"
echo "Target: Identify TLS Bootstrap failure causes"
echo ""

ISSUES_FOUND=0

# Check 1: Containerd filesystem capacity
info "1. Checking containerd filesystem capacity..."
CONTAINERD_CAPACITY=$(df -BG /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo "0")
if [ "$CONTAINERD_CAPACITY" = "0" ] || [ -z "$CONTAINERD_CAPACITY" ]; then
    error "✗ Containerd filesystem shows 0 capacity"
    error "  This causes 'invalid capacity 0 on image filesystem' errors"
    error "  Fix: Run worker_node_join_remediation.sh"
    ((ISSUES_FOUND++))
else
    info "✓ Containerd filesystem capacity: ${CONTAINERD_CAPACITY}G"
fi

# Check 2: API server connectivity
info "2. Checking API server connectivity..."
MASTER_IP="${1:-192.168.4.63}"
if timeout 5 bash -c "echo >/dev/tcp/$MASTER_IP/6443" 2>/dev/null; then
    info "✓ API server at $MASTER_IP:6443 is reachable"
else
    error "✗ Cannot connect to API server at $MASTER_IP:6443"
    error "  This prevents TLS Bootstrap token exchange"
    ((ISSUES_FOUND++))
fi

# Check 3: Kubelet service conflicts
info "3. Checking kubelet service configuration..."
if systemctl is-active kubelet >/dev/null 2>&1; then
    if journalctl -u kubelet --no-pager --since "5 minutes ago" | grep -q "standalone"; then
        warn "⚠ Kubelet is running but in standalone mode"
        warn "  This indicates previous failed join attempts"
        warn "  Fix: Reset kubelet state before retry"
        ((ISSUES_FOUND++))
    else
        info "✓ Kubelet is running and connected to cluster"
    fi
else
    info "✓ Kubelet is not running (expected before join)"
fi

# Check 4: CNI readiness
info "4. Checking CNI configuration readiness..."
if [ -d /etc/cni/net.d ] && [ -d /opt/cni/bin ]; then
    info "✓ CNI directories exist"
else
    warn "⚠ CNI directories missing"
    warn "  This may cause network readiness delays during join"
    warn "  Fix: Create /etc/cni/net.d and /opt/cni/bin directories"
    ((ISSUES_FOUND++))
fi

# Check 5: Previous join artifacts
info "5. Checking for stale join artifacts..."
STALE_FILES=""
[ -f /etc/kubernetes/kubelet.conf ] && STALE_FILES="$STALE_FILES kubelet.conf"
[ -f /etc/kubernetes/bootstrap-kubelet.conf ] && STALE_FILES="$STALE_FILES bootstrap-kubelet.conf"
[ -f /var/lib/kubelet/config.yaml ] && STALE_FILES="$STALE_FILES config.yaml"

if [ -n "$STALE_FILES" ]; then
    warn "⚠ Found stale join artifacts: $STALE_FILES"
    warn "  These may conflict with new join attempts"
    warn "  Fix: Clean up with kubeadm reset"
    ((ISSUES_FOUND++))
else
    info "✓ No stale join artifacts found"
fi

# Check 6: System load
info "6. Checking system load..."
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
if (( $(echo "$LOAD > 2.0" | bc -l 2>/dev/null || echo 0) )); then
    warn "⚠ High system load: $LOAD"
    warn "  This may slow TLS Bootstrap below 40s timeout"
    ((ISSUES_FOUND++))
else
    info "✓ System load acceptable: $LOAD"
fi

echo ""
echo "=== Diagnostic Summary ==="
if [ $ISSUES_FOUND -eq 0 ]; then
    info "✅ No obvious issues found - system appears ready for join"
    info "If join still fails, check kubelet logs during the process:"
    info "   journalctl -fu kubelet"
else
    error "❌ Found $ISSUES_FOUND potential issue(s)"
    error "Recommended actions:"
    error "1. Fix the issues identified above"
    error "2. Run kubeadm reset to clean up any stale state"
    error "3. Restart containerd service"
    error "4. Retry the join process"
fi

echo ""
info "For detailed analysis, also check:"
info "• systemctl status containerd"
info "• systemctl status kubelet" 
info "• journalctl -u kubelet -f (during join)"
info "• journalctl -u containerd"

exit $ISSUES_FOUND
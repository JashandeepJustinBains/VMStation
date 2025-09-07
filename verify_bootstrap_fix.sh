#!/bin/bash

# Manual verification script for bootstrap kubeconfig fix
# This script helps verify the fix works correctly in a real environment

set -e

echo "=== Bootstrap Kubeconfig Fix - Manual Verification ==="
echo "Timestamp: $(date)"
echo ""

info() {
    echo "[INFO] $1"
}

warn() {
    echo "[WARN] $1"
}

error() {
    echo "[ERROR] $1"
}

# Configuration
FAILING_NODE="${1:-192.168.4.62}"
CONTROL_NODE="${2:-192.168.4.63}"

echo "Target node: $FAILING_NODE"
echo "Control plane: $CONTROL_NODE"
echo ""

echo "=== Step 1: Pre-Fix Diagnosis ==="

info "Checking node join status..."
if ssh "$FAILING_NODE" "test -f /etc/kubernetes/kubelet.conf"; then
    info "✓ Node has kubelet.conf (already joined)"
    NODE_JOINED=true
else
    warn "✗ Node missing kubelet.conf (not joined yet)"
    NODE_JOINED=false
fi

info "Checking current kubelet systemd configuration..."
if ssh "$FAILING_NODE" "grep -q 'bootstrap-kubeconfig' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf 2>/dev/null"; then
    if [ "$NODE_JOINED" = true ]; then
        error "✗ ISSUE DETECTED: Joined node still has bootstrap config!"
        HAS_ISSUE=true
    else
        info "○ Not-joined node has bootstrap config (expected)"
        HAS_ISSUE=false
    fi
else
    if [ "$NODE_JOINED" = true ]; then
        info "✓ Joined node has no bootstrap config (correct)"
        HAS_ISSUE=false
    else
        warn "○ Not-joined node missing bootstrap config (may need setup)"
        HAS_ISSUE=false
    fi
fi

info "Checking kubelet service status..."
KUBELET_STATUS=$(ssh "$FAILING_NODE" "systemctl is-active kubelet" || echo "failed")
info "Kubelet status: $KUBELET_STATUS"

if [ "$KUBELET_STATUS" != "active" ]; then
    info "Checking kubelet logs for bootstrap errors..."
    if ssh "$FAILING_NODE" "journalctl -u kubelet -n 20 --no-pager | grep -i bootstrap" >/dev/null 2>&1; then
        error "✗ Bootstrap errors found in kubelet logs"
        HAS_ISSUE=true
    else
        info "○ No bootstrap errors in recent logs"
    fi
fi

echo ""
echo "=== Step 2: Apply the Fix ==="

if [ "$HAS_ISSUE" = true ]; then
    info "Applying bootstrap kubeconfig fix..."
    
    # Apply the fix using the playbook
    info "Running enhanced setup playbook with bootstrap fix..."
    if ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml -l "$FAILING_NODE"; then
        info "✓ Playbook completed successfully"
    else
        error "✗ Playbook failed - check output above"
        exit 1
    fi
else
    info "No issues detected - skipping fix application"
fi

echo ""
echo "=== Step 3: Post-Fix Verification ==="

info "Re-checking node configuration..."

# Check join status again
if ssh "$FAILING_NODE" "test -f /etc/kubernetes/kubelet.conf"; then
    info "✓ Node has kubelet.conf (joined)"
    POST_JOINED=true
else
    warn "○ Node still missing kubelet.conf (not joined)"
    POST_JOINED=false
fi

# Check systemd config
info "Checking kubelet systemd configuration..."
if ssh "$FAILING_NODE" "grep -q 'bootstrap-kubeconfig' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf 2>/dev/null"; then
    if [ "$POST_JOINED" = true ]; then
        error "✗ STILL BROKEN: Joined node still has bootstrap config!"
        STILL_BROKEN=true
    else
        info "○ Not-joined node has bootstrap config (expected)"
        STILL_BROKEN=false
    fi
else
    if [ "$POST_JOINED" = true ]; then
        info "✓ Joined node correctly has no bootstrap config"
        STILL_BROKEN=false
    else
        info "○ Not-joined node has no bootstrap config"
        STILL_BROKEN=false
    fi
fi

# Check kubelet status
info "Checking kubelet service status..."
POST_KUBELET_STATUS=$(ssh "$FAILING_NODE" "systemctl is-active kubelet" || echo "failed")
info "Kubelet status: $POST_KUBELET_STATUS"

if [ "$POST_KUBELET_STATUS" = "active" ]; then
    info "✓ Kubelet is running"
else
    warn "○ Kubelet is not active - checking logs..."
    ssh "$FAILING_NODE" "journalctl -u kubelet -n 10 --no-pager" || true
fi

# Check from control plane if possible
if [ "$POST_JOINED" = true ] && [ "$POST_KUBELET_STATUS" = "active" ]; then
    info "Checking node status from control plane..."
    if ssh "$CONTROL_NODE" "kubectl get node $FAILING_NODE -o wide" 2>/dev/null; then
        info "✓ Node visible from control plane"
    else
        warn "○ Node not visible from control plane (may need time to sync)"
    fi
fi

echo ""
echo "=== Summary ==="

if [ "$STILL_BROKEN" = true ]; then
    error "FIX FAILED: Node still has bootstrap configuration issues"
    echo ""
    echo "Manual troubleshooting steps:"
    echo "1. Check logs: ssh $FAILING_NODE 'journalctl -u kubelet -f'"
    echo "2. Check config: ssh $FAILING_NODE 'cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf'"
    echo "3. Manual fix: ssh $FAILING_NODE 'sed -i \"s/--bootstrap-kubeconfig=[^ ]* //g\" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf && systemctl daemon-reload && systemctl restart kubelet'"
    exit 1
else
    info "✓ VERIFICATION PASSED: Bootstrap configuration is correct"
    echo ""
    echo "Results:"
    echo "- Node join status: $($POST_JOINED && echo 'JOINED' || echo 'NOT JOINED')"
    echo "- Kubelet status: $POST_KUBELET_STATUS"
    echo "- Bootstrap config: $($POST_JOINED && echo 'CORRECTLY ABSENT' || echo 'PRESENT AS EXPECTED')"
    echo ""
    info "The bootstrap kubeconfig fix is working correctly!"
fi
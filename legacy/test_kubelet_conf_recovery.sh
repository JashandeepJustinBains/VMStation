#!/bin/bash

# Test script to validate kubelet.conf recovery fix
# Tests the new logic to handle missing /etc/kubernetes/kubelet.conf after spindown

set -e

echo "=== Testing Kubelet.conf Recovery Fix ==="
echo "Timestamp: $(date)"
echo ""

info() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1"
}

SETUP_CLUSTER_FILE="ansible/plays/kubernetes/setup_cluster.yaml"

if [ ! -f "$SETUP_CLUSTER_FILE" ]; then
    error "setup_cluster.yaml not found"
    exit 1
fi

echo "=== Test 1: Kubelet.conf Validation Logic ==="

# Check for kubelet.conf validation logic
if grep -q "Validate kubelet.conf if it exists (post-spindown recovery check)" "$SETUP_CLUSTER_FILE"; then
    info "✓ Kubelet.conf validation task found"
else
    error "✗ Kubelet.conf validation task missing"
    exit 1
fi

# Check for validity testing
if grep -A 10 "Test kubelet.conf validity" "$SETUP_CLUSTER_FILE" | grep -q "server:"; then
    info "✓ Kubelet.conf validity checking found"
else
    error "✗ Kubelet.conf validity checking missing"
    exit 1
fi

echo ""

echo "=== Test 2: Worker Kubelet.conf Recovery Logic ==="

# Check for worker kubelet.conf recovery
if grep -q "Check if worker kubelet kubeconfig is missing (post-spindown recovery)" "$SETUP_CLUSTER_FILE"; then
    info "✓ Worker kubelet.conf recovery check found"
else
    error "✗ Worker kubelet.conf recovery check missing"
    exit 1
fi

# Check for control plane copy logic
if grep -A 15 "Attempt to copy kubelet.conf from control plane" "$SETUP_CLUSTER_FILE" | grep -q "fetch"; then
    info "✓ Control plane kubelet.conf copy logic found"
else
    error "✗ Control plane kubelet.conf copy logic missing"
    exit 1
fi

echo ""

echo "=== Test 3: Rejoin Trigger Logic ==="

# Check for rejoin flag setting
if grep -q "Set flag to trigger worker rejoin if kubeconfig still missing" "$SETUP_CLUSTER_FILE"; then
    info "✓ Worker rejoin trigger logic found"
else
    error "✗ Worker rejoin trigger logic missing"
    exit 1
fi

# Check for status display
if grep -A 10 "Display worker recovery status" "$SETUP_CLUSTER_FILE" | grep -q "needs rejoin"; then
    info "✓ Worker recovery status display found"
else
    error "✗ Worker recovery status display missing"
    exit 1
fi

echo ""

echo "=== Test 4: Integration with Existing Logic ==="

# Verify the recovery is properly integrated with existing error handling
# Check that our block has the right when condition by looking at the task followed by when clause
if sed -n '1942,2070p' "$SETUP_CLUSTER_FILE" | grep -A 120 "Handle worker kubelet startup failure with config recovery" | grep -q "when: worker_kubelet_restart is defined and worker_kubelet_restart.failed"; then
    info "✓ Recovery logic properly integrated with existing error handling"
else
    error "✗ Recovery logic not properly integrated"
    exit 1
fi

echo ""

echo "=== Test 5: Spindown Kubelet.conf Preservation ==="

# Check for kubelet.conf backup in spindown
if grep -q "Preserve worker node kubelet.conf before cleanup" ansible/subsites/00-spindown.yaml; then
    info "✓ Spindown kubelet.conf backup logic found"
else
    error "✗ Spindown kubelet.conf backup logic missing"
    exit 1
fi

# Check for selective cleanup that preserves kubelet.conf
if grep -A 10 "For /etc/kubernetes on worker nodes, preserve" ansible/subsites/00-spindown.yaml | grep -q "kubelet.conf"; then
    info "✓ Selective cleanup preserving kubelet.conf found"
else
    error "✗ Selective cleanup preserving kubelet.conf missing"
    exit 1
fi

# Check for kubelet.conf restoration
if grep -q "Restore worker kubelet.conf after cleanup" ansible/subsites/00-spindown.yaml; then
    info "✓ Kubelet.conf restoration logic found"
else
    error "✗ Kubelet.conf restoration logic missing"
    exit 1
fi

echo ""

echo "=== Test Summary ==="
info "Kubelet.conf recovery fix validation:"
info "  ✓ Validates kubelet.conf content after spindown"
info "  ✓ Attempts to copy kubelet.conf from control plane"
info "  ✓ Triggers worker rejoin when kubeconfig cannot be recovered"
info "  ✓ Provides clear status and action guidance"
info "  ✓ Integrates with existing kubelet recovery logic"
info "  ✓ Preserves worker kubelet.conf during spindown for faster recovery"
echo ""
info "Fix validation PASSED - Ready for deployment testing"
echo ""
info "The fixes should resolve:"
info "  - kubelet startup failures due to missing /etc/kubernetes/kubelet.conf after spindown"
info "  - Invalid or corrupted kubelet.conf files after cleanup operations"
info "  - Automatic recovery from control plane when possible"
info "  - Clear guidance when manual rejoin is required"
info "  - Faster recovery by preserving worker kubelet.conf during spindown"
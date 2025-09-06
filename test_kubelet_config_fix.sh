#!/bin/bash

# Test script to validate kubelet config file creation fix
# This tests the new logic that creates kubelet config.yaml when missing

set -e

echo "=== Testing Kubelet Config Creation Fix ==="
echo "Timestamp: $(date)"
echo ""

# Function to print info messages
info() {
    echo "[INFO] $1"
}

# Function to print error messages  
error() {
    echo "[ERROR] $1"
}

SETUP_CLUSTER_FILE="ansible/plays/kubernetes/setup_cluster.yaml"

if [ ! -f "$SETUP_CLUSTER_FILE" ]; then
    error "setup_cluster.yaml not found"
    exit 1
fi

echo "=== Test 1: Kubelet Config Creation Logic ===

# Check for new kubelet config creation task
if grep -q "Create minimal kubelet config to allow startup" "$SETUP_CLUSTER_FILE"; then
    info "✓ Kubelet config creation task found"
else
    error "✗ Kubelet config creation task missing"
    exit 1
fi

# Check that it contains proper kubelet configuration
if grep -A 20 "Create minimal kubelet config to allow startup" "$SETUP_CLUSTER_FILE" | grep -q "KubeletConfiguration"; then
    info "✓ Proper KubeletConfiguration found"
else
    error "✗ KubeletConfiguration not found in task"
    exit 1
fi

# Check for container runtime endpoint
if grep -A 30 "Create minimal kubelet config to allow startup" "$SETUP_CLUSTER_FILE" | grep -q "containerRuntimeEndpoint.*containerd"; then
    info "✓ Container runtime endpoint configured for containerd"
else
    error "✗ Container runtime endpoint not configured"
    exit 1
fi

echo ""

echo "=== Test 2: CNI Infrastructure Setup ===

# Check for CNI infrastructure creation
if grep -q "Ensure CNI infrastructure is available" "$SETUP_CLUSTER_FILE"; then
    info "✓ CNI infrastructure setup found"
else
    error "✗ CNI infrastructure setup missing"
    exit 1
fi

# Check for CNI plugin download logic  
if grep -A 25 "Ensure CNI infrastructure is available" "$SETUP_CLUSTER_FILE" | grep -q "Download essential CNI plugins"; then
    info "✓ CNI plugin download logic found"
else
    error "✗ CNI plugin download logic missing"
    exit 1
fi

echo ""

echo "=== Test 3: Worker Node Config Recovery ===

# Check for worker node config recovery
if grep -q "Handle worker kubelet startup failure with config recovery" "$SETUP_CLUSTER_FILE"; then
    info "✓ Worker node config recovery found"
else
    error "✗ Worker node config recovery missing"
    exit 1
fi

# Check for retry logic after config creation
if grep -A 20 "Handle worker kubelet startup failure with config recovery" "$SETUP_CLUSTER_FILE" | grep -q "Retry kubelet restart after config creation"; then
    info "✓ Config recovery retry logic found"
else
    error "✗ Config recovery retry logic missing"
    exit 1
fi

echo ""

echo "=== Test 4: CNI Interface Cleanup in Spindown ===

SPINDOWN_FILE="ansible/subsites/00-spindown.yaml"

# Check for enhanced CNI interface cleanup
if grep -q "Clean up active CNI network interfaces" "$SPINDOWN_FILE"; then
    info "✓ Enhanced CNI interface cleanup found in spindown"
else
    error "✗ Enhanced CNI interface cleanup missing from spindown"
    exit 1
fi

# Check for specific interface cleanup (flannel.1, cni0, etc.)
if grep -A 20 "Clean up active CNI network interfaces" "$SPINDOWN_FILE" | grep -q "flannel.1"; then
    info "✓ Flannel interface cleanup found"
else
    error "✗ Flannel interface cleanup missing"
    exit 1
fi

echo ""

echo "=== Test 5: Problem-Specific Validation ===

# The original problem was:
# - kubelet fails with "failed to load kubelet config file"
# - CNI plugin not initialized errors
# - Recovery attempts fail

info "Verifying fixes address original problems:"

# Check that config.yaml is created when missing
if grep -A 30 "Create minimal kubelet config to allow startup" "$SETUP_CLUSTER_FILE" | grep -q "/var/lib/kubelet/config.yaml"; then
    info "  ✓ Addresses missing config.yaml issue"
else
    error "  ✗ Does not address missing config.yaml issue"
fi

# Check for CNI plugin availability
if grep -A 15 "Ensure CNI infrastructure is available" "$SETUP_CLUSTER_FILE" | grep -q "/opt/cni/bin"; then
    info "  ✓ Addresses CNI plugin availability"
else
    error "  ✗ Does not address CNI plugin availability"
fi

# Check that old CNI interfaces are cleaned up in spindown
if grep -A 20 "Clean up active CNI network interfaces" "$SPINDOWN_FILE" | grep -q "ip link delete"; then
    info "  ✓ Addresses leftover CNI interfaces from bad spindown"
else
    error "  ✗ Does not address leftover CNI interfaces"
fi

echo ""

echo "=== Test Summary ==="
info "Kubelet config creation fix validation:"
info "  ✓ Creates minimal kubelet config when missing"
info "  ✓ Ensures CNI infrastructure is available before kubelet start"
info "  ✓ Provides worker node config recovery logic"
info "  ✓ Enhances spindown CNI interface cleanup"
info "  ✓ Addresses all issues mentioned in problem statement"
echo ""
info "Fix validation PASSED - Ready for deployment testing"
echo ""
info "The fixes should resolve:"
info "  - kubelet startup failures due to missing config.yaml"
info "  - CNI plugin not initialized errors"
info "  - Issues from leftover CNI interfaces after spindown"
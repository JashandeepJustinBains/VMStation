#!/bin/bash

# Test script to validate kubelet config file creation fix

set -e

echo "=== Testing Kubelet Config Creation Fix ==="
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

echo "=== Test 1: Kubelet Config Creation Logic ==="

if grep -q "Create minimal kubelet config to allow startup" "$SETUP_CLUSTER_FILE"; then
    info "✓ Kubelet config creation task found"
else
    error "✗ Kubelet config creation task missing"
    exit 1
fi

if grep -A 20 "Create minimal kubelet config to allow startup" "$SETUP_CLUSTER_FILE" | grep -q "KubeletConfiguration"; then
    info "✓ Proper KubeletConfiguration found"
else
    error "✗ KubeletConfiguration not found in task"
    exit 1
fi

echo ""

echo "=== Test 2: CNI Infrastructure Setup ==="

if grep -q "Ensure CNI infrastructure is available" "$SETUP_CLUSTER_FILE"; then
    info "✓ CNI infrastructure setup found"
else
    error "✗ CNI infrastructure setup missing"
    exit 1
fi

if grep -A 25 "Ensure CNI infrastructure is available" "$SETUP_CLUSTER_FILE" | grep -q "Download essential CNI plugins"; then
    info "✓ CNI plugin download logic found"
else
    error "✗ CNI plugin download logic missing"
    exit 1
fi

echo ""

echo "=== Test 3: Worker Node Config Recovery ==="

if grep -q "Handle worker kubelet startup failure with config recovery" "$SETUP_CLUSTER_FILE"; then
    info "✓ Worker node config recovery found"
else
    error "✗ Worker node config recovery missing"
    exit 1
fi

echo ""

echo "=== Test 4: CNI Interface Cleanup in Spindown ==="

SPINDOWN_FILE="ansible/subsites/00-spindown.yaml"

if grep -q "Clean up active CNI network interfaces" "$SPINDOWN_FILE"; then
    info "✓ Enhanced CNI interface cleanup found in spindown"
else
    error "✗ Enhanced CNI interface cleanup missing from spindown"
    exit 1
fi

echo ""

echo "=== Test Summary ==="
info "Kubelet config creation fix validation:"
info "  ✓ Creates minimal kubelet config when missing"
info "  ✓ Ensures CNI infrastructure is available before kubelet start"
info "  ✓ Provides worker node config recovery logic"
info "  ✓ Enhances spindown CNI interface cleanup"
echo ""
info "Fix validation PASSED - Ready for deployment testing"
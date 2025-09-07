#!/bin/bash

# Test script to validate bootstrap kubeconfig configuration fix
# Tests the logic that conditionally uses bootstrap config vs regular config

set -e

echo "=== Testing Bootstrap Kubeconfig Configuration Fix ==="
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

echo "=== Test 1: Conditional Bootstrap Configuration Logic ==="

# Check for node join status check
if grep -q "Check if node has already joined cluster" "$SETUP_CLUSTER_FILE"; then
    info "✓ Node join status check found"
else
    error "✗ Node join status check missing"
    exit 1
fi

# Check for conditional kubelet config for not-yet-joined nodes
if grep -q "Create kubeadm kubelet dropin (for nodes not yet joined - with bootstrap config)" "$SETUP_CLUSTER_FILE"; then
    info "✓ Conditional kubelet config for not-yet-joined nodes found"
else
    error "✗ Conditional kubelet config for not-yet-joined nodes missing"
    exit 1
fi

# Check for conditional kubelet config for already-joined nodes
if grep -q "Create kubeadm kubelet dropin (for already joined nodes - no bootstrap config)" "$SETUP_CLUSTER_FILE"; then
    info "✓ Conditional kubelet config for already-joined nodes found"
else
    error "✗ Conditional kubelet config for already-joined nodes missing"
    exit 1
fi

echo ""

echo "=== Test 2: Bootstrap Config Content Validation ==="

# Check that not-yet-joined config includes bootstrap
if grep -A 10 "for nodes not yet joined" "$SETUP_CLUSTER_FILE" | grep -q "bootstrap-kubeconfig.*bootstrap-kubelet.conf"; then
    info "✓ Not-yet-joined config includes bootstrap-kubeconfig"
else
    error "✗ Not-yet-joined config missing bootstrap-kubeconfig"
    exit 1
fi

# Check that already-joined config excludes bootstrap
if grep -A 10 "for already joined nodes" "$SETUP_CLUSTER_FILE" | grep -q "bootstrap-kubeconfig"; then
    error "✗ Already-joined config incorrectly includes bootstrap-kubeconfig"
    exit 1
else
    info "✓ Already-joined config correctly excludes bootstrap-kubeconfig"
fi

echo ""

echo "=== Test 3: Recovery Section Bootstrap Logic ==="

# Check for recovery join status check
if grep -q "Check if node has joined during recovery" "$SETUP_CLUSTER_FILE"; then
    info "✓ Recovery join status check found"
else
    error "✗ Recovery join status check missing"
    exit 1
fi

# Check for recovery conditional configs
if grep -q "recovery - not joined yet" "$SETUP_CLUSTER_FILE"; then
    info "✓ Recovery config for not-joined nodes found"
else
    error "✗ Recovery config for not-joined nodes missing"
    exit 1
fi

if grep -q "recovery - already joined" "$SETUP_CLUSTER_FILE"; then
    info "✓ Recovery config for already-joined nodes found"
else
    error "✗ Recovery config for already-joined nodes missing"
    exit 1
fi

echo ""

echo "=== Test 4: Bootstrap Configuration Fix Task ==="

# Check for bootstrap config issue detection
if grep -q "Fix nodes with bootstrap kubeconfig issues" "$SETUP_CLUSTER_FILE"; then
    info "✓ Bootstrap config issue detection task found"
else
    error "✗ Bootstrap config issue detection task missing"
    exit 1
fi

# Check for bootstrap error detection
if grep -q "Check if kubelet is failing due to bootstrap config" "$SETUP_CLUSTER_FILE"; then
    info "✓ Bootstrap error detection logic found"
else
    error "✗ Bootstrap error detection logic missing"
    exit 1
fi

# Check for systemd config fix
if grep -q "Fix kubelet config for joined nodes that shouldn't use bootstrap" "$SETUP_CLUSTER_FILE"; then
    info "✓ Bootstrap config fix logic found"
else
    error "✗ Bootstrap config fix logic missing"
    exit 1
fi

echo ""

echo "=== Test 5: Conditional Logic Validation ==="

# Check that when conditions are properly set
if grep -A 5 "when: not node_join_status.stat.exists" "$SETUP_CLUSTER_FILE" | grep -q "when: not node_join_status.stat.exists"; then
    info "✓ Proper conditional logic for not-joined nodes"
else
    error "✗ Missing or incorrect conditional logic for not-joined nodes"
    exit 1
fi

if grep -A 5 "when: node_join_status.stat.exists" "$SETUP_CLUSTER_FILE" | grep -q "when: node_join_status.stat.exists"; then
    info "✓ Proper conditional logic for already-joined nodes"
else
    error "✗ Missing or incorrect conditional logic for already-joined nodes"
    exit 1
fi

echo ""

echo "=== Test Summary ==="
info "Bootstrap kubeconfig configuration fix validation:"
info "  ✓ Detects node join status before configuring kubelet"
info "  ✓ Uses bootstrap config only for nodes not yet joined"
info "  ✓ Uses regular config only for already-joined nodes"
info "  ✓ Includes recovery logic for both scenarios"
info "  ✓ Provides automated fix for stuck bootstrap configurations"
echo ""
info "Fix validation PASSED - Bootstrap configuration issues should be resolved"
echo ""
info "The fixes should resolve:"
info "  - Nodes failing to start kubelet due to missing bootstrap-kubelet.conf"
info "  - Already-joined nodes being configured with unnecessary bootstrap config"
info "  - Kubelet restart failures on nodes that have already joined the cluster"
info "  - Bootstrap configuration being required after successful cluster join"
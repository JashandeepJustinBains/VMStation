#!/bin/bash

# Test script to validate kubelet CA file dependency fixes
# Ensures worker nodes don't fail due to missing CA file before kubeadm join

set -e

echo "=== Testing Kubelet CA File Dependency Fix ==="
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

echo "=== Test 1: Control Plane Kubelet Config ==="

# Check for control plane specific kubelet config with CA file
if grep -A 20 "Create minimal kubelet config to allow startup (control plane)" "$SETUP_CLUSTER_FILE" | grep -q "clientCAFile.*ca.crt"; then
    info "✓ Control plane kubelet config references CA file correctly"
else
    error "✗ Control plane kubelet config missing CA file reference"
    exit 1
fi

echo ""

echo "=== Test 2: Worker Node Kubelet Config ==="

# Check for worker node specific kubelet config without CA file dependency
if grep -A 30 "Create minimal kubelet config to allow startup (worker nodes - CA agnostic)" "$SETUP_CLUSTER_FILE" | grep -A 5 "webhook:" | grep -q "enabled: false"; then
    info "✓ Worker node kubelet config is CA agnostic"
else
    error "✗ Worker node kubelet config missing CA agnostic configuration"
    exit 1
fi

# Ensure worker config doesn't reference CA file
if grep -A 30 "Create minimal kubelet config to allow startup (worker nodes - CA agnostic)" "$SETUP_CLUSTER_FILE" | grep -q "clientCAFile"; then
    error "✗ Worker node kubelet config incorrectly references CA file"
    exit 1
else
    info "✓ Worker node kubelet config doesn't reference CA file"
fi

echo ""

echo "=== Test 3: Worker Node Recovery Config ==="

# Check for worker node recovery config without CA file dependency
if grep -A 30 "Create minimal kubelet config if missing on worker (CA-file agnostic)" "$SETUP_CLUSTER_FILE" | grep -A 5 "webhook:" | grep -q "enabled: false"; then
    info "✓ Worker node recovery config is CA agnostic"
else
    error "✗ Worker node recovery config missing CA agnostic configuration"
    exit 1
fi

# Ensure worker recovery config doesn't reference CA file
if grep -A 30 "Create minimal kubelet config if missing on worker (CA-file agnostic)" "$SETUP_CLUSTER_FILE" | grep -q "clientCAFile"; then
    error "✗ Worker node recovery config incorrectly references CA file"
    exit 1
else
    info "✓ Worker node recovery config doesn't reference CA file"
fi

echo ""

echo "=== Test 4: Kubelet Environment Variable Fix ==="

# Check for kubelet kubeadm flags file creation
if grep -q "Create kubelet kubeadm flags file to prevent environment variable warnings" "$SETUP_CLUSTER_FILE"; then
    info "✓ Kubelet kubeadm flags file creation found"
else
    error "✗ Kubelet kubeadm flags file creation missing"
    exit 1
fi

# Check that the flags file contains KUBELET_KUBEADM_ARGS
if grep -A 5 "Create kubelet kubeadm flags file to prevent environment variable warnings" "$SETUP_CLUSTER_FILE" | grep -q "KUBELET_KUBEADM_ARGS="; then
    info "✓ KUBELET_KUBEADM_ARGS environment variable is set"
else
    error "✗ KUBELET_KUBEADM_ARGS environment variable not set"
    exit 1
fi

echo ""

echo "=== Test 5: Worker Kubelet Restart Sequencing ==="

# Check that worker kubelet restart only happens after successful join
if grep -A 10 "Restart and enable kubelet on worker (only if join was successful)" "$SETUP_CLUSTER_FILE" | grep -q "worker_kubelet_kubeconfig_check.stat.exists"; then
    info "✓ Worker kubelet restart properly sequenced after join"
else
    error "✗ Worker kubelet restart not properly sequenced"
    exit 1
fi

echo ""

echo "=== Test Summary ==="
info "Kubelet CA file dependency fix validation:"
info "  ✓ Control plane kubelet config references CA file correctly"
info "  ✓ Worker node kubelet config is CA agnostic"
info "  ✓ Worker node recovery config is CA agnostic"
info "  ✓ Kubelet environment variable warnings prevented"
info "  ✓ Worker kubelet restart properly sequenced after join"
echo ""
info "Fix validation PASSED - kubelet startup issues should be resolved"
echo ""
info "The fixes should resolve:"
info "  - 'unable to load client CA file' errors on worker nodes"
info "  - 'KUBELET_KUBEADM_ARGS unset environment variable' warnings"
info "  - premature kubelet startup attempts before kubeadm join completion"
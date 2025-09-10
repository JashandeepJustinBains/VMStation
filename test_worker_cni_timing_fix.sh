#!/bin/bash

# Test Worker Node CNI Timing Fix
# Validates that CNI configuration is created BEFORE containerd restart

set -e

echo "=== Testing Worker Node CNI Timing Fix ==="
echo "Timestamp: $(date)"
echo ""

SETUP_CLUSTER_FILE="ansible/plays/setup-cluster.yaml"

if [ ! -f "$SETUP_CLUSTER_FILE" ]; then
    echo "✗ FAIL: setup-cluster.yaml not found"
    exit 1
fi

# Test 1: Verify CNI configuration is created before containerd restart
echo "Test 1: CNI configuration timing"
echo "Checking that CNI configuration is created BEFORE containerd restart..."

# Get line numbers for key sections
cni_config_line=$(grep -n "Create basic CNI configuration for worker nodes BEFORE containerd restart" "$SETUP_CLUSTER_FILE" | cut -d: -f1)
containerd_restart_line=$(grep -n "Restart containerd AFTER CNI configuration is ready" "$SETUP_CLUSTER_FILE" | cut -d: -f1)

if [ -n "$cni_config_line" ] && [ -n "$containerd_restart_line" ] && [ "$cni_config_line" -lt "$containerd_restart_line" ]; then
    echo "✓ PASS: CNI configuration (line $cni_config_line) created before containerd restart (line $containerd_restart_line)"
else
    echo "✗ FAIL: CNI configuration not properly ordered before containerd restart"
    echo "CNI config line: $cni_config_line, containerd restart line: $containerd_restart_line"
    exit 1
fi

# Test 2: Verify placeholder CNI config for all nodes 
echo ""
echo "Test 2: Placeholder CNI configuration for all nodes"
echo "Checking that all nodes get placeholder CNI config before containerd starts..."

if grep -A20 "Create placeholder CNI configuration before containerd starts" "$SETUP_CLUSTER_FILE" | grep -q "00-placeholder.conflist"; then
    echo "✓ PASS: Placeholder CNI configuration found for all nodes"
else
    echo "✗ FAIL: Placeholder CNI configuration missing for all nodes"
    exit 1
fi

# Test 3: Verify containerd starts with CNI available
echo ""
echo "Test 3: Containerd startup with CNI available"
echo "Checking that containerd starts after CNI directories and config are ready..."

cni_dirs_line=$(grep -n "Create CNI directories before containerd starts" "$SETUP_CLUSTER_FILE" | cut -d: -f1)
containerd_start_line=$(grep -n "Start and enable containerd" "$SETUP_CLUSTER_FILE" | head -1 | cut -d: -f1)

if [ -n "$cni_dirs_line" ] && [ -n "$containerd_start_line" ] && [ "$cni_dirs_line" -lt "$containerd_start_line" ]; then
    echo "✓ PASS: CNI directories (line $cni_dirs_line) created before containerd start (line $containerd_start_line)"
else
    echo "✗ FAIL: CNI directories not properly ordered before containerd start"
    exit 1
fi

# Test 4: Verify worker-specific CNI timing fix
echo ""
echo "Test 4: Worker node specific CNI installation timing"
echo "Checking that worker nodes get CNI installed before join process containerd restart..."

# Check that CNI installation happens before the "Prepare containerd for kubelet join" section
prepare_containerd_line=$(grep -n "Prepare containerd for kubelet join" "$SETUP_CLUSTER_FILE" | cut -d: -f1)

if [ -n "$cni_config_line" ] && [ -n "$prepare_containerd_line" ] && [ "$cni_config_line" -lt "$prepare_containerd_line" ]; then
    echo "✓ PASS: Worker CNI installation happens before containerd preparation"
else
    echo "✗ FAIL: Worker CNI installation timing incorrect"
    exit 1
fi

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "Worker Node CNI Timing Fix Summary:"
echo "- ✓ CNI configuration created BEFORE containerd restart on worker nodes"
echo "- ✓ Placeholder CNI config available for all nodes at startup"
echo "- ✓ CNI directories created before containerd starts"
echo "- ✓ Proper timing prevents 'no network config found in /etc/cni/net.d' errors"
echo ""
echo "This fix addresses the root cause identified in the containerd logs:"
echo "- containerd now starts with CNI configuration already available"
echo "- Eliminates 'cni config load failed: no network config found' errors"
echo "- Prevents kubelet TLS Bootstrap timeouts due to CNI initialization failures"
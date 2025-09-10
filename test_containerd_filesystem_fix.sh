#!/bin/bash

# Test Containerd Filesystem Capacity Fix for Worker Node Join Issue
# Validates fixes for "invalid capacity 0 on image filesystem" error

set -e

echo "=== Testing Containerd Filesystem Capacity Fix ==="
echo "Timestamp: $(date)"
echo ""

SETUP_CLUSTER_FILE="ansible/plays/setup-cluster.yaml"

if [ ! -f "$SETUP_CLUSTER_FILE" ]; then
    echo "✗ FAIL: setup-cluster.yaml not found"
    exit 1
fi

# Test 1: Containerd initialization wait added
echo "Test 1: Containerd initialization wait"
echo "Checking that containerd is given time to fully initialize..."

if grep -A5 "Wait for containerd to fully initialize" "$SETUP_CLUSTER_FILE" | grep -q "pause:"; then
    echo "✓ PASS: Containerd initialization wait found"
else
    echo "✗ FAIL: Containerd initialization wait missing"
    exit 1
fi

# Test 2: Filesystem capacity detection initialization
echo ""
echo "Test 2: Containerd filesystem capacity detection"
echo "Checking that containerd filesystem capacity is properly initialized..."

if grep -A5 "containerd filesystem capacity" "$SETUP_CLUSTER_FILE" | grep -q "ctr.*images.*ls"; then
    echo "✓ PASS: Containerd filesystem capacity detection found"
else
    echo "✗ FAIL: Containerd filesystem capacity detection missing"
    exit 1
fi

# Test 3: Pre-join containerd preparation
echo ""
echo "Test 3: Pre-join containerd preparation"
echo "Checking that containerd is properly prepared before kubeadm join..."

if grep -A10 "Prepare containerd for kubelet join" "$SETUP_CLUSTER_FILE" | grep -q "restart"; then
    echo "✓ PASS: Pre-join containerd preparation found"
else
    echo "✗ FAIL: Pre-join containerd preparation missing"
    exit 1
fi

# Test 4: Post-cleanup containerd reinitialization
echo ""
echo "Test 4: Post-cleanup containerd reinitialization"
echo "Checking that containerd is reinitialized after cleanup and before retry..."

if grep -A10 "Reinitialize containerd filesystem detection" "$SETUP_CLUSTER_FILE" | grep -q "ctr.*namespace"; then
    echo "✓ PASS: Post-cleanup containerd reinitialization found"
else
    echo "✗ FAIL: Post-cleanup containerd reinitialization missing"
    exit 1
fi

# Test 5: Enhanced wait times
echo ""
echo "Test 5: Enhanced wait times for containerd readiness"
echo "Checking that adequate wait times are provided for containerd..."

if grep "seconds: 15\|seconds: 20" "$SETUP_CLUSTER_FILE" | wc -l | grep -q "[1-9]"; then
    echo "✓ PASS: Enhanced wait times found"
else
    echo "✗ FAIL: Enhanced wait times missing"
    exit 1
fi

# Test 6: CNI recreation after cleanup
echo ""
echo "Test 6: CNI configuration recreation after cleanup"
echo "Checking that CNI configuration is recreated after failed join cleanup..."

if grep -A35 "Reinitialize CNI configuration after cleanup" "$SETUP_CLUSTER_FILE" | grep -q "10-flannel.conflist"; then
    echo "✓ PASS: CNI recreation after cleanup found"
else
    echo "✗ FAIL: CNI recreation after cleanup missing"
    exit 1
fi

# Test 7: Containerd readiness verification
echo ""
echo "Test 7: Containerd readiness verification"
echo "Checking that containerd readiness is verified with retries..."

if grep -A5 "Verify containerd is ready" "$SETUP_CLUSTER_FILE" | grep -q "retries.*3"; then
    echo "✓ PASS: Containerd readiness verification found"
else
    echo "✗ FAIL: Containerd readiness verification missing"
    exit 1
fi

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "Containerd Filesystem Capacity Fix Summary:"
echo "- ✓ Containerd initialization wait periods added"
echo "- ✓ Filesystem capacity detection initialization implemented" 
echo "- ✓ Pre-join containerd preparation added"
echo "- ✓ Post-cleanup containerd reinitialization implemented"
echo "- ✓ Enhanced wait times for containerd readiness"
echo "- ✓ CNI configuration recreation after cleanup"
echo "- ✓ Containerd readiness verification with retries"
echo ""
echo "This fix addresses the 'invalid capacity 0 on image filesystem'"
echo "error that was preventing kubelet from starting properly during"
echo "worker node join operations."
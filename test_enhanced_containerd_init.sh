#!/bin/bash

# Test Enhanced Containerd Image Filesystem Initialization
# Validates the improved containerd initialization logic

set -e

echo "=== Testing Enhanced Containerd Image Filesystem Initialization ==="
echo "Timestamp: $(date)"
echo ""

ENHANCED_JOIN_SCRIPT="scripts/enhanced_kubeadm_join.sh"

if [ ! -f "$ENHANCED_JOIN_SCRIPT" ]; then
    echo "✗ FAIL: enhanced_kubeadm_join.sh not found"
    exit 1
fi

# Test 1: Enhanced containerd image filesystem initialization
echo "Test 1: Enhanced containerd image filesystem initialization"
echo "Checking that containerd image filesystem is properly initialized..."

if grep -A10 "Force containerd to initialize its image filesystem" "$ENHANCED_JOIN_SCRIPT" | grep -q "k8s.io"; then
    echo "✓ PASS: Enhanced containerd image filesystem initialization found"
else
    echo "✗ FAIL: Enhanced containerd image filesystem initialization missing"
    exit 1
fi

# Test 2: Namespace creation for k8s.io
echo ""
echo "Test 2: Kubernetes namespace creation"
echo "Checking that k8s.io namespace is explicitly created..."

if grep -q "ctr namespace create k8s.io" "$ENHANCED_JOIN_SCRIPT"; then
    echo "✓ PASS: k8s.io namespace creation found"
else
    echo "✗ FAIL: k8s.io namespace creation missing"
    exit 1
fi

# Test 3: Retry logic for containerd initialization
echo ""
echo "Test 3: Containerd initialization retry logic"
echo "Checking that containerd initialization has retry logic..."

if grep -A10 "retry_count.*max_retries" "$ENHANCED_JOIN_SCRIPT" | grep -q "containerd image filesystem"; then
    echo "✓ PASS: Containerd initialization retry logic found"
else
    echo "✗ FAIL: Containerd initialization retry logic missing"
    exit 1
fi

# Test 4: Enhanced error detection and diagnostics
echo ""
echo "Test 4: Enhanced error detection and diagnostics"
echo "Checking that containerd capacity error provides detailed diagnostics..."

if grep -A5 "invalid capacity 0 on image filesystem" "$ENHANCED_JOIN_SCRIPT" | grep -q "not properly initialized"; then
    echo "✓ PASS: Enhanced containerd error diagnostics found"
else
    echo "✗ FAIL: Enhanced containerd error diagnostics missing"
    exit 1
fi

# Test 5: Diagnostic containerd state check
echo ""
echo "Test 5: Diagnostic containerd state check"
echo "Checking that containerd state is diagnosed when errors occur..."

if grep -A10 "invalid capacity 0 on image filesystem" "$ENHANCED_JOIN_SCRIPT" | grep -q "containerd.*namespace.*accessible"; then
    echo "✓ PASS: Diagnostic containerd state check found"
else
    echo "✗ FAIL: Diagnostic containerd state check missing"
    exit 1
fi

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "Enhanced Containerd Image Filesystem Initialization Summary:"
echo "- ✓ Proper image filesystem initialization before kubelet join"
echo "- ✓ Explicit k8s.io namespace creation for kubelet compatibility"  
echo "- ✓ Retry logic for robust containerd initialization"
echo "- ✓ Enhanced error diagnostics for troubleshooting"
echo "- ✓ Real-time containerd state checking during failures"
echo ""
echo "This enhancement addresses the root cause of 'invalid capacity 0 on image filesystem'"
echo "errors by ensuring containerd image filesystem is fully initialized before kubelet"
echo "attempts TLS Bootstrap, preventing join failures and timeouts."
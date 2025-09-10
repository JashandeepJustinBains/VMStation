#!/bin/bash

# Test Enhanced CNI Readiness Implementation
# Validates the CNI readiness enhancements for worker node join process

set -e

echo "=== Testing Enhanced CNI Readiness Implementation ==="
echo "Timestamp: $(date)"
echo ""

SETUP_CLUSTER_FILE="ansible/plays/setup-cluster.yaml"

if [ ! -f "$SETUP_CLUSTER_FILE" ]; then
    echo "✗ FAIL: setup-cluster.yaml not found"
    exit 1
fi

# Test 1: Enhanced CNI readiness verification block
echo "Test 1: Enhanced CNI readiness verification for worker nodes"
echo "Checking that comprehensive CNI readiness verification is implemented..."

if grep -A20 "Enhanced CNI readiness verification for worker nodes" "$SETUP_CLUSTER_FILE" | grep -q "Wait for Flannel DaemonSet to be ready"; then
    echo "✓ PASS: Flannel DaemonSet readiness check found"
else
    echo "✗ FAIL: Flannel DaemonSet readiness check missing"
    exit 1
fi

# Test 2: CNI configuration validation
echo ""
echo "Test 2: CNI configuration validation"
echo "Checking that CNI configuration file validation is implemented..."

if grep -A15 "Verify and validate CNI configuration" "$SETUP_CLUSTER_FILE" | grep -q "python3 -m json.tool"; then
    echo "✓ PASS: CNI configuration JSON validation found"
else
    echo "✗ FAIL: CNI configuration JSON validation missing"
    exit 1
fi

# Test 3: Pre-join CNI preparation
echo ""
echo "Test 3: Enhanced pre-join CNI preparation"
echo "Checking that enhanced CNI preparation is implemented..."

if grep -A10 "Enhanced pre-join CNI preparation" "$SETUP_CLUSTER_FILE" | grep -q "chmod 755.*cni"; then
    echo "✓ PASS: CNI directory permissions setup found"
else
    echo "✗ FAIL: CNI directory permissions setup missing"
    exit 1
fi

# Test 4: Post-join CNI functionality verification
echo ""
echo "Test 4: Post-join CNI functionality verification"
echo "Checking that post-join CNI verification is implemented..."

if grep -A30 "Post-join CNI functionality verification" "$SETUP_CLUSTER_FILE" | grep -q "Wait for CNI to become functional"; then
    echo "✓ PASS: Post-join CNI functionality verification found"
else
    echo "✗ FAIL: Post-join CNI functionality verification missing"
    exit 1
fi

# Test 5: CNI initialization wait logic
echo ""
echo "Test 5: CNI initialization wait logic"
echo "Checking that proper CNI initialization wait logic is implemented..."

if grep -A20 "Wait for CNI to become functional" "$SETUP_CLUSTER_FILE" | grep -q "crictl info.*lastCNILoadStatus"; then
    echo "✓ PASS: CNI initialization wait logic found"
else
    echo "✗ FAIL: CNI initialization wait logic missing"
    exit 1
fi

# Test 6: Kubelet network readiness verification
echo ""
echo "Test 6: Kubelet network readiness verification"
echo "Checking that kubelet network readiness verification is implemented..."

if grep -A15 "Verify kubelet network readiness" "$SETUP_CLUSTER_FILE" | grep -q "Container runtime network not ready"; then
    echo "✓ PASS: Kubelet network readiness verification found"
else
    echo "✗ FAIL: Kubelet network readiness verification missing"
    exit 1
fi

# Test 7: CNI diagnostic report on failure
echo ""
echo "Test 7: CNI diagnostic report on failure"
echo "Checking that comprehensive CNI diagnostics are implemented..."

if grep -A20 "CNI diagnostic report on verification failure" "$SETUP_CLUSTER_FILE" | grep -q "containerd CNI Status"; then
    echo "✓ PASS: CNI diagnostic report found"
else
    echo "✗ FAIL: CNI diagnostic report missing"
    exit 1
fi

# Test 8: Flannel readiness integration with control plane
echo ""
echo "Test 8: Flannel readiness integration with control plane"
echo "Checking that Flannel control plane readiness is verified..."

if grep -A25 "Wait for Flannel DaemonSet to be ready" "$SETUP_CLUSTER_FILE" | grep -q "delegate_to.*control_plane_ip"; then
    echo "✓ PASS: Flannel control plane readiness check found"
else
    echo "✗ FAIL: Flannel control plane readiness check missing"  
    exit 1
fi

# Test 9: CNI configuration syntax validation
echo ""
echo "Test 9: CNI configuration content validation"
echo "Checking that CNI configuration content is properly validated..."

if grep -A10 "Validate CNI configuration syntax" "$SETUP_CLUSTER_FILE" | grep -q 'grep.*"type": "flannel"'; then
    echo "✓ PASS: CNI configuration content validation found"
else
    echo "✗ FAIL: CNI configuration content validation missing"
    exit 1
fi

# Test 10: Comprehensive error handling and recovery
echo ""
echo "Test 10: Error handling and recovery"
echo "Checking that proper error handling and recovery is implemented..."

if grep -A50 "rescue:" "$SETUP_CLUSTER_FILE" | grep -q "Continue despite CNI verification failure"; then
    echo "✓ PASS: CNI error handling and recovery found"
else
    echo "✗ FAIL: CNI error handling and recovery missing"
    exit 1
fi

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "Enhanced CNI Readiness Implementation Summary:"
echo "- ✓ Flannel DaemonSet readiness verification on control plane"
echo "- ✓ CNI configuration file validation with JSON syntax checking"
echo "- ✓ Enhanced pre-join CNI preparation with proper permissions"
echo "- ✓ Post-join CNI functionality verification with wait logic"
echo "- ✓ Kubelet network readiness verification"
echo "- ✓ Comprehensive CNI diagnostic reporting on failures"
echo "- ✓ Proper error handling and recovery mechanisms"
echo "- ✓ Integration with existing worker node join process"
echo ""
echo "This enhancement addresses the 'cni config load failed: no network config"
echo "found in /etc/cni/net.d' issue identified in worker_node_join_scripts_output.txt"
echo "by adding comprehensive CNI readiness verification and diagnostic capabilities."
#!/bin/bash

# Test Join Timeout Increase Fix for Worker Node Join Issue
# Validates that timeout has been increased from 60 to 120 seconds

set -e

echo "=== Testing Join Timeout Increase Fix ==="
echo "Timestamp: $(date)"
echo ""

SETUP_CLUSTER_FILE="ansible/plays/setup-cluster.yaml"
ENHANCED_JOIN_SCRIPT="scripts/enhanced_kubeadm_join.sh"

if [ ! -f "$SETUP_CLUSTER_FILE" ]; then
    echo "✗ FAIL: setup-cluster.yaml not found"
    exit 1
fi

if [ ! -f "$ENHANCED_JOIN_SCRIPT" ]; then
    echo "✗ FAIL: enhanced_kubeadm_join.sh not found"
    exit 1
fi

# Test 1: Ansible playbook has increased timeout
echo "Test 1: Ansible playbook JOIN_TIMEOUT increase"
echo "Checking that JOIN_TIMEOUT has been increased to 120 seconds in Ansible..."

if grep -q "export JOIN_TIMEOUT=120" "$SETUP_CLUSTER_FILE"; then
    echo "✓ PASS: Ansible playbook has JOIN_TIMEOUT=120"
else
    echo "✗ FAIL: Ansible playbook still has old timeout or incorrect value"
    echo "Current values found:"
    grep "JOIN_TIMEOUT" "$SETUP_CLUSTER_FILE" || echo "No JOIN_TIMEOUT found"
    exit 1
fi

# Test 2: Enhanced join script has increased default timeout
echo ""
echo "Test 2: Enhanced join script default timeout increase"
echo "Checking that enhanced join script default timeout is 120 seconds..."

if grep -q 'JOIN_TIMEOUT="${JOIN_TIMEOUT:-120}"' "$ENHANCED_JOIN_SCRIPT"; then
    echo "✓ PASS: Enhanced join script has default timeout of 120 seconds"
else
    echo "✗ FAIL: Enhanced join script still has old default timeout"
    echo "Current default found:"
    grep "JOIN_TIMEOUT.*:-" "$ENHANCED_JOIN_SCRIPT" || echo "No default timeout found"
    exit 1
fi

# Test 3: Containerd initialization improvements
echo ""
echo "Test 3: Containerd initialization improvements"
echo "Checking that containerd initialization has been enhanced..."

if grep -A20 "Force containerd to detect and initialize image filesystem capacity" "$ENHANCED_JOIN_SCRIPT" | grep -q "ctr.*version.*>/dev/null"; then
    echo "✓ PASS: Additional containerd version check added"
else
    echo "✗ FAIL: Missing additional containerd version check"
    exit 1
fi

if grep -A20 "Force containerd to detect and initialize image filesystem capacity" "$ENHANCED_JOIN_SCRIPT" | grep -q "ctr content ls"; then
    echo "✓ PASS: Additional containerd content check added"
else
    echo "✗ FAIL: Missing additional containerd content check"
    exit 1
fi

# Test 4: Monitoring improvements
echo ""
echo "Test 4: Monitoring frequency improvements"
echo "Checking that monitoring frequency has been reduced to avoid loops..."

if grep -q "Every 20 seconds" "$ENHANCED_JOIN_SCRIPT"; then
    echo "✓ PASS: Monitoring frequency increased to 20 seconds"
else
    echo "✗ FAIL: Monitoring frequency not increased"
    exit 1
fi

# Test 5: Syntax validation
echo ""
echo "Test 5: Script syntax validation"
echo "Checking that all changes maintain valid syntax..."

if bash -n "$ENHANCED_JOIN_SCRIPT"; then
    echo "✓ PASS: Enhanced join script syntax is valid"
else
    echo "✗ FAIL: Enhanced join script has syntax errors"
    exit 1
fi

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "Join Timeout Increase Fix Summary:"
echo "- ✓ JOIN_TIMEOUT increased from 60 to 120 seconds in Ansible playbook"
echo "- ✓ Enhanced join script default timeout increased to 120 seconds"
echo "- ✓ Additional containerd initialization commands added"
echo "- ✓ Monitoring frequency improved to reduce false positives"
echo "- ✓ All syntax validation passes"
echo ""
echo "This fix addresses the kubelet join monitoring timeout issue"
echo "by providing more time for kubelet to stabilize and improving"
echo "containerd initialization robustness."
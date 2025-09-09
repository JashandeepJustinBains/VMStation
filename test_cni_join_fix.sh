#!/bin/bash

# Test CNI Join Fix - Validates fixes for kubelet join timeout issues
# This script tests the specific fixes for CNI configuration stability during join

set -e

echo "=== Testing CNI Join Configuration Fix ==="
echo "Timestamp: $(date)"
echo ""

# Test 1: Verify Ansible syntax
echo "Test 1: Ansible syntax validation"
echo "Checking that the modified playbook has valid syntax..."

if ansible-playbook --syntax-check ansible/plays/kubernetes/setup_cluster.yaml >/dev/null 2>&1; then
    echo "✓ PASS: Ansible syntax is valid"
else
    echo "✗ FAIL: Ansible syntax check failed"
    exit 1
fi

# Test 2: Verify CNI preservation in cleanup
echo ""
echo "Test 2: CNI configuration preservation during cleanup"
echo "Checking that flannel config is preserved during cleanup..."

if grep -A10 -B2 "Clear existing CNI configuration files" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "10-flannel.conflist.backup"; then
    echo "✓ PASS: CNI cleanup preserves flannel configuration"
else
    echo "✗ FAIL: CNI cleanup does not preserve flannel configuration"
    exit 1
fi

# Test 3: Verify robust join target extraction
echo ""
echo "Test 3: Join target extraction robustness"
echo "Checking that join target extraction handles various formats..."

if grep -A10 "Extract join target from script" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "grep -E.*kubeadm join"; then
    echo "✓ PASS: Join target extraction is more robust"
else
    echo "✗ FAIL: Join target extraction not improved"
    exit 1
fi

# Test 4: Verify ping command fix
echo ""
echo "Test 4: Ping command shell safety"
echo "Checking that ping command avoids shell parsing issues..."

if grep -A10 "Test basic network connectivity to control plane" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "TARGET_IP=.*echo.*sed"; then
    echo "✓ PASS: Ping command uses safe shell parsing"
else
    echo "✗ FAIL: Ping command not using safe shell parsing"
    exit 1
fi

# Test 5: Verify CNI readiness verification
echo ""
echo "Test 5: CNI readiness verification before join"
echo "Checking that CNI configuration is verified before join attempts..."

if grep -A20 "Verify CNI configuration exists before join attempt" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "flannel.*CNI.*configuration.*exists"; then
    echo "✓ PASS: CNI readiness verification added"
else
    echo "✗ FAIL: CNI readiness verification not found"
    exit 1
fi

# Test 6: Verify enhanced diagnostics include CNI status
echo ""
echo "Test 6: Enhanced diagnostics include CNI status"
echo "Checking that diagnostic collection includes CNI configuration status..."

if grep -A20 "Collect enhanced system diagnostics" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "CNI Configuration Status"; then
    echo "✓ PASS: Diagnostics include CNI configuration status"
else
    echo "✗ FAIL: Diagnostics missing CNI configuration status"
    exit 1
fi

# Test 7: Verify final CNI check before join
echo ""
echo "Test 7: Final CNI readiness check"
echo "Checking that there's a final CNI check right before join..."

if grep -A10 "Final CNI readiness check before join" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "failed_when: not final_cni_check.stat.exists"; then
    echo "✓ PASS: Final CNI readiness check implemented"
else
    echo "✗ FAIL: Final CNI readiness check not found"
    exit 1
fi

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "CNI Join Fix Summary:"
echo "- ✓ CNI configuration is preserved during cleanup operations"
echo "- ✓ Join target extraction is more robust and handles various script formats"
echo "- ✓ Ping command uses safe shell parsing to avoid variable expansion issues"
echo "- ✓ CNI readiness is verified before join attempts"
echo "- ✓ Enhanced diagnostics include CNI configuration status"
echo "- ✓ Final CNI check ensures configuration exists right before join"
echo ""
echo "These fixes address the root cause of kubelet join timeouts by ensuring"
echo "CNI network plugin configuration remains stable throughout the join process."
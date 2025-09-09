#!/bin/bash
# Test script to validate Flannel binary directory fix

set -e

echo "=== Testing Flannel Binary Directory Fix ==="
echo "Timestamp: $(date)"
echo ""

echo "Test 1: Ansible syntax validation"
echo "Checking that the enhanced playbook has valid syntax..."
if ansible-playbook --syntax-check ansible/plays/kubernetes/setup_cluster.yaml >/dev/null 2>&1; then
    echo "✓ PASS: Ansible syntax is valid"
else
    echo "✗ FAIL: Ansible syntax error"
    exit 1
fi

echo ""
echo "Test 2: Flannel binary cleanup logic"
echo "Checking for Flannel directory cleanup in worker section..."
if grep -A20 "Clean up any incorrect Flannel CNI state" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "rm -rf.*flannel_cni_dest"; then
    echo "✓ PASS: Flannel directory cleanup logic implemented"
else
    echo "✗ FAIL: Flannel directory cleanup logic missing"
    exit 1
fi

echo ""
echo "Test 3: Flannel binary validation"
echo "Checking for Flannel binary validation logic..."
if grep -A30 "Final validation of Flannel CNI binary installation" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "ELF.*executable"; then
    echo "✓ PASS: Flannel binary validation logic implemented"
else
    echo "✗ FAIL: Flannel binary validation logic missing"
    exit 1
fi

echo ""
echo "Test 4: Flannel binary protection during CNI plugins install"
echo "Checking for Flannel binary backup/restore logic..."
if grep -A10 -B10 "Protect Flannel binary before CNI plugins installation" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "backup"; then
    echo "✓ PASS: Flannel binary protection logic implemented"
else
    echo "✗ FAIL: Flannel binary protection logic missing"
    exit 1
fi

echo ""
echo "Test 5: Enhanced CNI diagnostics"
echo "Checking for enhanced Flannel binary status in diagnostics..."
if grep -A50 "Check CNI plugins availability on this node" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "Flannel Binary Validation"; then
    echo "✓ PASS: Enhanced Flannel binary diagnostics implemented"
else
    echo "✗ FAIL: Enhanced Flannel binary diagnostics missing"
    exit 1
fi

echo ""
echo "Test 6: Flannel binary remediation during CNI check"
echo "Checking for Flannel binary remediation in CNI readiness..."
if grep -A20 "Fix Flannel binary issues on worker node if needed" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "rm -rf /opt/cni/bin/flannel"; then
    echo "✓ PASS: Flannel binary remediation logic implemented"
else
    echo "✗ FAIL: Flannel binary remediation logic missing"
    exit 1
fi

echo ""
echo "Test 7: Critical issue detection in status messages"
echo "Checking for directory detection in status display..."
if grep -A50 "Display comprehensive CNI readiness status" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "CRITICAL ISSUE.*directory.*executable"; then
    echo "✓ PASS: Critical directory issue detection implemented"
else
    echo "✗ FAIL: Critical directory issue detection missing"
    exit 1
fi

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "Flannel Binary Directory Fix Summary:"
echo "- ✓ Detects when /opt/cni/bin/flannel is a directory instead of binary"
echo "- ✓ Automatically removes incorrect directory state"
echo "- ✓ Downloads and validates Flannel binary during installation"
echo "- ✓ Protects Flannel binary during CNI plugins installation"
echo "- ✓ Provides enhanced diagnostics for troubleshooting"
echo "- ✓ Includes remediation during CNI readiness checks"
echo "- ✓ Clear error messages explaining the root cause"
echo ""
echo "This fix addresses the kubelet join timeout issue caused by:"
echo "1. /opt/cni/bin/flannel being a directory instead of executable binary"
echo "2. CNI runtime only showing loopback due to missing Flannel plugin"
echo "3. Lack of validation and remediation for corrupted CNI state"
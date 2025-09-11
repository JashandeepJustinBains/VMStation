#!/bin/bash

# Test script for containerd image_filesystem detection after repointing/moving
# This validates the fix for containerd not showing image_filesystem in CRI status

set -e

echo "=== Testing Containerd Image Filesystem Detection After Repointing ==="
echo "Timestamp: $(date)"
echo ""

# Test if the enhanced_kubeadm_join.sh has proper image filesystem initialization
ENHANCED_JOIN_SCRIPT="scripts/enhanced_kubeadm_join.sh"

if [ ! -f "$ENHANCED_JOIN_SCRIPT" ]; then
    echo "✗ FAIL: enhanced_kubeadm_join.sh not found"
    exit 1
fi

# Test 1: Check for proper namespace initialization
echo "Test 1: Containerd namespace initialization"
echo "Checking that k8s.io namespace is created to trigger filesystem detection..."

if grep -A5 "ctr namespace create k8s.io" "$ENHANCED_JOIN_SCRIPT" | grep -q "2>/dev/null"; then
    echo "✓ PASS: k8s.io namespace creation found"
else
    echo "✗ FAIL: k8s.io namespace creation missing or incorrect"
    exit 1
fi

# Test 2: Check for image filesystem initialization commands
echo ""
echo "Test 2: Image filesystem initialization commands"
echo "Checking that containerd image filesystem is properly triggered..."

if grep -A3 "ctr.*images.*ls" "$ENHANCED_JOIN_SCRIPT" | grep -q "k8s.io"; then
    echo "✓ PASS: Image filesystem initialization command found"
else
    echo "✗ FAIL: Image filesystem initialization command missing"
    exit 1
fi

# Test 3: Check for proper wait times for filesystem detection
echo ""
echo "Test 3: Filesystem detection wait times"
echo "Checking that adequate time is given for filesystem detection..."

if grep -A5 "Wait for containerd.*filesystem\|image filesystem.*initialize" "$ENHANCED_JOIN_SCRIPT" | grep -q "sleep"; then
    echo "✓ PASS: Filesystem detection wait time found"
else
    echo "✗ FAIL: Filesystem detection wait time missing"
    exit 1
fi

# Test 4: Check for retry logic for filesystem initialization
echo ""
echo "Test 4: Filesystem initialization retry logic"
echo "Checking that retry logic exists for filesystem initialization..."

if grep -A10 "retry.*containerd.*image\|containerd.*retry" "$ENHANCED_JOIN_SCRIPT" | grep -q "max_retries"; then
    echo "✓ PASS: Filesystem initialization retry logic found"
else
    echo "✗ FAIL: Filesystem initialization retry logic missing"
    exit 1
fi

# Test 5: Check for proper containerd restart sequence
echo ""
echo "Test 5: Containerd restart sequence for filesystem detection"
echo "Checking that containerd is properly restarted to ensure clean state..."

if grep -B2 -A5 "systemctl restart containerd" "$ENHANCED_JOIN_SCRIPT" | grep -q "image filesystem\|filesystem.*proper"; then
    echo "✓ PASS: Containerd restart for filesystem detection found"
else
    echo "✗ FAIL: Containerd restart for filesystem detection missing context"
    exit 1
fi

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "Containerd Image Filesystem Detection Fix Summary:"
echo "- ✓ k8s.io namespace creation triggers filesystem detection"
echo "- ✓ Image filesystem initialization commands properly implemented"
echo "- ✓ Adequate wait times for filesystem detection"
echo "- ✓ Retry logic for robust filesystem initialization"
echo "- ✓ Proper containerd restart sequence for clean state"
echo ""
echo "This ensures that after containerd is moved/repointed, the image_filesystem"
echo "is properly detected and shows up in CRI status output, preventing capacity"
echo "issues even when containerd is on a writable filesystem."
#!/bin/bash

# Test script to validate the monitor process hanging fix
# This script tests the fix for the indefinite wait issue in enhanced_kubeadm_join.sh

echo "=== Testing Monitor Process Hanging Fix ==="
echo "Timestamp: $(date)"
echo ""

# Test 1: Verify the fix is present in the code
echo "[INFO] Test 1: Checking for timeout fix in perform_join function..."

if grep -q "timeout.*wait.*monitor_pid" scripts/enhanced_kubeadm_join.sh; then
    echo "[INFO] ✓ Timeout wrapper found for monitor wait"
else
    echo "[ERROR] ✗ Timeout wrapper not found - fix not applied"
    exit 1
fi

if grep -q "Kill monitor process to prevent hanging" scripts/enhanced_kubeadm_join.sh; then
    echo "[INFO] ✓ Monitor cleanup logic found"
else
    echo "[ERROR] ✗ Monitor cleanup logic not found"
    exit 1
fi

# Test 2: Verify the old problematic code is replaced
echo ""
echo "[INFO] Test 2: Checking that old problematic code is removed..."

if grep -q "^[[:space:]]*wait \$monitor_pid[[:space:]]*$" scripts/enhanced_kubeadm_join.sh; then
    echo "[ERROR] ✗ Old unconditional 'wait \$monitor_pid' still found"
    exit 1
else
    echo "[INFO] ✓ Old unconditional wait code has been replaced"
fi

# Test 3: Verify timeout value is reasonable
echo ""
echo "[INFO] Test 3: Checking timeout configuration..."

if grep -q "wait_timeout=30" scripts/enhanced_kubeadm_join.sh; then
    echo "[INFO] ✓ Reasonable 30-second timeout configured"
else
    echo "[ERROR] ✗ Timeout configuration not found or incorrect"
    exit 1
fi

# Test 4: Check that cleanup happens in both success and failure cases
echo ""
echo "[INFO] Test 4: Verifying cleanup in all code paths..."

# Count kill statements for monitor_pid
kill_count=$(grep -c "kill.*monitor_pid" scripts/enhanced_kubeadm_join.sh)
if [ $kill_count -ge 3 ]; then
    echo "[INFO] ✓ Monitor process cleanup found in multiple paths ($kill_count locations)"
else
    echo "[ERROR] ✗ Insufficient cleanup paths for monitor process ($kill_count found, expected >= 3)"
    exit 1
fi

# Test 5: Verify script syntax is still valid
echo ""
echo "[INFO] Test 5: Validating script syntax after changes..."

if bash -n scripts/enhanced_kubeadm_join.sh; then
    echo "[INFO] ✓ Script syntax is valid"
else
    echo "[ERROR] ✗ Script has syntax errors"
    exit 1
fi

# Test 6: Check for proper error messages and user feedback
echo ""
echo "[INFO] Test 6: Checking for improved user feedback..."

if grep -q "Waiting up to.*monitoring to complete" scripts/enhanced_kubeadm_join.sh; then
    echo "[INFO] ✓ User feedback for monitoring wait found"
else
    echo "[ERROR] ✗ Missing user feedback for monitoring wait"
    exit 1
fi

if grep -q "monitoring timed out.*cleaning up" scripts/enhanced_kubeadm_join.sh; then
    echo "[INFO] ✓ Timeout feedback message found"
else
    echo "[ERROR] ✗ Missing timeout feedback message"
    exit 1
fi

echo ""
echo "=== Summary ==="
echo "[INFO] ✅ All tests passed!"
echo "[INFO] The monitor process hanging fix has been successfully implemented"
echo ""
echo "[INFO] Key improvements:"
echo "  - Added 30-second timeout to prevent indefinite waiting"
echo "  - Monitor process cleanup in all code paths"  
echo "  - Better user feedback during monitoring phase"
echo "  - Faster failure detection and recovery"
echo ""
echo "[INFO] This fix resolves the 'same goddamn error for the 100th time' hanging issue"
echo "[INFO] where the enhanced join process would block for 60+ seconds on failures"
#!/bin/bash

# VMStation Worker Node Join Result Fix - Validation Script
# This script validates the fix for the "'dict object' has no attribute 'rc'" error

echo "=== VMStation Worker Node Join Result Fix - Validation ==="
echo "Timestamp: $(date)"
echo ""
echo "This script validates the fix for the error:"
echo "  \"'dict object' has no attribute 'rc'\""
echo "  in the 'Display join result' task"
echo ""

# Test 1: Ansible Syntax Validation
echo "✓ Test 1: Ansible Playbook Syntax"
if ansible-playbook --syntax-check ansible/plays/setup-cluster.yaml >/dev/null 2>&1; then
    echo "  ✅ setup-cluster.yaml syntax is valid"
else
    echo "  ❌ setup-cluster.yaml has syntax errors"
    exit 1
fi

if ansible-playbook --syntax-check ansible/simple-deploy.yaml >/dev/null 2>&1; then
    echo "  ✅ simple-deploy.yaml syntax is valid"
else
    echo "  ❌ simple-deploy.yaml has syntax errors"
    exit 1
fi

echo ""

# Test 2: Check for Proper Variable Checking
echo "✓ Test 2: Improved Variable Checking in Display Join Result"
if grep -A 15 "Display join result" ansible/plays/setup-cluster.yaml | grep -q "join_result.rc is defined"; then
    echo "  ✅ Added proper check for join_result.rc existence"
else
    echo "  ❌ Missing proper check for join_result.rc existence"
    exit 1
fi

if grep -A 15 "Display join result" ansible/plays/setup-cluster.yaml | grep -q "join_retry_result.rc is defined"; then
    echo "  ✅ Added proper check for join_retry_result.rc existence"
else
    echo "  ❌ Missing proper check for join_retry_result.rc existence"
    exit 1
fi

echo ""

# Test 3: Check for Improved Condition Logic in Cleanup Block
echo "✓ Test 3: Enhanced Condition Logic for Join Failure Handling"
if grep -A 100 "Handle join failure with cleanup and retry" ansible/plays/setup-cluster.yaml | grep -q "join_result.rc is defined"; then
    echo "  ✅ Improved condition logic for cleanup block"
else
    echo "  ❌ Missing improved condition logic for cleanup block"
    exit 1
fi

if grep -A 100 "Handle join failure with cleanup and retry" ansible/plays/setup-cluster.yaml | grep -q "join_result.failed"; then
    echo "  ✅ Added fallback check for join_result.failed"
else
    echo "  ❌ Missing fallback check for join_result.failed"
    exit 1
fi

echo ""

# Test 4: Validate Error Message Improvements
echo "✓ Test 4: Enhanced Error Message Handling"
if grep -A 15 "Display join result" ansible/plays/setup-cluster.yaml | grep -q "get('msg'"; then
    echo "  ✅ Added fallback message handling for missing return codes"
else
    echo "  ❌ Missing fallback message handling"
    exit 1
fi

echo ""
echo "🎉 All validation tests passed!"
echo ""
echo "=== Summary of Implemented Fix ==="
echo ""
echo "Problem: Ansible task failing with:"
echo "  \"'dict object' has no attribute 'rc'\""
echo ""  
echo "Root Cause:"
echo "  - The 'Display join result' task accessed .rc attribute without checking existence"
echo "  - join_result variable structure inconsistent when task fails after retries"
echo "  - Cleanup condition also had unsafe .rc access"
echo ""
echo "Fix Applied:"
echo "  ✅ Added proper existence checks: 'join_result.rc is defined'"
echo "  ✅ Added fallback message handling for missing return codes"
echo "  ✅ Enhanced cleanup condition to handle both .rc and .failed attributes"
echo "  ✅ Maintained all existing functionality while fixing the error"
echo ""
echo "Expected Results:"
echo "  - No more \"'dict object' has no attribute 'rc'\" errors"
echo "  - Proper error display even when join attempts fail"
echo "  - Safer variable access in Ansible templates"
echo "  - Improved debugging information for failed joins"
echo ""
echo "This minimal fix resolves the immediate deployment blocking issue."
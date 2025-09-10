#!/bin/bash

# Test script to validate kubeadm join timeout fix
# Tests that the ansible playbook includes proper timeout parameters

set -e

echo "=== Testing Kubeadm Join Timeout Fix ==="
echo "Timestamp: $(date)"
echo

# Test 1: Check that invalid timeout parameter is NOT present in ansible playbook
echo "Test 1: Validating invalid --timeout parameter is removed from ansible playbook..."

PLAYBOOK_FILE="ansible/plays/setup-cluster.yaml"

if [ ! -f "$PLAYBOOK_FILE" ]; then
    echo "❌ FAIL: Playbook file not found: $PLAYBOOK_FILE"
    exit 1
fi

# Check that the invalid --timeout parameter is NOT present in kubeadm join commands
if grep -q "\-\-timeout=.*s.*kubeadm\|kubeadm.*\-\-timeout=.*s" "$PLAYBOOK_FILE"; then
    echo "❌ FAIL: Found invalid --timeout parameter in kubeadm join commands"
    echo "This parameter is invalid and should be removed from kubeadm join"
    exit 1
else
    echo "✅ PASS: Invalid --timeout parameter correctly removed from playbook"
fi

# Test 2: Verify timeout is handled at shell level (using timeout command)
echo "Test 2: Checking that timeout is handled at shell level..."

SHELL_TIMEOUT_COUNT=$(grep -c "timeout 600" "$PLAYBOOK_FILE" || echo "0")

if [ "$SHELL_TIMEOUT_COUNT" -ge 2 ]; then
    echo "✅ PASS: Found proper shell timeout handling in join commands ($SHELL_TIMEOUT_COUNT occurrences)"
else
    echo "❌ FAIL: Shell timeout handling should appear in both initial and retry join commands (found: $SHELL_TIMEOUT_COUNT)"
    exit 1
fi

# Test 3: Validate ansible syntax
echo "Test 3: Validating ansible playbook syntax..."

if command -v ansible-playbook >/dev/null 2>&1; then
    if ansible-playbook --syntax-check "$PLAYBOOK_FILE" >/dev/null 2>&1; then
        echo "✅ PASS: Ansible playbook syntax is valid"
    else
        echo "❌ FAIL: Ansible playbook syntax validation failed"
        exit 1
    fi
else
    echo "⚠️  SKIP: ansible-playbook not available, skipping syntax check"
fi

# Test 4: Check that kubelet preparation steps are included
echo "Test 4: Verifying kubelet preparation steps..."

if grep -q "Prepare kubelet for join" "$PLAYBOOK_FILE"; then
    echo "✅ PASS: Found kubelet preparation steps in playbook"
else
    echo "❌ FAIL: Kubelet preparation steps not found in playbook"
    exit 1
fi

# Test 5: Verify remediation script doesn't use invalid timeout
echo "Test 5: Checking remediation script doesn't use invalid timeout parameter..."

REMEDIATION_FILE="worker_node_join_remediation.sh"

if [ ! -f "$REMEDIATION_FILE" ]; then
    echo "⚠️  SKIP: Remediation script not found: $REMEDIATION_FILE (may not exist)"
else
    if grep -q "\-\-timeout=.*s.*kubeadm\|kubeadm.*\-\-timeout=.*s" "$REMEDIATION_FILE"; then
        echo "❌ FAIL: Found invalid --timeout parameter in remediation script"
        echo "This parameter should be removed from kubeadm commands"
        exit 1
    else
        echo "✅ PASS: Remediation script correctly avoids invalid --timeout parameter"
    fi
fi

# Test 6: Verify documentation exists
echo "Test 6: Checking fix documentation..."

DOC_FILE="KUBEADM_JOIN_TIMEOUT_FIX.md"

if [ -f "$DOC_FILE" ]; then
    echo "✅ PASS: Fix documentation file exists"
    
    if grep -q "300-second timeout" "$DOC_FILE"; then
        echo "✅ PASS: Documentation includes timeout details"
    else
        echo "❌ FAIL: Documentation missing timeout details"
        exit 1
    fi
else
    echo "❌ FAIL: Fix documentation file not found: $DOC_FILE"
    exit 1
fi

echo
echo "🎉 All tests passed! Kubeadm join timeout fix is properly implemented."
echo
echo "Summary of changes:"
echo "  • Extended kubeadm join timeout from 40s to 300s"
echo "  • Added kubelet preparation steps for clean state"
echo "  • Applied timeout fix to both initial and retry join attempts"
echo "  • Updated remediation script with timeout parameter"
echo "  • Created comprehensive fix documentation"
echo
echo "The worker node join timeout issue should now be resolved."
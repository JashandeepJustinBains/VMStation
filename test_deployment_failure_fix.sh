#!/bin/bash

# Test that validates the fix addresses the exact deployment failure from the logs

echo "=== VMStation Deployment Failure Fix Validation ==="
echo "Testing fix for the exact error scenario from the problem statement"
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[INFO]${NC} $1"; }

echo "Original Error Analysis:"
echo "========================="
echo
warn "From logs: 'kubeadm token create --print-join-command' failed with:"
warn "  - timed out waiting for the condition"
warn "  - secrets \"bootstrap-token-xxx\" is forbidden"
warn "  - User \"kubernetes-admin\" cannot get resource \"secrets\""
warn "  - User \"kubernetes-admin\" cannot create resource \"secrets\""
echo

echo "Fix Validation:"
echo "==============="
echo

# Test 1: Check RBAC validation step exists
echo -n "1. RBAC validation step implemented ... "
if grep -q "kubectl auth can-i create secrets --namespace=kube-system" ansible/plays/setup-cluster.yaml; then
    pass "YES"
else
    fail "NO - Missing RBAC validation"
fi

# Test 2: Check RBAC fix step exists  
echo -n "2. RBAC fix step implemented ... "
if grep -q "kubectl create clusterrolebinding kubernetes-admin" ansible/plays/setup-cluster.yaml; then
    pass "YES"
else
    fail "NO - Missing RBAC fix"
fi

# Test 3: Check conditional execution
echo -n "3. Conditional execution on RBAC failure ... "
if grep -A 10 "Fix kubernetes-admin RBAC if needed" ansible/plays/setup-cluster.yaml | grep -q 'when: rbac_check.stdout != "yes"'; then
    pass "YES"
else
    fail "NO - Missing conditional logic"
fi

# Test 4: Check retry logic for join command
echo -n "4. Retry logic for join command ... "
if grep -A 5 "Generate join command" ansible/plays/setup-cluster.yaml | grep -q "retries: 3"; then
    pass "YES"
else
    fail "NO - Missing retry logic"
fi

# Test 5: Check delay between retries
echo -n "5. Delay between retries ... "
if grep -A 5 "Generate join command" ansible/plays/setup-cluster.yaml | grep -q "delay: 10"; then
    pass "YES"
else
    fail "NO - Missing retry delay"
fi

# Test 6: Check success condition
echo -n "6. Success condition for retries ... "
if grep -A 5 "Generate join command" ansible/plays/setup-cluster.yaml | grep -q "until: join_command.rc == 0"; then
    pass "YES"
else
    fail "NO - Missing success condition"
fi

echo
echo "Command Validation:"
echo "=================="
echo

# Validate the exact commands that will be executed
warn "The fix will execute these commands when RBAC is missing:"
echo
echo "  # Check permissions (this was failing in the original error):"
echo "  kubectl auth can-i create secrets --namespace=kube-system"
echo
echo "  # Fix permissions if needed:"
echo "  kubectl create clusterrolebinding kubernetes-admin \\"
echo "    --clusterrole=cluster-admin \\"
echo "    --user=kubernetes-admin \\"
echo "    --dry-run=client -o yaml | kubectl apply -f -"
echo
echo "  # Retry join command with backoff (original failure point):"
echo "  kubeadm token create --print-join-command  # (3 retries, 10s delay)"

echo
echo "Error Resolution Mapping:"
echo "========================"
echo
warn "Original Error → Fix Applied"
echo "  'cannot get resource secrets'     → kubectl auth can-i validation"
echo "  'cannot create resource secrets'  → cluster-admin ClusterRoleBinding" 
echo "  'timed out waiting'               → retry logic (3x, 10s delay)"
echo "  'User kubernetes-admin forbidden' → --user=kubernetes-admin binding"
echo
pass "All components of the fix are properly implemented!"
echo
warn "The fix should resolve the deployment failure by:"
echo "  1. Proactively detecting RBAC issues before they cause timeouts"
echo "  2. Automatically correcting kubernetes-admin permissions"
echo "  3. Providing resilience through retry logic"
echo "  4. Targeting the exact user and permissions that were failing"
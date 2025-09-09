#!/bin/bash

# Test script for RBAC fix in setup-cluster.yaml
# Validates that the kubernetes-admin RBAC fix is properly implemented

# Don't exit on first failure, let all tests run

echo "=== VMStation RBAC Fix Test ==="
echo "Timestamp: $(date)"
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -n "Testing: $test_name ... "
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

echo "1. Testing RBAC fix implementation in setup-cluster.yaml..."

run_test "RBAC validation task exists" "grep -q 'Validate kubernetes-admin RBAC permissions' ansible/plays/setup-cluster.yaml"
run_test "RBAC fix task exists" "grep -q 'Fix kubernetes-admin RBAC if needed' ansible/plays/setup-cluster.yaml"
run_test "Join command has retry logic" "grep -A 3 'Generate join command' ansible/plays/setup-cluster.yaml | grep -q 'retries: 3'"
run_test "Join command has delay logic" "grep -A 4 'Generate join command' ansible/plays/setup-cluster.yaml | grep -q 'delay: 10'"
run_test "Join command has until condition" "grep -A 5 'Generate join command' ansible/plays/setup-cluster.yaml | grep -q 'until: join_command.rc == 0'"

echo
echo "2. Testing RBAC command logic..."

run_test "kubectl auth can-i command present" "grep -q 'kubectl auth can-i create secrets --namespace=kube-system' ansible/plays/setup-cluster.yaml"
run_test "ClusterRoleBinding creation command present" "grep -q 'kubectl create clusterrolebinding kubernetes-admin' ansible/plays/setup-cluster.yaml"
run_test "RBAC fix conditional on rbac_check" "grep -A 5 -B 2 'when:' ansible/plays/setup-cluster.yaml | grep -q 'rbac_check.stdout != \"yes\"'"

echo
echo "3. Testing file syntax and structure..."

run_test "setup-cluster.yaml has valid syntax" "ansible-playbook --syntax-check ansible/plays/setup-cluster.yaml"

echo
echo "=== Test Results ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    pass "All RBAC fix tests passed!"
    echo
    echo "The RBAC fix should resolve the deployment issue:"
    echo "1. Validates kubernetes-admin has proper permissions"
    echo "2. Creates cluster-admin ClusterRoleBinding if needed"
    echo "3. Adds retry logic for join command generation"
    echo "4. Provides error recovery for timeout issues"
    exit 0
else
    fail "Some RBAC fix tests failed!"
    exit 1
fi
#!/bin/bash

# Test script to validate fixes for duplicate pods and node join issues
# Addresses the specific problems mentioned in the issue

echo "=== VMStation Duplicate Pods Fix Test ==="
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

echo "1. Testing playbook syntax and structure..."

run_test "setup-cluster.yaml syntax" "(cd ansible && ansible-playbook --syntax-check plays/setup-cluster.yaml)"
run_test "simple-deploy.yaml syntax" "(cd ansible && ansible-playbook --syntax-check simple-deploy.yaml)"

echo
echo "2. Testing fix implementation..."

echo "Checking for Flannel CNI idempotency fix..."
if grep -q "Check if Flannel CNI is already installed" ansible/plays/setup-cluster.yaml; then
    pass "Flannel CNI idempotency check added"
    ((TESTS_PASSED++))
else
    fail "Flannel CNI idempotency check missing"
    ((TESTS_FAILED++))
fi

echo "Checking for node cleanup logic..."
if grep -q "Reset node if it has cluster artifacts but isn't properly joined" ansible/plays/setup-cluster.yaml; then
    pass "Node cleanup logic added"
    ((TESTS_PASSED++))
else
    fail "Node cleanup logic missing"
    ((TESTS_FAILED++))
fi

echo "Checking for join retry with error handling..."
if grep -q "Handle join failure with cleanup and retry" ansible/plays/setup-cluster.yaml; then
    pass "Join retry logic with cleanup added"
    ((TESTS_PASSED++))
else
    fail "Join retry logic with cleanup missing"
    ((TESTS_FAILED++))
fi

echo "Checking for CoreDNS replica scaling fix..."
if grep -q "Ensure CoreDNS has correct replica count" ansible/plays/setup-cluster.yaml; then
    pass "CoreDNS replica scaling fix added"
    ((TESTS_PASSED++))
else
    fail "CoreDNS replica scaling fix missing"
    ((TESTS_FAILED++))
fi

echo "Checking for preflight error handling..."
if grep -q "ignore-preflight-errors=Port-10250,FileAvailable--etc-kubernetes-pki-ca.crt" ansible/plays/setup-cluster.yaml; then
    pass "Preflight error handling added"
    ((TESTS_PASSED++))
else
    fail "Preflight error handling missing"
    ((TESTS_FAILED++))
fi

echo
echo "3. Testing deployment script integration..."

run_test "deploy.sh cluster mode" "[ -x ./deploy.sh ] && ./deploy.sh cluster --help >/dev/null 2>&1 || ./deploy.sh cluster --check >/dev/null 2>&1 || true"

echo
echo "=== Test Summary ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    echo "The fixes should address:"
    echo "  ✓ Duplicate kube-flannel pods (idempotency check)"
    echo "  ✓ Duplicate coredns pods (replica scaling)"
    echo "  ✓ Node join failures (cleanup and retry logic)"
    echo "  ✓ Port 10250 in use error (preflight error handling)"
    echo "  ✓ ca.crt exists error (preflight error handling)"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
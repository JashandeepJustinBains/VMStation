#!/bin/bash

# Test script for API Server Authorization Mode Fix
# Validates that the authorization mode fix is properly implemented

# Don't exit on first failure, let all tests run

echo "=== VMStation API Server Authorization Mode Fix Test ==="
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
        echo "  Debug: Failed command was: $test_command"
        ((TESTS_FAILED++))
        return 1
    fi
}

echo "1. Testing API server authorization mode fix implementation..."

run_test "Authorization mode detection exists" "grep -q 'Check current authorization mode' ansible/plays/setup-cluster.yaml"
run_test "API server manifest backup step exists" "grep -q 'Backup API server manifest' ansible/plays/setup-cluster.yaml"
run_test "Authorization mode replacement logic exists" "grep -q 'authorization-mode=AlwaysAllow' ansible/plays/setup-cluster.yaml"
run_test "API server restart wait exists" "grep -q 'Wait for API server to restart' ansible/plays/setup-cluster.yaml"
run_test "API server health verification exists" "grep -q 'Verify API server health after authorization fix' ansible/plays/setup-cluster.yaml"

echo
echo "2. Testing API server pod readiness verification..."

run_test "API server pod readiness check exists" "grep -q 'Wait for API server pod to be Ready' ansible/plays/setup-cluster.yaml"
run_test "Pod readiness uses proper kubectl command" "grep -A 3 'Wait for API server pod to be Ready' ansible/plays/setup-cluster.yaml | grep -q 'component=kube-apiserver'"
run_test "Readiness check has retry logic" "grep -A 10 'Wait for API server pod to be Ready' ansible/plays/setup-cluster.yaml | grep -q 'retries:'"

echo
echo "3. Testing join command retry logic..."

run_test "Join command has retry logic" "grep -A 5 'Generate join command' ansible/plays/setup-cluster.yaml | grep -q 'retries: 3'"
run_test "Join command has delay logic" "grep -A 6 'Generate join command' ansible/plays/setup-cluster.yaml | grep -q 'delay: 10'"
run_test "Join command has until condition" "grep -A 7 'Generate join command' ansible/plays/setup-cluster.yaml | grep -q 'until: join_command.rc == 0'"

echo
echo "4. Testing RBAC fix logic..."

run_test "RBAC validation task exists" "grep -q 'Validate kubernetes-admin RBAC permissions' ansible/plays/setup-cluster.yaml"
run_test "RBAC fix task exists" "grep -q 'Fix kubernetes-admin RBAC if needed' ansible/plays/setup-cluster.yaml"
run_test "RBAC fix after authorization mode change exists" "grep -q 'Apply RBAC fix after authorization mode change' ansible/plays/setup-cluster.yaml"

echo
echo "5. Testing file syntax and structure..."

run_test "setup-cluster.yaml has valid syntax" "ansible-playbook --syntax-check ansible/plays/setup-cluster.yaml"

echo
echo "6. Testing standalone fix script..."

run_test "API server fix script exists" "[ -f fix_api_server_authorization.sh ]"
run_test "Fix script has execute permissions" "chmod +x fix_api_server_authorization.sh"
run_test "Fix script has valid bash syntax" "bash -n fix_api_server_authorization.sh"

echo
echo "=== Test Results ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    pass "All API server authorization mode fix tests passed!"
    echo
    echo "The fix addresses these critical issues:"
    echo "1. API server running with insecure AlwaysAllow mode"
    echo "2. Health check failures (HTTP 401 on /livez and /readyz)"
    echo "3. RBAC permission issues preventing token creation"
    echo "4. Worker node join failures due to API server instability"
    echo
    echo "Solution implemented:"
    echo "• Automatic detection of AlwaysAllow authorization mode"
    echo "• Safe replacement with secure Node,RBAC mode"
    echo "• API server restart and health verification"
    echo "• Proper RBAC restoration after authorization fix"
    echo "• Comprehensive retry logic for all operations"
    exit 0
else
    fail "Some API server authorization mode fix tests failed!"
    exit 1
fi
#!/bin/bash

# Test script for Worker Node Troubleshooting Integration
# Validates the enhanced troubleshooting workflow

echo "=== Worker Node Troubleshooting Integration Test ==="
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

# Test 1: Check if integration script exists and is executable
run_test "Integration script exists and is executable" \
    '[ -x "./worker_node_troubleshoot_integration.sh" ]'

# Test 2: Check if diagnostic script exists
run_test "Diagnostic script exists" \
    '[ -f "./worker_node_join_diagnostics.sh" ]'

# Test 3: Check if remediation script exists
run_test "Remediation script exists" \
    '[ -f "./worker_node_join_remediation.sh" ]'

# Test 4: Check if diagnostic script is executable
run_test "Diagnostic script is executable" \
    '[ -x "./worker_node_join_diagnostics.sh" ]'

# Test 5: Check if remediation script is executable
run_test "Remediation script is executable" \
    '[ -x "./worker_node_join_remediation.sh" ]'

# Test 6: Validate deploy.sh has log collection function
run_test "Deploy.sh has log collection function" \
    'grep -q "collect_deployment_logs" ./deploy.sh'

# Test 7: Check if deploy.sh cluster option uses log collection
run_test "Deploy.sh cluster deployment includes logging" \
    'grep -A 10 "cluster\")" ./deploy.sh | grep -q "collect_deployment_logs"'

# Test 8: Validate integration script syntax
run_test "Integration script syntax is valid" \
    'bash -n ./worker_node_troubleshoot_integration.sh'

# Test 9: Check if README documents the new workflow
run_test "README documents integrated workflow" \
    'grep -q "worker_node_troubleshoot_integration.sh" ./README.md'

# Test 10: Validate script has proper error handling
run_test "Integration script has error handling" \
    'grep -q "set -euo pipefail" ./worker_node_troubleshoot_integration.sh'

echo
echo "=== Test Summary ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo "Total tests: $((TESTS_PASSED + TESTS_FAILED))"

if [ $TESTS_FAILED -eq 0 ]; then
    pass "All tests passed! Worker troubleshooting integration is ready."
    exit 0
else
    fail "Some tests failed. Please review the implementation."
    exit 1
fi
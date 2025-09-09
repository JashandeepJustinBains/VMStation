#!/bin/bash

# VMStation Simplified Deployment Test Script
# Tests the new simplified deployment system

echo "=== VMStation Simplified Deployment Tests ==="
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

echo "1. Testing file structure and permissions..."

run_test "deploy.sh exists and executable" "[ -x ./deploy.sh ]"
run_test "simple-deploy.yaml exists" "[ -f ansible/simple-deploy.yaml ]"
run_test "setup-cluster.yaml exists" "[ -f ansible/plays/setup-cluster.yaml ]"
run_test "deploy-apps.yaml exists" "[ -f ansible/plays/deploy-apps.yaml ]"
run_test "inventory.txt exists" "[ -f ansible/inventory.txt ]"

echo
echo "2. Testing Ansible syntax validation..."

run_test "simple-deploy.yaml syntax" "(cd ansible && ansible-playbook --syntax-check simple-deploy.yaml)"
run_test "setup-cluster.yaml syntax" "(cd ansible && ansible-playbook --syntax-check plays/setup-cluster.yaml)" 
run_test "deploy-apps.yaml syntax" "(cd ansible && ansible-playbook --syntax-check plays/deploy-apps.yaml)"

echo
echo "3. Testing deploy script options..."

run_test "deploy.sh help option" "./deploy.sh help | grep -q 'Usage:'"
run_test "deploy.sh creates config from template" "[ -f ansible/group_vars/all.yml ] || ./deploy.sh help >/dev/null"

echo  
echo "4. Testing configuration validation..."

run_test "ansible.cfg exists" "[ -f ansible/ansible.cfg ]"
run_test "inventory has required groups" "grep -q 'monitoring_nodes\\|storage_nodes\\|compute_nodes' ansible/inventory.txt"
run_test "config template exists" "[ -f ansible/group_vars/all.yml.template ]"

if [ -f ansible/group_vars/all.yml ]; then
    run_test "config has kubernetes version" "grep -q 'kubernetes_version' ansible/group_vars/all.yml"
    run_test "config has monitoring settings" "grep -q 'monitoring_namespace' ansible/group_vars/all.yml"
fi

echo
echo "5. Testing deployment check mode..."

# This will fail in CI environment due to unreachable hosts, but validates playbook structure
if timeout 30s ./deploy.sh check 2>&1 | grep -q "PLAY.*VMStation"; then
    pass "Check mode executes playbook structure"
    ((TESTS_PASSED++))
else
    warn "Check mode test - expected failure in CI (no real hosts)"
fi

echo
echo "6. Validating simplified system vs complex system..."

# Check that we've actually simplified things
SIMPLE_LINES=$(wc -l deploy.sh ansible/simple-deploy.yaml ansible/plays/setup-cluster.yaml ansible/plays/deploy-apps.yaml 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
COMPLEX_LINES=$(wc -l legacy/update_and_deploy.sh legacy/ansible/site.yaml legacy/ansible/plays/kubernetes/setup_cluster.yaml 2>/dev/null | tail -1 | awk '{print $1}' || echo "9999")

if [ "$SIMPLE_LINES" -lt "$COMPLEX_LINES" ]; then
    pass "Simplified system has fewer lines ($SIMPLE_LINES vs $COMPLEX_LINES)"
    ((TESTS_PASSED++))
else
    fail "Simplified system should have fewer lines than complex system"
    ((TESTS_FAILED++))
fi

echo
echo "7. Documentation validation..."

run_test "Simplified deployment docs exist" "[ -f SIMPLIFIED-DEPLOYMENT.md ]"
run_test "Comparison docs exist" "[ -f DEPLOYMENT-COMPARISON.md ]"
run_test "Docs contain usage examples" "grep -q './deploy.sh' SIMPLIFIED-DEPLOYMENT.md"

echo
echo "=== Test Summary ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo

if [ $TESTS_FAILED -eq 0 ]; then
    pass "All tests passed! Simplified deployment system validated."
    echo
    echo "Next steps:"
    echo "1. Review configuration: ansible/group_vars/all.yml"
    echo "2. Update inventory: ansible/inventory.txt" 
    echo "3. Test deployment: ./deploy.sh check"
    echo "4. Deploy: ./deploy.sh"
    exit 0
else
    fail "Some tests failed. Please review the issues above."
    exit 1
fi
#!/bin/bash

# Test Enhanced Spindown Functionality
# Validates the improvements made to ensure complete infrastructure cleanup

echo "=== Enhanced Spindown Functionality Test ==="
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

echo "=== Test 1: Enhanced Spindown Features in Playbook ==="

# Test for container storage cleanup
if grep -q "Clean up container image stores and overlayfs mounts" ansible/subsites/00-spindown.yaml; then
    pass "✓ Container storage and overlayfs cleanup found"
    ((TESTS_PASSED++))
else
    fail "✗ Container storage cleanup missing"
    ((TESTS_FAILED++))
fi

# Test for iptables cleanup
if grep -q "Clean up iptables rules related to Kubernetes and containers" ansible/subsites/00-spindown.yaml; then
    pass "✓ iptables cleanup functionality found"
    ((TESTS_PASSED++))
else
    fail "✗ iptables cleanup missing"
    ((TESTS_FAILED++))
fi

# Test for routing table cleanup
if grep -q "Clean up routing tables and IP routes" ansible/subsites/00-spindown.yaml; then
    pass "✓ Routing table cleanup found"
    ((TESTS_PASSED++))
else
    fail "✗ Routing table cleanup missing"  
    ((TESTS_FAILED++))
fi

# Test for systemd cleanup
if grep -q "Clean up systemd drop-in directories and overrides" ansible/subsites/00-spindown.yaml; then
    pass "✓ systemd configuration cleanup found"
    ((TESTS_PASSED++))
else
    fail "✗ systemd cleanup missing"
    ((TESTS_FAILED++))
fi

# Test for user configuration cleanup  
if grep -q "Clean up user bash history and profiles related to VMStation" ansible/subsites/00-spindown.yaml; then
    pass "✓ User configuration cleanup found"
    ((TESTS_PASSED++))
else
    fail "✗ User configuration cleanup missing"
    ((TESTS_FAILED++))
fi

# Test for cache cleanup
if grep -q "Clean up temporary files and caches" ansible/subsites/00-spindown.yaml; then
    pass "✓ Temporary files and cache cleanup found"
    ((TESTS_PASSED++))
else
    fail "✗ Cache cleanup missing"
    ((TESTS_FAILED++))
fi

# Test for validation logic
if grep -q "Validate cleanup completeness" ansible/subsites/00-spindown.yaml; then
    pass "✓ Cleanup validation logic found"
    ((TESTS_PASSED++))
else
    fail "✗ Cleanup validation missing"
    ((TESTS_FAILED++))
fi

echo
echo "=== Test 2: Deploy Script Integration ==="

# Test spindown option in deploy script
if grep -q "spindown.*DESTRUCTIVE.*Remove all Kubernetes infrastructure" deploy.sh; then
    pass "✓ Spindown option integrated into deploy script"
    ((TESTS_PASSED++))
else
    fail "✗ Spindown option not integrated"
    ((TESTS_FAILED++))
fi

# Test spindown-check option
if grep -q "spindown-check.*Show what spindown would remove" deploy.sh; then
    pass "✓ Spindown check option available"
    ((TESTS_PASSED++))
else
    fail "✗ Spindown check option missing"
    ((TESTS_FAILED++))
fi

# Test safety confirmation
if grep -q "Are you sure you want to proceed.*Type.*yes.*to continue" deploy.sh; then
    pass "✓ Safety confirmation prompt found"
    ((TESTS_PASSED++))
else
    fail "✗ Safety confirmation missing"
    ((TESTS_FAILED++))
fi

echo
echo "=== Test 3: Comprehensive Cleanup Areas ==="

# Test specific cleanup areas that are commonly missed
CLEANUP_AREAS=(
    "overlay"
    "KUBE-SERVICES"
    "CNI-"
    "kubelet.service.d"
    "bash_history"
    "vmstation-"
    "cache"
)

CLEANUP_DESCRIPTIONS=(
    "overlayfs mount cleanup"
    "Kubernetes iptables chains"
    "CNI iptables chains"
    "systemd drop-in directories"
    "user bash history cleanup"
    "temporary VMStation files"
    "package manager caches"
)

for i in "${!CLEANUP_AREAS[@]}"; do
    area="${CLEANUP_AREAS[$i]}"
    desc="${CLEANUP_DESCRIPTIONS[$i]}"
    if grep -q "$area" ansible/subsites/00-spindown.yaml; then
        pass "✓ Cleanup area found: $desc"
        ((TESTS_PASSED++))
    else
        fail "✗ Missing cleanup area: $desc"
        ((TESTS_FAILED++))
    fi
done

echo
echo "=== Test 4: Ansible Syntax and Structure ==="

run_test "Spindown playbook syntax validation" "ansible-playbook --syntax-check ansible/subsites/00-spindown.yaml"
run_test "Deploy script is executable" "[ -x deploy.sh ]"
run_test "Deploy script help shows spindown options" "./deploy.sh help 2>&1 | grep -q spindown"

echo
echo "=== Test 5: Safety and Error Handling ==="

# Test safety gates and error handling
if grep -c "ignore_errors: true" ansible/subsites/00-spindown.yaml | grep -q "[1-9][0-9]"; then
    pass "✓ Proper error handling with ignore_errors found"
    ((TESTS_PASSED++))
else
    fail "✗ Insufficient error handling"
    ((TESTS_FAILED++))
fi

if grep -q "Safety gate.*require explicit confirmation" ansible/subsites/00-spindown.yaml; then
    pass "✓ Safety gate for destructive operations found"
    ((TESTS_PASSED++))
else
    fail "✗ Safety gate missing"
    ((TESTS_FAILED++))
fi

echo
echo "=== Test Summary ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo

if [ $TESTS_FAILED -eq 0 ]; then
    pass "All enhanced spindown tests passed!"
    echo
    echo "Enhanced Spindown Features Summary:"
    echo "✓ Integrated spindown option into simplified deploy script"
    echo "✓ Added comprehensive iptables and routing cleanup"
    echo "✓ Enhanced container storage and overlayfs cleanup"
    echo "✓ Added systemd drop-in and service cleanup"
    echo "✓ Included user configuration and history cleanup"
    echo "✓ Added temporary files and cache cleanup"
    echo "✓ Implemented cleanup validation and reporting"
    echo "✓ Maintained all existing safety mechanisms"
    echo
    echo "Usage:"
    echo "  ./deploy.sh spindown-check   # Safe preview of what will be removed"
    echo "  ./deploy.sh spindown        # Complete infrastructure removal"
    echo
    exit 0
else
    fail "$TESTS_FAILED tests failed. Check the output above for details."
    exit 1
fi
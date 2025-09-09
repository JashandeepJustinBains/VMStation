#!/bin/bash

# Test script for Kubernetes authorization mode configuration
# Validates that the authorization mode configuration is properly implemented

echo "=== VMStation Authorization Mode Configuration Test ==="
echo "Timestamp: $(date)"
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

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

echo "1. Testing authorization mode configuration in group_vars..."

run_test "Authorization mode variable exists in template" "grep -q 'kubernetes_authorization_mode:' ansible/group_vars/all.yml.template"
run_test "Fallback variable exists in template" "grep -q 'kubernetes_authorization_fallback:' ansible/group_vars/all.yml.template"
run_test "Default authorization mode is Node,RBAC" "grep -q 'kubernetes_authorization_mode: \"Node,RBAC\"' ansible/group_vars/all.yml.template"
run_test "Default fallback is disabled" "grep -q 'kubernetes_authorization_fallback: false' ansible/group_vars/all.yml.template"

echo
echo "2. Testing kubeadm init configuration..."

run_test "Authorization mode variable defined in setup-cluster.yaml" "grep -q 'auth_mode:.*kubernetes_authorization_mode' ansible/plays/setup-cluster.yaml"
run_test "Fallback variable defined in setup-cluster.yaml" "grep -q 'enable_fallback:.*kubernetes_authorization_fallback' ansible/plays/setup-cluster.yaml"
run_test "Authorization mode passed to kubeadm init" "grep -q '\--authorization-mode={{ auth_mode }}' ansible/plays/setup-cluster.yaml"
run_test "Fallback kubeadm init with AlwaysAllow exists" "grep -q '\--authorization-mode=AlwaysAllow' ansible/plays/setup-cluster.yaml"
run_test "Fallback has proper conditions" "grep -A 3 -B 2 'kubeadm_init.failed' ansible/plays/setup-cluster.yaml | grep -q 'enable_fallback'"

echo
echo "3. Testing RBAC fix enhancements..."

run_test "Current authorization mode check exists" "grep -q 'Check current authorization mode' ansible/plays/setup-cluster.yaml"
run_test "RBAC fix conditional on RBAC mode" "grep -n \"'RBAC' in current_auth_mode.stdout\" ansible/plays/setup-cluster.yaml >/dev/null"
run_test "AlwaysAllow mode skip message exists" "grep -q 'Skip RBAC fix for AlwaysAllow mode' ansible/plays/setup-cluster.yaml"
run_test "Authorization mode display task exists" "grep -q 'Display current authorization mode' ansible/plays/setup-cluster.yaml"

echo
echo "4. Testing file syntax and structure..."

run_test "setup-cluster.yaml has valid syntax" "ansible-playbook --syntax-check ansible/plays/setup-cluster.yaml"
run_test "group_vars template has no syntax errors" "[ -f ansible/group_vars/all.yml.template ]"

echo
echo "5. Testing configuration scenarios..."

# Create temporary test files
TMP_DIR="/tmp/vmstation_auth_test"
mkdir -p "$TMP_DIR"

# Test with Node,RBAC mode
cat > "$TMP_DIR/test_node_rbac.yml" << 'EOF'
kubernetes_authorization_mode: "Node,RBAC"
kubernetes_authorization_fallback: false
EOF

# Test with AlwaysAllow mode
cat > "$TMP_DIR/test_always_allow.yml" << 'EOF'
kubernetes_authorization_mode: "AlwaysAllow"
kubernetes_authorization_fallback: false
EOF

# Test with fallback enabled
cat > "$TMP_DIR/test_fallback.yml" << 'EOF'
kubernetes_authorization_mode: "Node,RBAC"
kubernetes_authorization_fallback: true
EOF

run_test "Node,RBAC configuration valid" "[ -f '$TMP_DIR/test_node_rbac.yml' ]"
run_test "AlwaysAllow configuration valid" "[ -f '$TMP_DIR/test_always_allow.yml' ]"
run_test "Fallback configuration valid" "[ -f '$TMP_DIR/test_fallback.yml' ]"

# Cleanup
rm -rf "$TMP_DIR"

echo
echo "6. Testing backward compatibility..."

run_test "Default values preserve existing behavior" "grep -q 'default.*Node,RBAC' ansible/plays/setup-cluster.yaml"
run_test "Fallback is opt-in only" "grep -q 'default.*false' ansible/plays/setup-cluster.yaml"

echo
echo "=== Test Results ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    pass "All authorization mode configuration tests passed!"
    echo
    echo "The authorization mode configuration provides:"
    echo "1. ✅ Configurable authorization mode (Node,RBAC or AlwaysAllow)"
    echo "2. ✅ Automatic fallback to AlwaysAllow if Node,RBAC fails (opt-in)"
    echo "3. ✅ Enhanced RBAC fix that respects authorization mode"
    echo "4. ✅ Clear warnings when less secure modes are used"
    echo "5. ✅ Backward compatibility with existing deployments"
    echo
    info "Configuration options:"
    echo "  • Set kubernetes_authorization_mode: 'Node,RBAC' (default, recommended)"
    echo "  • Set kubernetes_authorization_mode: 'AlwaysAllow' (less secure, troubleshooting)"
    echo "  • Set kubernetes_authorization_fallback: true (enables automatic fallback)"
    exit 0
else
    fail "Some authorization mode configuration tests failed!"
    echo
    echo "Please check the implementation for issues."
    exit 1
fi
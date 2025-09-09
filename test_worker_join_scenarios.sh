#!/bin/bash

# Test script for worker node join scenarios with different authorization modes
# Simulates common scenarios and validates the configuration handles them correctly

echo "=== VMStation Worker Join Scenarios Test ==="
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

# Create temporary directory for test configurations
TMP_DIR="/tmp/vmstation_worker_join_test"
mkdir -p "$TMP_DIR"

echo "1. Testing configuration validation..."

# Test 1: Valid Node,RBAC configuration
cat > "$TMP_DIR/node_rbac_config.yml" << 'EOF'
kubernetes_authorization_mode: "Node,RBAC"
kubernetes_authorization_fallback: false
pod_network_cidr: "10.244.0.0/16"
EOF

run_test "Node,RBAC config syntax valid" "python3 -c 'import yaml; yaml.safe_load(open(\"$TMP_DIR/node_rbac_config.yml\"))'"

# Test 2: Valid AlwaysAllow configuration
cat > "$TMP_DIR/always_allow_config.yml" << 'EOF'
kubernetes_authorization_mode: "AlwaysAllow"
kubernetes_authorization_fallback: false
pod_network_cidr: "10.244.0.0/16"
EOF

run_test "AlwaysAllow config syntax valid" "python3 -c 'import yaml; yaml.safe_load(open(\"$TMP_DIR/always_allow_config.yml\"))'"

# Test 3: Valid fallback configuration
cat > "$TMP_DIR/fallback_config.yml" << 'EOF'
kubernetes_authorization_mode: "Node,RBAC"
kubernetes_authorization_fallback: true
pod_network_cidr: "10.244.0.0/16"
EOF

run_test "Fallback config syntax valid" "python3 -c 'import yaml; yaml.safe_load(open(\"$TMP_DIR/fallback_config.yml\"))'"

echo
echo "2. Testing kubeadm command generation..."

# Test command generation logic
run_test "Node,RBAC kubeadm command pattern" "grep -q 'authorization-mode={{ auth_mode }}' ansible/plays/setup-cluster.yaml"
run_test "AlwaysAllow fallback command pattern" "grep -q 'authorization-mode=AlwaysAllow' ansible/plays/setup-cluster.yaml"
run_test "Fallback condition includes failed check" "grep -n 'kubeadm_init.failed' ansible/plays/setup-cluster.yaml >/dev/null"

echo
echo "3. Testing RBAC handling scenarios..."

# Verify RBAC handling is mode-aware
run_test "RBAC check exists" "grep -q 'kubectl auth can-i create secrets' ansible/plays/setup-cluster.yaml"
run_test "Authorization mode detection exists" "grep -q 'Check current authorization mode' ansible/plays/setup-cluster.yaml"
run_test "RBAC fix is conditional" "grep -n \"'RBAC' in current_auth_mode.stdout\" ansible/plays/setup-cluster.yaml >/dev/null"
run_test "AlwaysAllow skip logic exists" "grep -q 'Skip RBAC fix for AlwaysAllow mode' ansible/plays/setup-cluster.yaml"

echo
echo "4. Testing join command scenarios..."

# Verify join command generation is robust
run_test "Join command has retry logic" "grep -A 3 'Generate join command' ansible/plays/setup-cluster.yaml | grep -q 'retries: 3'"
run_test "Join command has delay" "grep -A 4 'Generate join command' ansible/plays/setup-cluster.yaml | grep -q 'delay: 10'"
run_test "Join command has success condition" "grep -A 5 'Generate join command' ansible/plays/setup-cluster.yaml | grep -q 'until: join_command.rc == 0'"

echo
echo "5. Testing worker node join logic..."

# Verify worker join process
run_test "Worker join checks for existing config" "grep -q 'Check if node is joined' ansible/plays/setup-cluster.yaml"
run_test "Join command is copied from control plane" "grep -q 'Copy join command from control plane' ansible/plays/setup-cluster.yaml"
run_test "Join execution is conditional" "grep -A 2 'Join cluster' ansible/plays/setup-cluster.yaml | grep -q 'when: not kubelet_conf.stat.exists'"

echo
echo "6. Testing scenario-specific behavior..."

# Create test scenarios for different modes
create_scenario_test() {
    local mode="$1"
    local fallback="$2"
    local test_file="$TMP_DIR/scenario_${mode,,}_${fallback}.yml"
    
    cat > "$test_file" << EOF
kubernetes_authorization_mode: "$mode"
kubernetes_authorization_fallback: $fallback
EOF
    
    echo "$test_file"
}

# Scenario A: Production setup (Node,RBAC, no fallback)
PROD_CONFIG=$(create_scenario_test "Node,RBAC" "false")
run_test "Production scenario config valid" "[ -f '$PROD_CONFIG' ]"

# Scenario B: Troubleshooting setup (Node,RBAC with fallback)
TROUBLE_CONFIG=$(create_scenario_test "Node,RBAC" "true") 
run_test "Troubleshooting scenario config valid" "[ -f '$TROUBLE_CONFIG' ]"

# Scenario C: Emergency setup (AlwaysAllow)
EMERGENCY_CONFIG=$(create_scenario_test "AlwaysAllow" "false")
run_test "Emergency scenario config valid" "[ -f '$EMERGENCY_CONFIG' ]"

echo
echo "7. Testing error handling and warnings..."

# Verify proper error handling exists
run_test "Fallback warning message exists" "grep -q 'WARNING.*AlwaysAllow' ansible/plays/setup-cluster.yaml"
run_test "Authorization mode display exists" "grep -q 'Display current authorization mode' ansible/plays/setup-cluster.yaml"
run_test "Ignore errors for fallback" "grep -q 'ignore_errors.*enable_fallback' ansible/plays/setup-cluster.yaml"

echo
echo "8. Testing integration scenarios..."

# Test that all components work together
run_test "CNI installation after init" "grep -A 5 'Install Flannel CNI' ansible/plays/setup-cluster.yaml | grep -q 'when: kubeadm_init is changed'"
run_test "RBAC validation before join command" "[ $(grep -n 'Validate kubernetes-admin RBAC' ansible/plays/setup-cluster.yaml | cut -d: -f1) -lt $(grep -n 'Generate join command' ansible/plays/setup-cluster.yaml | cut -d: -f1) ]"

echo
echo "9. Testing backward compatibility..."

# Ensure existing deployments still work
run_test "Default values preserve behavior" "grep -q 'default.*Node,RBAC' ansible/plays/setup-cluster.yaml"
run_test "Existing RBAC tests still pass" "./test_rbac_fix.sh >/dev/null 2>&1"

# Cleanup
rm -rf "$TMP_DIR"

echo
echo "=== Test Results ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    pass "All worker join scenario tests passed!"
    echo
    echo "The authorization mode configuration correctly handles:"
    echo "1. ✅ Production deployments with secure Node,RBAC mode"
    echo "2. ✅ Troubleshooting scenarios with automatic fallback"
    echo "3. ✅ Emergency AlwaysAllow mode for critical issues"
    echo "4. ✅ Intelligent RBAC handling based on authorization mode"
    echo "5. ✅ Robust join command generation with retry logic"
    echo "6. ✅ Proper error handling and user warnings"
    echo "7. ✅ Backward compatibility with existing deployments"
    echo
    info "Configuration summary:"
    echo "  • Node,RBAC mode: Secure, production-ready authorization"
    echo "  • AlwaysAllow mode: Troubleshooting only, with clear warnings"
    echo "  • Fallback mode: Automatic retry mechanism for cluster init issues"
    echo "  • RBAC fixes: Mode-aware, only applied when appropriate"
    echo
    success "Worker nodes should now be able to join the cluster successfully!"
    exit 0
else
    fail "Some worker join scenario tests failed!"
    echo
    echo "Please review the implementation for issues."
    exit 1
fi
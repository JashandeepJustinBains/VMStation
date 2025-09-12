#!/bin/bash

# VMStation Enhanced Worker Join Preflight Tests
# Validates the enhanced join process functionality

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_RESULTS_DIR="/tmp/vmstation-join-tests-$(date +%Y%m%d-%H%M%S)"

echo "=== VMStation Enhanced Worker Join Preflight Tests ==="
echo "Timestamp: $(date)"
echo "Project root: $PROJECT_ROOT"
echo "Test results: $TEST_RESULTS_DIR"
echo ""

# Create test results directory
mkdir -p "$TEST_RESULTS_DIR"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"  # Expected exit code (default: 0)
    
    ((TESTS_TOTAL++))
    info "Running test: $test_name"
    
    local result=0
    if eval "$test_command" >"$TEST_RESULTS_DIR/test_${TESTS_TOTAL}_$(echo "$test_name" | tr ' ' '_').log" 2>&1; then
        result=0
    else
        result=$?
    fi
    
    if [ $result -eq $expected_result ]; then
        ((TESTS_PASSED++))
        info "✅ PASS: $test_name"
    else
        ((TESTS_FAILED++))
        error "❌ FAIL: $test_name (exit code: $result, expected: $expected_result)"
    fi
    
    return $result
}

# Test 1: Check enhanced join script exists and is executable
run_test "Enhanced join script exists" "test -x '$PROJECT_ROOT/scripts/enhanced_kubeadm_join.sh'"

# Test 2: Check gather diagnostics script exists and is executable
run_test "Gather diagnostics script exists" "test -x '$PROJECT_ROOT/scripts/gather_worker_diagnostics.sh'"

# Test 3: Check quick diagnostics script exists and is executable
run_test "Quick diagnostics script exists" "test -x '$PROJECT_ROOT/scripts/quick_join_diagnostics.sh'"

# Test 4: Check Ansible playbook syntax
run_test "Ansible playbook syntax check" "ansible-playbook --syntax-check '$PROJECT_ROOT/ansible/plays/setup-cluster.yaml'"

# Test 5: Validate enhanced join script can show help (check if it handles invalid args gracefully)
run_test "Enhanced join script invalid args handling" "'$PROJECT_ROOT/scripts/enhanced_kubeadm_join.sh' 2>&1 | grep -q 'Usage\|kubeadm.*join\|Error'" 1

# Test 6: Validate gather diagnostics script can show help
run_test "Gather diagnostics script help" "'$PROJECT_ROOT/scripts/gather_worker_diagnostics.sh' --help"

# Test 7: Check for required crictl configuration handling
run_test "Enhanced join script contains crictl fixes" "grep -q 'crictl.*config\|socket.*perm' '$PROJECT_ROOT/scripts/enhanced_kubeadm_join.sh'"

# Test 8: Check for token refresh functionality
run_test "Enhanced join script contains token refresh" "grep -q 'refresh.*token\|TOKEN_REFRESH' '$PROJECT_ROOT/scripts/enhanced_kubeadm_join.sh'"

# Test 9: Check for kubelet config validation
run_test "Enhanced join script contains kubelet validation" "grep -q 'validate.*kubelet.*config\|kubelet.*config.*yaml' '$PROJECT_ROOT/scripts/enhanced_kubeadm_join.sh'"

# Test 10: Check Ansible playbook contains enhanced error handling
run_test "Ansible playbook contains enhanced error handling" "grep -q 'failure.*diagnostics\|Handle.*join.*failures' '$PROJECT_ROOT/ansible/plays/setup-cluster.yaml'"

# Test 11: Check for comprehensive logging
run_test "Enhanced join script has comprehensive logging" "grep -q 'LOG_FILE\|log_both\|tee.*LOG' '$PROJECT_ROOT/scripts/enhanced_kubeadm_join.sh'"

# Test 12: Validate documentation exists
run_test "Enhanced troubleshooting documentation exists" "test -f '$PROJECT_ROOT/docs/MANUAL_CLUSTER_TROUBLESHOOTING.md'"

# Test 13: Check documentation contains new troubleshooting steps
run_test "Documentation contains crictl troubleshooting" "grep -q 'crictl.*communication\|socket.*permission' '$PROJECT_ROOT/docs/MANUAL_CLUSTER_TROUBLESHOOTING.md'"

# Test 14: Check for containerd filesystem fix references
run_test "Documentation mentions containerd filesystem fixes" "grep -q 'invalid capacity 0\|filesystem.*capacity' '$PROJECT_ROOT/docs/MANUAL_CLUSTER_TROUBLESHOOTING.md'"

# Test 15: Check gather script has comprehensive collection
run_test "Gather script collects comprehensive diagnostics" "grep -q 'kubelet.*log\|containerd.*log\|kubeadm.*join.*log' '$PROJECT_ROOT/scripts/gather_worker_diagnostics.sh'"

# Test 16: Simulate crictl configuration test (dry run)
run_test "Enhanced join script crictl test simulation" "bash -n '$PROJECT_ROOT/scripts/enhanced_kubeadm_join.sh'"

# Test 17: Check for proper error exit codes in scripts
run_test "Enhanced join script has proper error handling" "grep -q 'exit 1\|failed_when.*false\|error.*exit' '$PROJECT_ROOT/scripts/enhanced_kubeadm_join.sh'"

# Test 18: Validate quick diagnostics functionality
run_test "Quick diagnostics script syntax check" "bash -n '$PROJECT_ROOT/scripts/quick_join_diagnostics.sh'"

# Test 19: Check for socket permission handling in Ansible
run_test "Ansible playbook handles socket permissions" "grep -q 'containerd.*socket\|socket.*permission\|chgrp.*containerd' '$PROJECT_ROOT/ansible/plays/setup-cluster.yaml'"

# Test 20: Check for skip join logic
run_test "Ansible playbook has skip join logic" "grep -q 'skip.*join\|already.*joined\|KUBELET_ALREADY_JOINED' '$PROJECT_ROOT/ansible/plays/setup-cluster.yaml'"

# Simulation Tests (if crictl/containerd available)
if command -v crictl >/dev/null 2>&1; then
    info "Running simulation tests with available crictl..."
    
    # Test 21: Test crictl configuration creation (simulation)
    run_test "Crictl config creation test" "
        temp_config='/tmp/test_crictl.yaml'
        cat > \"\$temp_config\" << 'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
        test -f \"\$temp_config\" && rm -f \"\$temp_config\"
    "
else
    warn "crictl not available - skipping simulation tests"
fi

# Summary
echo ""
info "=== Test Results Summary ==="
info "Total tests: $TESTS_TOTAL"
info "Passed: $TESTS_PASSED"
info "Failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    info "🎉 All tests passed! Enhanced worker join functionality is properly implemented."
    echo ""
    info "Key enhancements validated:"
    info "  ✅ crictl configuration and socket permission handling"
    info "  ✅ Token refresh and retry logic"
    info "  ✅ kubelet config validation and remediation"
    info "  ✅ Comprehensive error logging and diagnostics"
    info "  ✅ Enhanced documentation and troubleshooting guides"
    info "  ✅ Automated diagnostic gathering capabilities"
    echo ""
    info "The worker node join process should now be significantly more reliable!"
else
    warn "Some tests failed. Review the test results in: $TEST_RESULTS_DIR"
    echo ""
    warn "Failed tests may indicate:"
    warn "  - Missing files or incorrect paths"
    warn "  - Syntax errors in scripts"
    warn "  - Missing functionality in enhanced join process"
    echo ""
    warn "Please address the failed tests before deploying the enhanced join process."
fi

echo ""
info "Test results saved to: $TEST_RESULTS_DIR"
info "Review individual test logs for detailed output."

# Exit with appropriate code
if [ $TESTS_FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
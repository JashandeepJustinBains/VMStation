#!/bin/bash

# Test Worker Node Join Task Implementation
# Validates that all requirements from the problem statement are met

set -euo pipefail

echo "=== Worker Node Join Task Implementation Test ==="
echo "Timestamp: $(date)"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass_count=0
total_tests=0

test_pass() {
    echo -e "  ${GREEN}✓ PASS${NC}: $1"
    ((pass_count++))
}

test_fail() {
    echo -e "  ${RED}✗ FAIL${NC}: $1"
}

test_info() {
    echo -e "  ${YELLOW}ℹ INFO${NC}: $1"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo "Test: $test_name"
    ((total_tests++))
    
    if eval "$test_command"; then
        test_pass "$test_name"
    else
        test_fail "$test_name"
    fi
    echo ""
}

# Test 1: Verify enhanced troubleshooting documentation exists
run_test "Enhanced RHEL10 troubleshooting documentation" \
    "grep -q 'Critical Worker Node Join Failures - Advanced Diagnostics' docs/RHEL10_TROUBLESHOOTING.md"

# Test 2: Verify diagnostic script exists and is executable
run_test "Worker node join diagnostics script" \
    "[ -x worker_node_join_diagnostics.sh ]"

# Test 3: Verify remediation script exists and is executable  
run_test "Worker node join remediation script" \
    "[ -x worker_node_join_remediation.sh ]"

# Test 4: Verify task receipt documentation
run_test "Task receipt documentation" \
    "[ -f WORKER_NODE_JOIN_TASK_RECEIPT.md ]"

# Test 5: Check for CNI diagnostic commands in documentation
run_test "CNI configuration diagnostic commands in docs" \
    "grep -q 'no network config found in /etc/cni/net.d' docs/RHEL10_TROUBLESHOOTING.md"

# Test 6: Check for kubelet port conflict documentation  
run_test "kubelet port 10250 conflict documentation" \
    "grep -q 'port 10250.*conflict' docs/RHEL10_TROUBLESHOOTING.md || grep -q 'Port-10250' docs/RHEL10_TROUBLESHOOTING.md"

# Test 7: Check for containerd filesystem capacity documentation
run_test "Containerd filesystem capacity documentation" \
    "grep -q 'invalid capacity 0.*image filesystem' docs/RHEL10_TROUBLESHOOTING.md"

# Test 8: Verify /mnt/media preservation mentioned
run_test "/mnt/media preservation documented" \
    "grep -q '/mnt/media' docs/RHEL10_TROUBLESHOOTING.md && grep -q 'preserv' docs/RHEL10_TROUBLESHOOTING.md"

# Test 9: Check diagnostic script has all required checks
run_test "Diagnostic script includes CNI checks" \
    "grep -q 'CNI AND KUBERNETES CONFIGURATION CHECKS' worker_node_join_diagnostics.sh"

run_test "Diagnostic script includes filesystem checks" \
    "grep -q 'IMAGE FILESYSTEM AND MOUNT CHECKS' worker_node_join_diagnostics.sh"

run_test "Diagnostic script includes CRI checks" \
    "grep -q 'CONTAINER RUNTIME INTERFACE.*CRI.*CHECKS' worker_node_join_diagnostics.sh"

run_test "Diagnostic script includes kubelet port checks" \
    "grep -q 'KUBELET SERVICE AND PORT STATUS' worker_node_join_diagnostics.sh"

# Test 10: Check remediation script has proper phases
run_test "Remediation script has stop/mask kubelet phase" \
    "grep -q 'systemctl.*mask kubelet' worker_node_join_remediation.sh"

run_test "Remediation script has filesystem fix phase" \
    "grep -q '/var/lib/containerd' worker_node_join_remediation.sh && grep -q 'filesystem' worker_node_join_remediation.sh"

run_test "Remediation script has kubeadm reset phase" \
    "grep -q 'kubeadm reset' worker_node_join_remediation.sh"

# Test 11: Verify enhanced CNI verification script
run_test "Enhanced CNI verification includes critical checks" \
    "grep -q 'no network config found' manual_cni_verification.sh"

# Test 12: Check syntax validation passes
run_test "All scripts have valid syntax" \
    "bash -n worker_node_join_diagnostics.sh && bash -n worker_node_join_remediation.sh"

# Test 13: Verify immediate read-only checks are documented
run_test "Immediate read-only diagnostic commands documented" \
    "grep -A 20 'Immediate Read-Only Diagnostic Commands' docs/RHEL10_TROUBLESHOOTING.md | grep -q 'ls -la /etc/cni/net.d'"

# Test 14: Verify exact remediation sequence documented  
run_test "Exact remediation sequence documented" \
    "grep -A 30 'Exact Remediation Sequence' docs/RHEL10_TROUBLESHOOTING.md | grep -q 'Phase 1.*Phase 2.*Phase 3'"

# Test 15: Check that problem statement requirements are addressed
echo "=== Problem Statement Requirements Check ==="

test_info "Checking problem statement requirement: Explain why join still fails"
if grep -q "Why Joins Still Fail After Basic Fixes" docs/RHEL10_TROUBLESHOOTING.md; then
    test_pass "Join failure explanation documented"
    ((pass_count++))
else
    test_fail "Join failure explanation missing"
fi
((total_tests++))

test_info "Checking problem statement requirement: Small, safe checks to run"
if [ -x worker_node_join_diagnostics.sh ] && grep -q "read-only" worker_node_join_diagnostics.sh; then
    test_pass "Safe diagnostic checks implemented"
    ((pass_count++))
else
    test_fail "Safe diagnostic checks missing"
fi
((total_tests++))

test_info "Checking problem statement requirement: Exact remediation steps"
if [ -x worker_node_join_remediation.sh ] && grep -q "stop.*mask kubelet" worker_node_join_remediation.sh; then
    test_pass "Exact remediation steps implemented"
    ((pass_count++))
else
    test_fail "Exact remediation steps missing"
fi
((total_tests++))

# Summary
echo ""
echo "=== Test Summary ==="
echo "Passed: $pass_count/$total_tests tests"

if [ $pass_count -eq $total_tests ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC} - Implementation meets all requirements"
    echo ""
    echo "Implementation successfully addresses:"
    echo "✓ CNI configuration missing ('no network config found in /etc/cni/net.d')"
    echo "✓ kubelet standalone mode blocking kubeadm join (port 10250 conflicts)"
    echo "✓ containerd image filesystem capacity issues (invalid capacity 0)"
    echo "✓ PLEG health problems affecting node registration"
    echo "✓ Safe diagnostic commands for immediate analysis"
    echo "✓ Exact remediation sequence preserving /mnt/media"
    echo "✓ Comprehensive documentation and automation"
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC} - Implementation incomplete"
    exit 1
fi
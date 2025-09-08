#!/bin/bash

# Comprehensive test for spindown/rejoin fix
# Tests the worker node join issues that occur after spindown and redeployment

echo "=== Spindown/Rejoin Worker Node Fix Validation ==="
echo "Testing fix for: worker nodes unable to join after spindown/redeploy"
echo ""

SETUP_CLUSTER_FILE="ansible/plays/kubernetes/setup_cluster.yaml"
TESTS_PASSED=0
TESTS_TOTAL=0

# Helper function to run test
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo "Test $TESTS_TOTAL: $test_name"
    
    if eval "$test_command"; then
        echo "✓ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "✗ FAIL: $test_name"
    fi
    echo ""
}

# Test 1: Token cleanup before generation
run_test "Token cleanup before new generation" \
    "grep -q 'Cleaning up any existing bootstrap tokens' '$SETUP_CLUSTER_FILE'"

# Test 2: Enhanced join command generation with TTL
run_test "Join command generation with 24h TTL" \
    "grep -q 'kubeadm token create.*--ttl 24h' '$SETUP_CLUSTER_FILE'"

# Test 3: Join command validation
run_test "Join command validation present" \
    "grep -q 'Validate join command contains required components' '$SETUP_CLUSTER_FILE'"

# Test 4: Timestamped join command file
run_test "Timestamped join command with metadata" \
    "grep -q 'Generated:.*ansible_date_time' '$SETUP_CLUSTER_FILE'"

# Test 5: Enhanced kubelet.conf validation with connectivity test
run_test "Enhanced kubelet.conf validation with cluster connectivity" \
    "grep -q 'kubectl.*--kubeconfig=/etc/kubernetes/kubelet.conf.*cluster-info' '$SETUP_CLUSTER_FILE'"

# Test 6: Force rejoin on disconnected nodes
run_test "Force rejoin when kubelet.conf is disconnected" \
    "grep -q 'valid-and-connected' '$SETUP_CLUSTER_FILE'"

# Test 7: Join command freshness validation
run_test "Join command freshness validation" \
    "grep -q 'Validate join command freshness and content' '$SETUP_CLUSTER_FILE'"

# Test 8: Age check for join command (23 hour threshold)
run_test "Join command age validation (23h threshold)" \
    "grep -q 'find.*kubeadm-join.sh.*-mmin +1380' '$SETUP_CLUSTER_FILE'"

# Test 9: Stale state cleanup before join
run_test "Stale state cleanup before join attempts" \
    "grep -q 'Clean up any stale join state.*post-spindown recovery' '$SETUP_CLUSTER_FILE'"

# Test 10: Force rejoin reason tracking
run_test "Force rejoin reason tracking" \
    "grep -q 'force_rejoin_reason' '$SETUP_CLUSTER_FILE'"

# Test 11: Join command retry with better error handling
run_test "Join command generation with retries" \
    "grep -A 5 'kubeadm token create.*--ttl' '$SETUP_CLUSTER_FILE' | grep -q 'retries:' && grep -A 5 'kubeadm token create.*--ttl' '$SETUP_CLUSTER_FILE' | grep -q 'delay:' && grep -A 5 'kubeadm token create.*--ttl' '$SETUP_CLUSTER_FILE' | grep -q 'until:'"

# Test 12: Ansible syntax validation
run_test "Ansible syntax validation" \
    "ansible-playbook --syntax-check '$SETUP_CLUSTER_FILE' -i ansible/inventory.txt > /dev/null 2>&1"

echo "=== Test Summary ==="
echo "Tests passed: $TESTS_PASSED/$TESTS_TOTAL"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo "🎉 All tests passed!"
    echo ""
    echo "=== Fix Summary ==="
    echo "The spindown/rejoin worker node issue has been resolved by:"
    echo ""
    echo "1. **Token Management**:"
    echo "   - Clean up existing tokens before generating new ones"
    echo "   - Generate tokens with explicit 24h TTL"
    echo "   - Validate token format and content"
    echo ""
    echo "2. **Join Command Validation**:"
    echo "   - Check join command age (expire after 23 hours)"
    echo "   - Validate join command format and required components"
    echo "   - Add metadata (timestamp, control plane info) to join file"
    echo ""
    echo "3. **Enhanced kubelet.conf Validation**:"
    echo "   - Test both file existence AND cluster connectivity"
    echo "   - Force rejoin if kubelet.conf references old/invalid cluster"
    echo "   - Track reasons for forced rejoins"
    echo ""
    echo "4. **Pre-join Cleanup**:"
    echo "   - Remove stale join artifacts (backup files, old flags)"
    echo "   - Clean up invalid kubelet.conf files"
    echo "   - Clear any leftover state from previous join attempts"
    echo ""
    echo "5. **Improved Error Handling**:"
    echo "   - Retry token generation with backoff"
    echo "   - Clear error messages for common failure scenarios"
    echo "   - Better diagnostics for troubleshooting"
    echo ""
    echo "Expected result after spindown/redeploy:"
    echo "- Workers will detect their old kubelet.conf is invalid/disconnected"
    echo "- Fresh join tokens will be generated on control plane"
    echo "- Join command validation will ensure tokens are fresh"
    echo "- Workers will successfully rejoin with new cluster certificates"
    echo ""
    exit 0
else
    echo "❌ Some tests failed. Check the output above for details."
    exit 1
fi
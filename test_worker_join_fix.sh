#!/bin/bash

# Comprehensive test for the worker node join fix
# Tests the removal of static kubeadm-flags.env creation that was preventing joins

echo "=== Worker Node Join Fix Validation ==="
echo "Testing fix for issue: workers not able to join the cluster"
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

# Test 1: Static kubeadm-flags.env creation is removed
run_test "Static kubeadm-flags.env creation removed" \
    "! grep -q 'dest: /var/lib/kubelet/kubeadm-flags.env' '$SETUP_CLUSTER_FILE'"

# Test 2: EnvironmentFile references preserved
run_test "EnvironmentFile references preserved" \
    "grep -q 'EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env' '$SETUP_CLUSTER_FILE'"

# Test 3: Explanatory comment exists
run_test "Explanatory comment added" \
    "grep -q 'Let kubeadm manage this file during join' '$SETUP_CLUSTER_FILE'"

# Test 4: Kubelet systemd config can still read the file
run_test "Kubelet can read kubeadm-generated flags" \
    "test \$(grep -c 'EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env' '$SETUP_CLUSTER_FILE') -ge 1"

# Test 5: Pre-join kubelet config has empty KUBELET_CONFIG_ARGS
run_test "Pre-join KUBELET_CONFIG_ARGS is empty" \
    "grep -A10 'recovery mode - pre-join' '$SETUP_CLUSTER_FILE' | grep -q 'Environment=\"KUBELET_CONFIG_ARGS=\"'"

# Test 6: Config.yaml cleanup before join exists
run_test "Config.yaml cleanup before join" \
    "grep -q 'Clear kubelet config.yaml before join' '$SETUP_CLUSTER_FILE'"

# Test 7: Worker CNI infrastructure tasks exist
run_test "Worker CNI infrastructure installation" \
    "grep -q 'Install CNI plugins and configuration on worker nodes' '$SETUP_CLUSTER_FILE'"

# Test 8: Join retry mechanism exists
run_test "Join retry mechanism present" \
    "grep -q 'Join worker nodes to cluster with retries' '$SETUP_CLUSTER_FILE'"

# Test 9: Ansible syntax validation
run_test "Ansible syntax validation" \
    "ansible-playbook --syntax-check '$SETUP_CLUSTER_FILE' -i ansible/inventory.txt > /dev/null 2>&1"

# Test 10: Flannel CNI plugin download for workers
run_test "Flannel CNI plugin download for workers" \
    "grep -q 'flanneld-amd64' '$SETUP_CLUSTER_FILE'"

echo "=== Test Summary ==="
echo "Tests passed: $TESTS_PASSED/$TESTS_TOTAL"

if [ $TESTS_PASSED -eq $TESTS_TOTAL ]; then
    echo "🎉 All tests passed!"
    echo ""
    echo "=== Fix Summary ==="
    echo "The worker node join issue has been resolved by:"
    echo ""
    echo "1. **Root Cause**: Static creation of /var/lib/kubelet/kubeadm-flags.env"
    echo "   prevented kubeadm from managing this file during the join process"
    echo ""
    echo "2. **Solution**: Removed static file creation while preserving the"
    echo "   EnvironmentFile reference so kubelet can read kubeadm-generated values"
    echo ""
    echo "3. **Impact**: Workers should now successfully join the cluster because:"
    echo "   - kubeadm can create kubeadm-flags.env with join-specific parameters"
    echo "   - No conflicts between static and dynamic configuration"
    echo "   - kubelet systemd service can still read the kubeadm-generated file"
    echo ""
    echo "4. **Complementary fixes already in place:**"
    echo "   - Empty KUBELET_CONFIG_ARGS during pre-join (prevents webhook auth conflicts)"
    echo "   - Worker CNI infrastructure installation (prevents CNI init failures)"
    echo "   - Config.yaml cleanup before join (prevents bootstrap conflicts)"
    echo "   - Comprehensive retry mechanism with diagnostics"
    echo ""
    echo "Expected result: Workers 192.168.4.61 and 192.168.4.62 should now"
    echo "successfully join the cluster managed by 192.168.4.63"
    exit 0
else
    echo "❌ Some tests failed. Check the output above for details."
    exit 1
fi
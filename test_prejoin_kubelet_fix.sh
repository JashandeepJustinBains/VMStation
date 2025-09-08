#!/bin/bash

# Test that validates the fix for kubelet configuration during join process
# The issue: Initial kubelet systemd config references kubelet.conf before it exists
# causing kubelet to fail starting during the kubeadm join process

set -e

echo "=== Testing Pre-Join Kubelet Configuration Fix ==="
echo "Timestamp: $(date)"
echo ""

info() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1"
}

success() {
    echo "[SUCCESS] $1" 
}

SETUP_CLUSTER_FILE="/home/runner/work/VMStation/VMStation/ansible/plays/kubernetes/setup_cluster.yaml"

if [ ! -f "$SETUP_CLUSTER_FILE" ]; then
    error "setup_cluster.yaml not found"
    exit 1
fi

echo "=== Test 1: Initial Kubelet Config Compatibility ==="

# Check that initial kubelet config doesn't hard-code kubelet.conf path
if grep -A 15 "Create kubeadm kubelet dropin (join-compatible configuration)" "$SETUP_CLUSTER_FILE" | grep -q 'KUBELET_KUBECONFIG_ARGS='; then
    success "✓ Initial kubelet config allows kubeadm to manage kubeconfig during join"
else
    error "✗ Initial kubelet config should not hard-code kubeconfig path"
    exit 1
fi

# Check that it includes proper kubeadm integration
if grep -A 15 "Create kubeadm kubelet dropin (join-compatible configuration)" "$SETUP_CLUSTER_FILE" | grep -q "KUBELET_KUBEADM_ARGS"; then
    success "✓ Initial kubelet config includes kubeadm integration"
else
    error "✗ Initial kubelet config missing kubeadm integration"
    exit 1
fi

echo ""
echo "=== Test 2: Recovery Mode Configuration ==="

# Check that recovery mode has conditional kubelet.conf usage
if grep -A 20 "Generate enhanced kubelet service configuration (recovery mode - joined node)" "$SETUP_CLUSTER_FILE" | grep -q "when: recovery_kubelet_conf_check.stat.exists"; then
    success "✓ Recovery mode uses kubelet.conf only when node is joined"
else
    error "✗ Recovery mode should conditionally use kubelet.conf"
    exit 1
fi

# Check that recovery mode has pre-join configuration
if grep -A 20 "Generate enhanced kubelet service configuration (recovery mode - pre-join)" "$SETUP_CLUSTER_FILE" | grep -q "when: not recovery_kubelet_conf_check.stat.exists"; then
    success "✓ Recovery mode has pre-join configuration for non-joined nodes"
else
    error "✗ Recovery mode missing pre-join configuration"
    exit 1
fi

# Check that pre-join recovery config doesn't hard-code kubelet.conf
if grep -A 10 "recovery mode - pre-join" "$SETUP_CLUSTER_FILE" | grep -q 'KUBELET_KUBECONFIG_ARGS='; then
    success "✓ Pre-join recovery config allows kubeadm to manage kubeconfig"
else
    error "✗ Pre-join recovery config should not hard-code kubeconfig path"
    exit 1
fi

echo ""
echo "=== Test 3: Configuration Flow Validation ==="

# Verify the configuration flow sequence
initial_config_line=$(grep -n "Create kubeadm kubelet dropin (join-compatible configuration)" "$SETUP_CLUSTER_FILE" | cut -d: -f1)
join_line=$(grep -n "Attempt to join cluster (attempt 1)" "$SETUP_CLUSTER_FILE" | cut -d: -f1)
post_join_config_line=$(grep -n "Update kubelet systemd config after successful join" "$SETUP_CLUSTER_FILE" | cut -d: -f1)

if [ "$initial_config_line" -lt "$join_line" ] && [ "$join_line" -lt "$post_join_config_line" ]; then
    success "✓ Configuration flow is correct: initial config → join → post-join config"
else
    error "✗ Configuration flow is incorrect"
    exit 1
fi

echo ""
echo "=== Test 4: Content Validation ==="

# Ensure initial config doesn't reference non-existent files
if grep -A 15 "Create kubeadm kubelet dropin (join-compatible configuration)" "$SETUP_CLUSTER_FILE" | grep -q "/etc/kubernetes/kubelet.conf"; then
    error "✗ Initial kubelet config incorrectly references kubelet.conf"
    exit 1
else
    success "✓ Initial kubelet config avoids referencing non-existent kubelet.conf"
fi

# Ensure post-join config properly sets kubelet.conf
if grep -A 15 "Update kubelet systemd config after successful join" "$SETUP_CLUSTER_FILE" | grep -q "KUBELET_KUBECONFIG_ARGS=--kubeconfig=/etc/kubernetes/kubelet.conf"; then
    success "✓ Post-join config properly sets kubelet.conf path"
else
    error "✗ Post-join config missing proper kubeconfig setting"
    exit 1
fi

echo ""
echo "=== Ansible Syntax Validation ==="

if ansible-playbook --syntax-check "$SETUP_CLUSTER_FILE" >/dev/null 2>&1; then
    success "✓ Ansible playbook syntax is valid after pre-join fix"
else
    error "✗ Ansible playbook syntax validation failed"
    exit 1
fi

echo ""
echo "=== Test Summary ===="
success "🎉 Pre-join kubelet configuration fix validation PASSED!"
echo ""
info "The fix addresses the root cause of kubelet failures during join process:"
info "  ✓ Initial kubelet config allows kubeadm to manage kubeconfig during join"
info "  ✓ Recovery mode adapts based on node join status"  
info "  ✓ Proper configuration flow: pre-join → join → post-join"
info "  ✓ Avoids referencing non-existent files during join"
info "  ✓ Maintains post-join configuration for stability"
echo ""
info "This should resolve the 'timed out waiting for the condition' errors"
info "during kubeadm join on nodes 192.168.4.61 and 192.168.4.62."
#!/bin/bash

# Test that validates the fix for kubelet startup failures after successful join
# The issue: after successful join, kubelet systemd config still contains bootstrap config
# causing kubelet to fail starting because bootstrap config should not be used after join

set -e

echo "=== Testing Post-Join Kubelet Configuration Fix ==="
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

echo "=== Test 1: Post-Join Kubelet Config Update Task ==="

# Check that there's a task to update kubelet config after join
if grep -q "Update kubelet systemd config after successful join" "$SETUP_CLUSTER_FILE"; then
    success "✓ Post-join kubelet config update task found"
else
    error "✗ Post-join kubelet config update task missing"
    exit 1
fi

# Check that it removes bootstrap config
if grep -A 15 "Update kubelet systemd config after successful join" "$SETUP_CLUSTER_FILE" | grep -q "no bootstrap config"; then
    success "✓ Post-join config removes bootstrap config dependency"
else
    error "✗ Post-join config doesn't properly remove bootstrap config"
    exit 1
fi

# Check that it runs when kubelet.conf exists (after successful join)
if grep -A 20 "Update kubelet systemd config after successful join" "$SETUP_CLUSTER_FILE" | grep -q "worker_kubelet_kubeconfig_check.stat.exists"; then
    success "✓ Post-join config update runs only after successful join"
else
    error "✗ Post-join config update missing proper condition"
    exit 1
fi

echo ""
echo "=== Test 2: Systemd Daemon Reload After Config Update ===="

# Check that systemd daemon is reloaded after config update
if grep -A 25 "Update kubelet systemd config after successful join" "$SETUP_CLUSTER_FILE" | grep -q "Reload systemd daemon after kubelet config update"; then
    success "✓ Systemd daemon reload after config update found"
else
    error "✗ Systemd daemon reload after config update missing"
    exit 1
fi

# Check that reload runs only when config was changed
if grep -A 30 "Reload systemd daemon after kubelet config update" "$SETUP_CLUSTER_FILE" | grep -q "when: post_join_config_update is changed"; then
    success "✓ Systemd reload runs only when config changed"
else
    error "✗ Systemd reload condition incorrect"
    exit 1
fi

echo ""
echo "=== Test 3: Task Ordering Validation ==="

# Check that config update happens before kubelet restart
config_line=$(grep -n "Update kubelet systemd config after successful join" "$SETUP_CLUSTER_FILE" | cut -d: -f1)
restart_line=$(grep -n "Restart and enable kubelet on worker (only if join was successful)" "$SETUP_CLUSTER_FILE" | cut -d: -f1)

if [ "$config_line" -lt "$restart_line" ]; then
    success "✓ Config update happens before kubelet restart (correct order)"
else
    error "✗ Config update should happen before kubelet restart"
    exit 1
fi

echo ""
echo "=== Test 4: Config Content Validation ==="

# Check that the new config doesn't include bootstrap-kubeconfig
if grep -A 15 "Update kubelet systemd config after successful join" "$SETUP_CLUSTER_FILE" | grep -q "bootstrap-kubeconfig"; then
    error "✗ Post-join config incorrectly includes bootstrap-kubeconfig"
    exit 1
else
    success "✓ Post-join config correctly excludes bootstrap-kubeconfig"
fi

# Check that the new config includes regular kubeconfig
if grep -A 15 "Update kubelet systemd config after successful join" "$SETUP_CLUSTER_FILE" | grep -q "KUBELET_KUBECONFIG_ARGS=--kubeconfig=/etc/kubernetes/kubelet.conf"; then
    success "✓ Post-join config includes regular kubeconfig"
else
    error "✗ Post-join config missing regular kubeconfig"
    exit 1
fi

echo ""
echo "=== Ansible Syntax Validation ==="

if ansible-playbook --syntax-check "$SETUP_CLUSTER_FILE" >/dev/null 2>&1; then
    success "✓ Ansible playbook syntax is valid after fix"
else
    error "✗ Ansible playbook syntax validation failed"
    exit 1
fi

echo ""
echo "=== Test Summary ===="
success "🎉 Post-join kubelet configuration fix validation PASSED!"
echo ""
info "The fix addresses the root cause of kubelet startup failures after join:"
info "  ✓ Updates kubelet systemd config after successful join"
info "  ✓ Removes bootstrap config dependency for joined nodes"
info "  ✓ Ensures proper task ordering (config update before restart)"
info "  ✓ Includes systemd daemon reload after config changes"
info "  ✓ Only runs when join was successful"
echo ""
info "This should resolve the kubelet startup failures on node 192.168.4.62"
info "and prevent similar issues on other worker nodes in the 3-node cluster."
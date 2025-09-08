#!/bin/bash

# Test script for deprecated --network-plugin flag fix
# This validates that the setup_cluster.yaml properly handles cleanup of deprecated kubelet flags

set -e

SETUP_CLUSTER_FILE="ansible/plays/kubernetes/setup_cluster.yaml"

# Color functions for output
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

echo "=== Testing Deprecated Network Plugin Flag Fix ==="
echo "Timestamp: $(date)"
echo ""

if [[ ! -f "$SETUP_CLUSTER_FILE" ]]; then
    error "Setup cluster file not found: $SETUP_CLUSTER_FILE"
    exit 1
fi

echo "=== Test 1: Verify Cleanup of Deprecated Sysconfig ====="

# Check that the retry cleanup removes /etc/sysconfig/kubelet
if grep -A 15 "Reset any partial join state cleanly" "$SETUP_CLUSTER_FILE" | grep -q "rm -f /etc/sysconfig/kubelet"; then
    success "✓ Retry cleanup removes potentially problematic sysconfig/kubelet file"
else
    error "✗ Retry cleanup should remove existing sysconfig/kubelet file"
    exit 1
fi

echo ""
echo "=== Test 2: Verify Clean Sysconfig Creation ====="

# Check that clean sysconfig/kubelet is created without deprecated flags
if grep -A 5 "Ensure clean /etc/sysconfig/kubelet without deprecated flags" "$SETUP_CLUSTER_FILE" | grep -q "KUBELET_EXTRA_ARGS=--cgroup-driver=systemd --container-runtime-endpoint"; then
    success "✓ Clean sysconfig/kubelet creation includes correct flags"
else
    error "✗ Clean sysconfig/kubelet creation task is missing or incorrect"
    exit 1
fi

# Check that it doesn't include deprecated network-plugin flag
if grep -A 10 "Ensure clean /etc/sysconfig/kubelet without deprecated flags" "$SETUP_CLUSTER_FILE" | grep -q "KUBELET_EXTRA_ARGS.*network-plugin"; then
    error "✗ Clean sysconfig creation should not include deprecated --network-plugin flag"
    exit 1
else
    success "✓ Clean sysconfig creation avoids deprecated --network-plugin flag"
fi

echo ""
echo "=== Test 3: Verify Retry Sysconfig Recreation ====="

# Check that sysconfig is recreated after cleanup for retry attempts
if grep -A 5 "Recreate clean sysconfig/kubelet for retry attempt" "$SETUP_CLUSTER_FILE" | grep -q "KUBELET_EXTRA_ARGS=--cgroup-driver=systemd --container-runtime-endpoint"; then
    success "✓ Retry attempts recreate clean sysconfig/kubelet"
else
    error "✗ Retry attempts should recreate clean sysconfig/kubelet"
    exit 1
fi

echo ""
echo "=== Test 4: Verify No Deprecated Flags in Configuration ====="

# Make sure no deprecated network-plugin flags exist in kubelet configurations
deprecated_count=$(grep -c "KUBELET_EXTRA_ARGS.*network-plugin\|KUBELET_NETWORK_ARGS.*network-plugin" "$SETUP_CLUSTER_FILE" || true)
if [[ "$deprecated_count" -eq 0 ]]; then
    success "✓ No deprecated --network-plugin flags found in kubelet configurations"
else
    error "✗ Found $deprecated_count instances of deprecated --network-plugin flag"
    # Show the context for debugging
    grep -n -C 3 "KUBELET_EXTRA_ARGS.*network-plugin\|KUBELET_NETWORK_ARGS.*network-plugin" "$SETUP_CLUSTER_FILE" || true
    exit 1
fi

echo ""
echo "=== Test 5: Validate Ansible Syntax ====="

if ansible-playbook --syntax-check "$SETUP_CLUSTER_FILE" >/dev/null 2>&1; then
    success "✓ Ansible syntax is valid"
else
    error "✗ Ansible syntax check failed"
    exit 1
fi

echo ""
echo "=== All Tests Passed! ===="
echo ""
echo "Summary of deprecated flag fixes:"
echo "  ✓ Cleanup removes potentially problematic /etc/sysconfig/kubelet files"
echo "  ✓ Clean sysconfig/kubelet creation without deprecated flags"  
echo "  ✓ Retry attempts properly recreate clean configuration"
echo "  ✓ No deprecated --network-plugin flags found in playbook"
echo "  ✓ Ansible syntax validation passes"
echo ""
info "This fix should resolve the kubelet flag parsing errors:"
info "  - 'unknown flag: --network-plugin' on node 192.168.4.61"
info "  - Similar deprecated flag issues on other worker nodes"
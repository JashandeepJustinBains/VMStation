#!/bin/bash

# Test script for sysconfig directory creation fix
# This validates that the setup_cluster.yaml properly ensures /etc/sysconfig directory exists
# before trying to create kubelet configuration files

set -e

SETUP_CLUSTER_FILE="ansible/plays/kubernetes/setup_cluster.yaml"

# Color functions for output
info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; }

echo "=== Testing Sysconfig Directory Creation Fix ==="
echo "Timestamp: $(date)"
echo ""

if [[ ! -f "$SETUP_CLUSTER_FILE" ]]; then
    error "Setup cluster file not found: $SETUP_CLUSTER_FILE"
    exit 1
fi

echo "=== Test 1: Verify Sysconfig Directory Creation Before Kubelet Config (Recovery Mode) ===="

# Check that /etc/sysconfig directory is created before kubelet config in recovery mode
if grep -B 10 -A 5 "Ensure clean /etc/sysconfig/kubelet without deprecated flags" "$SETUP_CLUSTER_FILE" | grep -q "Ensure /etc/sysconfig directory exists"; then
    success "✓ Recovery mode creates /etc/sysconfig directory before kubelet config"
else
    error "✗ Recovery mode should create /etc/sysconfig directory before creating kubelet config"
    exit 1
fi

echo ""
echo "=== Test 2: Verify Sysconfig Directory Creation Before Kubelet Config (Retry) ===="

# Check that /etc/sysconfig directory is created before kubelet config in retry attempt
if grep -B 10 -A 5 "Recreate clean sysconfig/kubelet for retry attempt" "$SETUP_CLUSTER_FILE" | grep -q "Ensure /etc/sysconfig directory exists for retry"; then
    success "✓ Retry attempt creates /etc/sysconfig directory before kubelet config"
else
    error "✗ Retry attempt should create /etc/sysconfig directory before creating kubelet config"
    exit 1
fi

echo ""
echo "=== Test 3: Verify Sysconfig Directory Creation (RHEL 10+) ===="

# Check that /etc/sysconfig directory is created before kubelet config for RHEL 10+
if grep -B 10 -A 5 "Ensure /etc/sysconfig/kubelet exists with systemd cgroup driver (RHEL 10+)" "$SETUP_CLUSTER_FILE" | grep -q "Ensure /etc/sysconfig directory exists (RHEL 10+)"; then
    success "✓ RHEL 10+ block creates /etc/sysconfig directory before kubelet config"
else
    error "✗ RHEL 10+ block should create /etc/sysconfig directory before creating kubelet config"
    exit 1
fi

echo ""
echo "=== Test 4: Verify Directory Permissions ===="

# Check that directory creation uses proper permissions (755)
directory_tasks=$(grep -A 5 "Ensure /etc/sysconfig directory exists" "$SETUP_CLUSTER_FILE")
if echo "$directory_tasks" | grep -q "mode: '0755'"; then
    success "✓ Directory creation uses proper permissions (755)"
else
    error "✗ Directory creation should use mode 0755"
    exit 1
fi

echo ""
echo "=== Test 5: Verify File Module Usage ===="

# Check that directory creation uses the 'file' module with state: directory
if echo "$directory_tasks" | grep -q "file:" && echo "$directory_tasks" | grep -q "state: directory"; then
    success "✓ Directory creation uses proper Ansible file module"
else
    error "✗ Directory creation should use file module with state: directory"
    exit 1
fi

echo ""
echo "=== Test 6: Ansible Syntax Validation ===="

# Test ansible syntax
if ansible-playbook --syntax-check "$SETUP_CLUSTER_FILE" > /dev/null 2>&1; then
    success "✓ Ansible playbook syntax is valid"
else
    error "✗ Ansible playbook syntax validation failed"
    exit 1
fi

echo ""
echo "=== Test 7: Verify No Breaking Changes ===="

# Ensure we still have the kubelet config creation tasks
kubelet_config_count=$(grep -c "dest: /etc/sysconfig/kubelet" "$SETUP_CLUSTER_FILE")
if [[ $kubelet_config_count -eq 3 ]]; then
    success "✓ All 3 kubelet config creation tasks are present"
else
    error "✗ Expected 3 kubelet config creation tasks, found $kubelet_config_count"
    exit 1
fi

# Ensure directory creation tasks don't conflict with existing logic
directory_count=$(grep -c "Ensure /etc/sysconfig directory exists" "$SETUP_CLUSTER_FILE")
if [[ $directory_count -eq 3 ]]; then
    success "✓ All 3 directory creation tasks are present"
else
    error "✗ Expected 3 directory creation tasks, found $directory_count"
    exit 1
fi

echo ""
success "All tests passed! Sysconfig directory creation fix is properly implemented."
echo ""
echo "=== Summary ==="
echo "✓ Recovery mode creates directory before kubelet config"
echo "✓ Retry attempt creates directory before kubelet config"  
echo "✓ RHEL 10+ block creates directory before kubelet config"
echo "✓ Directory permissions are properly set (755)"
echo "✓ Ansible file module is used correctly"
echo "✓ Ansible syntax validation passes"
echo "✓ No breaking changes to existing functionality"
echo ""
echo "This fix resolves the issue:"
echo "'Destination directory /etc/sysconfig does not exist'"
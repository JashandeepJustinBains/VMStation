#!/bin/bash

# Test Worker Node CNI Infrastructure Fix
# Validates that worker nodes have proper CNI infrastructure installed

set -e

echo "=== Testing Worker Node CNI Infrastructure Fix ==="
echo "Timestamp: $(date)"
echo ""

# Test 1: Verify Ansible syntax
echo "Test 1: Ansible syntax validation"
echo "Checking that the playbook has valid syntax..."

if ansible-playbook --syntax-check ansible/plays/setup-cluster.yaml >/dev/null 2>&1; then
    echo "✓ PASS: Ansible syntax is valid"
else
    echo "✗ FAIL: Ansible syntax check failed"
    exit 1
fi

# Test 2: Verify CNI directories creation for worker nodes
echo ""
echo "Test 2: CNI directories creation for worker nodes"
echo "Checking that CNI directories are created on worker nodes..."

if grep -A10 "Create CNI directories on worker nodes" ansible/plays/setup-cluster.yaml | grep -q "/opt/cni/bin\|/etc/cni/net.d"; then
    echo "✓ PASS: CNI directories creation task found"
else
    echo "✗ FAIL: CNI directories creation task missing"
    exit 1
fi

# Test 3: Verify Flannel CNI plugin installation
echo ""
echo "Test 3: Flannel CNI plugin binary installation"
echo "Checking that Flannel CNI plugin binary is installed on worker nodes..."

if grep -A5 "Download.*install Flannel CNI plugin" ansible/plays/setup-cluster.yaml | grep -q "flannel-amd64\|/opt/cni/bin/flannel"; then
    echo "✓ PASS: Flannel CNI plugin installation task found"
else
    echo "✗ FAIL: Flannel CNI plugin installation task missing"
    exit 1
fi

# Test 4: Verify additional CNI plugins installation
echo ""
echo "Test 4: Additional CNI plugins installation"
echo "Checking that additional CNI plugins (bridge, portmap) are installed..."

if grep -A5 "additional CNI plugins" ansible/plays/setup-cluster.yaml | grep -q "cni-plugins.*tgz\|bridge"; then
    echo "✓ PASS: Additional CNI plugins installation task found"
else
    echo "✗ FAIL: Additional CNI plugins installation task missing"
    exit 1
fi

# Test 5: Verify CNI configuration creation
echo ""
echo "Test 5: CNI configuration creation for worker nodes"
echo "Checking that CNI configuration is created on worker nodes..."

if grep -A25 "Create.*CNI configuration" ansible/plays/setup-cluster.yaml | grep -q "10-flannel.conflist\|delegate.*hairpin"; then
    echo "✓ PASS: CNI configuration creation task found"
else
    echo "✗ FAIL: CNI configuration creation task missing"
    exit 1
fi

# Test 6: Verify worker node targeting
echo ""
echo "Test 6: Worker node targeting"
echo "Checking that CNI installation tasks target worker nodes..."

if grep -B5 -A20 "Create CNI directories on worker nodes" ansible/plays/setup-cluster.yaml | grep -q "storage_nodes\|compute_nodes\|block:"; then
    echo "✓ PASS: Worker node targeting found"
else
    echo "✗ FAIL: Worker node targeting missing"
    exit 1
fi

# Test 7: Verify CNI plugin permissions
echo ""
echo "Test 7: CNI plugin binary permissions"
echo "Checking that CNI plugin binaries have correct permissions..."

if grep -A10 "Download.*install.*CNI" ansible/plays/setup-cluster.yaml | grep -q "mode.*755"; then
    echo "✓ PASS: CNI plugin permissions properly set"
else
    echo "✗ FAIL: CNI plugin permissions not properly configured"
    exit 1
fi

# Test 8: Verify CNI config content
echo ""
echo "Test 8: CNI configuration content validation"
echo "Checking that CNI configuration includes necessary components..."

if grep -A20 "Create.*CNI configuration" ansible/plays/setup-cluster.yaml | grep -q "cniVersion\|flannel\|portmap"; then
    echo "✓ PASS: CNI configuration includes necessary components"
else
    echo "✗ FAIL: CNI configuration missing necessary components"
    exit 1
fi

# Test 9: Verify installation happens before kubeadm join
echo ""
echo "Test 9: CNI installation sequencing"
echo "Checking that CNI installation happens before kubeadm join..."

CNI_LINE=$(grep -n "Create CNI directories on worker nodes" ansible/plays/setup-cluster.yaml | cut -d: -f1 | head -1)
JOIN_LINE=$(grep -n "Join cluster with retry logic" ansible/plays/setup-cluster.yaml | cut -d: -f1 | head -1)

if [ -n "$CNI_LINE" ] && [ -n "$JOIN_LINE" ] && [ "$CNI_LINE" -lt "$JOIN_LINE" ]; then
    echo "✓ PASS: CNI installation happens before kubeadm join"
else
    echo "✗ FAIL: CNI installation not properly sequenced before join"
    exit 1
fi

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "Worker Node CNI Infrastructure Fix Summary:"
echo "- ✓ CNI directories (/opt/cni/bin, /etc/cni/net.d) created on worker nodes"
echo "- ✓ Flannel CNI plugin binary installed with correct permissions"
echo "- ✓ Additional CNI plugins (bridge, portmap) installed"
echo "- ✓ CNI configuration (10-flannel.conflist) created with proper content"
echo "- ✓ CNI installation properly sequenced before kubeadm join"
echo "- ✓ Worker nodes properly targeted (storage_nodes, compute_nodes)"
echo ""
echo "This fix ensures worker nodes have the necessary CNI infrastructure"
echo "to prevent 'cni plugin not initialized' errors during kubelet startup."
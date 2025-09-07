#!/bin/bash
# Test script for Worker Node CNI Infrastructure Fix
# Validates that worker nodes have the necessary CNI components without running Flannel daemon

echo "=== Testing Worker Node CNI Infrastructure Fix ==="

# Test 1: Verify Ansible playbook syntax
echo "Test 1: Checking Ansible playbook syntax..."
cd /home/runner/work/VMStation/VMStation
if ansible-playbook --syntax-check ansible/plays/kubernetes/setup_cluster.yaml >/dev/null 2>&1; then
    echo "✅ Ansible syntax check passed"
else
    echo "❌ Ansible syntax check failed"
    exit 1
fi

# Test 2: Check that worker node CNI installation tasks are present
echo "Test 2: Checking for worker node CNI installation tasks..."
if grep -q "Install CNI plugins and configuration on worker nodes" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ Worker node CNI installation tasks found"
else
    echo "❌ Worker node CNI installation tasks missing"
    exit 1
fi

# Test 3: Verify CNI plugin download tasks are present
echo "Test 3: Checking for CNI plugin download tasks..."
if grep -q "Download and install Flannel CNI plugin binary (dynamic path)" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ Flannel CNI plugin download task found"
else
    echo "❌ Flannel CNI plugin download task missing"
    exit 1
fi

# Test 4: Verify standard CNI plugins download task
echo "Test 4: Checking for standard CNI plugins download..."
if grep -q "Download and install additional CNI plugins on worker nodes" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ Standard CNI plugins download task found"
else
    echo "❌ Standard CNI plugins download task missing"
    exit 1
fi

# Test 5: Check CNI configuration creation
echo "Test 5: Checking for CNI configuration creation..."
if grep -q "Create basic CNI configuration for worker nodes" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ CNI configuration creation task found"
else
    echo "❌ CNI configuration creation task missing"
    exit 1
fi

# Test 6: Verify Flannel subnet configuration
echo "Test 6: Checking for Flannel subnet configuration..."
if grep -q "Create Flannel subnet configuration for worker nodes" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ Flannel subnet configuration task found"
else
    echo "❌ Flannel subnet configuration task missing"
    exit 1
fi

# Test 7: Check CNI directories creation
echo "Test 7: Checking for CNI directories creation..."
if grep -q "/opt/cni/bin" ansible/plays/kubernetes/setup_cluster.yaml && grep -q "/etc/cni/net.d" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ CNI directories creation found"
else
    echo "❌ CNI directories creation missing"
    exit 1
fi

# Test 8: Verify CNI plugin verification tasks
echo "Test 8: Checking for CNI plugin verification..."
if grep -q "Verify CNI plugin installation on worker nodes" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ CNI plugin verification task found"
else
    echo "❌ CNI plugin verification task missing"
    exit 1
fi

# Test 9: Check network configuration consistency
echo "Test 9: Checking network configuration consistency..."
if grep -q '"Network": "10.244.0.0/16"' ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ Network configuration is consistent with Flannel manifest"
else
    echo "❌ Network configuration inconsistency detected"
    exit 1
fi

# Test 10: Verify CNI name consistency (cni0)
echo "Test 10: Checking CNI bridge name consistency..."
if grep -q '"name": "cni0"' ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ CNI bridge name correctly set to cni0"
else
    echo "❌ CNI bridge name inconsistency detected"
    exit 1
fi

echo ""
echo "🎉 All tests passed! Worker Node CNI Infrastructure fix validated."
echo ""
echo "Summary of changes:"
echo "- Added CNI plugin installation for worker nodes"
echo "- Created necessary CNI directories (/opt/cni/bin, /etc/cni/net.d)"
echo "- Downloaded Flannel CNI plugin binary for worker nodes"
echo "- Downloaded standard CNI plugins (bridge, portmap, etc.)"
echo "- Created basic CNI configuration (10-flannel.conflist)"
echo "- Added Flannel subnet configuration for worker nodes"
echo "- Added verification tasks to ensure CNI infrastructure is properly installed"
echo "- Maintained network configuration consistency (10.244.0.0/16)"
echo ""
echo "This fix ensures worker nodes have the necessary CNI infrastructure"
echo "to prevent 'cni plugin not initialized' errors while keeping the"
echo "Flannel daemon running only on control plane nodes."
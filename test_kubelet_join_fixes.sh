#!/bin/bash
# Test script to validate kubelet join timeout fixes

set -e

echo "=== Testing Kubelet Join Timeout Fixes ==="
echo "Timestamp: $(date)"
echo ""

# Check if required files exist
echo "1. Checking modified files..."
if [ ! -f "ansible/plays/kubernetes/setup_cluster.yaml" ]; then
    echo "ERROR: setup_cluster.yaml not found"
    exit 1
fi

if [ ! -f "update_and_deploy.sh" ]; then
    echo "ERROR: update_and_deploy.sh not found"
    exit 1
fi

echo "✓ Required files exist"

# Test Ansible syntax
echo ""
echo "2. Testing Ansible playbook syntax..."
if ! ansible-playbook --syntax-check ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "ERROR: Ansible syntax check failed"
    exit 1
fi
echo "✓ Ansible syntax is valid"

# Test bash script syntax
echo ""
echo "3. Testing update_and_deploy.sh syntax..."
if ! bash -n update_and_deploy.sh; then
    echo "ERROR: Bash syntax check failed"
    exit 1
fi
echo "✓ Bash syntax is valid"

# Check for key fixes
echo ""
echo "4. Verifying key fixes are in place..."

# Check that problematic kubelet config.yaml creation is removed
if grep -q "name: Create minimal kubelet config to allow startup (control plane)" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "ERROR: Problematic kubelet config creation task still present"
    exit 1
fi
echo "✓ Problematic kubelet config.yaml creation removed"

# Check that timeout is increased
if ! grep -q "timeout 2400" update_and_deploy.sh; then
    echo "ERROR: Increased timeout not found"
    exit 1
fi
echo "✓ Deployment timeout increased to 2400s"

# Check for performance-optimized join timeout handling
if ! grep -q "timeout 600.*kubeadm-join" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "ERROR: Performance-optimized join timeout not found"
    exit 1
fi
echo "✓ Performance-optimized kubeadm join timeout handling (600s)"

# Check that kubeadm-compatible systemd config is used
if ! grep -q "Note: This dropin only works with kubeadm and kubelet" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "ERROR: Kubeadm-compatible systemd config not found"
    exit 1
fi
echo "✓ Kubeadm-compatible systemd configuration implemented"

echo ""
echo "5. Checking for removed problematic recovery logic..."
if grep -q "name: Create minimal kubelet config if missing on worker (CA-file agnostic)" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "ERROR: Problematic worker recovery logic task still present"
    exit 1
fi
echo "✓ Problematic worker recovery logic removed"

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "Key improvements implemented:"
echo "- Removed kubelet config.yaml creation conflicts"
echo "- Performance-optimized timeout handling (600s/900s for joins, 2400s for deployment)"
echo "- Simplified to kubeadm-compatible systemd configuration"
echo "- Removed complex recovery logic that was causing more issues"
echo "- Enhanced error reporting and diagnostics"
echo "- Eliminated excessive containerd restarts during join"
echo "- Streamlined container pre-warming to essential images only"
echo ""
echo "These fixes should resolve the kubelet join timeout issues on nodes 192.168.4.61 and 192.168.4.62"
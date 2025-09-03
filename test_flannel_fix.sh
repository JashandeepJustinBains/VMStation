#!/bin/bash
# Test script for Flannel CNI controller placement fix
# Validates that the custom Flannel manifest restricts execution to control plane nodes only

echo "=== Testing Flannel CNI Controller Placement Fix ==="

# Test 1: Ansible playbook syntax check
echo "Test 1: Checking Ansible playbook syntax..."
cd /home/runner/work/VMStation/VMStation
if ansible-playbook --syntax-check ansible/plays/kubernetes/setup_cluster.yaml >/dev/null 2>&1; then
    echo "✅ Ansible syntax check passed"
else
    echo "❌ Ansible syntax check failed"
    exit 1
fi

# Test 2: Custom Flannel manifest YAML validation
echo "Test 2: Validating custom Flannel manifest YAML..."
if python3 -c "import yaml; list(yaml.safe_load_all(open('ansible/plays/kubernetes/templates/kube-flannel-masteronly.yml'))); print('✅ YAML syntax is valid')" 2>/dev/null; then
    echo "✅ Custom Flannel manifest YAML is valid"
else
    echo "❌ Custom Flannel manifest YAML validation failed"
    exit 1
fi

# Test 3: Verify nodeSelector is present in the DaemonSet
echo "Test 3: Checking for control plane nodeSelector..."
if grep -q "node-role.kubernetes.io/control-plane:" ansible/plays/kubernetes/templates/kube-flannel-masteronly.yml; then
    echo "✅ Control plane nodeSelector found"
else
    echo "❌ Control plane nodeSelector missing"
    exit 1
fi

# Test 4: Verify control plane tolerations are present
echo "Test 4: Checking for control plane tolerations..."
if grep -q "node-role.kubernetes.io/control-plane" ansible/plays/kubernetes/templates/kube-flannel-masteronly.yml && grep -q "tolerations:" ansible/plays/kubernetes/templates/kube-flannel-masteronly.yml; then
    echo "✅ Control plane tolerations found"
else
    echo "❌ Control plane tolerations missing"
    exit 1
fi

# Test 5: Verify setup_cluster.yaml uses custom manifest
echo "Test 5: Checking that setup_cluster.yaml uses custom manifest..."
if grep -q "kube-flannel-masteronly.yml" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ setup_cluster.yaml references custom Flannel manifest"
else
    echo "❌ setup_cluster.yaml does not reference custom Flannel manifest"
    exit 1
fi

# Test 6: Verify no upstream Flannel URL is being used
echo "Test 6: Checking that upstream Flannel URL is not used..."
if ! grep -q "github.com/flannel-io/flannel/releases/latest/download" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ Upstream Flannel URL removed"
else
    echo "❌ Upstream Flannel URL still present"
    exit 1
fi

echo ""
echo "🎉 All tests passed! Flannel CNI controller placement fix validated."
echo ""
echo "Summary of changes:"
echo "- Created custom Flannel manifest that restricts DaemonSet to control plane nodes only"
echo "- Added nodeSelector: node-role.kubernetes.io/control-plane"
echo "- Added specific tolerations for control plane taints"
echo "- Modified setup_cluster.yaml to use custom manifest instead of upstream"
echo "- This prevents cni0 interfaces from being created on worker nodes"
echo "- This ensures flanneld controller only runs on masternode (192.168.4.63)"
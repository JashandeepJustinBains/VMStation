#!/bin/bash
# Test script for Flannel All Nodes Fix
# Validates that Flannel can now run on all nodes to resolve CNI initialization errors

echo "=== Testing Flannel All Nodes Configuration Fix ==="

# Test 1: Verify new manifest file exists
echo "Test 1: Checking for new Flannel manifest..."
if [ -f "ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml" ]; then
    echo "✅ New Flannel all-nodes manifest found"
else
    echo "❌ New Flannel all-nodes manifest missing"
    exit 1
fi

# Test 2: Verify old master-only file was removed/renamed
echo "Test 2: Checking that master-only restriction is removed..."
if [ ! -f "ansible/plays/kubernetes/templates/kube-flannel-masteronly.yml" ]; then
    echo "✅ Old master-only manifest file removed"
else
    echo "❌ Old master-only manifest file still exists"
    exit 1
fi

# Test 3: Verify setup_cluster.yaml references new manifest
echo "Test 3: Checking setup_cluster.yaml references..."
if grep -q "kube-flannel-allnodes.yml" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ setup_cluster.yaml updated to use new manifest"
else
    echo "❌ setup_cluster.yaml not updated to use new manifest"
    exit 1
fi

# Test 4: Verify nodeSelector restriction is removed
echo "Test 4: Checking nodeSelector restriction removal..."
if ! grep -q 'nodeSelector:' ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml || grep -q '# nodeSelector:' ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml; then
    echo "✅ nodeSelector restriction removed/commented"
else
    echo "❌ nodeSelector restriction still present"
    exit 1
fi

# Test 5: Verify control-plane node affinity is removed from nodeAffinity section
echo "Test 5: Checking control-plane node affinity removal from nodeAffinity..."
if ! grep -A 20 "nodeAffinity:" ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml | grep -q "node-role.kubernetes.io/control-plane"; then
    echo "✅ Control-plane node affinity removed from nodeAffinity"
else
    echo "❌ Control-plane node affinity still present in nodeAffinity"
    exit 1
fi

# Test 6: Verify general tolerations are added
echo "Test 6: Checking for general tolerations..."
if grep -q "effect: NoSchedule" ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml && grep -q "operator: Exists" ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml; then
    echo "✅ General tolerations added for worker nodes"
else
    echo "❌ General tolerations missing"
    exit 1
fi

# Test 7: Verify manifest comments reflect new behavior
echo "Test 7: Checking manifest comments..."
if grep -q "run on all nodes" ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml; then
    echo "✅ Manifest comments updated to reflect all-nodes behavior"
else
    echo "❌ Manifest comments not updated"
    exit 1
fi

# Test 8: Verify CNI infrastructure setup is still present for workers
echo "Test 8: Checking worker CNI infrastructure is maintained..."
if grep -q "Install CNI plugins and configuration on worker nodes" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ Worker CNI infrastructure setup maintained"
else
    echo "❌ Worker CNI infrastructure setup missing"
    exit 1
fi

# Test 9: Verify Ansible syntax is valid
echo "Test 9: Checking Ansible syntax..."
if ansible-playbook --syntax-check ansible/plays/kubernetes/setup_cluster.yaml >/dev/null 2>&1; then
    echo "✅ Ansible syntax check passed"
else
    echo "❌ Ansible syntax check failed"
    exit 1
fi

echo ""
echo "🎉 All tests passed! Flannel All Nodes fix validated."
echo ""
echo "Summary of changes:"
echo "- Renamed kube-flannel-masteronly.yml to kube-flannel-allnodes.yml"
echo "- Removed nodeSelector restriction to control-plane only"
echo "- Removed control-plane node affinity requirement"
echo "- Added general tolerations to allow running on worker nodes"
echo "- Updated setup_cluster.yaml to use new manifest"
echo "- Updated comments to reflect all-nodes deployment"
echo ""
echo "This fix allows Flannel agents to run on all nodes (control plane and workers)"
echo "to resolve 'cni plugin not initialized' errors while maintaining the existing"
echo "CNI infrastructure setup on worker nodes."
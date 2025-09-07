#!/bin/bash
# Test script to verify Flannel CNI controller can schedule on homelab node
# Addresses the specific issue: "flanneld CNI controller get installed on the homelab node (compute_nodes)"

echo "=== Testing Homelab Node Flannel CNI Controller Fix ==="
echo "This test validates that Flannel DaemonSet can schedule on all nodes including homelab (compute_nodes)"
echo ""

# Test 1: Verify tolerations allow scheduling on any node
echo "Test 1: Checking comprehensive tolerations for all node taints..."
if grep -q "operator: Exists" ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml && \
   grep -A 1 "operator: Exists" ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml | grep -q "effect: NoSchedule"; then
    echo "✅ Comprehensive toleration found: operator=Exists, effect=NoSchedule"
else
    echo "❌ Missing comprehensive toleration for all NoSchedule taints"
    exit 1
fi

# Test 2: Verify no node restrictions that would exclude homelab node
echo "Test 2: Checking that nodeSelector doesn't restrict to control-plane only..."
if ! grep -q "nodeSelector:" ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml || \
   grep -A 2 "nodeSelector:" ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml | grep -q "#"; then
    echo "✅ No active nodeSelector restriction found"
else
    echo "❌ Active nodeSelector might prevent scheduling on worker nodes"
    exit 1
fi

# Test 3: Verify nodeAffinity allows linux nodes (which should include homelab)
echo "Test 3: Checking nodeAffinity allows linux nodes..."
if grep -A 10 "nodeAffinity:" ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml | grep -q "kubernetes.io/os" && \
   grep -A 10 "nodeAffinity:" ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml | grep -q "linux"; then
    echo "✅ nodeAffinity allows linux nodes (should include homelab)"
else
    echo "❌ nodeAffinity might be too restrictive"
    exit 1
fi

# Test 4: Verify setup_cluster.yaml deploys the all-nodes manifest
echo "Test 4: Checking setup_cluster.yaml uses all-nodes manifest..."
if grep -q "kube-flannel-allnodes.yml" ansible/plays/kubernetes/setup_cluster.yaml; then
    echo "✅ setup_cluster.yaml uses kube-flannel-allnodes.yml"
else
    echo "❌ setup_cluster.yaml doesn't reference the all-nodes manifest"
    exit 1
fi

# Test 5: Verify worker node CNI setup is preserved for homelab
echo "Test 5: Checking worker node CNI infrastructure setup..."
if grep -A 20 "Install CNI plugins and configuration on worker nodes" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "flannel"; then
    echo "✅ Worker node CNI setup includes Flannel infrastructure"
else
    echo "❌ Worker node CNI setup might be missing"
    exit 1
fi

# Test 6: Verify the tolerations are simpler and more robust than before
echo "Test 6: Checking tolerations are simplified for better compatibility..."
if [ $(grep -c "key:.*node-role" ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml) -eq 0 ]; then
    echo "✅ Simplified tolerations (no specific node-role key restrictions)"
else
    echo "❌ Still using complex node-role specific tolerations"
    exit 1
fi

echo ""
echo "🎉 All tests passed! Homelab node Flannel CNI controller fix validated."
echo ""
echo "Summary of the fix:"
echo "- Simplified tolerations to 'operator: Exists, effect: NoSchedule'"
echo "- This tolerates ALL NoSchedule taints regardless of key"
echo "- Matches the upstream Flannel manifest approach"
echo "- Removes complex node-role specific tolerations that might miss edge cases"
echo "- Ensures Flannel DaemonSet can schedule on homelab node (compute_nodes)"
echo ""
echo "Expected result:"
echo "- Flannel pods should now schedule on ALL nodes including homelab (192.168.4.62)"
echo "- MongoDB and Drone should be able to schedule on homelab node"
echo "- CNI networking should work properly on all worker nodes"
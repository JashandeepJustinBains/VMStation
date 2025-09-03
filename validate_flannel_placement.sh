#!/bin/bash
# Validation script to check if Flannel CNI controller placement fix is working correctly
# This script should be run AFTER Kubernetes cluster deployment

echo "=== Post-Deployment Flannel CNI Controller Placement Validation ==="

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ kubectl not found. Please ensure kubectl is installed and configured."
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Cannot connect to Kubernetes cluster. Please check kubeconfig."
    exit 1
fi

echo "✅ Connected to Kubernetes cluster"
echo ""

# Test 1: Check if kube-flannel namespace exists
echo "Test 1: Checking if kube-flannel namespace exists..."
if kubectl get namespace kube-flannel >/dev/null 2>&1; then
    echo "✅ kube-flannel namespace exists"
else
    echo "❌ kube-flannel namespace not found"
    exit 1
fi

# Test 2: Check Flannel DaemonSet exists
echo "Test 2: Checking if Flannel DaemonSet exists..."
if kubectl get daemonset kube-flannel-ds -n kube-flannel >/dev/null 2>&1; then
    echo "✅ Flannel DaemonSet found"
else
    echo "❌ Flannel DaemonSet not found"
    exit 1
fi

# Test 3: Check Flannel pods are only on control plane nodes
echo "Test 3: Checking Flannel pod placement..."
flannel_pods=$(kubectl get pods -n kube-flannel -o jsonpath='{.items[*].spec.nodeName}' 2>/dev/null)

if [ -z "$flannel_pods" ]; then
    echo "❌ No Flannel pods found"
    exit 1
fi

echo "Flannel pods are running on nodes: $flannel_pods"

# Check if any Flannel pods are on worker nodes (should be none)
worker_nodes=$(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane,!node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -n "$worker_nodes" ]; then
    echo "Worker nodes in cluster: $worker_nodes"
    
    for worker in $worker_nodes; do
        if echo "$flannel_pods" | grep -q "$worker"; then
            echo "❌ Flannel pod found on worker node: $worker (this should not happen)"
            exit 1
        fi
    done
    echo "✅ No Flannel pods found on worker nodes (correct)"
else
    echo "ℹ️  No worker nodes found in cluster (single-node setup)"
fi

# Test 4: Check control plane nodes have Flannel pods
echo "Test 4: Checking control plane has Flannel pods..."
control_plane_nodes=$(kubectl get nodes --selector='node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -z "$control_plane_nodes" ]; then
    # Fallback to master label for older Kubernetes versions
    control_plane_nodes=$(kubectl get nodes --selector='node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
fi

if [ -z "$control_plane_nodes" ]; then
    echo "❌ No control plane nodes found"
    exit 1
fi

echo "Control plane nodes: $control_plane_nodes"

for cp_node in $control_plane_nodes; do
    if echo "$flannel_pods" | grep -q "$cp_node"; then
        echo "✅ Flannel pod found on control plane node: $cp_node (correct)"
    else
        echo "❌ No Flannel pod on control plane node: $cp_node"
        exit 1
    fi
done

# Test 5: Check Flannel pod status
echo "Test 5: Checking Flannel pod status..."
flannel_status=$(kubectl get pods -n kube-flannel --no-headers 2>/dev/null | awk '{print $3}')

for status in $flannel_status; do
    if [ "$status" != "Running" ]; then
        echo "❌ Flannel pod not in Running state: $status"
        kubectl get pods -n kube-flannel
        exit 1
    fi
done

echo "✅ All Flannel pods are Running"

# Test 6: Verify no CNI0 interfaces on worker nodes (if we can SSH)
echo "Test 6: Checking for CNI0 interfaces on worker nodes..."
if [ -n "$worker_nodes" ]; then
    # This test is informational since we can't SSH from this context
    echo "ℹ️  To manually verify no CNI0 interfaces on worker nodes, run:"
    for worker in $worker_nodes; do
        # Try to identify IP addresses from node info
        worker_ip=$(kubectl get node "$worker" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
        if [ -n "$worker_ip" ]; then
            echo "   ssh root@$worker_ip 'ip link show cni0' 2>/dev/null || echo 'No CNI0 on $worker (good)'"
        else
            echo "   Check node $worker for CNI0 interfaces manually"
        fi
    done
else
    echo "ℹ️  No worker nodes to check"
fi

# Test 7: Show current network setup
echo ""
echo "=== Current Network Configuration ==="
echo "Pod CIDR in use:"
kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}' 2>/dev/null || echo "Pod CIDR not found"

echo ""
echo "Flannel configuration:"
kubectl get configmap kube-flannel-cfg -n kube-flannel -o jsonpath='{.data.net-conf\.json}' 2>/dev/null | jq . 2>/dev/null || kubectl get configmap kube-flannel-cfg -n kube-flannel -o jsonpath='{.data.net-conf\.json}' 2>/dev/null

echo ""
echo "🎉 All Flannel CNI controller placement validations passed!"
echo ""
echo "Summary:"
echo "- Flannel is running only on control plane nodes ✅"
echo "- No Flannel pods on worker nodes ✅"
echo "- Network controller is centralized as intended ✅"
echo "- This should prevent cert-manager hanging issues ✅"
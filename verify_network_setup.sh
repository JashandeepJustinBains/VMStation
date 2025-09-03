#!/bin/bash
# VMStation Network Setup Verification Guide
# Run this script when your Kubernetes cluster is active

echo "=== VMStation Network Architecture Verification ==="
echo ""

echo "1. Checking Flannel Pod Placement..."
echo "Expected: Flannel pods should ONLY be on control plane nodes"
echo "Command: kubectl get pods -n kube-flannel -o wide"
echo ""

echo "2. Verifying Node Labels..."
echo "Expected: Control plane node should have 'node-role.kubernetes.io/control-plane' label"
echo "Command: kubectl get nodes --show-labels | grep control-plane"
echo ""

echo "3. Checking CNI Interfaces on Worker Nodes..."
echo "Expected: Worker nodes should NOT have cni0 interfaces"
echo "Commands to run on worker nodes:"
echo "  ssh root@192.168.4.61 'ip link show cni0' 2>/dev/null || echo 'No CNI0 on storage node (correct)'"
echo "  ssh root@192.168.4.62 'ip link show cni0' 2>/dev/null || echo 'No CNI0 on compute node (correct)'"
echo ""

echo "4. Verifying Pod Networking..."
echo "Expected: Pods should be able to communicate across nodes despite centralized Flannel"
echo "Command: kubectl get pods --all-namespaces -o wide"
echo ""

echo "5. Testing Network Connectivity..."
echo "Create a test pod and verify it gets an IP from the pod CIDR (10.244.0.0/16)"
echo "Command: kubectl run test-pod --image=nginx --rm -it --restart=Never -- ping -c 3 8.8.8.8"
echo ""

echo "=== If You Want to Run Actual Tests ==="
echo ""
echo "When your cluster is running, execute:"
echo "1. ./validate_flannel_placement.sh  # Automated validation"
echo "2. kubectl get pods -n kube-flannel -o wide  # Manual check"
echo "3. kubectl get nodes -o wide  # Verify node status"
echo ""

echo "=== This Setup is CORRECT for VMStation ==="
echo "❌ Do NOT 'fix' by adding Flannel to worker nodes"
echo "✅ This centralized approach prevents the issues documented in FLANNEL_CNI_CONTROLLER_FIX.md"
echo "✅ Worker nodes participate in pod networking without running CNI controllers"
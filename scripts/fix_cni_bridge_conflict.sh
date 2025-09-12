#!/bin/bash

# Fix CNI Bridge IP Conflict Issue
# This script addresses the specific issue where pods are stuck in ContainerCreating
# due to CNI bridge (cni0) having an IP address different from the expected Flannel subnet

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if we have kubectl access
if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    exit 1
fi

echo "=== CNI Bridge Conflict Fix ==="
echo "Timestamp: $(date)"
echo "Fixing: cni0 bridge IP address conflicts preventing pod creation"
echo

# Step 1: Diagnose the CNI bridge issue
info "Step 1: Diagnosing CNI bridge configuration on all nodes"

# Get all cluster nodes
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

for node in $NODES; do
    echo
    echo "=== Node: $node ==="
    
    # Check if this is a node we can access directly (control plane)
    if [ "$node" = "masternode" ] || kubectl get nodes "$node" -o jsonpath='{.metadata.labels.node-role\.kubernetes\.io/control-plane}' | grep -q ""; then
        echo "Checking CNI bridge configuration on control plane node..."
        
        # Check current bridge configuration
        if ip addr show cni0 >/dev/null 2>&1; then
            echo "Current cni0 bridge configuration:"
            ip addr show cni0 | grep -E "inet|state"
            
            CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
            if [ -n "$CNI_IP" ]; then
                echo "Current cni0 IP: $CNI_IP"
                
                # Check if it matches expected Flannel subnet
                if echo "$CNI_IP" | grep -q "10.244."; then
                    info "cni0 bridge IP is in correct Flannel subnet"
                else
                    warn "cni0 bridge IP ($CNI_IP) is NOT in expected Flannel subnet (10.244.0.0/16)"
                    echo "This is likely causing the ContainerCreating issues"
                fi
            fi
        else
            echo "No cni0 bridge found on this node"
        fi
    else
        echo "Worker node - will be handled by CNI reset on control plane"
    fi
done

# Step 2: Check current pod status to confirm the issue
info "Step 2: Checking current pod status"

echo "Pods stuck in ContainerCreating:"
kubectl get pods --all-namespaces | grep "ContainerCreating" || echo "No pods currently stuck in ContainerCreating"

echo
echo "Recent pod creation errors:"
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i "failed to create pod sandbox" | tail -5 || echo "No recent pod sandbox creation errors found"

# Step 3: Fix the CNI bridge configuration
info "Step 3: Applying CNI bridge fix"

# First, check if any pods are currently using the bridge
PODS_ON_CNI=$(ip route | grep cni0 | wc -l 2>/dev/null || echo "0")
if [ "$PODS_ON_CNI" -gt 0 ]; then
    warn "Found $PODS_ON_CNI routes using cni0 - will need to reset networking"
fi

# Delete problematic CNI bridge to allow Flannel to recreate it properly
if ip addr show cni0 >/dev/null 2>&1; then
    warn "Deleting existing cni0 bridge to fix IP conflict"
    
    # First, bring down the interface
    sudo ip link set cni0 down 2>/dev/null || true
    
    # Delete the bridge
    sudo ip link delete cni0 2>/dev/null || true
    
    info "Deleted existing cni0 bridge"
else
    info "No existing cni0 bridge found"
fi

# Clean up any remaining CNI network configurations that might conflict
warn "Cleaning up potentially conflicting CNI configurations"

# Remove any conflicting CNI network configs (but preserve flannel config)
if [ -d "/etc/cni/net.d" ]; then
    # Keep only flannel configuration and remove others that might conflict
    sudo find /etc/cni/net.d -name "*.conflist" -not -name "*flannel*" -delete 2>/dev/null || true
    sudo find /etc/cni/net.d -name "*.conf" -not -name "*flannel*" -delete 2>/dev/null || true
    
    echo "Remaining CNI configurations:"
    ls -la /etc/cni/net.d/ 2>/dev/null || echo "No CNI config directory found"
fi

# Step 4: Restart network-related services to apply changes
info "Step 4: Restarting containerd to apply CNI changes"

sudo systemctl restart containerd

# Wait for containerd to stabilize
sleep 10

# Step 5: Restart Flannel pods to recreate bridge with correct configuration
info "Step 5: Restarting Flannel pods to recreate CNI bridge"

# Delete flannel pods to force recreation with clean network state
kubectl delete pods -n kube-flannel --all --force --grace-period=0

echo "Waiting for Flannel pods to recreate..."
sleep 20

# Check if Flannel DaemonSet is ready
info "Waiting for Flannel DaemonSet to be ready..."
kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=120s

# Step 6: Verify the CNI bridge is now correctly configured
info "Step 6: Verifying CNI bridge fix"

# Wait a moment for the bridge to be created
sleep 15

if ip addr show cni0 >/dev/null 2>&1; then
    echo "New cni0 bridge configuration:"
    ip addr show cni0 | grep -E "inet|state"
    
    NEW_CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
    if [ -n "$NEW_CNI_IP" ]; then
        echo "New cni0 IP: $NEW_CNI_IP"
        
        if echo "$NEW_CNI_IP" | grep -q "10.244."; then
            info "✓ cni0 bridge now has correct Flannel subnet IP"
        else
            warn "cni0 bridge still has incorrect IP - may need manual intervention"
        fi
    fi
else
    warn "cni0 bridge not yet created - Flannel may still be initializing"
fi

# Step 7: Check if ContainerCreating pods can now start
info "Step 7: Checking if stuck pods can now start"

echo "Current pod status:"
kubectl get pods --all-namespaces | grep -E "(ContainerCreating|Pending)" || echo "No pods stuck in ContainerCreating/Pending"

# Try to create a test pod to verify networking
info "Testing pod creation with clean CNI bridge..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cni-test
  namespace: kube-system
spec:
  containers:
  - name: test
    image: busybox:1.35
    command: ['sleep', '60']
  restartPolicy: Never
EOF

# Wait and check if test pod starts successfully
sleep 10

TEST_POD_STATUS=$(kubectl get pod cni-test -n kube-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$TEST_POD_STATUS" = "Running" ] || [ "$TEST_POD_STATUS" = "Succeeded" ]; then
    info "✓ Test pod created successfully - CNI bridge fix worked"
    
    # Get the pod IP to verify networking
    TEST_POD_IP=$(kubectl get pod cni-test -n kube-system -o jsonpath='{.status.podIP}' 2>/dev/null)
    if [ -n "$TEST_POD_IP" ]; then
        echo "Test pod IP: $TEST_POD_IP"
        if echo "$TEST_POD_IP" | grep -q "10.244."; then
            info "✓ Test pod received IP from correct Flannel subnet"
        fi
    fi
else
    warn "Test pod status: $TEST_POD_STATUS - CNI issues may persist"
    kubectl describe pod cni-test -n kube-system 2>/dev/null || true
fi

# Clean up test pod
kubectl delete pod cni-test -n kube-system --ignore-not-found

# Step 8: Restart CoreDNS and other stuck pods
info "Step 8: Restarting CoreDNS and other system pods"

# Restart CoreDNS deployment to clear any stuck pods
kubectl rollout restart deployment/coredns -n kube-system

echo "Waiting for CoreDNS to be ready..."
kubectl rollout status deployment/coredns -n kube-system --timeout=120s

# Final status check
echo
info "=== CNI Bridge Fix Complete ==="

echo "Final cluster status:"
kubectl get nodes -o wide

echo
echo "Final pod status (focusing on previously stuck pods):"
kubectl get pods --all-namespaces | grep -E "(kube-system|kube-flannel)" | grep -E "(coredns|flannel)"

echo
echo "Any remaining ContainerCreating pods:"
kubectl get pods --all-namespaces | grep "ContainerCreating" || echo "✓ No pods stuck in ContainerCreating"

echo
if ip addr show cni0 >/dev/null 2>&1; then
    echo "Final cni0 bridge status:"
    ip addr show cni0 | grep -E "inet|state"
else
    warn "cni0 bridge not found - this may be normal if no pods are scheduled yet"
fi

echo
info "CNI bridge conflict fix completed!"
echo
echo "If pods are still stuck, check:"
echo "  1. Flannel logs: kubectl logs -n kube-flannel -l app=flannel"
echo "  2. Containerd logs: sudo journalctl -u containerd --since '5 minutes ago'"
echo "  3. Pod events: kubectl get events --all-namespaces --sort-by='.lastTimestamp'"
#!/bin/bash

# Test CNI Bridge Conflict Fix
# This script simulates and tests the CNI bridge IP conflict fix

set -e

# Color output  
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=== CNI Bridge Conflict Fix Test ==="
echo "This test validates the CNI bridge conflict fix functionality"
echo

# Check prerequisites
if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    exit 1
fi

if [ ! -f "./scripts/fix_cni_bridge_conflict.sh" ]; then
    error "CNI bridge fix script not found"
    exit 1
fi

if [ ! -f "./scripts/check_cni_bridge_conflict.sh" ]; then
    error "CNI bridge check script not found"
    exit 1
fi

# Test 1: Check script functionality
info "Test 1: Checking CNI bridge conflict detection script"

./scripts/check_cni_bridge_conflict.sh
CHECK_RESULT=$?

case $CHECK_RESULT in
    0)
        info "✓ No CNI bridge conflicts detected"
        ;;
    1)
        warn "General networking issues detected"
        ;;
    2)
        warn "CNI bridge IP conflicts detected"
        ;;
    *)
        error "Unexpected result from check script"
        ;;
esac

# Test 2: Check current cluster state
info "Test 2: Analyzing current cluster state"

echo "Current node status:"
kubectl get nodes -o wide

echo
echo "Current pod status across namespaces:"
kubectl get pods --all-namespaces | grep -E "(ContainerCreating|CrashLoopBackOff|Error|Unknown)" || echo "No problematic pods found"

echo
echo "Flannel pod status:"
kubectl get pods -n kube-flannel -o wide

echo
echo "CoreDNS pod status:"
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# Test 3: Check CNI bridge configuration
info "Test 3: Checking CNI bridge configuration"

if ip addr show cni0 >/dev/null 2>&1; then
    echo "Current cni0 bridge configuration:"
    ip addr show cni0 | grep -E "inet|state"
    
    CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
    if [ -n "$CNI_IP" ]; then
        echo "Current cni0 IP: $CNI_IP"
        
        if echo "$CNI_IP" | grep -q "10.244."; then
            info "✓ cni0 bridge IP is in correct Flannel subnet"
        else
            warn "⚠ cni0 bridge IP is NOT in expected Flannel subnet (this might be the issue)"
        fi
    fi
else
    info "No cni0 bridge currently exists"
fi

# Test 4: Validate fix script components
info "Test 4: Validating fix script components"

echo "Checking if fix script has required components:"

if grep -q "ip link delete cni0" ./scripts/fix_cni_bridge_conflict.sh; then
    info "✓ Script includes CNI bridge deletion"
else
    warn "Script missing CNI bridge deletion command"
fi

if grep -q "systemctl restart containerd" ./scripts/fix_cni_bridge_conflict.sh; then
    info "✓ Script includes containerd restart"
else  
    warn "Script missing containerd restart"
fi

if grep -q "kubectl delete pods -n kube-flannel" ./scripts/fix_cni_bridge_conflict.sh; then
    info "✓ Script includes Flannel pod restart"
else
    warn "Script missing Flannel pod restart"
fi

# Test 5: Check integration with existing scripts
info "Test 5: Checking integration with existing fix scripts"

if grep -q "fix_cni_bridge_conflict.sh" ./scripts/fix_homelab_node_issues.sh; then
    info "✓ CNI bridge fix integrated with homelab node fix script"
else
    warn "CNI bridge fix not integrated with homelab node fix script"
fi

if grep -q "fix_cni_bridge_conflict.sh" ./deploy.sh; then
    info "✓ CNI bridge fix integrated with deployment script"
else
    warn "CNI bridge fix not integrated with deployment script"
fi

# Test 6: Create test pod to verify current networking
info "Test 6: Testing current pod creation capability"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cni-test-validation
  namespace: kube-system
spec:
  containers:
  - name: test
    image: busybox:1.35
    command: ['sleep', '30']
  restartPolicy: Never
EOF

echo "Waiting for test pod to start..."
sleep 15

TEST_POD_STATUS=$(kubectl get pod cni-test-validation -n kube-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
TEST_POD_IP=$(kubectl get pod cni-test-validation -n kube-system -o jsonpath='{.status.podIP}' 2>/dev/null || echo "none")

echo "Test pod status: $TEST_POD_STATUS"
echo "Test pod IP: $TEST_POD_IP"

if [ "$TEST_POD_STATUS" = "Running" ]; then
    info "✓ Pod creation is working normally"
    
    if echo "$TEST_POD_IP" | grep -q "10.244."; then
        info "✓ Pod received IP from correct Flannel subnet"
    else
        warn "Pod IP not in expected Flannel subnet"
    fi
elif [ "$TEST_POD_STATUS" = "ContainerCreating" ]; then
    warn "Pod stuck in ContainerCreating - CNI issues likely present"
    
    # Check for specific errors
    kubectl describe pod cni-test-validation -n kube-system | grep -A5 -B5 "Events:"
else
    warn "Unexpected pod status: $TEST_POD_STATUS"
fi

# Clean up test pod
kubectl delete pod cni-test-validation -n kube-system --ignore-not-found

echo
info "=== CNI Bridge Conflict Fix Test Results ==="

if [ "$CHECK_RESULT" -eq 2 ]; then
    error "CNI bridge IP conflicts detected - fix script should be run"
    echo "To fix: ./scripts/fix_cni_bridge_conflict.sh"
elif [ "$TEST_POD_STATUS" = "ContainerCreating" ]; then
    warn "Pod creation issues detected - may need CNI bridge fix"
    echo "To diagnose: ./scripts/check_cni_bridge_conflict.sh"
    echo "To fix: ./scripts/fix_cni_bridge_conflict.sh"
else
    info "✓ CNI bridge configuration appears healthy"
    echo "Fix scripts are ready if needed in the future"
fi

echo
echo "Manual testing commands:"
echo "  Check for conflicts: ./scripts/check_cni_bridge_conflict.sh" 
echo "  Apply fix: ./scripts/fix_cni_bridge_conflict.sh"
echo "  Check events: kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -10"
echo "  Check pods: kubectl get pods --all-namespaces | grep ContainerCreating"
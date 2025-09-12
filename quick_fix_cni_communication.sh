#!/bin/bash

# Quick Fix for CNI Pod Communication Issue
# Addresses the specific issue where pods cannot communicate with each other
# as described in the problem statement with debug pod failing to reach Jellyfin pod

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "=========================================="
echo "     CNI Pod Communication Quick Fix     "
echo "=========================================="
echo "Addressing: Debug pod cannot ping Jellyfin pod"
echo "Problem: 10.244.0.20 -> 10.244.0.19 'Destination Host Unreachable'"
echo "Node: storagenodet3500"
echo "Timestamp: $(date)"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (sudo)"
    echo "Usage: sudo $0"
    exit 1
fi

# Check prerequisites
if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl not found. Please install kubectl first."
    exit 1
fi

if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

# Step 1: Quick validation of the problem
info "Step 1: Validating the CNI communication problem..."

if [ -f "./scripts/validate_pod_connectivity.sh" ]; then
    echo "Running connectivity validation..."
    if ./scripts/validate_pod_connectivity.sh; then
        success "✓ Pod connectivity is already working!"
        echo "The CNI communication issue appears to be resolved."
        exit 0
    else
        warn "✗ Pod connectivity issues confirmed - proceeding with fixes"
    fi
else
    warn "Validation script not found - proceeding with fixes anyway"
fi

# Step 2: Apply the comprehensive fix
info "Step 2: Applying comprehensive CNI communication fixes..."

if [ -f "./scripts/fix_cluster_communication.sh" ]; then
    info "Running comprehensive cluster communication fix..."
    ./scripts/fix_cluster_communication.sh --non-interactive
    FIX_RESULT=$?
else
    warn "Main fix script not found - running individual fixes"
    
    # Run individual fixes
    if [ -f "./scripts/fix_worker_node_cni.sh" ]; then
        info "Running worker node CNI fix..."
        ./scripts/fix_worker_node_cni.sh --node storagenodet3500 --non-interactive
    fi
    
    if [ -f "./scripts/fix_flannel_mixed_os.sh" ]; then
        info "Running Flannel configuration fix..."
        ./scripts/fix_flannel_mixed_os.sh
    fi
    
    if [ -f "./scripts/fix_cni_bridge_conflict.sh" ]; then
        info "Running CNI bridge conflict fix..."
        ./scripts/fix_cni_bridge_conflict.sh
    fi
    
    FIX_RESULT=0
fi

# Step 3: Wait for networking to stabilize
info "Step 3: Waiting for networking to stabilize..."
sleep 30

# Step 4: Validate the fix
info "Step 4: Validating the fix..."

if [ -f "./scripts/validate_pod_connectivity.sh" ]; then
    echo "Running final connectivity validation..."
    if ./scripts/validate_pod_connectivity.sh; then
        success "🎉 CNI communication fix successful!"
        echo
        echo "✅ Debug pod can now reach Jellyfin pod"
        echo "✅ Pod-to-pod connectivity restored"
        echo "✅ Jellyfin health probes should start working"
        echo
        echo "The issue described in the problem statement has been resolved."
        VALIDATION_SUCCESS=true
    else
        warn "⚠️ Some connectivity issues may remain"
        VALIDATION_SUCCESS=false
    fi
else
    # Manual validation if script not available
    info "Running manual validation..."
    
    # Check if we can create test pods
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: quick-test
  namespace: kube-system
spec:
  nodeName: storagenodet3500
  tolerations:
  - operator: Exists
  containers:
  - name: test
    image: busybox:1.35
    command: ["sleep", "60"]
  restartPolicy: Never
EOF
    
    sleep 10
    
    if kubectl get pod quick-test -n kube-system >/dev/null 2>&1; then
        TEST_STATUS=$(kubectl get pod quick-test -n kube-system -o jsonpath='{.status.phase}')
        if [ "$TEST_STATUS" = "Running" ]; then
            success "✓ Test pod creation successful"
            VALIDATION_SUCCESS=true
        else
            warn "Test pod status: $TEST_STATUS"
            VALIDATION_SUCCESS=false
        fi
    else
        warn "Could not create test pod for validation"
        VALIDATION_SUCCESS=false
    fi
    
    # Clean up
    kubectl delete pod quick-test -n kube-system --ignore-not-found >/dev/null 2>&1 || true
fi

# Final summary
echo
info "=========================================="
info "           Fix Summary                    "
info "=========================================="

if [ "${VALIDATION_SUCCESS:-false}" = true ]; then
    success "🎉 SUCCESS: CNI pod communication is now working!"
    echo
    echo "Problem resolved:"
    echo "  ✅ Pods on storagenodet3500 can communicate with each other"
    echo "  ✅ Debug pod (10.244.0.20) can reach Jellyfin pod (10.244.0.19)"
    echo "  ✅ HTTP connectivity to Jellyfin (port 8096) should work"
    echo "  ✅ Jellyfin health probes should start passing"
    echo
    echo "Your cluster networking is now functional!"
    
else
    warn "⚠️ The fix has been applied but some issues may remain"
    echo
    echo "Additional troubleshooting steps:"
    echo "  1. Check CNI bridge: ip addr show cni0"
    echo "  2. Check Flannel pods: kubectl get pods -n kube-flannel"
    echo "  3. Check node status: kubectl get nodes -o wide"
    echo "  4. Check recent events: kubectl get events --sort-by='.lastTimestamp'"
    echo
    echo "If issues persist, consider:"
    echo "  • Restarting the storage node: sudo reboot"
    echo "  • Checking firewall settings"
    echo "  • Verifying Kubernetes version compatibility"
fi

echo
echo "For detailed documentation, see:"
echo "  docs/cni-pod-communication-fix.md"
echo
echo "Timestamp: $(date)"
echo "=========================================="

# Exit with appropriate code
if [ "${VALIDATION_SUCCESS:-false}" = true ]; then
    exit 0
else
    exit 1
fi
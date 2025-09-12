#!/bin/bash

# Test script for CoreDNS Unknown Status Fix
# This script simulates the issue and tests the fix

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=== CoreDNS Unknown Status Fix - Test Script ==="
echo

# Check if we have kubectl access
if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster. This test requires cluster access."
    exit 1
fi

info "Step 1: Check current cluster state"
echo "Current CoreDNS status:"
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

echo
echo "Current cluster pod status:"
kubectl get pods --all-namespaces | head -10

info "Step 2: Test the CoreDNS status checker"
echo "Running: ./scripts/check_coredns_status.sh"
if ./scripts/check_coredns_status.sh; then
    info "CoreDNS status check passed - no issues detected"
else
    warn "CoreDNS status check failed - issues detected"
    
    info "Step 3: Test the CoreDNS fix script"
    echo "Running: ./scripts/fix_coredns_unknown_status.sh"
    if ./scripts/fix_coredns_unknown_status.sh; then
        info "CoreDNS fix script completed successfully"
    else
        error "CoreDNS fix script failed"
        exit 1
    fi
    
    info "Step 4: Verify fix worked"
    echo "Re-running status check..."
    if ./scripts/check_coredns_status.sh; then
        info "✅ CoreDNS fix successful - issues resolved"
    else
        warn "❌ CoreDNS issues still persist after fix"
    fi
fi

info "Step 5: Test DNS resolution functionality"

# Create a test pod for DNS testing
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: dns-test-script
  namespace: default
spec:
  containers:
  - name: dns-test
    image: busybox:1.35
    command: ['sleep', '120']
  restartPolicy: Never
  dnsPolicy: ClusterFirst
EOF

echo "Waiting for test pod to be ready..."
if kubectl wait --for=condition=Ready pod/dns-test-script -n default --timeout=60s; then
    echo "Testing internal DNS resolution..."
    if kubectl exec -n default dns-test-script -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
        info "✅ Internal DNS resolution works"
    else
        warn "❌ Internal DNS resolution failed"
    fi
    
    echo "Testing external DNS resolution..."
    if kubectl exec -n default dns-test-script -- nslookup google.com >/dev/null 2>&1; then
        info "✅ External DNS resolution works"
    else
        warn "❌ External DNS resolution failed (may be expected in restricted environments)"
    fi
else
    warn "Test pod failed to become ready - this may indicate ongoing issues"
fi

# Clean up test pod
kubectl delete pod dns-test-script -n default --ignore-not-found

info "Step 6: Final cluster health check"
echo "Final CoreDNS status:"
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

echo
echo "Problematic pods (should be minimal):"
kubectl get pods --all-namespaces | grep -E "(ContainerCreating|Pending|Unknown|Error|CrashLoopBackOff)" || echo "No problematic pods found!"

info "=== Test Complete ==="
echo
echo "Summary:"
echo "- CoreDNS status checker: Available at ./scripts/check_coredns_status.sh"
echo "- CoreDNS fix script: Available at ./scripts/fix_coredns_unknown_status.sh"  
echo "- Documentation: Available at docs/COREDNS_UNKNOWN_STATUS_FIX.md"
echo "- Integration: Automatically runs during 'deploy.sh full'"
echo
echo "The fix addresses CoreDNS 'Unknown' status issues that occur after flannel regeneration."
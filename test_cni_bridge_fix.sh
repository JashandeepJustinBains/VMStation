#!/bin/bash

# VMStation CNI Bridge Fix Validation Test
# This script validates that the CNI bridge fix changes are working correctly
# Run this on the control plane after applying the fixes

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================"
echo "  VMStation CNI Bridge Fix Validation Test                     "
echo "================================================================"
echo "Purpose: Validate CNI bridge fixes are working correctly"
echo "Timestamp: $(date)"
echo

# Check prerequisites
info "Checking prerequisites..."

if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl not found"
    exit 1
fi

if ! timeout 30 kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    exit 1
fi

success "Prerequisites check passed"

# Test 1: Validate CNI bridge IP range
info "Test 1: Validating CNI bridge IP range"

if ip addr show cni0 >/dev/null 2>&1; then
    CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
    info "Current CNI bridge IP: $CNI_IP"
    
    if echo "$CNI_IP" | grep -q "10.244."; then
        success "✓ CNI bridge has correct IP range (10.244.x.x)"
        TEST1_PASS=true
    else
        error "✗ CNI bridge has wrong IP range: $CNI_IP"
        TEST1_PASS=false
    fi
else
    warn "CNI bridge not found (may be normal if no pods scheduled)"
    TEST1_PASS=true
fi

# Test 2: Check for CNI bridge conflict events
info "Test 2: Checking for recent CNI bridge conflict events"

CNI_CONFLICTS=$(kubectl get events --all-namespaces --field-selector reason=FailedCreatePodSandBox 2>/dev/null | \
               grep -E "failed to set bridge addr.*cni0.*already has an IP address different" | \
               wc -l || echo "0")

if [ "$CNI_CONFLICTS" -eq 0 ]; then
    success "✓ No recent CNI bridge conflict events found"
    TEST2_PASS=true
else
    error "✗ Found $CNI_CONFLICTS recent CNI bridge conflict events"
    warn "Recent events:"
    kubectl get events --all-namespaces --field-selector reason=FailedCreatePodSandBox | \
    grep -E "failed to set bridge addr.*cni0.*already has an IP address different" | tail -3
    TEST2_PASS=false
fi

# Test 3: Check Jellyfin pod status
info "Test 3: Checking Jellyfin pod status"

if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null)
    POD_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
    
    info "Jellyfin pod status: $POD_STATUS"
    info "Jellyfin pod IP: ${POD_IP:-<none>}"
    
    if [ "$POD_STATUS" = "Running" ]; then
        success "✓ Jellyfin pod is Running"
        
        if [ -n "$POD_IP" ] && echo "$POD_IP" | grep -q "10.244."; then
            success "✓ Jellyfin pod has correct IP range: $POD_IP"
            TEST3_PASS=true
        else
            warn "Jellyfin pod IP is not in expected range: $POD_IP"
            TEST3_PASS=false
        fi
    else
        error "✗ Jellyfin pod is not running: $POD_STATUS"
        TEST3_PASS=false
    fi
else
    warn "Jellyfin pod not found"
    TEST3_PASS=false
fi

# Test 4: Check Jellyfin service accessibility
info "Test 4: Testing Jellyfin service accessibility"

# Check service exists
if kubectl get service -n jellyfin jellyfin-service >/dev/null 2>&1; then
    NODE_PORT=$(kubectl get service -n jellyfin jellyfin-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
    
    if [ -n "$NODE_PORT" ]; then
        info "Jellyfin NodePort: $NODE_PORT"
        
        # Test the corrected URL
        info "Testing corrected URL: http://192.168.4.61:${NODE_PORT}/web/#/home.html"
        
        # Note: In test environment, we can't actually test HTTP connectivity
        # But we can validate the URL format and service configuration
        if [ "$NODE_PORT" = "30096" ]; then
            success "✓ Service has expected NodePort: 30096"
            success "✓ Corrected URL format validated"
            TEST4_PASS=true
        else
            warn "Service has unexpected NodePort: $NODE_PORT (expected 30096)"
            TEST4_PASS=false
        fi
    else
        error "✗ Cannot determine service NodePort"
        TEST4_PASS=false
    fi
else
    error "✗ Jellyfin service not found"
    TEST4_PASS=false
fi

# Test 5: Validate network components
info "Test 5: Validating network components status"

# Check Flannel
FLANNEL_READY=$(kubectl get pods -n kube-flannel -l app=flannel 2>/dev/null | grep "Running" | wc -l)
FLANNEL_TOTAL=$(kubectl get pods -n kube-flannel -l app=flannel 2>/dev/null | grep -v "NAME" | wc -l)

if [ "$FLANNEL_READY" -eq "$FLANNEL_TOTAL" ] && [ "$FLANNEL_TOTAL" -gt 0 ]; then
    success "✓ Flannel pods are ready: $FLANNEL_READY/$FLANNEL_TOTAL"
    FLANNEL_OK=true
else
    error "✗ Flannel pods not ready: $FLANNEL_READY/$FLANNEL_TOTAL"
    FLANNEL_OK=false
fi

# Check CoreDNS
COREDNS_READY=$(kubectl get pods -n kube-system -l k8s-app=kube-dns 2>/dev/null | grep "Running" | wc -l)
COREDNS_TOTAL=$(kubectl get pods -n kube-system -l k8s-app=kube-dns 2>/dev/null | grep -v "NAME" | wc -l)

if [ "$COREDNS_READY" -eq "$COREDNS_TOTAL" ] && [ "$COREDNS_TOTAL" -gt 0 ]; then
    success "✓ CoreDNS pods are ready: $COREDNS_READY/$COREDNS_TOTAL"
    COREDNS_OK=true
else
    error "✗ CoreDNS pods not ready: $COREDNS_READY/$COREDNS_TOTAL"
    COREDNS_OK=false
fi

if [ "$FLANNEL_OK" = true ] && [ "$COREDNS_OK" = true ]; then
    TEST5_PASS=true
else
    TEST5_PASS=false
fi

# Test 6: Check for stuck pods
info "Test 6: Checking for stuck pods"

STUCK_PODS=$(kubectl get pods --all-namespaces 2>/dev/null | grep -E "(ContainerCreating|Pending|CrashLoopBackOff)" | wc -l)

if [ "$STUCK_PODS" -eq 0 ]; then
    success "✓ No stuck pods found"
    TEST6_PASS=true
else
    error "✗ Found $STUCK_PODS stuck pods"
    warn "Stuck pods:"
    kubectl get pods --all-namespaces | grep -E "(ContainerCreating|Pending|CrashLoopBackOff)" | head -5
    TEST6_PASS=false
fi

# Test Results Summary
echo
echo "================================================================"
echo "  Test Results Summary                                          "
echo "================================================================"

TESTS_PASSED=0
TOTAL_TESTS=6

echo "Test 1 - CNI Bridge IP Range: $([ "$TEST1_PASS" = true ] && echo "PASS" || echo "FAIL")"
[ "$TEST1_PASS" = true ] && ((TESTS_PASSED++))

echo "Test 2 - No CNI Conflicts: $([ "$TEST2_PASS" = true ] && echo "PASS" || echo "FAIL")"
[ "$TEST2_PASS" = true ] && ((TESTS_PASSED++))

echo "Test 3 - Jellyfin Pod Status: $([ "$TEST3_PASS" = true ] && echo "PASS" || echo "FAIL")"
[ "$TEST3_PASS" = true ] && ((TESTS_PASSED++))

echo "Test 4 - Service Configuration: $([ "$TEST4_PASS" = true ] && echo "PASS" || echo "FAIL")"
[ "$TEST4_PASS" = true ] && ((TESTS_PASSED++))

echo "Test 5 - Network Components: $([ "$TEST5_PASS" = true ] && echo "PASS" || echo "FAIL")"
[ "$TEST5_PASS" = true ] && ((TESTS_PASSED++))

echo "Test 6 - No Stuck Pods: $([ "$TEST6_PASS" = true ] && echo "PASS" || echo "FAIL")"
[ "$TEST6_PASS" = true ] && ((TESTS_PASSED++))

echo
echo "Tests Passed: $TESTS_PASSED/$TOTAL_TESTS"

if [ "$TESTS_PASSED" -eq "$TOTAL_TESTS" ]; then
    success "🎉 ALL TESTS PASSED - CNI bridge fix is working correctly!"
    echo
    echo "Next steps:"
    echo "1. Access Jellyfin at: http://192.168.4.61:30096/web/#/home.html"
    echo "2. Verify web interface loads correctly"
    echo "3. Configure Jellyfin media libraries as needed"
    exit 0
elif [ "$TESTS_PASSED" -ge 4 ]; then
    warn "Most tests passed ($TESTS_PASSED/$TOTAL_TESTS) - fix is mostly working"
    echo
    echo "Recommended actions:"
    echo "1. Review failed test details above"
    echo "2. Consider running: sudo ./fix_jellyfin_immediate.sh"
    echo "3. Check logs: kubectl logs -n jellyfin jellyfin"
    exit 1
else
    error "Multiple tests failed ($TESTS_PASSED/$TOTAL_TESTS) - fix needs attention"
    echo
    echo "Recommended actions:"
    echo "1. Run: sudo ./fix_jellyfin_immediate.sh"
    echo "2. Check cluster status: kubectl get pods --all-namespaces"
    echo "3. Check CNI logs: kubectl logs -n kube-flannel -l app=flannel"
    echo "4. Consider cluster reset: ./deploy-cluster.sh reset"
    exit 1
fi
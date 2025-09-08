#!/bin/bash

# Test script for enhanced timeout handling fix
# Tests that timeout values are increased and diagnostics are enhanced

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_test_header() {
    echo ""
    echo "=== $1 ==="
}

# Test file
SETUP_CLUSTER_FILE="/home/runner/work/VMStation/VMStation/ansible/plays/kubernetes/setup_cluster.yaml"

if [ ! -f "$SETUP_CLUSTER_FILE" ]; then
    print_error "Setup cluster file not found: $SETUP_CLUSTER_FILE"
    exit 1
fi

echo "=== Enhanced Timeout Handling Fix Validation ==="
echo "Testing improvements for worker node join timeout issues"
echo ""

# Test 1: Primary timeout increased from 300s to 600s (10 minutes)
print_test_header "Test 1: Primary join timeout increased"
if grep -q "timeout 600.*kubeadm-join.sh" "$SETUP_CLUSTER_FILE" && grep -B 1 "timeout 600.*kubeadm-join.sh" "$SETUP_CLUSTER_FILE" | grep -q "primary attempt"; then
    print_success "Primary join timeout increased to 600s (10 minutes)"
else
    print_error "Primary join timeout not properly increased"
    exit 1
fi

# Test 2: Retry timeout increased from 420s to 900s (15 minutes)  
print_test_header "Test 2: Retry join timeout increased"
if grep -q "timeout 900.*kubeadm-join.sh" "$SETUP_CLUSTER_FILE" && grep -B 1 "timeout 900.*kubeadm-join.sh" "$SETUP_CLUSTER_FILE" | grep -q "retry"; then
    print_success "Retry join timeout increased to 900s (15 minutes)"
else
    print_error "Retry join timeout not properly increased"
    exit 1
fi

# Test 3: Enhanced diagnostics include kubelet status
print_test_header "Test 3: Kubelet diagnostics added"
if grep -q "Check kubelet status for diagnostic information" "$SETUP_CLUSTER_FILE"; then
    print_success "Kubelet diagnostic information collection added"
else
    print_error "Kubelet diagnostics missing"
    exit 1
fi

# Test 4: Pre-join verification added
print_test_header "Test 4: Pre-join kubelet readiness verification"
if grep -q "Pre-join kubelet readiness verification" "$SETUP_CLUSTER_FILE"; then
    print_success "Pre-join kubelet readiness verification added"
else
    print_error "Pre-join kubelet verification missing"
    exit 1
fi

# Test 5: Wait time before retry increased
print_test_header "Test 5: Extended wait time before retry"
if grep -q "seconds: 60" "$SETUP_CLUSTER_FILE" && grep -A 3 -B 3 "seconds: 60" "$SETUP_CLUSTER_FILE" | grep -q "Wait before retry"; then
    print_success "Wait time before retry increased to 60 seconds"
else
    print_error "Extended wait time before retry not found"
    exit 1
fi

# Test 6: Containerd socket verification
print_test_header "Test 6: Containerd socket verification"
if grep -q "Verify containerd socket is available" "$SETUP_CLUSTER_FILE"; then
    print_success "Containerd socket verification present"
else
    print_error "Containerd socket verification missing"
    exit 1
fi

# Test 7: Enhanced error information includes stdout
print_test_header "Test 7: Enhanced error information"
if grep -A 10 "Analyze first attempt failure" "$SETUP_CLUSTER_FILE" | grep -q "Stdout:"; then
    print_success "Enhanced error information includes stdout"
else
    print_error "Enhanced error information missing stdout"
    exit 1
fi

# Test 8: Ansible syntax validation
print_test_header "Test 8: Ansible syntax validation"
if ansible-playbook --syntax-check "$SETUP_CLUSTER_FILE" >/dev/null 2>&1; then
    print_success "Ansible playbook syntax is valid"
else
    print_error "Ansible playbook syntax validation failed"
    exit 1
fi

print_test_header "Test Summary"
print_success "🎉 All enhanced timeout handling tests passed!"
echo ""
print_info "Enhanced timeout handling improvements:"
print_info "  ✓ Primary join timeout: 300s → 600s (10 minutes)"
print_info "  ✓ Retry join timeout: 420s → 900s (15 minutes)"
print_info "  ✓ Wait before retry: 30s → 60s"
print_info "  ✓ Pre-join kubelet readiness verification"
print_info "  ✓ Enhanced kubelet diagnostics during failures"
print_info "  ✓ Containerd socket verification before join"
print_info "  ✓ Improved error reporting with stdout/stderr"
echo ""
print_info "These improvements should resolve timeout issues for:"
print_info "  - Worker node 192.168.4.61 (Return Code 1, kubelet-start timeout)"
print_info "  - Worker node 192.168.4.62 (Return Code 124, timeout)"
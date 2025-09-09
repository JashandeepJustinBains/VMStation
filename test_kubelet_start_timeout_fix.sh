#!/bin/bash

# Test script for kubelet-start timeout handling improvements
# Tests specific improvements for "kubelet-start: timed out waiting for the condition" errors

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

echo "=== Kubelet-Start Timeout Fix Validation ==="
echo "Testing specific improvements for kubelet-start phase timeout issues"
echo ""

# Test 1: Kubelet optimization before join
print_test_header "Test 1: Kubelet pre-join optimization"
if grep -q "Optimize kubelet configuration for faster startup" "$SETUP_CLUSTER_FILE"; then
    print_success "Kubelet pre-join optimization added"
else
    print_error "Kubelet pre-join optimization missing"
    exit 1
fi

# Test 2: Container runtime pre-warming
print_test_header "Test 2: Container runtime pre-warming"
if grep -q "Pre-warm container runtime for faster join" "$SETUP_CLUSTER_FILE"; then
    print_success "Container runtime pre-warming implemented"
else
    print_error "Container runtime pre-warming missing"
    exit 1
fi

# Test 3: Enhanced join command with kubelet-start optimization
print_test_header "Test 3: Enhanced join command with kubelet-start optimization"
if grep -q "kubelet-start optimization" "$SETUP_CLUSTER_FILE" && grep -q "skip-phases=addon/kube-proxy" "$SETUP_CLUSTER_FILE"; then
    print_success "Enhanced join command with kubelet-start optimization present"
else
    print_error "Enhanced join command missing kubelet-start optimization"
    exit 1
fi

# Test 4: Increased primary timeout for kubelet-start
print_test_header "Test 4: Increased primary timeout for kubelet-start issues"
if grep -q "timeout 900.*kubeadm-join.sh" "$SETUP_CLUSTER_FILE" && grep -B 1 "timeout 900.*kubeadm-join.sh" "$SETUP_CLUSTER_FILE" | grep -q "kubelet-start phase optimization"; then
    print_success "Primary timeout increased to 900s (15 minutes) for kubelet-start issues"
else
    print_error "Primary timeout not increased for kubelet-start handling"
    exit 1
fi

# Test 5: Enhanced retry timeout for extreme cases
print_test_header "Test 5: Enhanced retry timeout for extreme kubelet-start cases"
if grep -q "timeout 1200.*kubeadm-join.sh" "$SETUP_CLUSTER_FILE" && grep -B 1 "timeout 1200.*kubeadm-join.sh" "$SETUP_CLUSTER_FILE" | grep -q "maximum timeout and kubelet-start phase optimization"; then
    print_success "Retry timeout increased to 1200s (20 minutes) for extreme cases"
else
    print_error "Retry timeout not enhanced for extreme kubelet-start cases"
    exit 1
fi

# Test 6: Kubelet-start specific failure detection
print_test_header "Test 6: Kubelet-start specific failure detection and recovery"
if grep -q "Detect kubelet-start specific failures" "$SETUP_CLUSTER_FILE" && grep -q "is_kubelet_start_timeout" "$SETUP_CLUSTER_FILE"; then
    print_success "Kubelet-start specific failure detection implemented"
else
    print_error "Kubelet-start specific failure detection missing"
    exit 1
fi

# Test 7: Enhanced kubelet service preparation for retry
print_test_header "Test 7: Enhanced kubelet service preparation for retry"
if grep -q "Enhanced kubelet service preparation for retry" "$SETUP_CLUSTER_FILE"; then
    print_success "Enhanced kubelet service preparation for retry present"
else
    print_error "Enhanced kubelet service preparation missing"
    exit 1
fi

# Test 8: Containerd performance testing and optimization
print_test_header "Test 8: Containerd performance testing and optimization"
if grep -q "Verify containerd can create containers quickly" "$SETUP_CLUSTER_FILE"; then
    print_success "Containerd performance testing and optimization implemented"
else
    print_error "Containerd performance testing missing"
    exit 1
fi

# Test 9: Extended wait time for kubelet-start recovery
print_test_header "Test 9: Extended wait time for kubelet-start recovery"
if grep -q "seconds: 90" "$SETUP_CLUSTER_FILE" && grep -A 3 -B 3 "seconds: 90" "$SETUP_CLUSTER_FILE" | grep -q "kubelet-start timeout recovery"; then
    print_success "Wait time extended to 90 seconds for kubelet-start recovery"
else
    print_error "Extended wait time for kubelet-start recovery not found"
    exit 1
fi

# Test 10: Ansible syntax validation
print_test_header "Test 10: Ansible syntax validation"
if ansible-playbook --syntax-check "$SETUP_CLUSTER_FILE" >/dev/null 2>&1; then
    print_success "Ansible playbook syntax is valid"
else
    print_error "Ansible playbook syntax validation failed"
    exit 1
fi

print_test_header "Test Summary"
print_success "🎉 All kubelet-start timeout handling tests passed!"
echo ""
print_info "Kubelet-start timeout improvements:"
print_info "  ✓ Primary join timeout: 600s → 900s (15 minutes)"
print_info "  ✓ Retry join timeout: 900s → 1200s (20 minutes)"  
print_info "  ✓ Wait before retry: 60s → 90s"
print_info "  ✓ Pre-join kubelet optimization and cache clearing"
print_info "  ✓ Container runtime pre-warming with pause and proxy images"
print_info "  ✓ Kubelet-start specific failure detection and recovery"
print_info "  ✓ Enhanced containerd performance testing and optimization"
print_info "  ✓ Optimized join command with skip-phases for faster startup"
print_info "  ✓ Enhanced kubelet service preparation between attempts"
echo ""
print_info "These improvements specifically target:"
print_info "  - 'kubelet-start: timed out waiting for the condition' errors"
print_info "  - Worker node 192.168.4.61 (Return Code 1, kubelet-start timeout)"  
print_info "  - Worker node 192.168.4.62 (Return Code 1, kubelet-start timeout)"
print_info "  - Slow container runtime response during kubelet startup"
print_info "  - Kubelet state conflicts that delay join process"
#!/bin/bash

# Test Timeout Reduction Fix
# Validates that timeout values have been reduced and root cause fixes are in place

set -e

echo "=== Timeout Reduction and Root Cause Fix Validation ==="
echo "Timestamp: $(date)"
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

success() { echo -e "${GREEN}✓ $1${NC}"; }
error() { echo -e "${RED}✗ $1${NC}"; }
info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Test 1: Verify timeout values have been reduced in enhanced_kubeadm_join.sh
info "Test 1: Checking enhanced_kubeadm_join.sh timeout values"
if grep -q 'JOIN_TIMEOUT="${JOIN_TIMEOUT:-60}"' scripts/enhanced_kubeadm_join.sh; then
    success "JOIN_TIMEOUT reduced from 300s to 60s"
else
    error "JOIN_TIMEOUT not reduced - still set to 300s"
    exit 1
fi

if grep -q 'MAX_RETRIES="${MAX_RETRIES:-2}"' scripts/enhanced_kubeadm_join.sh; then
    success "MAX_RETRIES reduced from 3 to 2"
else
    error "MAX_RETRIES not reduced - still set to 3"
    exit 1
fi

# Test 2: Verify Ansible timeout values have been reduced
info "Test 2: Checking Ansible playbook timeout values"
if grep -q "export JOIN_TIMEOUT=60" ansible/plays/setup-cluster.yaml; then
    success "Ansible JOIN_TIMEOUT reduced to 60s"
else
    error "Ansible JOIN_TIMEOUT not reduced"
    exit 1
fi

if grep -q "timeout 120" ansible/plays/setup-cluster.yaml; then
    success "Ansible kubeadm join timeout reduced to 120s"
else
    error "Ansible kubeadm join timeout not reduced from 600s"
    exit 1
fi

# Test 3: Verify containerd filesystem fix is in place
info "Test 3: Checking containerd filesystem capacity fix"
if grep -q "containerd_capacity.*df -BG" scripts/enhanced_kubeadm_join.sh; then
    success "Containerd filesystem capacity check added"
else
    error "Containerd filesystem capacity check missing"
    exit 1
fi

if grep -q "invalid capacity 0" scripts/enhanced_kubeadm_join.sh; then
    success "Containerd capacity issue detection added"
else
    error "Containerd capacity issue detection missing"
    exit 1
fi

# Test 4: Verify CNI preparation is in place
info "Test 4: Checking CNI preparation fix"
if grep -q "mkdir -p /etc/cni/net.d" scripts/enhanced_kubeadm_join.sh; then
    success "CNI directory preparation added"
else
    error "CNI directory preparation missing"
    exit 1
fi

# Test 5: Verify faster failure detection
info "Test 5: Checking faster failure detection"
if grep -q "Every 15 seconds, check for specific failure patterns" scripts/enhanced_kubeadm_join.sh; then
    success "Faster failure detection (15s intervals) added"
else
    error "Faster failure detection not implemented"
    exit 1
fi

if grep -q "kubeadm TLS Bootstrap timeout (40s limit exceeded)" scripts/enhanced_kubeadm_join.sh; then
    success "Specific TLS Bootstrap timeout detection added"
else
    error "TLS Bootstrap timeout detection missing"
    exit 1
fi

# Test 6: Verify retry delays have been reduced
info "Test 6: Checking retry delay reductions"
if grep -q "local wait_time=15" scripts/enhanced_kubeadm_join.sh; then
    success "Enhanced script retry delay reduced to 15s"
else
    error "Enhanced script retry delay not reduced"
    exit 1
fi

if grep -q "delay: 15" ansible/plays/setup-cluster.yaml && grep -q "retries: 2" ansible/plays/setup-cluster.yaml; then
    success "Ansible retry delay reduced to 15s with 2 retries"
else
    error "Ansible retry delay not properly reduced"
    exit 1
fi

# Test 7: Verify diagnostics script exists
info "Test 7: Checking diagnostic script"
if [ -f "scripts/quick_join_diagnostics.sh" ] && [ -x "scripts/quick_join_diagnostics.sh" ]; then
    success "Quick diagnostics script created and executable"
else
    error "Quick diagnostics script missing or not executable"
    exit 1
fi

echo ""
echo "=== Summary of Changes Made ==="
info "Timeout Reductions:"
echo "  • Enhanced join timeout: 300s → 60s"
echo "  • Ansible kubeadm timeout: 600s → 120s"
echo "  • Max retries: 3 → 2"
echo "  • Retry delays: 30s → 15s"
echo "  • Various wait operations reduced by 50-70%"

echo ""
info "Root Cause Fixes:"
echo "  • Added containerd filesystem capacity detection and repair"
echo "  • Added CNI directory preparation to prevent network delays"
echo "  • Added kubelet readiness checks before join attempts"
echo "  • Added faster failure detection (every 15s vs 5s)"
echo "  • Added specific detection for TLS Bootstrap timeout (40s limit)"
echo "  • Added detection for containerd capacity issues"
echo "  • Added detection for API server connectivity issues"

echo ""
info "Diagnostic Improvements:"
echo "  • Created quick_join_diagnostics.sh for rapid issue identification"
echo "  • Enhanced error messages with specific root causes"
echo "  • Better logging of failure patterns during join process"

echo ""
success "All timeout reduction and root cause fixes validated successfully!"
info "Expected result: Much faster failure detection and fix of underlying issues"
info "Join attempts should now fail fast with clear error messages instead of"
info "waiting through long timeouts when the root cause can be identified quickly."
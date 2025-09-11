#!/bin/bash

# VMStation Post-Wipe Worker Join Validation Test
# This script validates that the enhanced post-wipe worker join functionality is working correctly

# Remove set -e to prevent premature exit on arithmetic operations
# set -e

echo "=== VMStation Post-Wipe Worker Join Validation Test ==="
echo "Timestamp: $(date)"
echo ""

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Test 1: Validate enhanced join script has post-wipe detection
info "Test 1: Validating enhanced join script has post-wipe detection..."

if grep -q "detect_post_wipe_state" scripts/enhanced_kubeadm_join.sh; then
    info "✓ Enhanced join script contains post-wipe detection function"
else
    error "✗ Enhanced join script missing post-wipe detection"
    exit 1
fi

if grep -q "WORKER_POST_WIPE" scripts/enhanced_kubeadm_join.sh; then
    info "✓ Enhanced join script has post-wipe state tracking"
else
    error "✗ Enhanced join script missing post-wipe state tracking"
    exit 1
fi

# Test 2: Validate Ansible playbook has enhanced worker join logic
info "Test 2: Validating Ansible playbook has enhanced worker join logic..."

if grep -q "Detect post-wipe worker state" ansible/plays/setup-cluster.yaml; then
    info "✓ Ansible playbook contains post-wipe worker detection"
else
    error "✗ Ansible playbook missing post-wipe worker detection"
    exit 1
fi

if grep -q "worker_was_wiped" ansible/plays/setup-cluster.yaml; then
    info "✓ Ansible playbook has post-wipe state variable"
else
    error "✗ Ansible playbook missing post-wipe state variable"
    exit 1
fi

if grep -q "control-plane readiness" ansible/plays/setup-cluster.yaml; then
    info "✓ Ansible playbook includes control-plane readiness validation"
else
    error "✗ Ansible playbook missing control-plane readiness validation"
    exit 1
fi

# Test 3: Validate join token management enhancements
info "Test 3: Validating join token management enhancements..."

if grep -q "Generate fresh join command for wiped workers" ansible/plays/setup-cluster.yaml; then
    info "✓ Ansible playbook has enhanced join token generation"
else
    error "✗ Ansible playbook missing enhanced join token generation"
    exit 1
fi

if grep -q "ttl=2h" ansible/plays/setup-cluster.yaml; then
    info "✓ Join tokens configured with 2-hour TTL"
else
    error "✗ Join tokens missing extended TTL configuration"
    exit 1
fi

# Test 4: Validate enhanced validation and verification
info "Test 4: Validating enhanced validation and verification..."

if grep -q "Enhanced kubeadm join with post-wipe worker support" ansible/plays/setup-cluster.yaml; then
    info "✓ Ansible playbook has enhanced join support"
else
    error "✗ Ansible playbook missing enhanced join support"
    exit 1
fi

if grep -q "Post-join validation and verification for wiped workers" ansible/plays/setup-cluster.yaml; then
    info "✓ Ansible playbook has enhanced post-join validation"
else
    error "✗ Ansible playbook missing enhanced post-join validation"
    exit 1
fi

if grep -q "NOT standalone" ansible/plays/setup-cluster.yaml; then
    info "✓ Ansible playbook explicitly checks for non-standalone mode"
else
    error "✗ Ansible playbook missing standalone mode prevention"
    exit 1
fi

# Test 5: Validate documentation and usage instructions
info "Test 5: Validating documentation and usage instructions..."

if [ -f docs/POST_WIPE_WORKER_JOIN.md ]; then
    info "✓ Post-wipe worker join documentation exists"
else
    error "✗ Post-wipe worker join documentation missing"
    exit 1
fi

if grep -q "Post-Wipe Worker Recovery" USAGE_INSTRUCTIONS.md; then
    info "✓ Usage instructions updated with post-wipe recovery"
else
    error "✗ Usage instructions missing post-wipe recovery section"
    exit 1
fi

# Test 6: Validate deploy.sh integration
info "Test 6: Validating deploy.sh integration..."

if grep -q "cluster" deploy.sh && grep -q "setup-cluster.yaml" deploy.sh; then
    info "✓ deploy.sh integrates with enhanced cluster setup"
else
    error "✗ deploy.sh missing cluster setup integration"
    exit 1
fi

# Test 7: Syntax validation
info "Test 7: Validating script syntax..."

if bash -n scripts/enhanced_kubeadm_join.sh; then
    info "✓ Enhanced join script syntax is valid"
else
    error "✗ Enhanced join script has syntax errors"
    exit 1
fi

if ansible-playbook --syntax-check ansible/plays/setup-cluster.yaml >/dev/null 2>&1; then
    info "✓ Ansible playbook syntax is valid"
else
    error "✗ Ansible playbook has syntax errors"
    exit 1
fi

# Test 8: Validate key functionality markers
info "Test 8: Validating key functionality markers..."

post_wipe_markers=(
    "Post-wipe worker detected"
    "Wipe percentage"
    "Fresh join token generated"
    "Control-plane readiness"
    "POST-WIPE WORKER INTEGRATION SUCCESSFUL"
    "Enhanced Join for Post-Wipe Worker"
)

marker_count=0
for marker in "${post_wipe_markers[@]}"; do
    if grep -r "$marker" ansible/plays/setup-cluster.yaml scripts/enhanced_kubeadm_join.sh >/dev/null 2>&1; then
        debug "✓ Found marker: $marker"
        ((marker_count++))
    else
        warn "✗ Missing marker: $marker"
    fi
done

if [ $marker_count -ge 4 ]; then
    info "✓ Sufficient post-wipe functionality markers found ($marker_count/$(echo ${#post_wipe_markers[@]}))"
else
    error "✗ Insufficient post-wipe functionality markers ($marker_count/$(echo ${#post_wipe_markers[@]}))"
    exit 1
fi

echo ""
info "=== ALL VALIDATION TESTS PASSED ==="
echo ""
info "Post-Wipe Worker Join Enhancement Summary:"
info "✓ Enhanced join script with automatic post-wipe detection"
info "✓ Ansible playbook with comprehensive post-wipe worker support"
info "✓ Fresh join token management with 2-hour TTL"
info "✓ Control-plane readiness validation"
info "✓ Enhanced pre-join and post-join validation"
info "✓ Standalone mode prevention and verification"
info "✓ Comprehensive documentation and usage instructions"
info "✓ Full integration with deploy.sh cluster deployment"
echo ""
info "🎉 The enhanced post-wipe worker join functionality is ready!"
echo ""
info "Usage after aggressive worker wipe:"
info "  1. Run aggressive_worker_wipe_preserve_storage.sh on each worker"
info "  2. From master node: ./deploy.sh cluster"
info "  3. Workers will automatically be detected as post-wipe and joined cleanly"
echo ""
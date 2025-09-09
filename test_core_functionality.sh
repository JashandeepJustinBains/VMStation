#!/bin/bash

# Core VMStation Functionality Test
# Tests the essential components after cleanup and kubelet join fixes

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}!${NC} $1"
}

info() {
    echo "[INFO] $1"
}

echo "=== VMStation Core Functionality Test ==="
echo "Timestamp: $(date)"
echo ""

FAILED_TESTS=0

# Test 1: Ansible Syntax Validation
echo "=== Test 1: Ansible Configuration ==="
if [ -f "ansible/plays/kubernetes/setup_cluster.yaml" ]; then
    info "Checking Ansible syntax..."
    if ansible-playbook --syntax-check ansible/plays/kubernetes/setup_cluster.yaml >/dev/null 2>&1; then
        success "Ansible playbook syntax is valid"
    else
        error "Ansible playbook syntax errors detected"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    error "Main setup_cluster.yaml not found"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 2: Essential Scripts Present
echo ""
echo "=== Test 2: Essential Scripts ==="
ESSENTIAL_SCRIPTS=("update_and_deploy.sh" "deploy_kubernetes.sh" "troubleshoot_kubelet_join.sh")

for script in "${ESSENTIAL_SCRIPTS[@]}"; do
    if [ -f "$script" ] && [ -x "$script" ]; then
        success "$script is present and executable"
    else
        error "$script is missing or not executable"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done

# Test 3: Kubelet Join Configuration
echo ""
echo "=== Test 3: Kubelet Join Configuration ==="
SETUP_FILE="ansible/plays/kubernetes/setup_cluster.yaml"

# Check for proper kubeadm join configuration
if grep -q "kubeadm.*join" "$SETUP_FILE"; then
    success "Kubeadm join configuration found"
else
    error "Kubeadm join configuration missing"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Check that deprecated network-plugin flag is not used
if grep -q "network-plugin" "$SETUP_FILE" && ! grep -q "# .*network-plugin" "$SETUP_FILE"; then
    error "Deprecated --network-plugin flag found in use"
    FAILED_TESTS=$((FAILED_TESTS + 1))
else
    success "No deprecated network-plugin flags in active configuration"
fi

# Test 4: Documentation Updates
echo ""
echo "=== Test 4: Documentation ==="
if [ -f "TODO.md" ]; then
    if grep -q "kubeadm" TODO.md && ! grep -q "K3s" TODO.md; then
        success "TODO.md updated for kubeadm (no K3s references)"
    else
        warn "TODO.md may still contain outdated K3s references"
    fi
else
    error "TODO.md missing"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

# Test 5: Directory Structure
echo ""
echo "=== Test 5: Directory Organization ==="
TEST_COUNT=$(find . -maxdepth 1 -name "test_*.sh" | wc -l)
info "Test scripts in root: $TEST_COUNT (reduced from 33+ original)"

if [ "$TEST_COUNT" -lt 25 ]; then
    success "Test script count reduced (cleanup successful)"
else
    warn "Test script count still high - more cleanup may be needed"
fi

# Test 6: Key Components Present
echo ""
echo "=== Test 6: Infrastructure Components ==="
DIRS=("ansible/plays/kubernetes" "scripts" "docs")

for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        success "$dir directory exists"
    else
        error "$dir directory missing"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done

# Summary
echo ""
echo "=== Test Summary ==="
if [ "$FAILED_TESTS" -eq 0 ]; then
    success "All core functionality tests passed!"
    echo ""
    info "VMStation is ready for deployment:"
    info "  1. Run: ./update_and_deploy.sh"
    info "  2. For kubelet issues: sudo ./troubleshoot_kubelet_join.sh" 
    info "  3. Monitoring: ./deploy_kubernetes.sh"
    echo ""
    info "Worker node join procedure (if needed):"
    info "  1. On control plane: kubeadm token create --print-join-command"
    info "  2. On worker: sudo <join-command>"
    info "  3. On control plane: kubectl certificate approve <csr-name>"
else
    error "$FAILED_TESTS test(s) failed"
    echo ""
    warn "Please fix the failing tests before deployment"
    exit 1
fi
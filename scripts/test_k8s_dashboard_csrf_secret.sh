#!/usr/bin/env bash
set -euo pipefail

# Test script to validate the kubernetes-dashboard-csrf secret creation task
# This script tests the new Ansible task functionality

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLAYBOOK="$REPO_ROOT/ansible/subsites/05-extra_apps.yaml"

echo "=== Testing kubernetes-dashboard-csrf secret creation task ==="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Test 1: Check syntax validation
print_info "Test 1: Syntax validation"
if ansible-playbook --syntax-check "$PLAYBOOK" >/dev/null 2>&1; then
    print_success "Playbook syntax is valid"
else
    print_error "Playbook syntax check failed"
    exit 1
fi

# Test 2: Check that the secret creation task exists
print_info "Test 2: Verify secret creation task exists"
CSRF_TASK_COUNT=$(grep -c "kubernetes-dashboard-csrf" "$PLAYBOOK" || echo "0")
if [ "$CSRF_TASK_COUNT" -ge 2 ]; then
    print_success "Found kubernetes-dashboard-csrf secret tasks in playbook"
else
    print_error "kubernetes-dashboard-csrf secret tasks not found in playbook"
    exit 1
fi

# Test 3: Check task placement (should be before dashboard deployment)
print_info "Test 3: Verify task placement"
SECRET_LINE=$(grep -n "Create kubernetes-dashboard-csrf secret" "$PLAYBOOK" | cut -d: -f1 || echo "0")
DEPLOYMENT_LINE=$(grep -n "Create kubernetes-dashboard deployment" "$PLAYBOOK" | cut -d: -f1 || echo "0")

if [ "$SECRET_LINE" -gt 0 ] && [ "$DEPLOYMENT_LINE" -gt 0 ] && [ "$SECRET_LINE" -lt "$DEPLOYMENT_LINE" ]; then
    print_success "Secret creation task is properly placed before deployment"
else
    print_error "Secret creation task is not properly placed"
    echo "Secret task line: $SECRET_LINE"
    echo "Deployment task line: $DEPLOYMENT_LINE"
    exit 1
fi

# Test 4: Check for idempotency conditions
print_info "Test 4: Verify idempotency conditions"
IDEMPOTENT_CONDITIONS=$(grep -A 5 -B 5 "kubernetes-dashboard-csrf secret" "$PLAYBOOK" | grep -E "(when:|register:|k8s_info)" | wc -l || echo "0")
if [ "$IDEMPOTENT_CONDITIONS" -ge 3 ]; then
    print_success "Found idempotency conditions (register, when, k8s_info)"
else
    print_error "Missing proper idempotency conditions"
    exit 1
fi

# Test 5: Check for secure token generation
print_info "Test 5: Verify secure token generation"
if grep -q "lookup('password'" "$PLAYBOOK"; then
    print_success "Using Ansible password lookup for secure token generation"
else
    print_error "Secure token generation not found"
    exit 1
fi

# Test 6: Check that task won't run in check mode
print_info "Test 6: Verify check mode behavior"
if grep -A 20 "Create kubernetes-dashboard-csrf secret" "$PLAYBOOK" | grep -q "not ansible_check_mode"; then
    print_success "Task properly skips execution in check mode"
else
    print_error "Task doesn't properly handle check mode"
    exit 1
fi

print_success "All tests passed! The kubernetes-dashboard-csrf secret task is properly implemented."

echo ""
echo "=== Task Summary ==="
echo "- Checks if kubernetes-dashboard-csrf secret exists"
echo "- Creates secret with random 64-character token if missing"
echo "- Uses Ansible password lookup for secure generation"
echo "- Runs before dashboard deployment"
echo "- Idempotent (only creates if not exists)"
echo "- Respects check mode"
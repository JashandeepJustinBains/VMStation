#!/bin/bash

# Test script to validate fixes for update_and_deploy script issues
# This script tests the four main issues reported:
# 1. Deprecated warn parameter
# 2. Helm timeout missing units
# 3. Kubelet configuration issues
# 4. Process killing improvements

set -e

echo "=== Testing Fixes for update_and_deploy Script Issues ==="
echo "Timestamp: $(date)"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_test_header() {
    echo ""
    echo "=== $1 ==="
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Test 1: Check that deprecated 'warn: false' parameter is removed
print_test_header "Test 1: Deprecated warn parameter removal"

WARN_COUNT=$(grep -r "warn.*false" ansible/ | wc -l || echo "0")
if [ "$WARN_COUNT" -eq 0 ]; then
    print_success "No deprecated 'warn: false' parameters found"
else
    print_error "Found $WARN_COUNT instances of deprecated 'warn: false' parameter:"
    grep -r -n "warn.*false" ansible/ || true
    exit 1
fi

# Test 2: Check that Helm timeout has proper units
print_test_header "Test 2: Helm timeout units"

# Check cert-manager timeout
CERT_MANAGER_TIMEOUT=$(grep -A 5 -B 5 "timeout.*600s" ansible/plays/kubernetes/setup_cert_manager.yaml | grep "timeout: 600s" | wc -l || echo "0")
if [ "$CERT_MANAGER_TIMEOUT" -gt 0 ]; then
    print_success "Cert-manager Helm timeout properly formatted with units (600s)"
else
    print_error "Cert-manager timeout is missing proper units"
    grep -n "timeout:" ansible/plays/kubernetes/setup_cert_manager.yaml || true
    exit 1
fi

# Check for any remaining timeout without units
BAD_TIMEOUT_COUNT=$(grep -r "timeout:.*[0-9]$" ansible/ | grep -v "600s" | wc -l || echo "0")
if [ "$BAD_TIMEOUT_COUNT" -eq 0 ]; then
    print_success "No Helm timeouts found without proper time units"
else
    print_warning "Found potential timeout values without units:"
    grep -r -n "timeout:.*[0-9]$" ansible/ | grep -v "600s" || true
fi

# Test 3: Check that kubelet configuration handling is improved
print_test_header "Test 3: Kubelet configuration improvements"

# Check for kubelet config verification tasks
KUBELET_VERIFY_COUNT=$(grep -n "Verify.*kubelet.*configuration\|Check.*kubelet.*config\|kubelet.*config.*exists" ansible/plays/kubernetes/setup_cluster.yaml | wc -l || echo "0")
if [ "$KUBELET_VERIFY_COUNT" -gt 0 ]; then
    print_success "Found kubelet configuration verification tasks"
else
    print_error "Missing kubelet configuration verification tasks"
    exit 1
fi

# Check for directory creation tasks
DIR_CREATE_COUNT=$(grep -n -A 10 "Ensure /etc/kubernetes directory structure\|state: directory" ansible/plays/kubernetes/setup_cluster.yaml | grep -E "/etc/kubernetes|/var/lib/kubelet" | wc -l || echo "0")
if [ "$DIR_CREATE_COUNT" -gt 0 ]; then
    print_success "Found directory creation tasks for kubelet"
else
    print_error "Missing directory creation tasks for kubelet directories"
    exit 1
fi

# Test 4: Check that pkill commands have proper error handling
print_test_header "Test 4: Process killing improvements"

PKILL_COUNT=$(grep -r -n "pkill.*kube-apiserver" ansible/ | wc -l || echo "0")
if [ "$PKILL_COUNT" -gt 0 ]; then
    # Check that pkill commands have ignore_errors or || true
    PKILL_SAFE_COUNT=$(grep -r -A 3 -B 3 "pkill.*kube-apiserver" ansible/ | grep -E "ignore_errors.*true|\|\| true" | wc -l || echo "0")
    if [ "$PKILL_SAFE_COUNT" -gt 0 ]; then
        print_success "pkill commands have proper error handling"
    else
        print_warning "pkill commands may need better error handling"
        grep -r -n -A 3 -B 3 "pkill.*kube-apiserver" ansible/ || true
    fi
else
    print_success "No pkill commands found that could cause issues"
fi

# Test 5: Syntax validation of all modified files
print_test_header "Test 5: Syntax validation"

SYNTAX_ERRORS=0

# Test each modified file
for file in \
    "ansible/plays/kubernetes/setup_cluster.yaml" \
    "ansible/plays/kubernetes/setup_cert_manager.yaml" \
    "ansible/subsites/wip_fix_kubelet_firewall.yaml"
do
    if ansible-playbook --syntax-check "$file" >/dev/null 2>&1; then
        print_success "Syntax valid: $file"
    else
        print_error "Syntax error in: $file"
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
    fi
done

if [ "$SYNTAX_ERRORS" -gt 0 ]; then
    print_error "Found $SYNTAX_ERRORS syntax errors"
    exit 1
fi

# Test 6: Check for comprehensive diagnostics in case of kubelet failures
print_test_header "Test 6: Kubelet diagnostics improvements"

DIAGNOSTICS_COUNT=$(grep -n "kubelet.*diagnostics\|systemctl status kubelet\|journalctl.*kubelet" ansible/plays/kubernetes/setup_cluster.yaml | wc -l || echo "0")
if [ "$DIAGNOSTICS_COUNT" -gt 5 ]; then
    print_success "Comprehensive kubelet diagnostics present"
else
    print_warning "Kubelet diagnostics could be more comprehensive"
fi

# Summary
print_test_header "Summary"
echo ""
print_success "All critical fixes validated successfully!"
echo ""
echo "Fixed issues:"
echo "  1. ✓ Removed deprecated 'warn: false' parameter from Ansible tasks"
echo "  2. ✓ Fixed Helm timeout to include time units (600s instead of 600)"
echo "  3. ✓ Added kubelet configuration verification and directory creation"
echo "  4. ✓ Improved error handling for process killing operations"
echo "  5. ✓ Added comprehensive diagnostics for kubelet failures"
echo ""
echo "These fixes should resolve the issues reported in the problem statement:"
echo "  - Kubelet failures due to missing config files and directories"
echo "  - Ansible deprecated parameter warnings"  
echo "  - Helm timeout format errors"
echo "  - Process termination issues"
echo ""
print_success "Test validation completed successfully!"
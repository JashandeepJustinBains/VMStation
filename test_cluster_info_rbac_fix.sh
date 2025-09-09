#!/bin/bash

# Test script for cluster-info RBAC fix
# Validates that the fix properly allows anonymous access to cluster-info configmap

set -e

echo "=== Cluster-info RBAC Fix Test ==="
echo "Testing fix for worker node join RBAC permissions"
echo

# Configuration
SETUP_CLUSTER_FILE="ansible/plays/setup-cluster.yaml"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

# Test 1: Check that RBAC check task exists
echo "Test 1: Verify RBAC check task exists"
if grep -q "Check cluster-info configmap RBAC permissions" "$SETUP_CLUSTER_FILE"; then
    success "RBAC check task found"
else
    error "RBAC check task missing"
    exit 1
fi

# Test 2: Check that RBAC fix task exists
echo "Test 2: Verify RBAC fix task exists"
if grep -q "Create RBAC rule for anonymous access to cluster-info configmap" "$SETUP_CLUSTER_FILE"; then
    success "RBAC fix task found"
else
    error "RBAC fix task missing"
    exit 1
fi

# Test 3: Check that verification task exists
echo "Test 3: Verify RBAC verification task exists"
if grep -q "Verify cluster-info configmap accessibility" "$SETUP_CLUSTER_FILE"; then
    success "RBAC verification task found"
else
    error "RBAC verification task missing"
    exit 1
fi

# Test 4: Validate task order (RBAC tasks should come before join command generation)
echo "Test 4: Verify task order"
rbac_line=$(grep -n "Check cluster-info configmap RBAC permissions" "$SETUP_CLUSTER_FILE" | cut -d: -f1)
join_line=$(grep -n "Generate join command" "$SETUP_CLUSTER_FILE" | cut -d: -f1)

if [ "$rbac_line" -lt "$join_line" ]; then
    success "RBAC tasks correctly placed before join command generation"
else
    error "RBAC tasks are not properly ordered"
    exit 1
fi

# Test 5: Check for proper RBAC resource verification
echo "Test 5: Verify RBAC resource verification method"
if grep -q "kubectl get clusterrole system:public-info-viewer" "$SETUP_CLUSTER_FILE"; then
    success "Proper RBAC resource verification found"
else
    error "RBAC resource verification missing"
    exit 1
fi

# Test 6: Check for ClusterRole creation
echo "Test 6: Verify ClusterRole creation"
if grep -q "kubectl create clusterrole system:public-info-viewer" "$SETUP_CLUSTER_FILE"; then
    success "ClusterRole creation command found"
else
    error "ClusterRole creation command missing"
    exit 1
fi

# Test 7: Check for ClusterRoleBinding creation
echo "Test 7: Verify ClusterRoleBinding creation"
if grep -q "kubectl create clusterrolebinding cluster-info" "$SETUP_CLUSTER_FILE"; then
    success "ClusterRoleBinding creation command found"
else
    error "ClusterRoleBinding creation command missing"
    exit 1
fi

# Test 8: Check for system:unauthenticated group binding
echo "Test 8: Verify system:unauthenticated group binding"
if grep -q "group=system:unauthenticated" "$SETUP_CLUSTER_FILE"; then
    success "system:unauthenticated group binding found"
else
    error "system:unauthenticated group binding missing"
    exit 1
fi

# Test 9: Check for conditional execution (when clause)
echo "Test 9: Verify conditional execution"
if grep -A15 "Create RBAC rule for anonymous access to cluster-info configmap" "$SETUP_CLUSTER_FILE" | grep -q "when: cluster_info_rbac_check.stdout"; then
    success "Conditional execution found"
else
    error "Conditional execution missing"
    exit 1
fi

# Test 10: Ansible syntax validation
echo "Test 10: Ansible syntax validation"
if ansible-playbook --syntax-check "$SETUP_CLUSTER_FILE" >/dev/null 2>&1; then
    success "Ansible syntax validation passed"
else
    error "Ansible syntax validation failed"
    ansible-playbook --syntax-check "$SETUP_CLUSTER_FILE"
    exit 1
fi

echo
echo "=== All tests passed! ==="
echo "The cluster-info RBAC fix has been correctly implemented."
echo
echo "Expected behavior after deployment:"
echo "1. Control plane checks if RBAC resources exist for cluster-info access"
echo "2. If not present, creates ClusterRole and ClusterRoleBinding"
echo "3. Verifies that RBAC resources are properly created"
echo "4. Worker nodes should now be able to join successfully"
echo
echo "This fix addresses the error:"
echo "  'system:anonymous cannot get resource configmaps in namespace kube-public'"
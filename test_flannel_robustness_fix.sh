#!/bin/bash

# Test script for Flannel CNI robustness improvements
# Validates that Flannel installation includes proper validation steps

set -e

echo "=== Flannel CNI Robustness Fix Test ==="
echo "Testing improvements to Flannel CNI installation and validation"
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

# Test 1: Check that Flannel installation task exists
echo "Test 1: Verify Flannel CNI installation task"
if grep -q "Install Flannel CNI" "$SETUP_CLUSTER_FILE"; then
    success "Flannel installation task found"
else
    error "Flannel installation task missing"
    exit 1
fi

# Test 2: Check for DaemonSet validation
echo "Test 2: Verify Flannel DaemonSet validation"
if grep -q "Wait for Flannel DaemonSet to be created" "$SETUP_CLUSTER_FILE"; then
    success "Flannel DaemonSet validation found"
else
    error "Flannel DaemonSet validation missing"
    exit 1
fi

# Test 3: Check for Flannel status checking
echo "Test 3: Verify Flannel status checking"
if grep -q "Check Flannel namespace and resources" "$SETUP_CLUSTER_FILE"; then
    success "Flannel status checking found"
else
    error "Flannel status checking missing"
    exit 1
fi

# Test 4: Check for Flannel status display
echo "Test 4: Verify Flannel status display"
if grep -q "Display Flannel status" "$SETUP_CLUSTER_FILE"; then
    success "Flannel status display found"
else
    error "Flannel status display missing"
    exit 1
fi

# Test 5: Validate retry logic for Flannel installation
echo "Test 5: Verify Flannel installation retry logic"
if grep -A10 "Install Flannel CNI" "$SETUP_CLUSTER_FILE" | grep -q "retries: 3"; then
    success "Flannel installation retry logic found"
else
    error "Flannel installation retry logic missing"
    exit 1
fi

# Test 6: Validate DaemonSet check retry logic
echo "Test 6: Verify DaemonSet validation retry logic"
if grep -A10 "Wait for Flannel DaemonSet to be created" "$SETUP_CLUSTER_FILE" | grep -q "retries: 10"; then
    success "DaemonSet validation retry logic found"
else
    error "DaemonSet validation retry logic missing"
    exit 1
fi

# Test 7: Check for proper kubectl namespace usage
echo "Test 7: Verify kubectl namespace usage"
if grep -A5 "Check Flannel namespace and resources" "$SETUP_CLUSTER_FILE" | grep -q "kubectl get all -n kube-flannel"; then
    success "Proper kubectl namespace usage found"
else
    error "Proper kubectl namespace usage missing"
    exit 1
fi

# Test 8: Check for explanatory message about CrashLoopBackOff
echo "Test 8: Verify explanatory message about expected behavior"
if grep -A10 "Display Flannel status" "$SETUP_CLUSTER_FILE" | grep -q "CrashLoopBackOff until worker nodes join"; then
    success "Explanatory message about expected behavior found"
else
    error "Explanatory message about expected behavior missing"
    exit 1
fi

# Test 9: Validate task order (Flannel tasks should be properly sequenced)
echo "Test 9: Verify task sequencing"
install_line=$(grep -n "Install Flannel CNI" "$SETUP_CLUSTER_FILE" | cut -d: -f1)
daemonset_line=$(grep -n "Wait for Flannel DaemonSet to be created" "$SETUP_CLUSTER_FILE" | cut -d: -f1)
check_line=$(grep -n "Check Flannel namespace and resources" "$SETUP_CLUSTER_FILE" | cut -d: -f1)

if [ "$install_line" -lt "$daemonset_line" ] && [ "$daemonset_line" -lt "$check_line" ]; then
    success "Flannel tasks are properly sequenced"
else
    error "Flannel tasks are not properly sequenced"
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
echo "The Flannel CNI robustness improvements have been correctly implemented."
echo
echo "Expected behavior after deployment:"
echo "1. Flannel CNI is installed from the official GitHub release"
echo "2. DaemonSet creation is validated with retries"
echo "3. Flannel namespace and resources are checked"
echo "4. Status is displayed with explanatory notes"
echo "5. CrashLoopBackOff is expected until worker nodes join"
echo
echo "This improvement provides better visibility into Flannel deployment status"
echo "and sets proper expectations about expected behavior during deployment."
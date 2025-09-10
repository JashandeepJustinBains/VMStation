#!/bin/bash

# Simple validation script to confirm all fixes are in place
# No sudo required - just validates the code changes

echo "=== VMStation Worker Join Fix Validation ==="
echo "Timestamp: $(date)"
echo

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
fail() { echo -e "${RED}[✗]${NC} $1"; }

CHECKS_PASSED=0
TOTAL_CHECKS=6

echo "Validating fixes for the 'Join cluster with retry logic' hanging issue..."
echo

# Check 1: Control plane detection in remediation script
if grep -q "control plane node" worker_node_join_remediation.sh && 
   grep -q "/etc/kubernetes/admin.conf" worker_node_join_remediation.sh; then
    success "Remediation script detects control plane nodes"
    ((CHECKS_PASSED++))
else
    fail "Remediation script missing control plane detection"
fi

# Check 2: Worker node safety in Ansible
if grep -q "Verify this is not a control plane node" ansible/plays/setup-cluster.yaml; then
    success "Ansible playbook has control plane safety checks"
    ((CHECKS_PASSED++))
else
    fail "Ansible playbook missing control plane safety checks"
fi

# Check 3: Async execution to prevent hanging
if grep -A 15 "Join cluster with retry logic" ansible/plays/setup-cluster.yaml | grep -q "async:" &&
   grep -A 15 "Join cluster with retry logic" ansible/plays/setup-cluster.yaml | grep -q "poll:"; then
    success "Join task uses async execution to prevent hanging"
    ((CHECKS_PASSED++))
else
    fail "Join task missing async configuration"
fi

# Check 4: Timeout protection
if grep -A 15 "Join cluster with retry logic" ansible/plays/setup-cluster.yaml | grep -q "timeout 300"; then
    success "Join task has timeout protection (5 minutes)"
    ((CHECKS_PASSED++))
else
    fail "Join task missing timeout protection"
fi

# Check 5: Control plane health checks
if grep -q "control plane health" ansible/plays/setup-cluster.yaml; then
    success "Control plane health verification implemented"
    ((CHECKS_PASSED++))
else
    fail "Control plane health verification missing"
fi

# Check 6: Disruption recovery
if grep -q "control_plane_disrupted" ansible/plays/setup-cluster.yaml; then
    success "Control plane disruption recovery logic added"
    ((CHECKS_PASSED++))
else
    fail "Control plane disruption recovery missing"
fi

echo
echo "=== Validation Results ==="
echo "Checks passed: $CHECKS_PASSED/$TOTAL_CHECKS"

if [ $CHECKS_PASSED -eq $TOTAL_CHECKS ]; then
    success "All fixes validated successfully!"
    echo
    info "The worker node join hanging issue should now be resolved."
    echo 
    echo "What was fixed:"
    echo "• Control plane detection prevents incorrect remediation"
    echo "• Async execution prevents indefinite hanging (5min timeout)"  
    echo "• Health checks ensure control plane readiness"
    echo "• Recovery logic handles disrupted states"
    echo "• Better error messages guide troubleshooting"
    echo
    info "Ready to deploy:"
    echo "  ./deploy.sh full"
    echo
else
    fail "Some fixes are missing - deployment may still have issues"
    exit 1
fi
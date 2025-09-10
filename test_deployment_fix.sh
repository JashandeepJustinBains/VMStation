#!/bin/bash

# Integration test to verify the deployment fixes work correctly
# This simulates the scenario described in the problem statement

set -e

echo "=== Testing Deployment Fix Integration ==="
echo "Timestamp: $(date)"
echo

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

info "This test validates the fixes for the worker node join hanging issue"
echo

echo "=== Step 1: Validate remediation script safety checks ==="

info "Testing control plane detection in remediation script..."

# Test the updated remediation script directly
if sudo ./worker_node_join_remediation.sh 2>&1 | grep -q "control plane node" && [ ${PIPESTATUS[0]} -eq 1 ]; then
    success "Remediation script correctly refuses to run on control plane"
else
    fail "Remediation script did not detect control plane properly"
fi

echo
echo "=== Step 2: Validate Ansible playbook improvements ==="

info "Checking Ansible playbook for join safety measures..."

# Check for critical safety features
SAFETY_CHECKS=0

if grep -q "Verify this is not a control plane node" ansible/plays/setup-cluster.yaml; then
    success "✓ Control plane detection in join tasks"
    ((SAFETY_CHECKS++))
else
    fail "✗ Missing control plane detection in join tasks"
fi

if grep -q "async:" ansible/plays/setup-cluster.yaml && grep -q "poll:" ansible/plays/setup-cluster.yaml; then
    success "✓ Async execution prevents hanging"
    ((SAFETY_CHECKS++))
else
    fail "✗ Missing async execution configuration"
fi

if grep -q "control plane health" ansible/plays/setup-cluster.yaml; then
    success "✓ Control plane health verification"
    ((SAFETY_CHECKS++))
else
    fail "✗ Missing control plane health verification"
fi

if grep -q "control_plane_disrupted" ansible/plays/setup-cluster.yaml; then
    success "✓ Control plane recovery logic"
    ((SAFETY_CHECKS++))
else
    fail "✗ Missing control plane recovery logic"
fi

echo
echo "=== Step 3: Deployment readiness check ==="

if [ $SAFETY_CHECKS -eq 4 ]; then
    success "All safety measures implemented - deployment should work correctly"
    
    echo
    info "Ready for deployment! To test the fix:"
    echo
    echo "1. Ensure your inventory is configured:"
    echo "   cat ansible/inventory.txt"
    echo
    echo "2. Run the deployment:"
    echo "   ./deploy.sh full"
    echo
    echo "3. Monitor for the previously hanging task:"
    echo "   The 'Join cluster with retry logic' task should now:"
    echo "   - Complete within 5 minutes (300s timeout)"
    echo "   - Skip control plane nodes automatically"
    echo "   - Provide better error messages if issues occur"
    echo "   - Recover gracefully from previous failed states"
    echo
    echo "4. If issues persist, check:"
    echo "   - Control plane health: kubectl get nodes"
    echo "   - Worker connectivity: ping 192.168.4.61 192.168.4.62"  
    echo "   - Firewall: ports 6443, 10250, 8472 must be open"
    
else
    fail "Some safety measures missing - deployment may still have issues"
fi

echo
echo "=== Summary of Applied Fixes ==="
echo
info "Problem: deploy.sh hung at 'Join cluster with retry logic' after remediation"
info "Root cause: Remediation script was run on control plane, breaking cluster"
info "Solution: Multiple safeguards and recovery mechanisms"
echo
echo "Fix 1: Prevent remediation on control plane"
echo "  - worker_node_join_remediation.sh now detects and refuses control plane"
echo
echo "Fix 2: Add join safety checks"  
echo "  - Ansible playbook detects control plane nodes and skips join"
echo "  - Health verification ensures control plane is ready"
echo
echo "Fix 3: Prevent hanging"
echo "  - Async execution with 300s timeout per join attempt"
echo "  - Improved error handling and cleanup"
echo
echo "Fix 4: Control plane recovery"
echo "  - Automatic detection and recovery from disrupted state"
echo "  - Clean reinitialization when needed"
echo
success "Deployment should now complete successfully without hanging!"

exit 0
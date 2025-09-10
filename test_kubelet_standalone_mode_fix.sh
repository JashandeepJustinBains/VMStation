#!/bin/bash

# Test Kubelet Standalone Mode Fix
# Validates enhancements to fix_kubelet_cluster_connection.sh for the specific issue pattern

set -e

echo "=== Kubelet Standalone Mode Fix Test ==="
echo "Testing enhanced diagnostics for missing kubelet.conf and standalone mode issues"
echo "Timestamp: $(date)"
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

success() { echo -e "${GREEN}✓ $1${NC}"; }
error() { echo -e "${RED}✗ $1${NC}"; }
info() { echo -e "${BLUE}ℹ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Test script file
SCRIPT_FILE="scripts/fix_kubelet_cluster_connection.sh"

# Test 1: Verify enhanced kubelet mode checking
info "Test 1: Check enhanced kubelet mode detection"
if grep -q "Kubelet is running in standalone mode" "$SCRIPT_FILE" && \
   grep -q "will skip API server sync" "$SCRIPT_FILE" && \
   grep -q "No API server defined - no node status update" "$SCRIPT_FILE" && \
   grep -q "Kubernetes client is nil" "$SCRIPT_FILE"; then
    success "Enhanced kubelet mode detection with specific log patterns from problem statement"
else
    error "Missing enhanced kubelet mode detection patterns"
    exit 1
fi

# Test 2: Check for missing kubelet.conf diagnostics
info "Test 2: Check missing kubelet.conf diagnostic function"
if grep -q "diagnose_missing_kubelet_conf" "$SCRIPT_FILE"; then
    success "Missing kubelet.conf diagnostic function exists"
    
    # Check for key diagnostic elements
    if grep -A20 "diagnose_missing_kubelet_conf" "$SCRIPT_FILE" | grep -q "kubelet.conf is missing"; then
        success "Proper error message for missing kubelet.conf"
    else
        error "Missing error message for kubelet.conf"
        exit 1
    fi
    
    if grep -A40 "diagnose_missing_kubelet_conf" "$SCRIPT_FILE" | grep -q "bootstrap-kubelet.conf"; then
        success "Checks for partial join artifacts (bootstrap-kubelet.conf)"
    else
        error "Missing check for partial join artifacts"
        exit 1
    fi
    
else
    error "Missing kubelet.conf diagnostic function not found"
    exit 1
fi

# Test 3: Check remediation guidance function
info "Test 3: Check remediation guidance function"
if grep -q "suggest_kubelet_conf_remediation" "$SCRIPT_FILE"; then
    success "Remediation guidance function exists"
    
    # Check for key remediation steps
    if grep -A30 "suggest_kubelet_conf_remediation" "$SCRIPT_FILE" | grep -q "kubeadm token create --print-join-command"; then
        success "Includes step to generate new join command"
    else
        error "Missing join command generation step"
        exit 1
    fi
    
    if grep -A30 "suggest_kubelet_conf_remediation" "$SCRIPT_FILE" | grep -q "kubeadm reset --force"; then
        success "Includes node reset step"
    else
        error "Missing node reset step"
        exit 1
    fi
    
    if grep -A30 "suggest_kubelet_conf_remediation" "$SCRIPT_FILE" | grep -q "ansible-playbook.*setup-cluster.yaml"; then
        success "Includes automated cluster setup alternative"
    else
        error "Missing automated setup alternative"
        exit 1
    fi
    
else
    error "Remediation guidance function not found"
    exit 1
fi

# Test 4: Check integration in main execution flow
info "Test 4: Check integration of new diagnostics in main flow"
if grep -A10 -B10 "diagnose_missing_kubelet_conf" "$SCRIPT_FILE" | grep -q "suggest_kubelet_conf_remediation"; then
    success "Missing kubelet.conf diagnostic properly integrated with remediation"
else
    error "Diagnostics not properly integrated"
    exit 1
fi

# Test 5: Verify enhanced log pattern detection
info "Test 5: Verify comprehensive log pattern detection"
patterns=(
    "Kubelet is running in standalone mode"
    "will skip API server sync"
    "No API server defined - no node status update"
    "Kubernetes client is nil"
    "Successfully registered node"
    "Node ready"
)

missing_patterns=0
for pattern in "${patterns[@]}"; do
    if ! grep -q "$pattern" "$SCRIPT_FILE"; then
        warn "Missing log pattern: $pattern"
        ((missing_patterns++))
    fi
done

if [ $missing_patterns -eq 0 ]; then
    success "All expected log patterns are detected"
else
    error "$missing_patterns log patterns missing"
    exit 1
fi

# Test 6: Check error counting and reporting
info "Test 6: Check standalone indicator counting"
if grep -A30 "check_kubelet_mode" "$SCRIPT_FILE" | grep -q "standalone_indicators" && \
   grep -A30 "check_kubelet_mode" "$SCRIPT_FILE" | grep -q "standalone_indicators.*0"; then
    success "Proper counting and reporting of standalone indicators"
else
    error "Missing standalone indicator counting"
    exit 1
fi

# Test 7: Verify script syntax is valid
info "Test 7: Verify script syntax"
if bash -n "$SCRIPT_FILE"; then
    success "Script syntax is valid"
else
    error "Script has syntax errors"
    exit 1
fi

echo ""
success "All tests passed! Enhanced kubelet standalone mode fix is ready."
echo ""
info "Summary of enhancements:"
echo "✓ Enhanced log pattern detection for specific standalone mode issues"
echo "✓ Comprehensive missing kubelet.conf diagnostics"
echo "✓ Step-by-step remediation guidance"
echo "✓ Proper integration with existing fix workflow"
echo "✓ Detection of partial join failures and bootstrap artifacts"
echo ""
info "This fix addresses the exact issue patterns reported in the problem statement:"
echo "- Missing /etc/kubernetes/kubelet.conf"
echo "- 'Kubelet is running in standalone mode' log messages"
echo "- 'will skip API server sync' and 'No API server defined' messages"
echo "- 'Kubernetes client is nil' messages"
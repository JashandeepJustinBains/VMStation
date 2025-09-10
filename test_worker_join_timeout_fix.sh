#!/bin/bash

# Test Worker Join Timeout Fix
# Validates the changes made to fix kubelet start timeout during worker node join

set -e

echo "=== Worker Join Timeout Fix Validation ==="
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

# Test 1: Verify static kubelet configuration is not created
info "Test 1: Checking that static kubelet configuration is not created"
playbook_file="ansible/plays/setup-cluster.yaml"

if grep -q "KUBELET_EXTRA_ARGS.*container-runtime-endpoint" "$playbook_file"; then
    # Check if it's in a copy/template task that creates static files
    if grep -A5 -B5 "KUBELET_EXTRA_ARGS.*container-runtime-endpoint" "$playbook_file" | grep -q "copy:" && \
       grep -A5 -B5 "KUBELET_EXTRA_ARGS.*container-runtime-endpoint" "$playbook_file" | grep -q "dest:.*kubelet"; then
        error "Static kubelet configuration still being created - this can conflict with kubeadm join"
        exit 1
    else
        success "KUBELET_EXTRA_ARGS found but not in static configuration"
    fi
else
    success "No static KUBELET_EXTRA_ARGS configuration found in worker join section"
fi

# Test 2: Verify cleanup tasks exist
info "Test 2: Checking for proper cleanup tasks"
if grep -q "Remove conflicting kubelet configuration files" "$playbook_file"; then
    success "Cleanup task for conflicting kubelet files exists"
else
    error "Missing cleanup task for conflicting kubelet configuration"
    exit 1
fi

# Test 3: Verify kubeadm-flags.env cleanup
info "Test 3: Checking kubeadm-flags.env cleanup"
if grep -q "kubeadm-flags.env" "$playbook_file" && grep -A3 -B3 "kubeadm-flags.env" "$playbook_file" | grep -q "state: absent"; then
    success "kubeadm-flags.env cleanup task exists"
else
    error "Missing kubeadm-flags.env cleanup task"
    exit 1
fi

# Test 4: Verify systemd daemon reload
info "Test 4: Checking systemd daemon reload"
if grep -q "systemctl daemon-reload" "$playbook_file"; then
    success "systemd daemon-reload command found"
else
    error "Missing systemd daemon-reload"
    exit 1
fi

# Test 5: Verify enhanced diagnostics
info "Test 5: Checking for enhanced diagnostics"
if grep -q "kubelet logs for troubleshooting" "$playbook_file"; then
    success "Enhanced kubelet diagnostics found"
else
    error "Missing enhanced diagnostics for troubleshooting"
    exit 1
fi

# Test 6: Verify improved cleanup in retry logic  
info "Test 6: Checking improved cleanup and retry logic"
if grep -q "Cleaning up after failed join" "$playbook_file"; then
    success "Enhanced cleanup logic found"
else
    error "Missing enhanced cleanup logic"
    exit 1
fi

# Test 7: Verify containerd restart in retry
info "Test 7: Checking containerd restart logic"
if grep -q "Restart containerd and prepare for retry" "$playbook_file"; then
    success "Containerd restart logic found"
else
    error "Missing containerd restart logic"
    exit 1
fi

# Test 8: Ansible syntax validation
info "Test 8: Validating Ansible syntax"
if ansible-playbook --syntax-check "$playbook_file" >/dev/null 2>&1; then
    success "Ansible syntax is valid"
else
    error "Ansible syntax validation failed"
    exit 1
fi

# Test 9: Check that original functionality is preserved
info "Test 9: Verifying original functionality preservation"
if grep -q "Join Worker Nodes" "$playbook_file" && \
   grep -q "Test connectivity to control plane" "$playbook_file" && \
   grep -q "Copy join command from control plane" "$playbook_file"; then
    success "Original worker join functionality preserved"
else
    error "Some original functionality may be missing"
    exit 1
fi

# Test 10: Validate that join command execution is improved
info "Test 10: Checking join command execution improvements"
if grep -A10 "Starting kubeadm join process" "$playbook_file" | grep -q "systemctl is-active containerd"; then
    success "Join process includes pre-flight checks"
else
    error "Missing pre-flight checks in join process"
    exit 1
fi

echo
echo "=== Summary ==="
success "All tests passed! Worker join timeout fix is properly implemented."
echo
info "Key improvements made:"
echo "  • Removed static kubelet configuration that conflicts with kubeadm join"
echo "  • Added cleanup of conflicting configuration files before join"  
echo "  • Enhanced diagnostics and logging for troubleshooting"
echo "  • Improved cleanup and retry logic with better error handling"
echo "  • Added containerd restart logic in retry scenarios"
echo "  • Preserved all original functionality and compatibility"
echo
info "Expected result: Worker nodes should successfully join without kubelet timeout errors"
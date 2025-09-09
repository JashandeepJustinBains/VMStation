#!/bin/bash

# Test script to validate download tools validation fix
# Ensures proper validation is in place for curl/wget availability

set -e

echo "=== Testing Download Tools Validation Fix ===" 
echo "Timestamp: $(date)"
echo ""

info() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1"  
}

SETUP_CLUSTER_FILE="ansible/plays/kubernetes/setup_cluster.yaml"

if [ ! -f "$SETUP_CLUSTER_FILE" ]; then
    error "setup_cluster.yaml not found"
    exit 1
fi

echo "=== Test 1: Ansible Syntax Validation ==="

# Validate Ansible syntax is still correct
if ansible-playbook --syntax-check "$SETUP_CLUSTER_FILE" >/dev/null 2>&1; then
    info "✓ Ansible syntax is valid"
else
    error "✗ Ansible syntax error introduced"
    exit 1
fi

echo ""

echo "=== Test 2: Download Tools Validation Block ==="

# Check that validation block exists
if grep -q "Validate download tools are available after installation" "$SETUP_CLUSTER_FILE"; then
    info "✓ Download tools validation block found"
else
    error "✗ Download tools validation block missing"
    exit 1
fi

# Check for curl availability check
if grep -A 10 "Validate download tools are available" "$SETUP_CLUSTER_FILE" | grep -q "which curl"; then
    info "✓ Curl availability check implemented"
else
    error "✗ Curl availability check missing"
    exit 1
fi

# Check for wget availability check  
if grep -A 10 "Validate download tools are available" "$SETUP_CLUSTER_FILE" | grep -q "which wget"; then
    info "✓ Wget availability check implemented"
else
    error "✗ Wget availability check missing"
    exit 1
fi

echo ""

echo "=== Test 3: Proper Error Handling ==="

# Check for failure condition when no tools available
if grep -A 25 "Fail if no download tools are available" "$SETUP_CLUSTER_FILE" | grep -q "when: curl_check.rc != 0 and wget_check.rc != 0"; then
    info "✓ Proper failure condition for missing tools"
else
    error "✗ Missing failure condition for when no tools available"
    exit 1
fi

# Check for helpful error message
if grep -A 15 "No download tools.*are available" "$SETUP_CLUSTER_FILE" | grep -q "Manual resolution required"; then
    info "✓ Helpful error message with manual resolution steps"
else
    error "✗ Missing helpful error message"
    exit 1
fi

echo ""

echo "=== Test 4: OS-Specific Instructions ==="

# Check for OS-specific installation instructions
if grep -A 20 "Manual resolution required" "$SETUP_CLUSTER_FILE" | grep -q "ansible_os_family == 'RedHat'"; then
    info "✓ OS-specific installation instructions included"
else
    error "✗ OS-specific installation instructions missing"
    exit 1
fi

echo ""

echo "=== Test 5: Existing Functionality Preserved ==="

# Ensure original download tools installation is still there
if grep -q "Ensure download tools are available for Flannel installation" "$SETUP_CLUSTER_FILE"; then
    info "✓ Original download tools installation task preserved"
else
    error "✗ Original download tools installation task removed"
    exit 1
fi

# Ensure ignore_errors is still present (maintains backward compatibility)
if grep -A 8 "Ensure download tools are available for Flannel installation" "$SETUP_CLUSTER_FILE" | grep -q "ignore_errors: yes"; then
    info "✓ Original ignore_errors behavior preserved"
else
    error "✗ Original ignore_errors behavior changed"
    exit 1
fi

echo ""

echo "=== Test Summary ==="
info "Download tools validation fix validation:"
info "  ✓ Ansible syntax remains valid"
info "  ✓ Download tools validation block implemented"
info "  ✓ Proper error handling for missing tools"  
info "  ✓ Helpful error messages with manual resolution"
info "  ✓ OS-specific installation instructions"
info "  ✓ Existing functionality preserved"
echo ""

info "Fix should prevent worker nodes from failing silently when download tools are unavailable"
info "Provides clear feedback and resolution steps when tools are missing"
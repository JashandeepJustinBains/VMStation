#!/bin/bash

# Test script to validate Flannel CNI download permission improvements
# Ensures CNI directory cleanup and recreation has proper permission handling

set -e

echo "=== Testing Flannel CNI Download Permission Fix ==="
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

echo "=== Test 1: Enhanced CNI Cleanup with Directory Preservation ==="

# Check that CNI cleanup preserves directory structure
if grep -q "Clear existing CNI configuration files (preserve directory structure)" "$SETUP_CLUSTER_FILE"; then
    info "✓ Enhanced CNI cleanup task found"
else
    error "✗ Enhanced CNI cleanup task missing"
    exit 1
fi

# Check that cleanup includes directory recreation with proper permissions
if grep -A 15 "Clear existing CNI configuration files (preserve directory structure)" "$SETUP_CLUSTER_FILE" | grep -q "mkdir -p" && \
   grep -A 15 "Clear existing CNI configuration files (preserve directory structure)" "$SETUP_CLUSTER_FILE" | grep -q "chmod 755" && \
   grep -A 15 "Clear existing CNI configuration files (preserve directory structure)" "$SETUP_CLUSTER_FILE" | grep -q "chown root:root"; then
    info "✓ Directory recreation with permissions in cleanup"
else
    error "✗ Directory recreation with permissions missing from cleanup"
    exit 1
fi

echo ""

echo "=== Test 2: CNI Directory Permission Validation ==="

# Check for CNI directory permission validation
if grep -q "Validate CNI directory permissions before download" "$SETUP_CLUSTER_FILE"; then
    info "✓ CNI directory permission validation found"
else
    error "✗ CNI directory permission validation missing"
    exit 1
fi

# Check that validation includes writability test
if grep -A 20 "Validate CNI directory permissions before download" "$SETUP_CLUSTER_FILE" | grep -q "! -w"; then
    info "✓ Directory writability validation included"
else
    error "✗ Directory writability validation missing"
    exit 1
fi

echo ""

echo "=== Test 3: Pre-download Target Directory Validation ==="

# Check for pre-download validation
if grep -q "Pre-download validation for Flannel CNI binary" "$SETUP_CLUSTER_FILE"; then
    info "✓ Pre-download validation task found"
else
    error "✗ Pre-download validation task missing"
    exit 1
fi

# Check that pre-download validation includes write test
if grep -A 25 "Pre-download validation for Flannel CNI binary" "$SETUP_CLUSTER_FILE" | grep -q "write_test"; then
    info "✓ Write test included in pre-download validation"
else
    error "✗ Write test missing from pre-download validation"
    exit 1
fi

echo ""

echo "=== Test 4: Enhanced Error Diagnostics ==="

# Check for enhanced directory permission diagnostics
if grep -q "Check directory permissions and disk space" "$SETUP_CLUSTER_FILE"; then
    info "✓ Enhanced directory permission diagnostics found"
else
    error "✗ Enhanced directory permission diagnostics missing"
    exit 1
fi

# Check that diagnostics include disk space and write test
if grep -A 15 "Check directory permissions and disk space" "$SETUP_CLUSTER_FILE" | grep -q "df -h" && \
   grep -A 15 "Check directory permissions and disk space" "$SETUP_CLUSTER_FILE" | grep -q "Write Test"; then
    info "✓ Disk space and write test included in diagnostics"
else
    error "✗ Disk space and write test missing from diagnostics"
    exit 1
fi

echo ""

echo "=== Test 5: Improved Error Messages ==="

# Check that error messages include permission troubleshooting
if grep -A 20 "Fail if Flannel binary still missing" "$SETUP_CLUSTER_FILE" | grep -q "Directory permissions issues"; then
    info "✓ Permission troubleshooting included in error messages"
else
    error "✗ Permission troubleshooting missing from error messages"
    exit 1
fi

# Check for common causes section
if grep -A 20 "Fail if Flannel binary still missing" "$SETUP_CLUSTER_FILE" | grep -q "Common causes:"; then
    info "✓ Common causes section found in error messages"
else
    error "✗ Common causes section missing from error messages"
    exit 1
fi

echo ""

echo "=== Test Summary ==="
info "Flannel CNI download permission fix validation:"
info "  ✓ Enhanced CNI cleanup preserves directory structure"
info "  ✓ CNI directory permission validation before downloads"
info "  ✓ Pre-download target directory validation with write test"
info "  ✓ Enhanced error diagnostics for permission issues"
info "  ✓ Improved error messages with troubleshooting steps"
echo ""

info "Permission fix validation PASSED - Flannel download permission issues should be resolved"
echo ""
info "The fixes should resolve:"
info "  - CNI directory deletion causing permission issues"
info "  - Insufficient permissions for Flannel binary downloads"
info "  - Missing or corrupted directory structure after cleanup"
info "  - Improved debugging of permission-related failures"
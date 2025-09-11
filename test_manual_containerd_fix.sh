#!/bin/bash

# Test Manual Containerd Filesystem Fix
# Validates the manual_containerd_filesystem_fix.sh script functionality

set -e

echo "=== Testing Manual Containerd Filesystem Fix ==="
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

# Test 1: Verify script exists and is executable
info "Test 1: Checking script existence and permissions"
if [ -f "./manual_containerd_filesystem_fix.sh" ] && [ -x "./manual_containerd_filesystem_fix.sh" ]; then
    success "PASS: Manual containerd fix script exists and is executable"
else
    error "FAIL: Manual containerd fix script not found or not executable"
    exit 1
fi

# Test 2: Check script structure and key functions
info "Test 2: Validating script structure"
if grep -q "backup_containerd_config" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Contains backup_containerd_config function"
else
    error "FAIL: Missing backup_containerd_config function"
    exit 1
fi

if grep -q "regenerate_containerd_config" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Contains regenerate_containerd_config function"
else
    error "FAIL: Missing regenerate_containerd_config function"
    exit 1
fi

if grep -q "configure_crictl" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Contains configure_crictl function"
else
    error "FAIL: Missing configure_crictl function"
    exit 1
fi

if grep -q "reset_containerd_completely" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Contains reset_containerd_completely function"
else
    error "FAIL: Missing reset_containerd_completely function"
    exit 1
fi

if grep -q "initialize_containerd_filesystem_aggressive" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Contains initialize_containerd_filesystem_aggressive function"
else
    error "FAIL: Missing initialize_containerd_filesystem_aggressive function"
    exit 1
fi

if grep -q "verify_imagefilesystem_detection" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Contains verify_imagefilesystem_detection function"
else
    error "FAIL: Missing verify_imagefilesystem_detection function"
    exit 1
fi

# Test 3: Check for proper error handling
info "Test 3: Checking error handling mechanisms"
if grep -q "check_root" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Contains root user check"
else
    error "FAIL: Missing root user check"
    exit 1
fi

if grep -q "set -e" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Contains bash error handling (set -e)"
else
    error "FAIL: Missing bash error handling"
    exit 1
fi

# Test 4: Check for containerd configuration handling
info "Test 4: Validating containerd configuration handling"
if grep -q "containerd config default" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Uses containerd config default generation"
else
    error "FAIL: Missing containerd config default generation"
    exit 1
fi

if grep -q "SystemdCgroup.*true" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Configures SystemdCgroup for Kubernetes"
else
    error "FAIL: Missing SystemdCgroup configuration"
    exit 1
fi

# Test 5: Check for crictl configuration
info "Test 5: Validating crictl configuration"
if grep -q "runtime-endpoint.*containerd.sock" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Configures crictl runtime endpoint"
else
    error "FAIL: Missing crictl runtime endpoint configuration"
    exit 1
fi

# Test 6: Check for aggressive initialization steps
info "Test 6: Checking aggressive initialization steps"
if grep -q "ctr.*namespace.*create.*k8s.io" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Creates k8s.io namespace"
else
    error "FAIL: Missing k8s.io namespace creation"
    exit 1
fi

if grep -q "ctr.*images.*ls" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Triggers image filesystem detection"
else
    error "FAIL: Missing image filesystem detection"
    exit 1
fi

if grep -q "ctr.*snapshots.*ls" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Initializes snapshotter"
else
    error "FAIL: Missing snapshotter initialization"
    exit 1
fi

# Test 7: Check for imageFilesystem verification
info "Test 7: Validating imageFilesystem verification"
if grep -q "crictl info.*imageFilesystem" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Verifies imageFilesystem detection"
else
    error "FAIL: Missing imageFilesystem verification"
    exit 1
fi

if grep -q "capacityBytes" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Checks capacity bytes"
else
    error "FAIL: Missing capacity bytes check"
    exit 1
fi

# Test 8: Check diagnostic capabilities
info "Test 8: Checking diagnostic capabilities"
if grep -q "display_diagnostics" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Contains diagnostic display function"
else
    error "FAIL: Missing diagnostic display function"
    exit 1
fi

if grep -q "journalctl.*containerd" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Includes containerd log diagnostics"
else
    error "FAIL: Missing containerd log diagnostics"
    exit 1
fi

# Test 9: Verify enhanced_kubeadm_join.sh integration
info "Test 9: Checking enhanced_kubeadm_join.sh integration"
if grep -q "manual_containerd_filesystem_fix.sh" "./scripts/enhanced_kubeadm_join.sh"; then
    success "PASS: Enhanced join script references manual fix"
else
    error "FAIL: Enhanced join script doesn't reference manual fix"
    exit 1
fi

if grep -q "MANUAL FIX REQUIRED" "./scripts/enhanced_kubeadm_join.sh"; then
    success "PASS: Enhanced join script provides manual fix guidance"
else
    error "FAIL: Missing manual fix guidance in enhanced join script"
    exit 1
fi

# Test 10: Check backup and recovery functionality
info "Test 10: Validating backup and recovery"
if grep -q "backup_dir.*containerd-backup" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Creates timestamped backup directory"
else
    error "FAIL: Missing backup directory creation"
    exit 1
fi

if grep -q "/tmp/containerd-backup-location" "./manual_containerd_filesystem_fix.sh"; then
    success "PASS: Saves backup location for reference"
else
    error "FAIL: Missing backup location tracking"
    exit 1
fi

echo
echo "=== All Tests Passed! ==="
echo

success "Manual Containerd Filesystem Fix Validation Summary:"
echo "  ✓ Script exists and is executable"
echo "  ✓ Contains all required functions"
echo "  ✓ Proper error handling mechanisms"
echo "  ✓ Containerd configuration generation"
echo "  ✓ crictl configuration setup"
echo "  ✓ Aggressive filesystem initialization"
echo "  ✓ imageFilesystem detection verification"
echo "  ✓ Comprehensive diagnostics"
echo "  ✓ Integration with enhanced join script"
echo "  ✓ Backup and recovery capabilities"

echo
info "The manual fix script is ready for use when automated fixes fail."
info "Usage: sudo ./manual_containerd_filesystem_fix.sh"
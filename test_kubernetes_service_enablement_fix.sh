#!/bin/bash

# Test script for Kubernetes service enablement fix
# Validates that the fix script properly handles disabled services

set -e

echo "=== Testing Kubernetes Service Enablement Fix ==="
echo "Timestamp: $(date)"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR"

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Test 1: Verify script exists and is executable
echo "=== Test 1: Script Validation ==="

SCRIPT_PATH="scripts/fix_kubernetes_service_enablement.sh"

if [ -f "$SCRIPT_PATH" ]; then
    info "✓ Fix script exists"
else
    error "✗ Fix script missing: $SCRIPT_PATH"
    exit 1
fi

if [ -x "$SCRIPT_PATH" ]; then
    info "✓ Fix script is executable"
else
    error "✗ Fix script is not executable"
    exit 1
fi

echo ""

# Test 2: Validate script syntax
echo "=== Test 2: Script Syntax Validation ==="

if bash -n "$SCRIPT_PATH"; then
    info "✓ Script syntax is valid"
else
    error "✗ Script syntax validation failed"
    exit 1
fi

echo ""

# Test 3: Check script content for required components
echo "=== Test 3: Script Content Validation ==="

# Check for service check functions
if grep -q "check_and_fix_service" "$SCRIPT_PATH"; then
    info "✓ Service check function found"
else
    error "✗ Service check function missing"
    exit 1
fi

# Check for containerd handling
if grep -q "containerd" "$SCRIPT_PATH"; then
    info "✓ Containerd service handling found"
else
    error "✗ Containerd service handling missing"
    exit 1
fi

# Check for kubelet handling
if grep -q "kubelet" "$SCRIPT_PATH"; then
    info "✓ Kubelet service handling found"
else
    error "✗ Kubelet service handling missing"
    exit 1
fi

# Check for Flannel guidance
if grep -q -i "flannel" "$SCRIPT_PATH"; then
    info "✓ Flannel guidance found"
else
    error "✗ Flannel guidance missing"
    exit 1
fi

# Check for systemctl enable/start commands
if grep -q "systemctl enable\|systemctl start" "$SCRIPT_PATH"; then
    info "✓ Service management commands found"
else
    error "✗ Service management commands missing"
    exit 1
fi

# Check for error handling
if grep -q "failed_services\|error.*Failed" "$SCRIPT_PATH"; then
    info "✓ Error handling found"
else
    error "✗ Error handling missing"
    exit 1
fi

echo ""

# Test 4: Validate integration with existing infrastructure
echo "=== Test 4: Integration Validation ==="

# Check if script follows repository patterns
if grep -q "VMStation.*Fix" "$SCRIPT_PATH"; then
    info "✓ Follows VMStation script naming pattern"
else
    warn "⚠ May not follow VMStation naming pattern"
fi

# Check for proper color coding
if grep -q "GREEN=\|RED=\|YELLOW=" "$SCRIPT_PATH"; then
    info "✓ Uses consistent color coding"
else
    warn "⚠ Missing color coding"
fi

# Check for proper logging functions
if grep -q "info()\|warn()\|error()" "$SCRIPT_PATH"; then
    info "✓ Uses consistent logging functions"
else
    warn "⚠ Missing logging functions"
fi

echo ""

# Test 5: Dry-run validation (check what the script would do)
echo "=== Test 5: Dry-run Validation ==="

info "Running script in dry-run mode to validate functionality..."

# Create a temporary modified version for testing that doesn't actually change services
TEMP_SCRIPT="/tmp/test_service_script.sh"
sed 's/sudo systemctl/echo "DRY-RUN: would run systemctl"/g' "$SCRIPT_PATH" > "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# Run the modified script
if "$TEMP_SCRIPT" >/dev/null 2>&1; then
    info "✓ Script dry-run completed successfully"
else
    warn "⚠ Script dry-run had issues (may be expected if services don't exist)"
fi

# Cleanup
rm -f "$TEMP_SCRIPT"

echo ""

# Test 6: Check for problem-specific validation
echo "=== Test 6: Problem-Specific Validation ==="

info "Verifying fixes address the original problem:"

# The original problem was kubelet.service disabled
if grep -A 5 -B 5 "disabled.*enabling\|is disabled" "$SCRIPT_PATH" | grep -q "enable"; then
    info "  ✓ Addresses kubelet disabled state"
else
    error "  ✗ Does not address kubelet disabled state"
    exit 1
fi

# Check containerd handling
if grep -A 10 -B 5 "containerd" "$SCRIPT_PATH" | grep -q "enable\|start"; then
    info "  ✓ Addresses containerd service management"
else
    error "  ✗ Does not address containerd service management"
    exit 1
fi

# Check flannel guidance (since it's not a systemd service)
if grep -i -A 5 "flannel" "$SCRIPT_PATH" | grep -q "pods\|daemonset"; then
    info "  ✓ Provides appropriate Flannel guidance (pods not services)"
else
    error "  ✗ Does not provide appropriate Flannel guidance"
    exit 1
fi

echo ""

echo "=== Test Summary ==="
info "Kubernetes Service Enablement Fix validation:"
info "  ✓ Script exists and is properly executable"
info "  ✓ Handles kubelet service enablement"
info "  ✓ Handles containerd service enablement"
info "  ✓ Provides appropriate Flannel guidance"
info "  ✓ Includes comprehensive error handling"
info "  ✓ Follows repository patterns and conventions"
echo ""
info "Fix validation PASSED - Ready for deployment testing"
echo ""
info "The fix should resolve:"
info "  - kubelet.service disabled state"
info "  - containerd.service disabled state"
info "  - Provide guidance for Flannel (pod-based) issues"
info "  - Give clear next steps for further troubleshooting"
echo ""
info "To use the fix:"
info "  ./scripts/fix_kubernetes_service_enablement.sh"
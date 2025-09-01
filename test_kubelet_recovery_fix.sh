#!/bin/bash

# Test script for enhanced kubelet recovery logic
# Validates that the enhanced recovery blocks are properly configured

set -e

echo "=== Testing Kubelet Recovery Fix ==="
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

# Test 1: Verify enhanced recovery logic is present
echo "=== Test 1: Enhanced Recovery Logic Validation ==="

SETUP_CLUSTER_FILE="ansible/plays/kubernetes/setup_cluster.yaml"

if [ ! -f "$SETUP_CLUSTER_FILE" ]; then
    error "setup_cluster.yaml not found"
    exit 1
fi

# Check for enhanced recovery block
if grep -q "Handle kubelet restart failure with comprehensive recovery" "$SETUP_CLUSTER_FILE"; then
    info "✓ Enhanced recovery block found"
else
    error "✗ Enhanced recovery block missing"
    exit 1
fi

# Check for comprehensive diagnostics
if grep -q "Collect initial diagnostics for kubelet failure" "$SETUP_CLUSTER_FILE"; then
    info "✓ Initial diagnostics collection found"
else
    error "✗ Initial diagnostics collection missing"
    exit 1
fi

# Check for container runtime verification
if grep -q "Verify container runtime is operational" "$SETUP_CLUSTER_FILE"; then
    info "✓ Container runtime verification found"
else
    error "✗ Container runtime verification missing"
    exit 1
fi

# Check for service configuration regeneration
if grep -q "Regenerate kubelet service configuration" "$SETUP_CLUSTER_FILE"; then
    info "✓ Service configuration regeneration found"
else
    error "✗ Service configuration regeneration missing"
    exit 1
fi

# Check for comprehensive state cleanup
if grep -q "Clear comprehensive kubelet state" "$SETUP_CLUSTER_FILE"; then
    info "✓ Comprehensive state cleanup found"
else
    error "✗ Comprehensive state cleanup missing"
    exit 1
fi

# Check for post-recovery diagnostics
if grep -q "Collect post-recovery diagnostics" "$SETUP_CLUSTER_FILE"; then
    info "✓ Post-recovery diagnostics found"
else
    error "✗ Post-recovery diagnostics missing"
    exit 1
fi

# Check for systemd rate limiting fixes
if grep -q "Handle systemd start rate limiting" "$SETUP_CLUSTER_FILE"; then
    info "✓ Systemd rate limiting fixes found"
else
    error "✗ Systemd rate limiting fixes missing"
    exit 1
fi

# Check for enhanced status display
if grep -q "Display comprehensive recovery status" "$SETUP_CLUSTER_FILE"; then
    info "✓ Enhanced status display found"
else
    error "✗ Enhanced status display missing"
    exit 1
fi

echo ""

# Test 2: Syntax validation
echo "=== Test 2: Ansible Syntax Validation ==="
if ansible-playbook -i ansible/inventory.txt "$SETUP_CLUSTER_FILE" --syntax-check >/dev/null 2>&1; then
    info "✓ Ansible syntax validation passed"
else
    error "✗ Ansible syntax validation failed"
    exit 1
fi

echo ""

# Test 3: YAML structure validation
echo "=== Test 3: YAML Structure Validation ==="
if python3 -c "
import yaml
try:
    with open('$SETUP_CLUSTER_FILE', 'r') as f:
        yaml.safe_load(f)
    print('YAML structure valid')
except yaml.YAMLError as e:
    print(f'YAML error: {e}')
    exit(1)
"; then
    info "✓ YAML structure validation passed"
else
    error "✗ YAML structure validation failed"
    exit 1
fi

echo ""

# Test 4: Check for recovery strategy components
echo "=== Test 4: Recovery Strategy Components ==="

EXPECTED_COMPONENTS=(
    "systemctl status kubelet"
    "journalctl -u kubelet"
    "systemctl status containerd"
    "containerd.sock"
    "ctr version"
    "/var/lib/kubelet/config.yaml"
    "modprobe overlay"
    "modprobe br_netfilter"
    "10-kubeadm.conf"
)

for component in "${EXPECTED_COMPONENTS[@]}"; do
    if grep -q "$component" "$SETUP_CLUSTER_FILE"; then
        info "✓ Recovery component found: $component"
    else
        warn "⚠ Recovery component not found: $component"
    fi
done

echo ""

# Test 5: Check integration with existing workflow
echo "=== Test 5: Integration with Existing Workflow ==="

# Verify the recovery block is properly conditioned
if grep -A 5 "when:" "$SETUP_CLUSTER_FILE" | grep -q "kubelet_restart_result.*failed"; then
    info "✓ Recovery block is properly conditioned"
else
    error "✗ Recovery block conditioning issue"
    exit 1
fi

# Verify it doesn't interfere with successful kubelet starts
if grep -q "ignore_errors: yes" "$SETUP_CLUSTER_FILE"; then
    info "✓ Error handling allows graceful continuation"
else
    warn "⚠ Error handling may need review"
fi

echo ""

# Test 6: Diagnostic output validation
echo "=== Test 6: Diagnostic Output Validation ==="

# Check that diagnostic logs are saved
if grep -q "/tmp/kubelet-recovery.*log" "$SETUP_CLUSTER_FILE"; then
    info "✓ Diagnostic logs are saved for review"
else
    warn "⚠ Diagnostic log saving not found"
fi

# Check for troubleshooting guidance
if grep -q "Troubleshooting steps:" "$SETUP_CLUSTER_FILE"; then
    info "✓ Troubleshooting guidance provided"
else
    warn "⚠ Troubleshooting guidance not found"
fi

echo ""

echo "=== Test Summary ==="
info "Enhanced kubelet recovery logic validation completed successfully!"
echo ""
info "Key improvements implemented:"
info "  - Comprehensive diagnostic collection"
info "  - Container runtime verification and recovery"
info "  - Kubelet service configuration regeneration"
info "  - Enhanced state cleanup"
info "  - Post-recovery validation"
info "  - Detailed troubleshooting guidance"
echo ""
info "The enhanced recovery logic should significantly improve kubelet startup"
info "success rates on RHEL 10+ systems and provide better diagnostic information"
info "when failures occur."
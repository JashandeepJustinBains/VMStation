#!/bin/bash

# Validation script for Premium Copilot K8s Monitoring Prompt functionality
# Tests that the get_copilot_prompt.sh script properly loads and displays the operator-grade prompts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

echo "=== Premium Copilot Prompt Validation ==="
echo ""

# Test 1: Check if prompt files exist
echo "1. Checking for required prompt files..."
if [[ -f "$REPO_ROOT/docs/premium_copilot_k8s_monitoring_prompt.md" ]]; then
    info "Template prompt file exists"
else
    error "Template prompt file missing: docs/premium_copilot_k8s_monitoring_prompt.md"
    exit 1
fi

if [[ -f "$REPO_ROOT/docs/premium_copilot_k8s_monitoring_complete_prompt.md" ]]; then
    info "Complete prompt file exists"
else
    error "Complete prompt file missing: docs/premium_copilot_k8s_monitoring_complete_prompt.md"
    exit 1
fi

# Test 2: Check if get_copilot_prompt.sh is executable
echo ""
echo "2. Checking script permissions..."
if [[ -x "$REPO_ROOT/scripts/get_copilot_prompt.sh" ]]; then
    info "get_copilot_prompt.sh is executable"
else
    warn "Making get_copilot_prompt.sh executable"
    chmod +x "$REPO_ROOT/scripts/get_copilot_prompt.sh"
fi

# Test 3: Test script functionality
echo ""
echo "3. Testing script functionality..."

# Test --help
if "$REPO_ROOT/scripts/get_copilot_prompt.sh" --help >/dev/null 2>&1; then
    info "--help option works"
else
    error "--help option failed"
    exit 1
fi

# Test --show
if "$REPO_ROOT/scripts/get_copilot_prompt.sh" --show | grep -q "duplicate Grafana instances"; then
    info "--show option works and contains expected content"
else
    error "--show option failed or missing expected content"
    exit 1
fi

# Test --complete
if "$REPO_ROOT/scripts/get_copilot_prompt.sh" --complete | grep -q "duplicate Grafana instances"; then
    info "--complete option works and contains expected content"
else
    error "--complete option failed or missing expected content"
    exit 1
fi

# Test --gather
if "$REPO_ROOT/scripts/get_copilot_prompt.sh" --gather | grep -q "Basic diagnostics complete"; then
    info "--gather option works"
else
    error "--gather option failed"
    exit 1
fi

# Test 4: Validate prompt content
echo ""
echo "4. Validating prompt content..."

# Check for required sections in template prompt
template_content=$("$REPO_ROOT/scripts/get_copilot_prompt.sh" --show)

required_sections=(
    "Discovery"
    "Backup"
    "Dry-run remediation"
    "Execute safe removal"
    "Handle.*loki-1.*completing pod"
    "Post-change sanity checks"
    "Rollback plan"
    "operator confirmation"
)

for section in "${required_sections[@]}"; do
    if echo "$template_content" | grep -q "$section"; then
        info "Found required section: $section"
    else
        error "Missing required section: $section"
        exit 1
    fi
done

# Test 5: Check integration with existing monitoring scripts
echo ""
echo "5. Checking integration with existing monitoring scripts..."

if [[ -f "$REPO_ROOT/scripts/analyze_k8s_monitoring_diagnostics.sh" ]]; then
    info "Integration with analyze_k8s_monitoring_diagnostics.sh available"
else
    warn "analyze_k8s_monitoring_diagnostics.sh not found - optional integration"
fi

if [[ -f "$REPO_ROOT/scripts/validate_grafana_fix.sh" ]]; then
    info "Integration with validate_grafana_fix.sh available"
else
    warn "validate_grafana_fix.sh not found - will be created if needed"
fi

echo ""
info "All validation tests passed!"
echo ""
echo "Usage examples:"
echo "  # Get template prompt for manual copy:"
echo "  ./scripts/get_copilot_prompt.sh --show"
echo ""
echo "  # Get complete prompt with embedded diagnostics:"
echo "  ./scripts/get_copilot_prompt.sh --complete"
echo ""
echo "  # Gather diagnostic information separately:"
echo "  ./scripts/get_copilot_prompt.sh --gather"
echo ""
echo "  # Copy to clipboard (if xclip/pbcopy available):"
echo "  ./scripts/get_copilot_prompt.sh --copy"
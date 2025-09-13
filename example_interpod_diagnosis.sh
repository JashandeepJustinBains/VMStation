#!/bin/bash

# Example Usage of Inter-Pod Communication Diagnostics
# This script demonstrates how to use VMStation's diagnostic tools
# to analyze the specific issues shown in the problem statement

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "=== VMStation Inter-Pod Communication Diagnostic Example ==="
echo "Demonstrating how to diagnose the issues from your problem statement"
echo

info "Your problem statement showed:"
echo "  NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE"
echo "  kube-proxy   3         3         2       3            2"
echo
echo "  And iptables output showing:"
echo "  'jellyfin/jellyfin-service:http has no endpoints'"
echo

echo "=== Step 1: Use the specific inter-pod diagnostic script ==="
echo "This will analyze your exact symptoms:"
echo
echo "Command: ./scripts/diagnose_interpod_communication.sh"
echo

if [ -f "scripts/diagnose_interpod_communication.sh" ]; then
    info "✅ New diagnostic script is available"
    echo "This script will check:"
    echo "  • kube-proxy daemonset readiness (3 desired vs 2 ready)"
    echo "  • Services with no endpoints (jellyfin pattern)"
    echo "  • iptables KUBE-EXTERNAL-SERVICES REJECT rules"
    echo "  • Flannel networking and routing"
    echo "  • Actual pod-to-pod connectivity"
else
    error "❌ Diagnostic script not found"
fi

echo
echo "=== Step 2: Use enhanced cluster validation ==="
echo "The existing validation script now includes enhanced detection:"
echo
echo "Command: ./scripts/validate_cluster_communication.sh"
echo

if [ -f "scripts/validate_cluster_communication.sh" ]; then
    info "✅ Enhanced validation script available"
    echo "New features added:"
    echo "  • kube-proxy daemonset readiness analysis"
    echo "  • Service endpoint validation"
    echo "  • iptables REJECT rule detection"
else
    warn "⚠️  Enhanced validation script not found"
fi

echo
echo "=== Step 3: Apply fixes for identified issues ==="
echo "Use the existing fix scripts:"
echo
echo "Commands:"
echo "  ./scripts/fix_cluster_communication.sh      # Primary fix"
echo "  ./scripts/fix_iptables_compatibility.sh     # iptables issues"
echo "  ./scripts/fix_remaining_pod_issues.sh       # kube-proxy issues"

echo
echo "=== Step 4: Validate fixes worked ==="
echo "Re-run diagnostics to confirm resolution:"
echo
echo "Commands:"
echo "  ./scripts/validate_cluster_communication.sh"
echo "  ./scripts/test_problem_statement_scenarios.sh"
echo "  ./scripts/validate_pod_connectivity.sh"

echo
success "✅ VMStation repository CAN help diagnose your inter-pod communication errors!"
echo
echo "Key Benefits:"
echo "  🔍 Targeted diagnosis of your specific symptoms"
echo "  🛠️  Automated fixes for root causes"
echo "  ✅ Comprehensive validation of solutions"
echo "  📊 Detailed analysis of networking components"
echo
info "Start with: ./scripts/diagnose_interpod_communication.sh"
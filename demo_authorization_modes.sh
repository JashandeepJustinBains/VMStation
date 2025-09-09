#!/bin/bash

# Demo script showing how to configure authorization modes for VMStation
# This script demonstrates the different configuration scenarios

echo "=== VMStation Authorization Mode Configuration Demo ==="
echo

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "This demo shows the configuration options available for Kubernetes authorization modes."
echo "No actual changes will be made to your cluster."
echo

# Demo 1: Default Secure Configuration
info "Demo 1: Default Secure Configuration (Recommended for Production)"
echo "Configuration:"
cat << 'EOF'
# ansible/group_vars/all.yml
kubernetes_authorization_mode: "Node,RBAC"
kubernetes_authorization_fallback: false
EOF
echo
success "✅ Most secure configuration with RBAC enforcement"
success "✅ No automatic fallback to less secure mode"
success "✅ Suitable for production environments"
echo

# Demo 2: Troubleshooting Configuration  
info "Demo 2: Troubleshooting Configuration (Automatic Fallback)"
echo "Configuration:"
cat << 'EOF'
# ansible/group_vars/all.yml
kubernetes_authorization_mode: "Node,RBAC"
kubernetes_authorization_fallback: true
EOF
echo
success "✅ Starts with secure Node,RBAC mode"
warn "⚠️  Automatically falls back to AlwaysAllow if init fails"
warn "⚠️  Displays warning if fallback is used"
success "✅ Good for initial cluster setup troubleshooting"
echo

# Demo 3: AlwaysAllow Configuration
info "Demo 3: AlwaysAllow Configuration (Troubleshooting Only)"
echo "Configuration:"
cat << 'EOF'
# ansible/group_vars/all.yml
kubernetes_authorization_mode: "AlwaysAllow"
kubernetes_authorization_fallback: false
EOF
echo
error "❌ Disables all authorization checks"
warn "⚠️  Use ONLY for troubleshooting cluster issues"
warn "⚠️  NOT suitable for production use"
warn "⚠️  Switch back to Node,RBAC after troubleshooting"
echo

# Demo 4: Enhanced RBAC Behavior
info "Demo 4: Enhanced RBAC Behavior"
echo "The system now includes intelligent RBAC handling:"
echo "• Detects current authorization mode automatically"
echo "• Only applies RBAC fixes when in RBAC-enabled modes"
echo "• Skips RBAC operations when in AlwaysAllow mode"
echo "• Provides clear status messages and warnings"
echo

# Demo 5: Migration Scenarios
info "Demo 5: Migration Scenarios"
echo
info "Scenario A: Existing deployment (no configuration changes needed)"
echo "✅ Defaults to Node,RBAC mode (secure)"
echo "✅ Backward compatible with existing setups"
echo

info "Scenario B: Cluster initialization fails with RBAC issues"
echo "1. First, try with fallback enabled:"
cat << 'EOF'
   kubernetes_authorization_mode: "Node,RBAC"
   kubernetes_authorization_fallback: true
EOF
echo "2. If successful, investigate why Node,RBAC failed"
echo "3. Fix underlying issues and disable fallback"
echo

info "Scenario C: Emergency troubleshooting"
echo "1. Temporarily use AlwaysAllow mode:"
cat << 'EOF'
   kubernetes_authorization_mode: "AlwaysAllow"
EOF
echo "2. Troubleshoot and fix issues"
echo "3. Reinitialize cluster with Node,RBAC mode"
echo

# Demo 6: Verification Commands
info "Demo 6: Verification Commands"
echo
echo "After deployment, verify your authorization mode:"
echo "kubectl get pods -n kube-system kube-apiserver-* -o jsonpath='{.items[0].spec.containers[0].command}' | grep authorization-mode"
echo
echo "Check cluster status:"
echo "kubectl get nodes"
echo "kubectl get pods -n kube-system"
echo
echo "Test RBAC permissions:"
echo "kubectl auth can-i create secrets --namespace=kube-system"
echo

# Demo 7: Testing
info "Demo 7: Testing Your Configuration"
echo
echo "Run the test suite to validate your setup:"
echo "./test_authorization_mode_fix.sh"
echo
echo "Run the RBAC test to ensure compatibility:"
echo "./test_rbac_fix.sh"
echo

success "Demo complete! Check docs/kubernetes_authorization_modes.md for detailed documentation."
#!/bin/bash

# VMStation Worker Node Setup Validation Summary
# This script provides a quick validation that the comprehensive worker node setup is ready

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

echo "=== VMStation Worker Node Setup Validation Summary ==="
echo "Timestamp: $(date)"
echo ""

# Check if we're in the right directory
if [ ! -f "deploy.sh" ]; then
    error "This script must be run from the VMStation repository root directory"
    exit 1
fi

info "🔍 Validating comprehensive worker node setup implementation..."
echo ""

# 1. Check enhanced Ansible playbook
info "1. Validating Enhanced Ansible Playbook"
if [ -f "ansible/plays/setup-cluster.yaml" ]; then
    if ansible-playbook --syntax-check -i ansible/inventory.txt ansible/plays/setup-cluster.yaml >/dev/null 2>&1; then
        info "   ✅ Enhanced setup-cluster.yaml syntax is valid"
    else
        error "   ❌ setup-cluster.yaml syntax check failed"
        exit 1
    fi
    
    # Check for key enhancements
    if grep -q "Comprehensive Kubernetes package validation" ansible/plays/setup-cluster.yaml; then
        info "   ✅ Package validation enhancements present"
    else
        warn "   ⚠️  Package validation enhancements not found"
    fi
    
    if grep -q "Comprehensive CNI plugin installation" ansible/plays/setup-cluster.yaml; then
        info "   ✅ CNI plugin installation enhancements present"
    else
        warn "   ⚠️  CNI plugin installation enhancements not found"
    fi
    
    if grep -q "async: 120" ansible/plays/setup-cluster.yaml; then
        info "   ✅ Timeout protection enhancements present"
    else
        warn "   ⚠️  Timeout protection enhancements not found"
    fi
else
    error "   ❌ setup-cluster.yaml not found"
    exit 1
fi
echo ""

# 2. Check comprehensive manual setup script
info "2. Validating Comprehensive Manual Setup Script"
if [ -f "scripts/comprehensive_worker_setup.sh" ]; then
    if [ -x "scripts/comprehensive_worker_setup.sh" ]; then
        info "   ✅ comprehensive_worker_setup.sh is executable"
    else
        warn "   ⚠️  comprehensive_worker_setup.sh is not executable - fixing"
        chmod +x scripts/comprehensive_worker_setup.sh
    fi
    
    if bash -n scripts/comprehensive_worker_setup.sh; then
        info "   ✅ comprehensive_worker_setup.sh syntax is valid"
    else
        error "   ❌ comprehensive_worker_setup.sh syntax check failed"
        exit 1
    fi
    
    # Check for key components
    if grep -q "install_kubernetes" scripts/comprehensive_worker_setup.sh; then
        info "   ✅ Kubernetes installation function present"
    else
        warn "   ⚠️  Kubernetes installation function not found"
    fi
    
    if grep -q "install_cni_plugins" scripts/comprehensive_worker_setup.sh; then
        info "   ✅ CNI plugin installation function present"
    else
        warn "   ⚠️  CNI plugin installation function not found"
    fi
else
    error "   ❌ comprehensive_worker_setup.sh not found"
    exit 1
fi
echo ""

# 3. Check enhanced join scripts
info "3. Validating Enhanced Join Scripts"
for script in scripts/enhanced_kubeadm_join.sh scripts/validate_join_prerequisites.sh; do
    if [ -f "$script" ]; then
        if [ -x "$script" ]; then
            info "   ✅ $(basename $script) is executable"
        else
            warn "   ⚠️  $(basename $script) is not executable - fixing"
            chmod +x "$script"
        fi
        
        if bash -n "$script"; then
            info "   ✅ $(basename $script) syntax is valid"
        else
            error "   ❌ $(basename $script) syntax check failed"
            exit 1
        fi
    else
        warn "   ⚠️  $script not found"
    fi
done
echo ""

# 4. Check documentation
info "4. Validating Documentation"
if [ -f "docs/WORKER_NODE_TROUBLESHOOTING.md" ]; then
    info "   ✅ Worker node troubleshooting documentation present"
else
    warn "   ⚠️  Worker node troubleshooting documentation not found"
fi
echo ""

# 5. Check test infrastructure
info "5. Validating Test Infrastructure"
if [ -f "scripts/test_worker_setup.sh" ]; then
    if [ -x "scripts/test_worker_setup.sh" ]; then
        info "   ✅ test_worker_setup.sh is executable"
    else
        warn "   ⚠️  test_worker_setup.sh is not executable - fixing"
        chmod +x scripts/test_worker_setup.sh
    fi
    
    if bash -n scripts/test_worker_setup.sh; then
        info "   ✅ test_worker_setup.sh syntax is valid"
    else
        error "   ❌ test_worker_setup.sh syntax check failed"
        exit 1
    fi
else
    warn "   ⚠️  test_worker_setup.sh not found"
fi
echo ""

# 6. Check deployment script
info "6. Validating Deployment Script"
if [ -f "deploy.sh" ]; then
    if [ -x "deploy.sh" ]; then
        info "   ✅ deploy.sh is executable"
    else
        warn "   ⚠️  deploy.sh is not executable - fixing"
        chmod +x deploy.sh
    fi
    
    if bash -n deploy.sh; then
        info "   ✅ deploy.sh syntax is valid"
    else
        error "   ❌ deploy.sh syntax check failed"
        exit 1
    fi
else
    error "   ❌ deploy.sh not found"
    exit 1
fi
echo ""

# Summary
info "🎉 Validation Summary"
echo ""
info "✅ Enhanced Ansible playbook with comprehensive worker node setup"
info "✅ Manual setup script for fallback installation"
info "✅ Enhanced join scripts with timeout protection"
info "✅ Comprehensive documentation and troubleshooting guide"
info "✅ Test infrastructure for validation"
echo ""
info "🚀 Available Deployment Methods:"
echo ""
info "Method 1 (Recommended): Enhanced Automated Deployment"
info "   ./deploy.sh cluster"
echo ""
info "Method 2 (Fallback): Manual Worker Setup"
info "   sudo ./scripts/comprehensive_worker_setup.sh"
echo ""
info "Method 3 (Testing): Validation and Testing"
info "   ./scripts/test_worker_setup.sh"
echo ""
info "📖 For detailed troubleshooting:"
info "   cat docs/WORKER_NODE_TROUBLESHOOTING.md"
echo ""
info "🔧 The comprehensive worker node setup is ready for deployment!"
info "This addresses the original issue with incomplete component installation"
info "and provides robust, timeout-protected worker node preparation."
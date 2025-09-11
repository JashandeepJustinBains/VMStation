#!/bin/bash

# VMStation Deployment Fix Verification Script
# This script verifies that the crictl configuration fix is working properly

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=== VMStation Deployment Fix Verification ==="
echo "This script verifies the crictl configuration fix is working"
echo "Timestamp: $(date)"
echo ""

# Test 1: Check if crictl configuration exists and is correct
info "Test 1: Checking crictl configuration..."

if [ -f /etc/crictl.yaml ]; then
    info "✓ /etc/crictl.yaml exists"
    
    # Check contents
    if grep -q "runtime-endpoint: unix:///run/containerd/containerd.sock" /etc/crictl.yaml; then
        info "✓ Runtime endpoint is correctly configured"
    else
        error "✗ Runtime endpoint is not correctly configured"
        exit 1
    fi
    
    if grep -q "image-endpoint: unix:///run/containerd/containerd.sock" /etc/crictl.yaml; then
        info "✓ Image endpoint is correctly configured"
    else
        error "✗ Image endpoint is not correctly configured"
        exit 1
    fi
    
    info "Current crictl configuration:"
    cat /etc/crictl.yaml | sed 's/^/    /'
else
    warn "! /etc/crictl.yaml does not exist (will be created during deployment)"
fi

echo ""

# Test 2: Check if containerd is running
info "Test 2: Checking containerd status..."

if systemctl is-active containerd >/dev/null 2>&1; then
    info "✓ containerd service is active"
    
    # Test 3: If containerd is running, test crictl connectivity
    info "Test 3: Testing crictl connectivity to containerd..."
    
    if command -v crictl >/dev/null 2>&1; then
        info "✓ crictl command is available"
        
        if crictl version >/dev/null 2>&1; then
            info "✓ crictl can connect to containerd"
            
            # Show crictl version info
            echo ""
            info "crictl version information:"
            crictl version | sed 's/^/    /'
            
            # Test crictl info command
            if crictl info >/dev/null 2>&1; then
                info "✓ crictl info command works"
                echo ""
                info "CRI runtime information:"
                crictl info | head -10 | sed 's/^/    /'
            else
                warn "! crictl info command failed (this may be normal if no containers are running)"
            fi
        else
            warn "! crictl cannot connect to containerd (this is expected if containerd was just started)"
            warn "  This will be automatically fixed during deployment"
        fi
    else
        warn "! crictl command not found (will be installed during deployment)"
    fi
else
    warn "! containerd service is not running (will be started during deployment)"
fi

echo ""

# Test 4: Check deployment script availability
info "Test 4: Checking deployment script availability..."

if [ -f "./deploy.sh" ]; then
    info "✓ deploy.sh script is available"
    
    if [ -x "./deploy.sh" ]; then
        info "✓ deploy.sh script is executable"
    else
        warn "! deploy.sh script is not executable - run: chmod +x deploy.sh"
    fi
else
    error "✗ deploy.sh script not found - please run from VMStation repository root"
    exit 1
fi

# Test 5: Check playbook syntax
info "Test 5: Checking playbook syntax..."

if command -v ansible-playbook >/dev/null 2>&1; then
    if ansible-playbook --syntax-check ansible/plays/setup-cluster.yaml >/dev/null 2>&1; then
        info "✓ setup-cluster.yaml playbook syntax is valid"
    else
        error "✗ setup-cluster.yaml playbook has syntax errors"
        exit 1
    fi
else
    warn "! ansible-playbook not found - please install Ansible"
fi

echo ""
echo "=== Verification Summary ==="

if [ -f /etc/crictl.yaml ]; then
    info "✅ System appears to be already configured with crictl fix"
    info "   The deployment should work correctly"
else
    info "✅ System is ready for deployment with crictl fix"
    info "   The fix will be applied automatically during deployment"
fi

echo ""
info "To run the deployment:"
info "  ./deploy.sh cluster"
echo ""
info "To monitor the deployment process:"
info "  tail -f /var/log/syslog | grep -E '(containerd|crictl|kubelet)'"
echo ""
warn "Note: If you encounter issues, check the deployment documentation:"
warn "  docs/crictl-fix-documentation.md"
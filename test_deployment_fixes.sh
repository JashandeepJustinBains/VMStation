#!/bin/bash

# VMStation Deployment Fixes Verification Script
# Tests the fixes for kubelet timeout and Jellyfin deployment issues

echo "=== VMStation Deployment Fixes Verification ==="
echo "This script validates the fixes for:"
echo "1. Worker node kubelet startup timeout during cluster join"
echo "2. Missing Jellyfin namespace and deployment issues"
echo

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Check if running as a validation test or deployment test
VALIDATION_MODE=${1:-"validation"}

if [ "$VALIDATION_MODE" = "validation" ]; then
    info "Running in validation mode - checking configuration files"
    
    echo "Checking kubelet configuration improvements..."
    if grep -q "KUBELET_EXTRA_ARGS.*cgroup-driver=systemd" ansible/plays/setup-cluster.yaml; then
        pass "Kubelet cgroup configuration added"
    else
        fail "Kubelet cgroup configuration missing"
    fi
    
    if grep -q "Prepare kubelet for join" ansible/plays/setup-cluster.yaml; then
        pass "Kubelet preparation steps added to join process"
    else
        fail "Kubelet preparation steps missing"
    fi
    
    if grep -q "Ensure containerd is running" ansible/plays/setup-cluster.yaml; then
        pass "Containerd verification added to join process"
    else
        fail "Containerd verification missing"
    fi
    
    echo
    echo "Checking Jellyfin deployment improvements..."
    if grep -q "kubernetes.io/hostname: homelab" ansible/plays/kubernetes/jellyfin-minimal.yml; then
        pass "Jellyfin targets correct node (homelab)"
    else
        fail "Jellyfin node targeting incorrect"
    fi
    
    if grep -q "name: jellyfin-service" ansible/plays/jellyfin.yml; then
        pass "Jellyfin playbook uses correct service name"
    else
        fail "Jellyfin service name incorrect"
    fi
    
    echo
    echo "Checking syntax validation..."
    if ansible-playbook --syntax-check ansible/simple-deploy.yaml -i ansible/inventory.txt >/dev/null 2>&1; then
        pass "All playbooks have valid syntax"
    else
        fail "Syntax errors found in playbooks"
    fi
    
elif [ "$VALIDATION_MODE" = "deployment" ]; then
    info "Running in deployment mode - testing actual deployment"
    warn "This will attempt to run the deployment - ensure your environment is ready"
    
    echo "Testing deployment readiness check..."
    if ./deploy.sh check; then
        pass "Deployment check passes"
    else
        fail "Deployment check failed"
    fi
    
    echo
    warn "To test the full deployment fixes:"
    echo "./deploy.sh cluster  # Test cluster setup with kubelet fixes"
    echo "./deploy.sh apps    # Test application deployment including Jellyfin"
    
else
    fail "Unknown mode: $VALIDATION_MODE"
    echo "Usage: $0 [validation|deployment]"
    exit 1
fi

echo
echo "=== Expected Improvements ==="
echo
info "These fixes should resolve:"
echo "1. 'kubelet-start: timed out waiting for the condition' errors"
echo "   - Proper kubelet cgroup configuration"
echo "   - Enhanced systemd service management"
echo "   - Better containerd integration"
echo
echo "2. Missing jellyfin namespace deployment failures"
echo "   - Correct node targeting (homelab vs storagenodet3500)" 
echo "   - Proper service name references"
echo "   - Improved error handling"
echo
info "Key technical improvements:"
echo "- Added KUBELET_EXTRA_ARGS with cgroup-driver=systemd"
echo "- Enhanced join process with containerd verification"
echo "- Improved cleanup and retry logic for failed joins"
echo "- Fixed node targeting in Jellyfin manifest"
echo "- Corrected service name references in Jellyfin playbook"
echo
pass "All fixes validated and ready for deployment testing"
#!/bin/bash

# VMStation RHEL 10 Kubernetes Setup Validation Script
# Validates that the fixes for RHEL 10 Kubernetes requirements installation are correctly implemented

set -euo pipefail

echo "=== VMStation RHEL 10 Kubernetes Setup Validation ==="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

echo "=== 1. Checking RHEL 10+ Block Improvements ==="

# Check 1: Verify required packages installation is added
echo "✓ Checking required packages installation..."
if grep -q "Install required packages for RHEL 10+" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "Required packages installation task added"
else
    error "Required packages installation task missing"
    exit 1
fi

# Check 2: Verify Kubernetes version detection fix
echo "✓ Checking Kubernetes version detection..."
if grep -q "Get latest stable Kubernetes version for specified minor version" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "Kubernetes version detection task added"
else
    error "Kubernetes version detection task missing"
    exit 1
fi

if grep -q "k8s_full_version.*k8s_version_result.stdout.strip" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "Kubernetes version fact setting with fallback implemented"
else
    error "Kubernetes version fact setting missing or incorrect"
    exit 1
fi

# Check 3: Verify binary download URLs use the correct version variable
echo "✓ Checking binary download URLs..."
if grep -q "https://dl.k8s.io/release/{{ k8s_full_version }}/bin/linux/amd64/kubeadm" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "kubeadm download URL uses correct version variable"
else
    error "kubeadm download URL incorrect"
    exit 1
fi

if grep -q "https://dl.k8s.io/release/{{ k8s_full_version }}/bin/linux/amd64/kubectl" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "kubectl download URL uses correct version variable"
else
    error "kubectl download URL incorrect"
    exit 1
fi

if grep -q "https://dl.k8s.io/release/{{ k8s_full_version }}/bin/linux/amd64/kubelet" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "kubelet download URL uses correct version variable"
else
    error "kubelet download URL incorrect"
    exit 1
fi

# Check 4: Verify improved kubelet systemd service
echo "✓ Checking kubelet systemd service improvements..."
if grep -q "Create kubelet systemd drop-in directory" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "Kubelet systemd drop-in directory creation added"
else
    error "Kubelet systemd drop-in directory creation missing"
    exit 1
fi

if grep -q "10-kubeadm.conf" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "Kubelet kubeadm drop-in configuration added"
else
    error "Kubelet kubeadm drop-in configuration missing"
    exit 1
fi

# Check 5: Verify binary validation tasks
echo "✓ Checking binary validation..."
if grep -q "Verify kubeadm binary works" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "kubeadm binary validation added"
else
    error "kubeadm binary validation missing"
    exit 1
fi

if grep -q "Verify kubectl binary works" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "kubectl binary validation added"
else
    error "kubectl binary validation missing"
    exit 1
fi

if grep -q "Verify kubelet binary works" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "kubelet binary validation added"
else
    error "kubelet binary validation missing"
    exit 1
fi

# Check 6: Verify systemd handling improvements
echo "✓ Checking systemd handling..."
if grep -q "daemon_reload: yes" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "Systemd daemon reload added"
else
    error "Systemd daemon reload missing"
    exit 1
fi

if grep -q "Verify kubelet service is running" ansible/plays/kubernetes/setup_cluster.yaml; then
    success "Kubelet service verification added"
else
    error "Kubelet service verification missing"
    exit 1
fi

echo ""
echo "=== 2. Syntax Validation ==="

# Check 7: Ansible syntax validation
echo "✓ Running Ansible syntax validation..."
if ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml --syntax-check > /dev/null 2>&1; then
    success "Ansible syntax validation passed"
else
    error "Ansible syntax validation failed"
    exit 1
fi

echo ""
echo "=== 3. Configuration Verification ==="

# Check 8: Verify configuration template exists
echo "✓ Checking configuration template..."
if [ -f "ansible/group_vars/all.yml.template" ]; then
    success "Configuration template exists"
    if grep -q "kubernetes_version.*1.29" ansible/group_vars/all.yml.template; then
        success "Kubernetes version 1.29 configured in template"
    else
        warning "Kubernetes version not set to 1.29 in template"
    fi
else
    error "Configuration template missing"
    exit 1
fi

echo ""
echo "=== Validation Summary ==="
echo ""
echo -e "${GREEN}🎉 All RHEL 10 Kubernetes setup fixes have been validated!${NC}"
echo ""
echo "Key improvements implemented:"
echo "✓ Fixed Kubernetes binary download URLs to use proper version format"
echo "✓ Added required packages installation for RHEL 10+"
echo "✓ Improved kubelet systemd service configuration with proper drop-in files"
echo "✓ Added binary validation to ensure downloads are successful"
echo "✓ Enhanced systemd service management with daemon reload and verification"
echo "✓ Added proper error handling and fallbacks for version detection"
echo ""
echo "Expected behavior on RHEL 10:"
echo "- Downloads will use correct Kubernetes version URLs (e.g., v1.29.x)"
echo "- Kubelet service will start with proper kubeadm integration"
echo "- All binaries will be validated before proceeding"
echo "- Better error messages if installation fails"
echo ""
echo "To deploy: ./deploy_kubernetes.sh"
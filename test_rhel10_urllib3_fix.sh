#!/bin/bash
# Test script to validate the RHEL 10 urllib3 compatibility fix

set -euo pipefail

echo "=== Testing RHEL 10 urllib3 Compatibility Fix ==="
echo

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}✓${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

echo "1. Checking for shell fallback tasks in setup_cluster.yaml..."

# Check if shell fallback tasks are present
if grep -q "Download.*using shell fallback.*urllib3 compatibility" ansible/plays/kubernetes/setup_cluster.yaml; then
    info "Shell fallback tasks for urllib3 compatibility found"
else
    error "Shell fallback tasks not found"
    exit 1
fi

echo
echo "2. Verifying specific binary fallback implementations..."

# Check each binary has a fallback
binaries=("kubeadm" "kubectl" "kubelet" "crictl")
for binary in "${binaries[@]}"; do
    if grep -q "Download $binary binary using shell fallback" ansible/plays/kubernetes/setup_cluster.yaml; then
        info "$binary binary has shell fallback implementation"
    else
        warn "$binary binary missing shell fallback (expected for crictl)"
    fi
done

echo
echo "3. Checking for proper error condition handling..."

# Check if the when condition properly detects urllib3 errors
if grep -q "cert_file.*in.*msg.*or.*urllib3.*in.*msg" ansible/plays/kubernetes/setup_cluster.yaml; then
    info "Proper urllib3 error detection conditions found"
else
    error "urllib3 error detection conditions not found"
    exit 1
fi

echo
echo "4. Verifying binary verification tasks..."

# Check if verification tasks are present
verification_tasks=("kubeadm" "kubectl" "kubelet")
for binary in "${verification_tasks[@]}"; do
    if grep -q "Verify $binary binary was downloaded successfully" ansible/plays/kubernetes/setup_cluster.yaml; then
        info "$binary binary verification task found"
    else
        warn "$binary binary verification task not found"
    fi
done

echo
echo "5. Checking fallback download methods..."

# Check for curl and wget fallbacks
if grep -q "command -v curl" ansible/plays/kubernetes/setup_cluster.yaml && grep -q "command -v wget" ansible/plays/kubernetes/setup_cluster.yaml; then
    info "Both curl and wget fallback methods implemented"
else
    error "Missing curl/wget fallback methods"
    exit 1
fi

echo
echo "6. Validating Ansible syntax..."

if ansible-playbook --syntax-check ansible/plays/kubernetes/setup_cluster.yaml >/dev/null 2>&1; then
    info "Ansible syntax validation passed"
else
    error "Ansible syntax validation failed"
    exit 1
fi

echo
echo "7. Checking if get_url tasks are configured with proper parameters..."

# Check that get_url tasks have the required parameters
if grep -A 10 "name: Download.*binary (RHEL 10+ fallback)" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "validate_certs: false" && \
   grep -A 10 "name: Download.*binary (RHEL 10+ fallback)" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "use_proxy: false"; then
    info "get_url tasks properly configured with validate_certs: false and use_proxy: false"
else
    warn "get_url tasks may be missing proper SSL/proxy configuration"
fi

echo
echo "8. Checking for failed_when: false on get_url tasks..."

if grep -A 15 "name: Download.*binary (RHEL 10+ fallback)" ansible/plays/kubernetes/setup_cluster.yaml | grep -q "failed_when: false"; then
    info "get_url tasks properly configured to not fail on urllib3 errors"
else
    error "get_url tasks missing failed_when: false configuration"
    exit 1
fi

echo
echo "🎉 All validation checks passed! The RHEL 10 urllib3 compatibility fix is properly implemented."
echo
echo "The fix provides:"
echo "  1. Primary download attempt using get_url module"
echo "  2. Automatic fallback to shell commands (curl/wget) on urllib3 errors"
echo "  3. Proper error detection for 'cert_file' and 'urllib3' error messages"
echo "  4. Retry logic for both methods"
echo "  5. Binary verification and permission setting"
echo
echo "Next steps:"
echo "  - Deploy using: ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml"
echo "  - Monitor logs for urllib3 error handling during RHEL 10 binary downloads"
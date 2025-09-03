#!/bin/bash

# Test script for cert-manager timeout fixes
# Validates that the timeout configurations are properly set

set -e

echo "=== Testing Cert-Manager Timeout Fixes ==="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Phase 1: Syntax Validation ==="

echo "Validating cert-manager playbook syntax..."
if ansible-playbook --syntax-check ansible/plays/kubernetes/setup_cert_manager.yaml >/dev/null 2>&1; then
    echo -e "${GREEN}✓ cert-manager playbook syntax is valid${NC}"
else
    echo -e "${RED}✗ cert-manager playbook syntax errors${NC}"
    exit 1
fi

echo "Validating local-path provisioner playbook syntax..."
if ansible-playbook --syntax-check ansible/plays/kubernetes/setup_local_path_provisioner.yaml >/dev/null 2>&1; then
    echo -e "${GREEN}✓ local-path provisioner playbook syntax is valid${NC}"
else
    echo -e "${RED}✗ local-path provisioner playbook syntax errors${NC}"
    exit 1
fi

echo "Validating kubernetes_stack playbook syntax..."
if ansible-playbook --syntax-check ansible/plays/kubernetes_stack.yaml >/dev/null 2>&1; then
    echo -e "${GREEN}✓ kubernetes_stack playbook syntax is valid${NC}"
else
    echo -e "${RED}✗ kubernetes_stack playbook syntax errors${NC}"
    exit 1
fi

echo ""
echo "=== Phase 2: Timeout Configuration Validation ==="

# Check cert-manager timeout values
echo "Checking cert-manager timeout configurations..."
if grep -q "timeout: 900s" ansible/plays/kubernetes/setup_cert_manager.yaml; then
    echo -e "${GREEN}✓ cert-manager Helm timeout is generous: 900s${NC}"
else
    echo -e "${RED}✗ cert-manager Helm timeout not set to 900s${NC}"
    exit 1
fi

# Check rollout timeout values
if grep -q "timeout=900s" ansible/plays/kubernetes/setup_cert_manager.yaml; then
    echo -e "${GREEN}✓ cert-manager rollout timeout is generous: 900s${NC}"
else
    echo -e "${RED}✗ cert-manager rollout timeout not set to 900s${NC}"
    exit 1
fi

# Check local-path provisioner timeout
if grep -q "wait_timeout: 600" ansible/plays/kubernetes/setup_local_path_provisioner.yaml; then
    echo -e "${GREEN}✓ local-path provisioner timeout is generous: 600s${NC}"
else
    echo -e "${RED}✗ local-path provisioner timeout not set to 600s${NC}"
    exit 1
fi

echo ""
echo "=== Phase 3: Retry Logic Validation ==="

# Check for retry logic in cert-manager
if grep -q "retries:" ansible/plays/kubernetes/setup_cert_manager.yaml; then
    echo -e "${GREEN}✓ cert-manager has retry logic configured${NC}"
else
    echo -e "${RED}✗ cert-manager missing retry logic${NC}"
    exit 1
fi

# Check for retry logic in local-path provisioner  
if grep -q "retries:" ansible/plays/kubernetes/setup_local_path_provisioner.yaml; then
    echo -e "${GREEN}✓ local-path provisioner has retry logic configured${NC}"
else
    echo -e "${RED}✗ local-path provisioner missing retry logic${NC}"
    exit 1
fi

echo ""
echo "=== Phase 4: Pre-flight Check Validation ==="

# Check for cluster readiness checks
if grep -q "Check cluster readiness" ansible/plays/kubernetes/setup_cert_manager.yaml; then
    echo -e "${GREEN}✓ cert-manager has pre-flight cluster checks${NC}"
else
    echo -e "${RED}✗ cert-manager missing pre-flight cluster checks${NC}"
    exit 1
fi

# Check for cleanup logic
if grep -q "Clean up any previous failed" ansible/plays/kubernetes/setup_cert_manager.yaml; then
    echo -e "${GREEN}✓ cert-manager has cleanup logic for failed installations${NC}"
else
    echo -e "${RED}✗ cert-manager missing cleanup logic${NC}"
    exit 1
fi

echo ""
echo "=== Phase 5: Directory Prerequisites Validation ==="

# Check for monitoring directory creation
if grep -q "/srv/monitoring_data" ansible/plays/kubernetes_stack.yaml; then
    echo -e "${GREEN}✓ kubernetes_stack creates monitoring directories${NC}"
else
    echo -e "${RED}✗ kubernetes_stack missing monitoring directory creation${NC}"
    exit 1
fi

echo ""
echo "=== Phase 6: Resource Configuration Validation ==="

# Check for resource requests in cert-manager
if grep -q "cpu: 10m" ansible/plays/kubernetes/setup_cert_manager.yaml; then
    echo -e "${GREEN}✓ cert-manager has resource requests configured${NC}"
else
    echo -e "${RED}✗ cert-manager missing resource requests${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== All Timeout Fix Tests PASSED! ===${NC}"
echo ""
echo "Summary of improvements:"
echo "• cert-manager Helm timeout: 900s (was 120s)"
echo "• cert-manager rollout timeout: 900s (was 600s)"  
echo "• local-path provisioner timeout: 600s (was 120s)"
echo "• Added retry logic with exponential backoff"
echo "• Added pre-flight cluster readiness checks"
echo "• Added cleanup of failed installations"
echo "• Added monitoring directory creation"
echo "• Added resource requests to prevent starvation"
echo "• Added debugging information for troubleshooting"
echo ""
echo "These fixes should resolve the 'context deadline exceeded' and"
echo "'deployment exceeded its progress deadline' errors."
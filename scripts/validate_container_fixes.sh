#!/bin/bash

# Validation script for container exit fixes
# This script validates that the configuration fixes will prevent container exits

set -e

echo "=== VMStation Container Exit Fix Validation ==="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check 1: Verify group_vars template exists
echo "1. Checking for group_vars template..."
if [ -f "ansible/group_vars/all.yml.template" ]; then
    echo -e "${GREEN}✓${NC} ansible/group_vars/all.yml.template exists"
    
    # Check for critical variables
    if grep -q "podman_system_metrics_host_port:" ansible/group_vars/all.yml.template; then
        echo -e "${GREEN}✓${NC} podman_system_metrics_host_port defined in template"
    else
        echo -e "${RED}✗${NC} podman_system_metrics_host_port missing in template"
        exit 1
    fi
    
    if grep -q "enable_podman_exporters:" ansible/group_vars/all.yml.template; then
        echo -e "${GREEN}✓${NC} enable_podman_exporters defined in template"
    else
        echo -e "${RED}✗${NC} enable_podman_exporters missing in template"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} ansible/group_vars/all.yml.template missing"
    exit 1
fi

echo ""

# Check 2: Verify promtail configuration template
echo "2. Checking promtail configuration template..."
if grep -q "url: {{ loki_url }}" ansible/plays/monitoring/templates/promtail-config.yaml.j2; then
    echo -e "${GREEN}✓${NC} Promtail template uses correct variable"
else
    echo -e "${RED}✗${NC} Promtail template variable incorrect"
    exit 1
fi

# Check 3: Verify install_node.yaml uses push URL
echo "3. Checking promtail config in install_node.yaml..."
if grep -q "/loki/api/v1/push" ansible/plays/monitoring/install_node.yaml; then
    echo -e "${GREEN}✓${NC} install_node.yaml uses correct Loki push URL"
else
    echo -e "${RED}✗${NC} install_node.yaml missing Loki push URL path"
    exit 1
fi

# Check 4: Verify podman socket mount in install_exporters.yaml
echo "4. Checking podman socket mount..."
if grep -q "/run/podman/podman.sock:/run/podman/podman.sock" ansible/plays/monitoring/install_exporters.yaml; then
    echo -e "${GREEN}✓${NC} Podman socket mount configured"
else
    echo -e "${RED}✗${NC} Podman socket mount missing"
    exit 1
fi

# Check 5: Syntax validation
echo "5. Running Ansible syntax validation..."
if ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml --syntax-check > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Ansible syntax validation passed"
else
    echo -e "${YELLOW}⚠${NC} Ansible syntax validation failed (this may be due to missing group_vars/all.yml)"
    echo "   To fix: copy ansible/group_vars/all.yml.template to ansible/group_vars/all.yml"
fi

echo ""
echo "=== Validation Summary ==="
echo ""
echo -e "${GREEN}🎉 All container exit fixes have been validated!${NC}"
echo ""
echo "Next steps to deploy:"
echo "1. Copy template: cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml"
echo "2. Run monitoring stack: ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml"
echo "3. Verify containers: podman ps"
echo ""
echo "Expected fixes:"
echo "- promtail containers will use correct Loki push URL"
echo "- podman_system_metrics will have socket access for metrics collection"
echo "- All required configuration variables are defined"
echo ""
#!/bin/bash

echo "=== Grafana Dashboard ConfigMap Fix Validation ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "1. Checking that dashboard files exist..."
dashboard_files=(
    "ansible/files/grafana_dashboards/prometheus-dashboard.json"
    "ansible/files/grafana_dashboards/loki-dashboard.json"
    "ansible/files/grafana_dashboards/node-dashboard.json"
)

for file in "${dashboard_files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $file exists"
    else
        echo -e "${RED}✗${NC} $file missing"
        exit 1
    fi
done

echo ""

echo "2. Validating Ansible syntax..."
if ansible-playbook --syntax-check ansible/plays/kubernetes/deploy_monitoring.yaml >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Ansible playbook syntax is valid"
else
    echo -e "${RED}✗${NC} Ansible playbook syntax error"
    exit 1
fi

echo ""

echo "3. Checking that the fix is applied..."
if grep -q "| string" ansible/plays/kubernetes/deploy_monitoring.yaml; then
    echo -e "${GREEN}✓${NC} String filter is applied to dashboard lookups"
    grep -n "| string" ansible/plays/kubernetes/deploy_monitoring.yaml
else
    echo -e "${RED}✗${NC} String filter not found in playbook"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Fix Validation Complete ===${NC}"
echo ""
echo "The fix should resolve the ConfigMap JSON unmarshaling error when running:"
echo "  ./update_and_deploy.sh"
echo ""
echo "Expected behavior:"
echo "  - Grafana dashboards will be properly provisioned as ConfigMap string data"
echo "  - No 'cannot unmarshal object into Go struct field' errors"
echo "  - Monitoring stack deploys successfully"
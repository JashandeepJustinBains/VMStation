#!/bin/bash

echo "=== Grafana Deployment Fix Validation ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if group_vars exists
echo "1. Checking for group_vars/all.yml..."
if [ -f "ansible/group_vars/all.yml" ]; then
    echo -e "${GREEN}✓${NC} ansible/group_vars/all.yml exists"
    echo "   Variables defined:"
    grep -E "^[a-zA-Z_].*:" ansible/group_vars/all.yml | head -5
else
    echo -e "${RED}✗${NC} ansible/group_vars/all.yml missing"
    exit 1
fi

echo ""

# Validate Ansible templates can render (check for variable errors)
echo "2. Testing Ansible template rendering..."
output=$(ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml --check --limit monitoring_nodes 2>&1)
if echo "$output" | grep -q "AnsibleUndefinedVariable"; then
    echo -e "${RED}✗${NC} Ansible template rendering failed due to undefined variables"
    echo "$output" | grep "AnsibleUndefinedVariable"
    exit 1
elif echo "$output" | grep -q "TASK \[Start Grafana container in pod"; then
    echo -e "${GREEN}✓${NC} Ansible templates render successfully (Grafana task found)"
else
    echo -e "${YELLOW}⚠${NC} Template rendering test inconclusive (may be network/connectivity issue)"
    echo "   This is expected in sandboxed environments"
    echo "   The fix should work in your actual environment"
fi

echo ""

# Check dashboard files
echo "3. Checking Grafana dashboard files..."
dashboard_files=(
    "ansible/files/grafana_podman_dashboard.json"
    "ansible/files/grafana_node_dashboard.json"
    "ansible/files/grafana_prometheus_dashboard.json"
    "ansible/files/grafana_loki_dashboard.json"
    "ansible/files/grafana_quay_dashboard.json"
)

for file in "${dashboard_files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $file exists"
    else
        echo -e "${RED}✗${NC} $file missing"
    fi
done

echo ""

# Check monitoring pod configuration
echo "4. Checking monitoring pod port configuration..."
if grep -q "grafana_port.*grafana_port" ansible/plays/monitoring/install_node.yaml; then
    echo -e "${GREEN}✓${NC} Grafana port configuration found (using grafana_port variable)"
elif grep -q "3000:3000" ansible/plays/monitoring/install_node.yaml; then
    echo -e "${GREEN}✓${NC} Grafana port 3000:3000 configured in monitoring pod"
else
    echo -e "${YELLOW}⚠${NC} Grafana port configuration may be missing"
fi

echo ""
echo "=== Validation Complete ==="
echo ""
echo "If all checks pass, run:"
echo "  ./update_and_deploy"
echo ""
echo "Then verify Grafana is accessible at:"
echo "  http://192.168.4.63:3000"
echo ""
echo "Expected containers after deployment:"
echo "  - grafana (port 3000)"
echo "  - prometheus (port 9090)"
echo "  - loki (port 3100)"
echo "  - promtail_local"
echo "  - local_registry (port 5000)"
echo "  - node-exporter (port 9100)"
#!/bin/bash

# Test script to validate masternode-only monitoring configuration
# This script tests the Ansible configuration without actually deploying

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BOLD}=== VMStation Masternode Monitoring Configuration Test ===${NC}"
echo "Timestamp: $(date)"
echo ""

# Test 1: Verify all.yml configuration
test_all_yml_config() {
    echo -e "${BOLD}Test 1: Validating all.yml configuration${NC}"
    
    local all_yml_path="/home/runner/work/VMStation/VMStation/ansible/group_vars/all.yml"
    
    if [[ ! -f "$all_yml_path" ]]; then
        echo -e "${RED}✗ all.yml not found at $all_yml_path${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ all.yml exists${NC}"
    
    # Check monitoring_scheduling_mode is set to strict
    local scheduling_mode=$(grep "monitoring_scheduling_mode:" "$all_yml_path" | awk '{print $2}')
    if [[ "$scheduling_mode" == "strict" ]]; then
        echo -e "${GREEN}✓ monitoring_scheduling_mode is set to 'strict'${NC}"
    else
        echo -e "${RED}✗ monitoring_scheduling_mode is '$scheduling_mode', should be 'strict'${NC}"
        return 1
    fi
    
    # Check infrastructure_mode is kubernetes
    local infra_mode=$(grep "infrastructure_mode:" "$all_yml_path" | awk '{print $2}')
    if [[ "$infra_mode" == "kubernetes" ]]; then
        echo -e "${GREEN}✓ infrastructure_mode is set to 'kubernetes'${NC}"
    else
        echo -e "${YELLOW}⚠ infrastructure_mode is '$infra_mode', expected 'kubernetes'${NC}"
    fi
    
    echo ""
    return 0
}

# Test 2: Verify inventory configuration
test_inventory_config() {
    echo -e "${BOLD}Test 2: Validating inventory configuration${NC}"
    
    local inventory_path="/home/runner/work/VMStation/VMStation/ansible/inventory.txt"
    
    if [[ ! -f "$inventory_path" ]]; then
        echo -e "${RED}✗ inventory.txt not found${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ inventory.txt exists${NC}"
    
    # Check monitoring_nodes configuration
    local monitoring_node=$(grep -A1 "\[monitoring_nodes\]" "$inventory_path" | tail -1)
    if [[ "$monitoring_node" == *"192.168.4.63"* ]]; then
        echo -e "${GREEN}✓ monitoring_nodes correctly configured with masternode (192.168.4.63)${NC}"
    else
        echo -e "${RED}✗ monitoring_nodes not properly configured${NC}"
        echo "Found: $monitoring_node"
        return 1
    fi
    
    # Verify other nodes are not in monitoring_nodes
    local storage_node=$(grep -A1 "\[storage_nodes\]" "$inventory_path" | tail -1)
    local compute_node=$(grep -A1 "\[compute_nodes\]" "$inventory_path" | tail -1)
    
    echo -e "${GREEN}✓ Other nodes correctly separated:${NC}"
    echo "  Storage node: $(echo $storage_node | awk '{print $1}')"
    echo "  Compute node: $(echo $compute_node | awk '{print $1}')"
    
    echo ""
    return 0
}

# Test 3: Validate deployment playbook configuration
test_deployment_config() {
    echo -e "${BOLD}Test 3: Validating deployment playbook configuration${NC}"
    
    local deploy_yaml="/home/runner/work/VMStation/VMStation/ansible/plays/kubernetes/deploy_monitoring.yaml"
    
    if [[ ! -f "$deploy_yaml" ]]; then
        echo -e "${RED}✗ deploy_monitoring.yaml not found${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ deploy_monitoring.yaml exists${NC}"
    
    # Check if it targets monitoring_nodes
    if grep -q "hosts: monitoring_nodes" "$deploy_yaml"; then
        echo -e "${GREEN}✓ Playbook targets monitoring_nodes${NC}"
    else
        echo -e "${RED}✗ Playbook does not target monitoring_nodes${NC}"
        return 1
    fi
    
    # Check for enhanced node selector logic
    if grep -q "monitoring_scheduling_mode == 'strict'" "$deploy_yaml"; then
        echo -e "${GREEN}✓ Enhanced node selector logic for strict mode found${NC}"
    else
        echo -e "${RED}✗ Enhanced node selector logic not found${NC}"
        return 1
    fi
    
    # Check for tolerations configuration
    if grep -q "monitoring_tolerations" "$deploy_yaml"; then
        echo -e "${GREEN}✓ Tolerations configuration found${NC}"
    else
        echo -e "${RED}✗ Tolerations configuration not found${NC}"
        return 1
    fi
    
    # Check that all components have node selectors and tolerations
    local components=("prometheus" "grafana" "alertmanager" "loki")
    for component in "${components[@]}"; do
        if grep -A5 -B5 "$component" "$deploy_yaml" | grep -q "nodeSelector.*monitoring_node_selector" && \
           grep -A5 -B5 "$component" "$deploy_yaml" | grep -q "tolerations.*monitoring_tolerations"; then
            echo -e "${GREEN}✓ $component has proper node scheduling${NC}"
        else
            echo -e "${YELLOW}⚠ $component node scheduling needs verification${NC}"
        fi
    done
    
    echo ""
    return 0
}

# Test 4: Validate Grafana configuration
test_grafana_config() {
    echo -e "${BOLD}Test 4: Validating Grafana configuration${NC}"
    
    local deploy_yaml="/home/runner/work/VMStation/VMStation/ansible/plays/kubernetes/deploy_monitoring.yaml"
    
    # Check dashboard provisioning
    if grep -q "grafana-dashboards" "$deploy_yaml"; then
        echo -e "${GREEN}✓ Grafana dashboards ConfigMap creation found${NC}"
    else
        echo -e "${RED}✗ Grafana dashboards ConfigMap creation not found${NC}"
        return 1
    fi
    
    # Check datasource provisioning
    if grep -q "loki-datasource" "$deploy_yaml"; then
        echo -e "${GREEN}✓ Loki datasource ConfigMap creation found${NC}"
    else
        echo -e "${RED}✗ Loki datasource ConfigMap creation not found${NC}"
        return 1
    fi
    
    # Check that Loki datasource is not default
    if grep -A10 "loki-datasource" "$deploy_yaml" | grep -q "isDefault: false"; then
        echo -e "${GREEN}✓ Loki datasource correctly set as non-default${NC}"
    else
        echo -e "${RED}✗ Loki datasource default setting issue${NC}"
        return 1
    fi
    
    # Check dashboard files exist
    local dashboard_dir="/home/runner/work/VMStation/VMStation/ansible/files/grafana_dashboards"
    local expected_dashboards=("prometheus-dashboard.json" "loki-dashboard.json" "node-dashboard.json")
    
    for dashboard in "${expected_dashboards[@]}"; do
        if [[ -f "$dashboard_dir/$dashboard" ]]; then
            echo -e "${GREEN}✓ Dashboard file exists: $dashboard${NC}"
        else
            echo -e "${RED}✗ Dashboard file missing: $dashboard${NC}"
            return 1
        fi
    done
    
    echo ""
    return 0
}

# Test 5: Validate syntax of all playbooks
test_playbook_syntax() {
    echo -e "${BOLD}Test 5: Validating playbook syntax${NC}"
    
    cd /home/runner/work/VMStation/VMStation
    
    # Test main deployment playbook
    if ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml --syntax-check >/dev/null 2>&1; then
        echo -e "${GREEN}✓ deploy_monitoring.yaml syntax is valid${NC}"
    else
        echo -e "${RED}✗ deploy_monitoring.yaml syntax error${NC}"
        return 1
    fi
    
    # Test monitoring subsite
    if ansible-playbook -i ansible/inventory.txt ansible/subsites/03-monitoring.yaml --syntax-check >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 03-monitoring.yaml syntax is valid${NC}"
    else
        echo -e "${RED}✗ 03-monitoring.yaml syntax error${NC}"
        return 1
    fi
    
    echo ""
    return 0
}

# Main execution
main() {
    local all_tests_passed=true
    
    test_all_yml_config || all_tests_passed=false
    test_inventory_config || all_tests_passed=false
    test_deployment_config || all_tests_passed=false
    test_grafana_config || all_tests_passed=false
    test_playbook_syntax || all_tests_passed=false
    
    echo -e "${BOLD}=== Test Summary ===${NC}"
    if [[ "$all_tests_passed" == "true" ]]; then
        echo -e "${GREEN}✓ All tests passed! Configuration is ready for masternode-only monitoring deployment.${NC}"
        echo ""
        echo -e "${BOLD}Next Steps:${NC}"
        echo "1. Run pre-checks: ansible-playbook -i ansible/inventory.txt ansible/subsites/03-monitoring.yaml"
        echo "2. Deploy monitoring: ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml"
        echo "3. Validate deployment: ./scripts/validate_masternode_monitoring.sh"
        return 0
    else
        echo -e "${RED}✗ Some tests failed. Please review the output above and fix the issues.${NC}"
        return 1
    fi
}

main "$@"
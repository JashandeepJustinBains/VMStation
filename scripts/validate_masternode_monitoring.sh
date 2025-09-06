#!/bin/bash

# VMStation Monitoring Masternode Deployment Validation Script
# Validates that monitoring components are scheduled only on the masternode

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BOLD}=== VMStation Monitoring Masternode Validation ===${NC}"
echo "Timestamp: $(date)"
echo ""

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${RED}✗ kubectl not found${NC}"
        return 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ kubectl connection verified${NC}"
    return 0
}

# Function to check if monitoring namespace exists
check_monitoring_namespace() {
    if ! kubectl get namespace monitoring >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ monitoring namespace not found${NC}"
        return 1
    else
        echo -e "${GREEN}✓ monitoring namespace exists${NC}"
        return 0
    fi
}

# Function to validate node scheduling for monitoring pods
validate_node_scheduling() {
    echo ""
    echo -e "${BOLD}=== Validating Node Scheduling ===${NC}"
    
    # Get the masternode name from inventory
    local masternode="192.168.4.63"
    echo "Target masternode: $masternode"
    echo ""
    
    # Check if there are any monitoring pods running
    local monitoring_pods=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)
    if [[ $monitoring_pods -eq 0 ]]; then
        echo -e "${YELLOW}⚠ No monitoring pods found - monitoring stack may not be deployed yet${NC}"
        return 0
    fi
    
    echo "Found $monitoring_pods monitoring pods"
    echo ""
    
    # Check each monitoring component
    local components=("prometheus" "grafana" "alertmanager" "loki")
    local all_on_masternode=true
    
    for component in "${components[@]}"; do
        echo "Checking $component pods..."
        
        # Get pods for this component
        local component_pods=$(kubectl get pods -n monitoring -l "app.kubernetes.io/name=$component" --no-headers -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName 2>/dev/null || true)
        
        if [[ -z "$component_pods" ]]; then
            # Try alternative labels
            case $component in
                "prometheus")
                    component_pods=$(kubectl get pods -n monitoring -l "app.kubernetes.io/component=prometheus" --no-headers -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName 2>/dev/null || true)
                    ;;
                "grafana")
                    component_pods=$(kubectl get pods -n monitoring -l "app.kubernetes.io/name=grafana" --no-headers -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName 2>/dev/null || true)
                    ;;
                "alertmanager")
                    component_pods=$(kubectl get pods -n monitoring -l "app.kubernetes.io/name=alertmanager" --no-headers -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName 2>/dev/null || true)
                    ;;
                "loki")
                    component_pods=$(kubectl get pods -n monitoring -l "app=loki" --no-headers -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName 2>/dev/null || true)
                    ;;
            esac
        fi
        
        if [[ -n "$component_pods" ]]; then
            echo "$component_pods" | while read -r pod_name node_name; do
                if [[ "$node_name" == *"$masternode"* ]] || [[ "$node_name" == "192.168.4.63" ]]; then
                    echo -e "  ${GREEN}✓${NC} $pod_name is scheduled on masternode ($node_name)"
                else
                    echo -e "  ${RED}✗${NC} $pod_name is scheduled on wrong node ($node_name)"
                    all_on_masternode=false
                fi
            done
        else
            echo -e "  ${YELLOW}⚠${NC} No $component pods found"
        fi
        echo ""
    done
    
    return 0
}

# Function to validate Grafana dashboards
validate_grafana_dashboards() {
    echo ""
    echo -e "${BOLD}=== Validating Grafana Dashboards ===${NC}"
    
    # Check if dashboard ConfigMap exists
    if kubectl get configmap grafana-dashboards -n monitoring >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Grafana dashboards ConfigMap exists${NC}"
        
        # List dashboard files
        local dashboards=$(kubectl get configmap grafana-dashboards -n monitoring -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "Could not parse dashboard data")
        echo "Available dashboards: $dashboards"
    else
        echo -e "${RED}✗ Grafana dashboards ConfigMap not found${NC}"
    fi
}

# Function to validate Grafana datasources
validate_grafana_datasources() {
    echo ""
    echo -e "${BOLD}=== Validating Grafana Datasources ===${NC}"
    
    # Check if Loki datasource ConfigMap exists
    if kubectl get configmap loki-datasource -n monitoring >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Loki datasource ConfigMap exists${NC}"
        
        # Check that Loki datasource is not set as default
        local loki_default=$(kubectl get configmap loki-datasource -n monitoring -o jsonpath='{.data.loki-datasource\.yaml}' | grep -o 'isDefault: false' || echo "not found")
        if [[ "$loki_default" == "isDefault: false" ]]; then
            echo -e "${GREEN}✓ Loki datasource correctly configured as non-default${NC}"
        else
            echo -e "${YELLOW}⚠ Loki datasource default setting unclear${NC}"
        fi
    else
        echo -e "${RED}✗ Loki datasource ConfigMap not found${NC}"
    fi
    
    echo "Note: Prometheus datasource is automatically created by kube-prometheus-stack"
}

# Function to show monitoring pod distribution
show_pod_distribution() {
    echo ""
    echo -e "${BOLD}=== Monitoring Pod Distribution ===${NC}"
    
    kubectl get pods -n monitoring -o wide 2>/dev/null || echo "No monitoring pods found"
}

# Function to show node labels and taints
show_node_info() {
    echo ""
    echo -e "${BOLD}=== Node Information ===${NC}"
    
    echo "Node labels (monitoring-related):"
    kubectl get nodes --show-labels | grep -E "(NAME|monitoring|master|control-plane)" || echo "No relevant labels found"
    
    echo ""
    echo "Node taints:"
    kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints[*].key}{"\n"}{end}' | grep -v "^$" || echo "No taints found"
}

# Main execution
main() {
    if ! check_kubectl; then
        exit 1
    fi
    
    if ! check_monitoring_namespace; then
        echo "Run the monitoring deployment first: ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml"
        exit 1
    fi
    
    validate_node_scheduling
    validate_grafana_dashboards
    validate_grafana_datasources
    show_pod_distribution
    show_node_info
    
    echo ""
    echo -e "${BOLD}=== Validation Complete ===${NC}"
    echo "Check the output above for any issues with masternode-only scheduling"
}

main "$@"
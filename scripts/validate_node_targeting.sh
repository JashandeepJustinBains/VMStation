#!/bin/bash
# Runtime validation script for VMStation node targeting
# Verifies that pods are actually scheduled on the correct nodes in a running cluster

echo "=== VMStation Runtime Node Targeting Validation ==="

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please ensure Kubernetes is installed and configured.${NC}"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster. Please check kubeconfig.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Connected to Kubernetes cluster${NC}"
echo ""

# Show current node labels
echo -e "${BLUE}=== Current Node Labels ===${NC}"
kubectl get nodes --show-labels | grep -E "(NAME|node-role\.vmstation\.io/monitoring)" || kubectl get nodes -o wide

echo ""
echo -e "${BLUE}=== Pod Placement Validation ===${NC}"

# Function to check pod placement
check_pod_placement() {
    local namespace=$1
    local label_selector=$2
    local expected_node_pattern=$3
    local component_name=$4
    
    echo "Checking $component_name placement..."
    
    # Get pods with node information
    local pods_output
    pods_output=$(kubectl get pods -n "$namespace" -l "$label_selector" -o wide 2>/dev/null)
    
    if [ -z "$pods_output" ] || [ "$(echo "$pods_output" | wc -l)" -eq 1 ]; then
        echo -e "${YELLOW}⚠️  No $component_name pods found in namespace $namespace${NC}"
        return 0
    fi
    
    echo "$pods_output"
    
    # Check if any pods are on unexpected nodes
    local unexpected_nodes
    unexpected_nodes=$(echo "$pods_output" | grep -v "NAME" | grep -v "$expected_node_pattern" || true)
    
    if [ -n "$unexpected_nodes" ]; then
        echo -e "${RED}❌ $component_name pods found on unexpected nodes:${NC}"
        echo "$unexpected_nodes"
        return 1
    else
        echo -e "${GREEN}✅ All $component_name pods correctly placed${NC}"
        return 0
    fi
}

# Validation results
validation_errors=0

# Check monitoring components (should be on masternode/192.168.4.63)
echo -e "${BLUE}--- Monitoring Components ---${NC}"
if ! check_pod_placement "monitoring" "app.kubernetes.io/name=prometheus" "192\.168\.4\.63\|masternode" "Prometheus"; then
    ((validation_errors++))
fi

if ! check_pod_placement "monitoring" "app.kubernetes.io/name=grafana" "192\.168\.4\.63\|masternode" "Grafana"; then
    ((validation_errors++))
fi

if ! check_pod_placement "monitoring" "app=loki-stack" "192\.168\.4\.63\|masternode" "Loki"; then
    ((validation_errors++))
fi

if ! check_pod_placement "monitoring" "app.kubernetes.io/name=alertmanager" "192\.168\.4\.63\|masternode" "AlertManager"; then
    ((validation_errors++))
fi

# Check cert-manager components (should be on masternode/192.168.4.63)
echo -e "${BLUE}--- cert-manager Components ---${NC}"
if ! check_pod_placement "cert-manager" "app.kubernetes.io/name=cert-manager" "192\.168\.4\.63\|masternode" "cert-manager"; then
    ((validation_errors++))
fi

if ! check_pod_placement "cert-manager" "app.kubernetes.io/name=webhook" "192\.168\.4\.63\|masternode" "cert-manager-webhook"; then
    ((validation_errors++))
fi

if ! check_pod_placement "cert-manager" "app.kubernetes.io/name=cainjector" "192\.168\.4\.63\|masternode" "cert-manager-cainjector"; then
    ((validation_errors++))
fi

# Check Drone CI (should be on r430computenode/192.168.4.62)
echo -e "${BLUE}--- Drone CI ---${NC}"
if ! check_pod_placement "drone" "app=drone" "192\.168\.4\.62\|r430computenode" "Drone CI"; then
    ((validation_errors++))
fi

# Check Jellyfin (should be on storagenodet3500/192.168.4.61)
echo -e "${BLUE}--- Jellyfin ---${NC}"
if ! check_pod_placement "jellyfin" "app=jellyfin" "192\.168\.4\.61\|storagenodet3500" "Jellyfin"; then
    ((validation_errors++))
fi

# Summary
echo ""
echo -e "${BLUE}=== Validation Summary ===${NC}"

if [ $validation_errors -eq 0 ]; then
    echo -e "${GREEN}🎉 All components are correctly placed according to VMStation architecture!${NC}"
    echo ""
    echo "✅ Masternode (192.168.4.63): monitoring stack + cert-manager + control-plane"
    echo "✅ Compute node (192.168.4.62): Drone CI"  
    echo "✅ Storage node (192.168.4.61): Jellyfin"
    echo ""
    echo "The node targeting fix has been successfully applied."
else
    echo -e "${RED}❌ Found $validation_errors placement issues.${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Ensure node labels are properly set:"
    echo "   kubectl get nodes --show-labels | grep monitoring"
    echo ""
    echo "2. Re-run node labeling setup:"
    echo "   ./scripts/setup_monitoring_node_labels.sh"
    echo ""
    echo "3. Force pod rescheduling:"
    echo "   kubectl delete pods -n monitoring --all"
    echo "   kubectl delete pods -n cert-manager --all"
    echo "   kubectl delete pods -n drone --all"
    echo ""
    echo "4. Check for node taints that might prevent scheduling:"
    echo "   kubectl describe nodes"
    exit 1
fi
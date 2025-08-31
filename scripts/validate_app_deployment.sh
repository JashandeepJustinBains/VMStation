#!/bin/bash

# VMStation Extra Apps Deployment Validation Script
# Tests that kubernetes-dashboard, drone, and mongodb are deployed to correct nodes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BOLD}=== VMStation Extra Apps Deployment Validation ===${NC}"
echo "Timestamp: $(date)"
echo ""

# Expected node assignments based on deployment configuration
declare -A EXPECTED_NODES
EXPECTED_NODES["kubernetes-dashboard"]="masternode"
EXPECTED_NODES["drone"]="localhost.localdomain"
EXPECTED_NODES["mongodb"]="localhost.localdomain"

declare -A APP_NAMESPACES
APP_NAMESPACES["kubernetes-dashboard"]="kubernetes-dashboard"
APP_NAMESPACES["drone"]="drone"
APP_NAMESPACES["mongodb"]="mongodb"

# Function to check kubectl availability
check_kubectl() {
    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${RED}✗ kubectl not found${NC}"
        echo "Install kubectl and ensure it's configured to access your cluster"
        return 1
    fi
    
    echo -e "${GREEN}✓ kubectl available${NC}"
    return 0
}

# Function to validate app deployment
validate_app() {
    local app_name="$1"
    local namespace="${APP_NAMESPACES[$app_name]}"
    local expected_node="${EXPECTED_NODES[$app_name]}"
    
    echo -e "${BOLD}=== Checking $app_name ===${NC}"
    
    # Check if namespace exists
    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        echo -e "${RED}✗ $namespace namespace not found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ $namespace namespace exists${NC}"
    
    # Check if deployment exists
    if ! kubectl get deployment "$app_name" -n "$namespace" >/dev/null 2>&1; then
        echo -e "${RED}✗ $app_name deployment not found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ $app_name deployment exists${NC}"
    
    # Check pod status and node assignment
    local pod_info
    pod_info=$(kubectl get pods -n "$namespace" -l "app=$app_name" -o jsonpath='{.items[0].spec.nodeName},{.items[0].status.phase},{.items[0].metadata.name}' 2>/dev/null || echo ",,")
    
    IFS=',' read -r actual_node pod_phase pod_name <<< "$pod_info"
    
    if [ -z "$pod_name" ] || [ "$pod_name" = "" ]; then
        echo -e "${RED}✗ No $app_name pods found${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ $app_name pod found: $pod_name${NC}"
    
    # Check pod phase
    if [ "$pod_phase" != "Running" ]; then
        echo -e "${YELLOW}⚠ $app_name pod phase: $pod_phase (expected: Running)${NC}"
        
        # Get pod conditions for more details
        echo -e "${BLUE}Pod conditions:${NC}"
        kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.conditions[*].type}:{.status.conditions[*].status} ' 2>/dev/null || echo "Unable to get conditions"
        echo ""
    else
        echo -e "${GREEN}✓ $app_name pod is Running${NC}"
    fi
    
    # Check node assignment
    if [ "$actual_node" != "$expected_node" ]; then
        echo -e "${RED}✗ $app_name scheduled on wrong node${NC}"
        echo -e "   Expected: $expected_node"
        echo -e "   Actual: $actual_node"
        return 1
    else
        echo -e "${GREEN}✓ $app_name correctly scheduled on $expected_node${NC}"
    fi
    
    # Check service
    if kubectl get service "$app_name" -n "$namespace" >/dev/null 2>&1; then
        local nodeport
        nodeport=$(kubectl get service "$app_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
        echo -e "${GREEN}✓ $app_name service exists (NodePort: $nodeport)${NC}"
    else
        echo -e "${YELLOW}⚠ $app_name service not found${NC}"
    fi
    
    echo ""
    return 0
}

# Main execution
main() {
    # Check prerequisites
    if ! check_kubectl; then
        exit 1
    fi
    echo ""
    
    local issues=0
    
    # Validate each app
    for app in kubernetes-dashboard drone mongodb; do
        if ! validate_app "$app"; then
            ((issues++))
        fi
    done
    
    # Summary
    echo -e "${BOLD}=== Summary ===${NC}"
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}✓ All extra apps are correctly deployed and scheduled${NC}"
        echo ""
        echo -e "${BLUE}Access URLs:${NC}"
        echo "  - Kubernetes Dashboard: https://masternode:32000"
        echo "  - Drone CI: http://localhost.localdomain:32001"
        echo "  - MongoDB: localhost.localdomain:32002"
    else
        echo -e "${RED}✗ Found $issues deployment issues${NC}"
        echo ""
        echo -e "${BLUE}To fix issues:${NC}"
        echo "  1. Check deployment configuration: ansible/subsites/05-extra_apps.yaml"
        echo "  2. Redeploy apps: ansible-playbook -i inventory.txt ansible/subsites/05-extra_apps.yaml"
        echo "  3. Check pod logs: kubectl logs -n <namespace> -l app=<app-name>"
        exit 1
    fi
}

# Run main function
main "$@"
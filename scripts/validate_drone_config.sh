#!/bin/bash

# Drone Configuration Validation Script
# Tests drone deployment with GitHub integration and validates configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BOLD}=== VMStation Drone Configuration Validation ===${NC}"
echo "Timestamp: $(date)"
echo ""

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

# Function to check drone namespace and deployment
check_drone_deployment() {
    echo -e "${BOLD}=== Checking Drone Deployment ===${NC}"
    
    # Check if drone namespace exists
    if ! kubectl get namespace drone >/dev/null 2>&1; then
        echo -e "${RED}✗ drone namespace not found${NC}"
        echo "Create drone namespace or run: ansible-playbook -i inventory.txt ansible/subsites/05-extra_apps.yaml"
        return 1
    fi
    
    echo -e "${GREEN}✓ drone namespace exists${NC}"
    
    # Check drone deployment
    if ! kubectl get deployment drone -n drone >/dev/null 2>&1; then
        echo -e "${RED}✗ drone deployment not found${NC}"
        echo "Create drone deployment or run: ansible-playbook -i inventory.txt ansible/subsites/05-extra_apps.yaml"
        return 1
    fi
    
    echo -e "${GREEN}✓ drone deployment exists${NC}"
    
    # Check pod status
    local pod_status=$(kubectl get pods -n drone --no-headers | grep drone | awk '{print $3}' | head -n 1)
    echo "Current pod status: $pod_status"
    
    if [[ "$pod_status" == "Running" ]]; then
        echo -e "${GREEN}✓ drone pod is running${NC}"
        return 0
    elif [[ "$pod_status" == "CrashLoopBackOff" || "$pod_status" == "Error" ]]; then
        echo -e "${RED}✗ drone pod in failed state${NC}"
        return 1
    else
        echo -e "${YELLOW}⚠ drone pod status: $pod_status${NC}"
        return 1
    fi
}

# Function to check drone secrets
check_drone_secrets() {
    echo -e "${BOLD}=== Checking Drone Secrets ===${NC}"
    
    if ! kubectl get secret drone-secrets -n drone >/dev/null 2>&1; then
        echo -e "${RED}✗ drone-secrets not found${NC}"
        echo "Create secrets or run: ansible-playbook -i inventory.txt ansible/subsites/05-extra_apps.yaml"
        return 1
    fi
    
    echo -e "${GREEN}✓ drone-secrets exists${NC}"
    
    # Check secret keys
    local secret_keys=$(kubectl get secret drone-secrets -n drone -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "")
    
    if [[ -z "$secret_keys" ]]; then
        echo -e "${YELLOW}⚠ Cannot read secret keys (this is normal for security)${NC}"
    else
        echo "Secret keys found:"
        echo "$secret_keys" | sed 's/^/  - /'
    fi
    
    # Check for required keys
    local required_keys=("rpc-secret" "github-client-id" "github-client-secret" "server-host")
    local missing_keys=()
    
    for key in "${required_keys[@]}"; do
        if kubectl get secret drone-secrets -n drone -o jsonpath="{.data.$key}" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ $key present${NC}"
        else
            echo -e "${RED}✗ $key missing${NC}"
            missing_keys+=("$key")
        fi
    done
    
    if [[ ${#missing_keys[@]} -gt 0 ]]; then
        echo ""
        echo "Missing keys: ${missing_keys[*]}"
        return 1
    fi
    
    return 0
}

# Function to check drone logs for configuration issues
check_drone_logs() {
    echo -e "${BOLD}=== Analyzing Drone Logs ===${NC}"
    
    local drone_pod=$(kubectl get pods -n drone --no-headers | grep drone | awk '{print $1}' | head -n 1)
    
    if [[ -z "$drone_pod" ]]; then
        echo -e "${RED}✗ No drone pod found${NC}"
        return 1
    fi
    
    echo "Checking logs for pod: $drone_pod"
    echo ""
    
    # Get recent logs
    local logs=$(kubectl logs $drone_pod -n drone --tail=50 2>/dev/null || echo "")
    
    if [[ -z "$logs" ]]; then
        echo "No logs available"
        return 0
    fi
    
    # Check for common issues
    echo -e "${BLUE}Log Analysis:${NC}"
    
    if echo "$logs" | grep -q "github.*client.*id"; then
        echo -e "${GREEN}✓ GitHub client ID configuration detected${NC}"
    else
        echo -e "${YELLOW}⚠ No GitHub client ID configuration found${NC}"
    fi
    
    if echo "$logs" | grep -q "database.*sqlite"; then
        echo -e "${GREEN}✓ SQLite database configuration detected${NC}"
    else
        echo -e "${YELLOW}⚠ No database configuration found${NC}"
    fi
    
    if echo "$logs" | grep -qi "error\|fail\|crash"; then
        echo -e "${RED}✗ Errors found in logs:${NC}"
        echo "$logs" | grep -i "error\|fail\|crash" | head -5 | sed 's/^/  /'
        return 1
    else
        echo -e "${GREEN}✓ No obvious errors in recent logs${NC}"
    fi
    
    return 0
}

# Function to test drone service connectivity
test_drone_service() {
    echo -e "${BOLD}=== Testing Drone Service ===${NC}"
    
    # Get service details
    local service_info=$(kubectl get service drone -n drone -o jsonpath='{.spec.type}:{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
    
    if [[ -z "$service_info" ]]; then
        echo -e "${RED}✗ drone service not found${NC}"
        return 1
    fi
    
    echo "Service type and port: $service_info"
    
    # Get node IP
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")
    
    if [[ -n "$node_ip" ]]; then
        local node_port=$(echo "$service_info" | cut -d: -f2)
        echo "Testing connectivity to: http://$node_ip:$node_port"
        
        # Simple connectivity test
        if curl -f -s -o /dev/null --max-time 10 "http://$node_ip:$node_port" 2>/dev/null; then
            echo -e "${GREEN}✓ Drone service is accessible${NC}"
        else
            echo -e "${YELLOW}⚠ Drone service not accessible (may be starting up)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Cannot determine node IP for testing${NC}"
    fi
}

# Function to provide configuration recommendations
provide_recommendations() {
    echo -e "${BOLD}=== Configuration Recommendations ===${NC}"
    echo ""
    
    echo -e "${BLUE}1. GitHub OAuth Application Setup:${NC}"
    echo "   Visit: https://github.com/settings/applications/new"
    echo "   - Application name: VMStation Drone CI"
    echo "   - Homepage URL: http://your-node-ip:32001"
    echo "   - Authorization callback URL: http://your-node-ip:32001/login"
    echo ""
    
    echo -e "${BLUE}2. Update secrets with real values:${NC}"
    echo "   ansible-vault edit ansible/group_vars/secrets.yml"
    echo "   # Add your GitHub OAuth client ID and secret"
    echo ""
    
    echo -e "${BLUE}3. Generate RPC secret:${NC}"
    echo "   openssl rand -hex 16"
    echo "   # Add to secrets.yml as drone_rpc_secret"
    echo ""
    
    echo -e "${BLUE}4. Redeploy with updated secrets:${NC}"
    echo "   ansible-playbook -i inventory.txt ansible/subsites/05-extra_apps.yaml --ask-vault-pass"
    echo ""
    
    echo -e "${BLUE}5. Verification commands:${NC}"
    echo "   kubectl get pods -n drone"
    echo "   kubectl logs -n drone -l app=drone"
    echo "   curl -I http://NODE_IP:32001"
}

# Main execution flow
main() {
    # Check prerequisites
    check_kubectl
    echo ""
    
    local issues=0
    
    # Run checks
    if ! check_drone_deployment; then
        ((issues++))
    fi
    echo ""
    
    if ! check_drone_secrets; then
        ((issues++))
    fi
    echo ""
    
    if ! check_drone_logs; then
        ((issues++))
    fi
    echo ""
    
    test_drone_service
    echo ""
    
    # Summary
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}✓ Drone configuration validation passed${NC}"
        echo ""
        echo "Drone should be accessible at NodePort 32001"
        echo "If you're still experiencing issues, check GitHub OAuth configuration"
    else
        echo -e "${RED}✗ Found $issues configuration issues${NC}"
        echo ""
        provide_recommendations
    fi
}

# Run main function
main "$@"
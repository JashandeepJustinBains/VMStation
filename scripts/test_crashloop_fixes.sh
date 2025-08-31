#!/bin/bash

# VMStation CrashLoopBackOff Fix Integration Test
# Tests both drone and dashboard fixes end-to-end

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BOLD}=== VMStation CrashLoopBackOff Fix Integration Test ===${NC}"
echo "Timestamp: $(date)"
echo ""

# Test mode flag
DRY_RUN="yes"
if [[ "$1" == "--apply" ]]; then
    DRY_RUN="no"
    echo -e "${YELLOW}⚠️  APPLY mode enabled - changes will be made to cluster${NC}"
else
    echo -e "${BLUE}ℹ️  DRY RUN mode - use --apply to make actual changes${NC}"
fi
echo ""

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BOLD}=== Checking Prerequisites ===${NC}"
    
    local issues=0
    
    # Check kubectl
    if command -v kubectl >/dev/null 2>&1; then
        echo -e "${GREEN}✓ kubectl available${NC}"
    else
        echo -e "${RED}✗ kubectl not found${NC}"
        ((issues++))
    fi
    
    # Check ansible
    if command -v ansible-playbook >/dev/null 2>&1; then
        echo -e "${GREEN}✓ ansible-playbook available${NC}"
    else
        echo -e "${RED}✗ ansible-playbook not found${NC}"
        ((issues++))
    fi
    
    # Check if cluster is accessible
    if kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Kubernetes cluster accessible${NC}"
    else
        echo -e "${RED}✗ Cannot access Kubernetes cluster${NC}"
        ((issues++))
    fi
    
    # Check for required files
    local required_files=(
        "ansible/subsites/05-extra_apps.yaml"
        "scripts/validate_drone_config.sh"
        "scripts/fix_k8s_dashboard_permissions.sh"
        "scripts/diagnose_monitoring_permissions.sh"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            echo -e "${GREEN}✓ $file exists${NC}"
        else
            echo -e "${RED}✗ $file missing${NC}"
            ((issues++))
        fi
    done
    
    return $issues
}

# Function to test current cluster state
test_current_state() {
    echo -e "${BOLD}=== Testing Current Cluster State ===${NC}"
    
    # Check for CrashLoopBackOff pods
    local crashloop_pods=$(kubectl get pods -A --no-headers 2>/dev/null | grep -E "(CrashLoopBackOff|Init:CrashLoopBackOff)" | wc -l || echo "0")
    
    echo "CrashLoopBackOff pods found: $crashloop_pods"
    
    if [[ "$crashloop_pods" -gt 0 ]]; then
        echo -e "${YELLOW}CrashLoopBackOff pods detected:${NC}"
        kubectl get pods -A --no-headers | grep -E "(CrashLoopBackOff|Init:CrashLoopBackOff)" | sed 's/^/  /'
        return 1
    else
        echo -e "${GREEN}✓ No CrashLoopBackOff pods found${NC}"
        return 0
    fi
}

# Function to test drone configuration
test_drone_configuration() {
    echo -e "${BOLD}=== Testing Drone Configuration ===${NC}"
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "DRY RUN: Would validate drone configuration"
        echo "Command: ./scripts/validate_drone_config.sh"
        return 0
    else
        ./scripts/validate_drone_config.sh
        return $?
    fi
}

# Function to test dashboard configuration
test_dashboard_configuration() {
    echo -e "${BOLD}=== Testing Dashboard Configuration ===${NC}"
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "DRY RUN: Would check dashboard permissions"
        echo "Command: ./scripts/fix_k8s_dashboard_permissions.sh"
        return 0
    else
        ./scripts/fix_k8s_dashboard_permissions.sh
        return $?
    fi
}

# Function to apply fixes
apply_fixes() {
    echo -e "${BOLD}=== Applying Fixes ===${NC}"
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "DRY RUN: Would apply the following fixes:"
        echo ""
        echo "1. Deploy updated drone configuration:"
        echo "   ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml --check"
        echo ""
        echo "2. Fix dashboard permissions:"
        echo "   ./scripts/fix_k8s_dashboard_permissions.sh --auto-approve"
        echo ""
        echo "3. Run diagnostic checks:"
        echo "   ./scripts/diagnose_monitoring_permissions.sh"
        return 0
    else
        echo "Applying fixes..."
        echo ""
        
        # Deploy updated configuration
        echo -e "${BLUE}1. Deploying updated drone configuration...${NC}"
        if ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml; then
            echo -e "${GREEN}✓ Deployment successful${NC}"
        else
            echo -e "${RED}✗ Deployment failed${NC}"
            return 1
        fi
        
        echo ""
        
        # Fix dashboard permissions
        echo -e "${BLUE}2. Fixing dashboard permissions...${NC}"
        if ./scripts/fix_k8s_dashboard_permissions.sh --auto-approve; then
            echo -e "${GREEN}✓ Dashboard permission fix applied${NC}"
        else
            echo -e "${YELLOW}⚠ Dashboard permission fix had issues (check output above)${NC}"
        fi
        
        echo ""
        
        # Run diagnostics
        echo -e "${BLUE}3. Running diagnostic checks...${NC}"
        ./scripts/diagnose_monitoring_permissions.sh
        
        return 0
    fi
}

# Function to verify fixes
verify_fixes() {
    echo -e "${BOLD}=== Verifying Fixes ===${NC}"
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "DRY RUN: Would verify fixes with:"
        echo "  - kubectl get pods -A | grep -E '(drone|dashboard)'"
        echo "  - ./scripts/validate_drone_config.sh"
        echo "  - Connectivity tests"
        return 0
    fi
    
    echo "Waiting 30 seconds for pods to start..."
    sleep 30
    
    # Check pod status
    echo -e "${BLUE}Checking pod status:${NC}"
    kubectl get pods -n drone 2>/dev/null || echo "No drone namespace"
    kubectl get pods -n kubernetes-dashboard 2>/dev/null || echo "No kubernetes-dashboard namespace"
    
    echo ""
    
    # Run validation
    echo -e "${BLUE}Running validation:${NC}"
    ./scripts/validate_drone_config.sh
    
    echo ""
    
    # Final CrashLoopBackOff check
    local final_crashloop=$(kubectl get pods -A --no-headers 2>/dev/null | grep -E "(CrashLoopBackOff|Init:CrashLoopBackOff)" | wc -l || echo "0")
    
    if [[ "$final_crashloop" -eq 0 ]]; then
        echo -e "${GREEN}✓ SUCCESS: No CrashLoopBackOff pods found${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ WARNING: $final_crashloop CrashLoopBackOff pods still present${NC}"
        kubectl get pods -A --no-headers | grep -E "(CrashLoopBackOff|Init:CrashLoopBackOff)" | sed 's/^/  /'
        return 1
    fi
}

# Main execution flow
main() {
    local issues=0
    
    # Check prerequisites
    if ! check_prerequisites; then
        echo -e "${RED}✗ Prerequisites check failed${NC}"
        exit 1
    fi
    echo ""
    
    # Test current state
    echo -e "${BLUE}Testing current state...${NC}"
    if ! test_current_state; then
        echo -e "${YELLOW}⚠ CrashLoopBackOff pods detected - fixes needed${NC}"
        ((issues++))
    fi
    echo ""
    
    # Test configurations
    if ! test_drone_configuration; then
        echo -e "${YELLOW}⚠ Drone configuration issues detected${NC}"
        ((issues++))
    fi
    echo ""
    
    if ! test_dashboard_configuration; then
        echo -e "${YELLOW}⚠ Dashboard configuration issues detected${NC}"
        ((issues++))
    fi
    echo ""
    
    # Apply fixes if needed
    if [[ $issues -gt 0 ]] || [[ "$DRY_RUN" == "yes" ]]; then
        apply_fixes
        echo ""
        
        # Verify fixes (only in apply mode)
        if [[ "$DRY_RUN" == "no" ]]; then
            verify_fixes
        fi
    else
        echo -e "${GREEN}✓ No issues detected - no fixes needed${NC}"
    fi
    
    echo ""
    echo -e "${BOLD}=== Integration Test Complete ===${NC}"
    
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo ""
        echo -e "${BLUE}To apply fixes, run: $0 --apply${NC}"
    fi
}

# Run main function
main "$@"
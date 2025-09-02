#!/bin/bash

# Monitoring Scheduling Fix Script
# Automatically fixes Kubernetes scheduling constraints for monitoring pods
# Handles pending pods due to node selectors, taints, and resource constraints

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BOLD}=== VMStation Monitoring Scheduling Fix ===${NC}"
echo "Timestamp: $(date)"
echo ""

# Function to check if kubectl is available and cluster is accessible
check_kubectl() {
    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${RED}✗ kubectl not found. Skipping Kubernetes scheduling fixes.${NC}"
        return 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}✗ Cannot connect to Kubernetes cluster. Skipping scheduling fixes.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ kubectl connection verified${NC}"
    return 0
}

# Function to check if monitoring namespace exists
check_monitoring_namespace() {
    if ! kubectl get namespace monitoring >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ monitoring namespace not found, creating it...${NC}"
        kubectl create namespace monitoring
        echo -e "${GREEN}✓ monitoring namespace created${NC}"
    else
        echo -e "${GREEN}✓ monitoring namespace exists${NC}"
    fi
}

# Function to analyze and fix pending monitoring pods
fix_pending_monitoring_pods() {
    echo ""
    echo -e "${BOLD}=== Analyzing Pending Monitoring Pods ===${NC}"
    
    # Check for pending monitoring pods
    local pending_pods=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -E "Pending" || true)
    
    if [[ -z "$pending_pods" ]]; then
        echo -e "${GREEN}✓ No pending monitoring pods found${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}⚠ Found pending monitoring pods:${NC}"
    echo "$pending_pods"
    echo ""
    
    # Get detailed scheduling information
    local first_pending_pod=$(echo "$pending_pods" | head -1 | awk '{print $1}')
    echo "Analyzing scheduling constraints for: $first_pending_pod"
    
    # Check for common scheduling issues
    local pod_events=$(kubectl describe pod -n monitoring "$first_pending_pod" 2>/dev/null | grep -A 10 "Events:" || true)
    
    echo ""
    echo -e "${BLUE}Pod events:${NC}"
    echo "$pod_events"
    echo ""
    
    # Fix common scheduling issues
    fix_node_taints
    fix_node_labels
    fix_scheduling_mode
    
    # Wait for pods to reschedule
    echo ""
    echo -e "${BLUE}Waiting for pods to reschedule...${NC}"
    sleep 10
    
    # Check if fix was successful
    local remaining_pending=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -E "Pending" || true)
    if [[ -z "$remaining_pending" ]]; then
        echo -e "${GREEN}✓ All monitoring pods successfully scheduled${NC}"
    else
        echo -e "${YELLOW}⚠ Some pods still pending after fixes. Manual intervention may be required.${NC}"
        echo "$remaining_pending"
    fi
}

# Function to remove node taints that prevent scheduling
fix_node_taints() {
    echo -e "${BOLD}=== Checking Node Taints ===${NC}"
    
    # Check if any nodes have control-plane taints
    local tainted_nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")].effect}{"\n"}{end}' 2>/dev/null | grep -v "^$" || true)
    
    if [[ -n "$tainted_nodes" ]]; then
        echo -e "${YELLOW}⚠ Found nodes with control-plane taints:${NC}"
        echo "$tainted_nodes"
        echo ""
        
        # For single-node clusters or when all nodes are tainted, remove the taints
        local total_nodes=$(kubectl get nodes --no-headers | wc -l)
        local tainted_count=$(echo "$tainted_nodes" | wc -l)
        
        if [[ $tainted_count -eq $total_nodes ]] || [[ $total_nodes -eq 1 ]]; then
            echo -e "${BLUE}Removing control-plane taints (single-node cluster or all nodes tainted)...${NC}"
            
            kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
            kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule- 2>/dev/null || true
            
            echo -e "${GREEN}✓ Control-plane taints removed${NC}"
        else
            echo -e "${BLUE}Multiple nodes available, keeping control-plane taints intact${NC}"
        fi
    else
        echo -e "${GREEN}✓ No problematic node taints found${NC}"
    fi
}

# Function to ensure nodes have monitoring labels
fix_node_labels() {
    echo ""
    echo -e "${BOLD}=== Checking Node Labels ===${NC}"
    
    # Check if any nodes have the monitoring label
    local labeled_nodes=$(kubectl get nodes -l node-role.vmstation.io/monitoring=true --no-headers 2>/dev/null | wc -l)
    
    if [[ $labeled_nodes -eq 0 ]]; then
        echo -e "${YELLOW}⚠ No nodes labeled for monitoring workloads${NC}"
        
        # Get all available nodes
        local available_nodes=$(kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name,READY:.status.conditions[?@.type==\"Ready\"].status | grep " True" | awk '{print $1}')
        
        if [[ -n "$available_nodes" ]]; then
            echo -e "${BLUE}Labeling available nodes for monitoring workloads...${NC}"
            
            # Label all ready nodes for monitoring
            while read -r node; do
                if [[ -n "$node" ]]; then
                    kubectl label node "$node" node-role.vmstation.io/monitoring=true --overwrite 2>/dev/null || true
                    echo "  ✓ Labeled node: $node"
                fi
            done <<< "$available_nodes"
            
            echo -e "${GREEN}✓ Nodes labeled for monitoring workloads${NC}"
        else
            echo -e "${RED}✗ No ready nodes available for labeling${NC}"
        fi
    else
        echo -e "${GREEN}✓ Found $labeled_nodes nodes labeled for monitoring${NC}"
    fi
}

# Function to apply unrestricted scheduling if needed
fix_scheduling_mode() {
    echo ""
    echo -e "${BOLD}=== Checking Scheduling Mode Configuration ===${NC}"
    
    # Check if we still have pending pods after taint/label fixes
    local remaining_pending=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -E "Pending" || true)
    
    if [[ -n "$remaining_pending" ]]; then
        echo -e "${YELLOW}⚠ Pods still pending after taint/label fixes${NC}"
        echo -e "${BLUE}Applying unrestricted scheduling mode...${NC}"
        
        # Remove node selectors from Grafana deployment
        kubectl patch deployment kube-prometheus-stack-grafana -n monitoring -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}' 2>/dev/null || true
        
        # Remove node selectors from Prometheus StatefulSet
        kubectl patch statefulset prometheus-kube-prometheus-stack-prometheus -n monitoring -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}' 2>/dev/null || true
        
        # Remove node selectors from AlertManager StatefulSet
        kubectl patch statefulset alertmanager-kube-prometheus-stack-alertmanager -n monitoring -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}' 2>/dev/null || true
        
        # Remove node selectors from Loki StatefulSet
        kubectl patch statefulset loki-stack -n monitoring -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}' 2>/dev/null || true
        
        echo -e "${GREEN}✓ Applied unrestricted scheduling mode${NC}"
    else
        echo -e "${GREEN}✓ No additional scheduling fixes needed${NC}"
    fi
}

# Function to verify monitoring pods are running
verify_monitoring_pods() {
    echo ""
    echo -e "${BOLD}=== Final Verification ===${NC}"
    
    echo "Current monitoring pod status:"
    kubectl get pods -n monitoring -o wide 2>/dev/null || echo "No pods found in monitoring namespace"
    
    echo ""
    local failed_pods=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -E "(Pending|CrashLoopBackOff|Init:CrashLoopBackOff)" || true)
    
    if [[ -z "$failed_pods" ]]; then
        echo -e "${GREEN}✅ All monitoring pods are scheduled and running${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ Some monitoring pods still have issues:${NC}"
        echo "$failed_pods"
        echo ""
        echo -e "${BLUE}Additional troubleshooting may be required. Consider running:${NC}"
        echo "  ./scripts/fix_k8s_monitoring_pods.sh --auto-approve"
        echo "  ./scripts/fix_monitoring_permissions.sh"
        return 1
    fi
}

# Main execution flow
main() {
    # Check prerequisites
    if ! check_kubectl; then
        exit 0  # Not an error, just skip Kubernetes fixes
    fi
    
    # Ensure monitoring namespace exists
    check_monitoring_namespace
    
    # Fix pending monitoring pods
    fix_pending_monitoring_pods
    
    # Verify final state
    verify_monitoring_pods
    
    echo ""
    echo -e "${BOLD}=== Monitoring Scheduling Fix Complete ===${NC}"
}

# Run main function
main "$@"
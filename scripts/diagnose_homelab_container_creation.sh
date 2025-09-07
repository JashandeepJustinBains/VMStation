#!/bin/bash

# Homelab Node Container Creation Diagnostics
# This script helps diagnose why pods are stuck in ContainerCreating state on the homelab node

echo "=== VMStation Homelab Node Container Creation Diagnostics ==="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster.${NC}"
    echo "Please verify:"
    echo "1. Cluster is running"
    echo "2. kubectl is properly configured"
    echo "3. Current context points to correct cluster"
    exit 1
fi

echo -e "${GREEN}✅ Connected to Kubernetes cluster${NC}"
echo ""

# Function to check node status
check_node_status() {
    echo -e "${BOLD}=== Node Status Check ===${NC}"
    
    # Get homelab node details
    local homelab_node_info
    homelab_node_info=$(kubectl get nodes homelab -o wide 2>/dev/null || echo "")
    
    if [[ -z "$homelab_node_info" ]]; then
        echo -e "${RED}❌ Homelab node not found in cluster${NC}"
        echo "Available nodes:"
        kubectl get nodes -o wide
        return 1
    fi
    
    echo "Homelab node details:"
    echo "$homelab_node_info"
    echo ""
    
    # Check node conditions
    echo "Node conditions:"
    kubectl describe node homelab | grep -A 10 "Conditions:" | head -15
    echo ""
    
    # Check node taints
    echo "Node taints:"
    local taints
    taints=$(kubectl describe node homelab | grep "Taints:" | head -1)
    if [[ "$taints" == *"<none>"* ]]; then
        echo -e "${GREEN}✓ No taints on homelab node${NC}"
    else
        echo -e "${YELLOW}⚠ Taints found:${NC}"
        echo "$taints"
    fi
    echo ""
}

# Function to check CNI status
check_cni_status() {
    echo -e "${BOLD}=== CNI Network Status ===${NC}"
    
    # Check flannel pods
    echo "Flannel pods on homelab node:"
    local flannel_pods
    flannel_pods=$(kubectl get pods -n kube-flannel -o wide | grep homelab || echo "None found")
    echo "$flannel_pods"
    echo ""
    
    # Check if CNI is working by looking for network attachments
    echo "Network attachments on homelab:"
    kubectl get nodes homelab -o jsonpath='{.status.addresses}' | python3 -m json.tool 2>/dev/null || echo "Could not parse node addresses"
    echo ""
}

# Function to check pods stuck in ContainerCreating
check_container_creating_pods() {
    echo -e "${BOLD}=== ContainerCreating Pods Analysis ===${NC}"
    
    # Find all pods stuck in ContainerCreating on homelab
    local stuck_pods
    stuck_pods=$(kubectl get pods --all-namespaces -o wide | grep "homelab.*ContainerCreating" || echo "")
    
    if [[ -z "$stuck_pods" ]]; then
        echo -e "${GREEN}✓ No pods stuck in ContainerCreating state on homelab${NC}"
        return 0
    fi
    
    echo -e "${RED}❌ Found pods stuck in ContainerCreating:${NC}"
    echo "$stuck_pods"
    echo ""
    
    # Analyze the first stuck pod
    local first_pod_line
    first_pod_line=$(echo "$stuck_pods" | head -1)
    local namespace
    local pod_name
    namespace=$(echo "$first_pod_line" | awk '{print $1}')
    pod_name=$(echo "$first_pod_line" | awk '{print $2}')
    
    if [[ -n "$namespace" && -n "$pod_name" ]]; then
        echo "Analyzing pod: $namespace/$pod_name"
        echo ""
        
        echo "Pod events:"
        kubectl describe pod "$pod_name" -n "$namespace" | grep -A 20 "Events:" | head -25
        echo ""
        
        echo "Pod conditions:"
        kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.conditions}' | python3 -m json.tool 2>/dev/null || echo "Could not parse conditions"
        echo ""
    fi
}

# Function to check storage issues
check_storage_issues() {
    echo -e "${BOLD}=== Storage Configuration ===${NC}"
    
    # Check if hostPaths exist
    echo "Checking common hostPath directories on homelab node..."
    
    # Note: We can't directly access the node filesystem from kubectl
    # But we can check if storage classes are available
    echo "Available storage classes:"
    kubectl get storageclass
    echo ""
    
    # Check PVs that might be bound to homelab hostPaths
    echo "Persistent Volumes (looking for hostPath types):"
    kubectl get pv -o wide | grep -E "hostPath|local" || echo "No hostPath or local PVs found"
    echo ""
}

# Function to provide troubleshooting recommendations
provide_recommendations() {
    echo -e "${BOLD}=== Troubleshooting Recommendations ===${NC}"
    
    echo "Based on this analysis, try these steps:"
    echo ""
    
    echo "1. Check container runtime on homelab node:"
    echo "   # SSH to homelab node and run:"
    echo "   sudo systemctl status docker     # for Docker"
    echo "   sudo systemctl status containerd # for containerd"
    echo "   sudo systemctl status crio       # for CRI-O"
    echo ""
    
    echo "2. Check kubelet status on homelab node:"
    echo "   # SSH to homelab node and run:"
    echo "   sudo systemctl status kubelet"
    echo "   sudo journalctl -u kubelet --since '10 minutes ago'"
    echo ""
    
    echo "3. Check network connectivity:"
    echo "   # From homelab node, test cluster DNS:"
    echo "   nslookup kubernetes.default.svc.cluster.local"
    echo ""
    
    echo "4. Check if hostPath directories exist and have correct permissions:"
    echo "   # SSH to homelab node and run:"
    echo "   sudo ls -la /mnt/storage/"
    echo "   sudo mkdir -p /mnt/storage/drone"
    echo "   sudo chown -R 1000:1000 /mnt/storage/drone"
    echo ""
    
    echo "5. Restart kubelet if needed:"
    echo "   # SSH to homelab node and run:"
    echo "   sudo systemctl restart kubelet"
    echo ""
    
    echo "6. Check for disk space issues:"
    echo "   # SSH to homelab node and run:"
    echo "   df -h"
    echo "   sudo docker system df  # if using Docker"
    echo ""
}

# Main execution
main() {
    check_node_status
    check_cni_status
    check_container_creating_pods
    check_storage_issues
    provide_recommendations
    
    echo -e "${BOLD}=== Diagnostic Complete ===${NC}"
    echo ""
    echo "For the specific drone-hostpath-init pod issue, ensure:"
    echo "1. The node name 'homelab' matches the actual cluster node"
    echo "2. The node can schedule pods (no blocking taints)"
    echo "3. Container runtime is working properly"
    echo "4. Network connectivity is established"
    echo ""
    echo "Run this script again after applying fixes to verify improvements."
}

# Run the main function
main
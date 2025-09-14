#!/bin/bash

# VMStation Network Prerequisites Validation
# Validates network configuration before deploying Jellyfin and other pods
# Prevents common CNI bridge conflicts and mixed OS compatibility issues

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

echo "=== VMStation Network Prerequisites Validation ==="
echo "Timestamp: $(date)"
echo "Purpose: Validate network configuration before pod deployment"
echo

# Check if we have kubectl access
if ! timeout 30 kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    echo "Please ensure this script is run from the control plane node"
    exit 1
fi

# Function to check CNI bridge configuration
check_cni_bridge() {
    info "Step 1: Checking CNI bridge configuration"
    
    # Check for specific CNI bridge conflict errors in recent events
    CNI_BRIDGE_ERRORS=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' 2>/dev/null | \
        grep -i "failed to set bridge addr.*cni0.*already has an IP address different from" | wc -l)
    
    if [ "$CNI_BRIDGE_ERRORS" -gt 0 ]; then
        error "✗ Detected CNI bridge IP conflicts in recent events"
        warn "Error pattern: 'cni0 already has an IP address different from 10.244.x.x/xx'"
        warn "This is exactly the issue preventing pod creation"
        echo "Recent CNI bridge errors:"
        kubectl get events --all-namespaces --sort-by='.lastTimestamp' 2>/dev/null | \
            grep -i "failed to set bridge addr.*cni0" | tail -3
        echo
        warn "SOLUTION: Run 'sudo ./scripts/reset_cni_bridge.sh' to fix this issue"
        return 1
    fi
    
    if ip addr show cni0 >/dev/null 2>&1; then
        CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
        info "Current cni0 bridge IP: $CNI_IP"
        
        if echo "$CNI_IP" | grep -q "10.244."; then
            info "✓ cni0 bridge has correct Flannel subnet IP"
            return 0
        else
            warn "✗ cni0 bridge IP ($CNI_IP) is not in Flannel subnet (10.244.0.0/16)"
            warn "This will cause pod IP assignment failures"
            warn "SOLUTION: Run 'sudo ./scripts/reset_cni_bridge.sh' to fix this issue"
            return 1
        fi
    else
        info "cni0 bridge not found - will be created by CNI plugin"
        return 0
    fi
}

# Function to check node network readiness
check_node_readiness() {
    info "Step 2: Checking node network readiness"
    
    # Get node status
    kubectl get nodes -o wide
    echo
    
    # Check for NotReady nodes
    NOT_READY_NODES=$(kubectl get nodes --no-headers | grep "NotReady" | wc -l)
    if [ "$NOT_READY_NODES" -gt 0 ]; then
        warn "Found $NOT_READY_NODES NotReady nodes"
        kubectl get nodes --no-headers | grep "NotReady" | while read line; do
            NODE_NAME=$(echo "$line" | awk '{print $1}')
            warn "NotReady node: $NODE_NAME"
        done
        return 1
    else
        info "✓ All nodes are Ready"
        return 0
    fi
}

# Function to check flannel pod status
check_flannel_status() {
    info "Step 3: Checking Flannel CNI plugin status"
    
    # Check if flannel namespace exists
    if ! kubectl get namespace kube-flannel >/dev/null 2>&1; then
        warn "kube-flannel namespace not found"
        return 1
    fi
    
    # Check flannel pod status
    FLANNEL_PODS=$(kubectl get pods -n kube-flannel -l app=flannel --no-headers 2>/dev/null | wc -l)
    FLANNEL_RUNNING=$(kubectl get pods -n kube-flannel -l app=flannel --no-headers 2>/dev/null | grep "Running" | wc -l)
    FLANNEL_CRASHLOOP=$(kubectl get pods -n kube-flannel -l app=flannel --no-headers 2>/dev/null | grep "CrashLoopBackOff" | wc -l)
    
    info "Flannel pods: $FLANNEL_RUNNING/$FLANNEL_PODS running"
    
    if [ "$FLANNEL_CRASHLOOP" -gt 0 ]; then
        warn "✗ Found $FLANNEL_CRASHLOOP flannel pods in CrashLoopBackOff"
        kubectl get pods -n kube-flannel -l app=flannel -o wide
        return 1
    elif [ "$FLANNEL_RUNNING" -eq "$FLANNEL_PODS" ] && [ "$FLANNEL_PODS" -gt 0 ]; then
        info "✓ All flannel pods are running"
        return 0
    else
        warn "✗ Flannel pods not all running: $FLANNEL_RUNNING/$FLANNEL_PODS"
        return 1
    fi
}

# Function to check kube-proxy status
check_kube_proxy_status() {
    info "Step 4: Checking kube-proxy status"
    
    PROXY_PODS=$(kubectl get pods -n kube-system -l component=kube-proxy --no-headers 2>/dev/null | wc -l)
    PROXY_RUNNING=$(kubectl get pods -n kube-system -l component=kube-proxy --no-headers 2>/dev/null | grep "Running" | wc -l)
    PROXY_CRASHLOOP=$(kubectl get pods -n kube-system -l component=kube-proxy --no-headers 2>/dev/null | grep "CrashLoopBackOff" | wc -l)
    
    info "kube-proxy pods: $PROXY_RUNNING/$PROXY_PODS running"
    
    if [ "$PROXY_CRASHLOOP" -gt 0 ]; then
        warn "✗ Found $PROXY_CRASHLOOP kube-proxy pods in CrashLoopBackOff"
        kubectl get pods -n kube-system -l component=kube-proxy -o wide
        return 1
    elif [ "$PROXY_RUNNING" -eq "$PROXY_PODS" ] && [ "$PROXY_PODS" -gt 0 ]; then
        info "✓ All kube-proxy pods are running"
        return 0
    else
        warn "✗ kube-proxy pods not all running: $PROXY_RUNNING/$PROXY_PODS"
        return 1
    fi
}

# Function to check DNS resolution
check_dns_resolution() {
    info "Step 5: Checking DNS resolution"
    
    # Create a test pod for DNS resolution
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: network-validation-test
  namespace: kube-system
spec:
  containers:
  - name: test
    image: busybox:1.35
    command: ['sleep', '60']
  restartPolicy: Never
EOF

    # Wait for pod to start
    sleep 10
    
    # Test DNS resolution
    if kubectl exec -n kube-system network-validation-test -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
        info "✓ DNS resolution working"
        DNS_OK=true
    else
        warn "✗ DNS resolution failed"
        DNS_OK=false
    fi
    
    # Clean up test pod
    kubectl delete pod -n kube-system network-validation-test --ignore-not-found >/dev/null 2>&1
    
    if [ "$DNS_OK" = true ]; then
        return 0
    else
        return 1
    fi
}

# Function to check mixed OS compatibility
check_mixed_os_compatibility() {
    info "Step 6: Checking mixed OS environment compatibility"
    
    # Check for RHEL/AlmaLinux nodes
    RHEL_NODES=$(kubectl get nodes -o jsonpath='{.items[?(@.status.nodeInfo.osImage=~".*Red Hat.*|.*AlmaLinux.*|.*CentOS.*")].metadata.name}' 2>/dev/null || echo "")
    UBUNTU_NODES=$(kubectl get nodes -o jsonpath='{.items[?(@.status.nodeInfo.osImage=~".*Ubuntu.*")].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$RHEL_NODES" ] && [ -n "$UBUNTU_NODES" ]; then
        warn "Mixed OS environment detected:"
        echo "  RHEL/AlmaLinux nodes: $RHEL_NODES"
        echo "  Ubuntu nodes: $UBUNTU_NODES"
        
        # Check for potential iptables compatibility issues
        if command -v nft >/dev/null 2>&1; then
            NFT_TABLES=$(nft list tables 2>/dev/null | wc -l)
            if [ "$NFT_TABLES" -gt 0 ]; then
                warn "nftables detected - may conflict with iptables-based CNI"
            fi
        fi
        
        info "Mixed OS environments require careful CNI configuration"
        return 1
    elif [ -n "$RHEL_NODES" ]; then
        info "RHEL/AlmaLinux environment detected: $RHEL_NODES"
        return 0
    elif [ -n "$UBUNTU_NODES" ]; then
        info "Ubuntu environment detected: $UBUNTU_NODES"
        return 0
    else
        warn "Unable to determine node OS types"
        return 1
    fi
}

# Function to check for existing stuck pods
check_stuck_pods() {
    info "Step 7: Checking for existing stuck pods"
    
    STUCK_PODS=$(kubectl get pods --all-namespaces | grep -E "ContainerCreating|Pending|ImagePullBackOff" | wc -l)
    
    if [ "$STUCK_PODS" -gt 0 ]; then
        warn "Found $STUCK_PODS pods in problematic states:"
        kubectl get pods --all-namespaces | grep -E "ContainerCreating|Pending|ImagePullBackOff" | head -5
        
        # Check for specific CNI bridge IP conflict errors (the exact issue from problem statement)
        CNI_BRIDGE_CONFLICTS=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' 2>/dev/null | \
            grep -i "failed to set bridge addr.*cni0.*already has an IP address different from" | wc -l)
        
        if [ "$CNI_BRIDGE_CONFLICTS" -gt 0 ]; then
            error "✗ DETECTED CNI BRIDGE IP CONFLICTS - this is the exact issue from your error!"
            warn "Error: cni0 already has an IP address different from 10.244.x.x/xx"
            echo "Recent CNI bridge conflict events:"
            kubectl get events --all-namespaces --sort-by='.lastTimestamp' 2>/dev/null | \
                grep -i "failed to set bridge addr.*cni0" | tail -2
            echo
            warn "🔧 IMMEDIATE FIX: Run 'sudo ./scripts/reset_cni_bridge.sh'"
            warn "This will reset the CNI bridge to align with kube-flannel configuration"
        fi
        
        # Check for other networking errors  
        OTHER_NETWORK_ERRORS=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' | \
            grep -i "failed to create pod sandbox\|network plugin is not ready" | grep -v "failed to set bridge addr" | wc -l)
        if [ "$OTHER_NETWORK_ERRORS" -gt 0 ]; then
            warn "Found $OTHER_NETWORK_ERRORS other networking-related events"
        fi
        
        return 1
    else
        info "✓ No stuck pods found"
        return 0
    fi
}

# Function to validate storage node for Jellyfin
validate_jellyfin_node() {
    info "Step 8: Validating Jellyfin target node (storagenodet3500)"
    
    # Check if target node exists and is ready
    if kubectl get node storagenodet3500 >/dev/null 2>&1; then
        NODE_STATUS=$(kubectl get node storagenodet3500 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        if [ "$NODE_STATUS" = "True" ]; then
            info "✓ Jellyfin target node (storagenodet3500) is Ready"
            
            # Check if required directories exist (this would need SSH access in real environment)
            info "Note: Ensure /var/lib/jellyfin and /srv/media directories exist on storagenodet3500"
            return 0
        else
            warn "✗ Jellyfin target node (storagenodet3500) is not Ready"
            return 1
        fi
    else
        error "✗ Jellyfin target node (storagenodet3500) not found"
        return 1
    fi
}

# Main validation flow
main() {
    local exit_code=0
    local issues=()
    
    # Run all checks
    if ! check_cni_bridge; then
        issues+=("CNI bridge configuration")
        exit_code=1
    fi
    
    if ! check_node_readiness; then
        issues+=("Node readiness")
        exit_code=1
    fi
    
    if ! check_flannel_status; then
        issues+=("Flannel CNI status")
        exit_code=1
    fi
    
    if ! check_kube_proxy_status; then
        issues+=("kube-proxy status")
        exit_code=1
    fi
    
    if ! check_dns_resolution; then
        issues+=("DNS resolution")
        exit_code=1
    fi
    
    if ! check_mixed_os_compatibility; then
        issues+=("Mixed OS compatibility")
        # Don't set exit_code=1 for this as it's more of a warning
    fi
    
    if ! check_stuck_pods; then
        issues+=("Existing stuck pods")
        exit_code=1
    fi
    
    if ! validate_jellyfin_node; then
        issues+=("Jellyfin target node")
        exit_code=1
    fi
    
    echo
    echo "=== Network Prerequisites Validation Summary ==="
    
    if [ $exit_code -eq 0 ]; then
        info "✅ All network prerequisites validated successfully"
        echo "The cluster is ready for Jellyfin and other pod deployments"
    else
        warn "⚠️ Network prerequisites validation found issues:"
        for issue in "${issues[@]}"; do
            echo "  - $issue"
        done
        echo
        echo "Recommended actions:"
        echo "  1. Run sudo ./scripts/reset_cni_bridge.sh if CNI bridge conflicts detected"
        echo "  2. Run ./scripts/fix_cni_bridge_conflict.sh for comprehensive CNI fixes"
        echo "  3. Run ./scripts/fix_homelab_node_issues.sh for node-specific problems"
        echo "  4. Check flannel and kube-proxy logs: kubectl logs -n kube-flannel <pod-name>"
        echo "  5. Ensure all nodes have proper network connectivity"
        echo
        echo "After addressing issues, re-run this validation script"
    fi
    
    return $exit_code
}

# Run main function
main "$@"
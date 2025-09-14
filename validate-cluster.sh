#!/bin/bash

# VMStation Cluster Validation Script
# Validates that the CNI bridge fix worked and cluster is healthy

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

echo "=== VMStation Cluster Validation ==="
echo "Timestamp: $(date)"
echo "Purpose: Validate CNI bridge fix and cluster health"
echo ""

# Check if we're on control plane
if [ ! -f "/etc/kubernetes/admin.conf" ]; then
    error "Not running on Kubernetes control plane"
    exit 1
fi

export KUBECONFIG=/etc/kubernetes/admin.conf

# Validation functions
validate_nodes() {
    info "Checking node status..."
    
    local nodes_output=$(kubectl get nodes --no-headers 2>/dev/null)
    local total_nodes=$(echo "$nodes_output" | wc -l)
    local ready_nodes=$(echo "$nodes_output" | grep -c " Ready " || echo "0")
    
    echo "Total nodes: $total_nodes"
    echo "Ready nodes: $ready_nodes"
    
    if [ "$ready_nodes" -eq "$total_nodes" ] && [ "$total_nodes" -ge 3 ]; then
        success "All $total_nodes nodes are Ready"
        return 0
    else
        error "Not all nodes are Ready ($ready_nodes/$total_nodes)"
        return 1
    fi
}

validate_cni_bridge() {
    info "Checking CNI bridge configuration..."
    
    if ip addr show cni0 >/dev/null 2>&1; then
        local cni_ip=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
        echo "CNI bridge IP: $cni_ip"
        
        if echo "$cni_ip" | grep -q "10.244."; then
            success "CNI bridge has correct IP range: $cni_ip"
            return 0
        else
            error "CNI bridge has wrong IP range: $cni_ip (expected 10.244.x.x)"
            return 1
        fi
    else
        warn "CNI bridge not found (may be normal if flannel not ready)"
        return 1
    fi
}

validate_network_pods() {
    info "Checking network pod status..."
    
    local all_good=true
    
    # Check flannel
    local flannel_desired=$(kubectl get daemonset kube-flannel-ds -n kube-flannel -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    local flannel_ready=$(kubectl get daemonset kube-flannel-ds -n kube-flannel -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    
    echo "Flannel pods: $flannel_ready/$flannel_desired"
    if [ "$flannel_ready" -eq "$flannel_desired" ] && [ "$flannel_ready" -gt 0 ]; then
        success "Flannel DaemonSet is ready"
    else
        error "Flannel DaemonSet not ready"
        all_good=false
    fi
    
    # Check CoreDNS
    local coredns_desired=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    local coredns_ready=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    echo "CoreDNS pods: $coredns_ready/$coredns_desired"
    if [ "$coredns_ready" -eq "$coredns_desired" ] && [ "$coredns_ready" -gt 0 ]; then
        success "CoreDNS Deployment is ready"
    else
        error "CoreDNS Deployment not ready"
        all_good=false
    fi
    
    # Check kube-proxy
    local proxy_desired=$(kubectl get daemonset kube-proxy -n kube-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    local proxy_ready=$(kubectl get daemonset kube-proxy -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    
    echo "kube-proxy pods: $proxy_ready/$proxy_desired"
    if [ "$proxy_ready" -eq "$proxy_desired" ] && [ "$proxy_ready" -gt 0 ]; then
        success "kube-proxy DaemonSet is ready"
    else
        error "kube-proxy DaemonSet not ready"
        all_good=false
    fi
    
    if [ "$all_good" = true ]; then
        return 0
    else
        return 1
    fi
}

validate_jellyfin() {
    info "Checking Jellyfin pod status..."
    
    if kubectl get pod jellyfin -n jellyfin >/dev/null 2>&1; then
        local jellyfin_status=$(kubectl get pod jellyfin -n jellyfin -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        echo "Jellyfin pod status: $jellyfin_status"
        
        if [ "$jellyfin_status" = "Running" ]; then
            success "Jellyfin pod is running"
            
            # Check if it has an IP
            local jellyfin_ip=$(kubectl get pod jellyfin -n jellyfin -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
            if [ -n "$jellyfin_ip" ]; then
                echo "Jellyfin pod IP: $jellyfin_ip"
                if echo "$jellyfin_ip" | grep -q "10.244."; then
                    success "Jellyfin has correct pod IP range"
                    return 0
                else
                    error "Jellyfin has wrong pod IP range: $jellyfin_ip"
                    return 1
                fi
            else
                warn "Jellyfin pod has no IP assigned yet"
                return 1
            fi
        else
            error "Jellyfin pod not running (status: $jellyfin_status)"
            return 1
        fi
    else
        warn "Jellyfin pod not found"
        return 1
    fi
}

validate_cni_errors() {
    info "Checking for recent CNI bridge errors..."
    
    local recent_errors=$(kubectl get events --all-namespaces --field-selector reason=FailedCreatePodSandBox 2>/dev/null | grep "failed to set bridge addr.*already has an IP address different" | wc -l || echo "0")
    
    echo "Recent CNI bridge errors: $recent_errors"
    
    if [ "$recent_errors" -eq 0 ]; then
        success "No recent CNI bridge errors"
        return 0
    else
        error "Found $recent_errors recent CNI bridge errors"
        return 1
    fi
}

validate_dns() {
    info "Checking DNS resolution..."
    
    # Test DNS from a simple pod
    local dns_test=$(kubectl run dns-test-validation --image=busybox --rm -it --restart=Never --timeout=30s -- nslookup kubernetes.default.svc.cluster.local 2>/dev/null || echo "FAILED")
    
    if echo "$dns_test" | grep -q "Name:.*kubernetes.default.svc.cluster.local"; then
        success "DNS resolution working"
        return 0
    else
        error "DNS resolution failed"
        return 1
    fi
}

validate_stuck_pods() {
    info "Checking for stuck pods..."
    
    local stuck_pods=$(kubectl get pods --all-namespaces | grep -E "(ContainerCreating|Pending|CrashLoopBackOff)" | wc -l || echo "0")
    
    echo "Stuck pods: $stuck_pods"
    
    if [ "$stuck_pods" -eq 0 ]; then
        success "No stuck pods found"
        return 0
    else
        error "Found $stuck_pods stuck pods"
        kubectl get pods --all-namespaces | grep -E "(ContainerCreating|Pending|CrashLoopBackOff)" || true
        return 1
    fi
}

# Run all validations
main() {
    local validation_results=()
    local all_passed=true
    
    # Run validations
    if validate_nodes; then
        validation_results+=("Nodes: ✓")
    else
        validation_results+=("Nodes: ✗")
        all_passed=false
    fi
    
    if validate_cni_bridge; then
        validation_results+=("CNI Bridge: ✓")
    else
        validation_results+=("CNI Bridge: ✗")
        all_passed=false
    fi
    
    if validate_network_pods; then
        validation_results+=("Network Pods: ✓")
    else
        validation_results+=("Network Pods: ✗")
        all_passed=false
    fi
    
    if validate_jellyfin; then
        validation_results+=("Jellyfin: ✓")
    else
        validation_results+=("Jellyfin: ✗")
        all_passed=false
    fi
    
    if validate_cni_errors; then
        validation_results+=("CNI Errors: ✓")
    else
        validation_results+=("CNI Errors: ✗")
        all_passed=false
    fi
    
    if validate_stuck_pods; then
        validation_results+=("Stuck Pods: ✓")
    else
        validation_results+=("Stuck Pods: ✗")
        all_passed=false
    fi
    
    # Show results
    echo ""
    echo "=== Validation Results ==="
    for result in "${validation_results[@]}"; do
        echo "$result"
    done
    
    echo ""
    if [ "$all_passed" = true ]; then
        success "🎉 All validations passed! Your cluster is healthy."
        echo ""
        info "Access URLs:"
        echo "• Jellyfin: http://192.168.4.61:30096"
        echo "• Grafana: http://192.168.4.63:30300 (if deployed)"
        echo "• Prometheus: http://192.168.4.63:30090 (if deployed)"
        echo ""
        success "The CNI bridge fix was successful!"
        exit 0
    else
        error "❌ Some validations failed. Review the issues above."
        echo ""
        warn "Troubleshooting steps:"
        echo "1. Wait 2-3 minutes for pods to stabilize, then run this script again"
        echo "2. Check individual pod logs: kubectl logs -n <namespace> <pod-name>"
        echo "3. Re-run the fix: ./fix-cluster.sh"
        echo "4. Check node connectivity: kubectl describe nodes"
        exit 1
    fi
}

# Run main function
main "$@"
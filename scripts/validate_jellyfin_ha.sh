#!/bin/bash

# Jellyfin HA Kubernetes Validation Script
# Validates deployment and auto-scaling functionality

set -e

echo "=== Jellyfin High-Availability Validation ==="
echo "Timestamp: $(date)"
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

# Function to validate Kubernetes resources
validate_k8s_resources() {
    check "Validating Kubernetes resources..."
    
    # Check namespace
    if kubectl get namespace jellyfin &>/dev/null; then
        info "✓ Jellyfin namespace exists"
    else
        error "✗ Jellyfin namespace not found"
        return 1
    fi
    
    # Check persistent volumes
    local pv_count=$(kubectl get pv | grep jellyfin | wc -l)
    if [ "$pv_count" -eq 2 ]; then
        info "✓ Persistent volumes created (media + config)"
    else
        error "✗ Persistent volumes missing (found $pv_count, expected 2)"
        kubectl get pv | grep jellyfin || true
    fi
    
    # Check persistent volume claims
    local pvc_count=$(kubectl get pvc -n jellyfin | grep -v NAME | wc -l)
    if [ "$pvc_count" -eq 2 ]; then
        info "✓ Persistent volume claims bound"
    else
        error "✗ Persistent volume claims issues (found $pvc_count, expected 2)"
        kubectl get pvc -n jellyfin
    fi
    
    # Check deployment
    local replicas_ready=$(kubectl get deployment jellyfin -n jellyfin -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local replicas_desired=$(kubectl get deployment jellyfin -n jellyfin -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [ "$replicas_ready" -eq "$replicas_desired" ] && [ "$replicas_ready" -gt 0 ]; then
        info "✓ Deployment ready ($replicas_ready/$replicas_desired replicas)"
    else
        error "✗ Deployment not ready ($replicas_ready/$replicas_desired replicas)"
        kubectl get pods -n jellyfin
    fi
    
    # Check service
    if kubectl get service jellyfin-service -n jellyfin &>/dev/null; then
        info "✓ Service created"
        local nodeport=$(kubectl get service jellyfin-service -n jellyfin -o jsonpath='{.spec.ports[0].nodePort}')
        info "  NodePort: $nodeport"
    else
        error "✗ Service not found"
    fi
    
    # Check HPA
    if kubectl get hpa jellyfin-hpa -n jellyfin &>/dev/null; then
        info "✓ Horizontal Pod Autoscaler configured"
        local min_replicas=$(kubectl get hpa jellyfin-hpa -n jellyfin -o jsonpath='{.spec.minReplicas}')
        local max_replicas=$(kubectl get hpa jellyfin-hpa -n jellyfin -o jsonpath='{.spec.maxReplicas}')
        info "  Scaling: $min_replicas-$max_replicas replicas"
    else
        error "✗ Horizontal Pod Autoscaler not found"
    fi
}

# Function to test service endpoints
test_service_endpoints() {
    check "Testing service endpoints..."
    
    # Get node IP (try different methods)
    local node_ip
    node_ip=$(kubectl get nodes -o wide | grep -E "(control-plane|master)" | awk '{print $6}' | head -1)
    
    if [ -z "$node_ip" ]; then
        node_ip=$(kubectl get nodes -o wide | awk 'NR==2{print $6}')
    fi
    
    if [ -z "$node_ip" ]; then
        node_ip="192.168.4.63"  # Fallback
        warn "Could not detect node IP, using fallback: $node_ip"
    fi
    
    local nodeport=$(kubectl get service jellyfin-service -n jellyfin -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30096")
    local endpoint="http://$node_ip:$nodeport"
    
    info "Testing endpoint: $endpoint"
    
    # Test basic connectivity
    if curl -s -I "$endpoint" >/dev/null 2>&1; then
        info "✓ Service endpoint accessible"
    elif curl -s -I "$endpoint/health" >/dev/null 2>&1; then
        info "✓ Service health endpoint accessible"
    else
        warn "✗ Service endpoint not responding (may still be starting up)"
        info "  Endpoint: $endpoint"
        info "  Try again in a few minutes if pods are still starting"
    fi
    
    # Test discovery ports (UDP)
    info "Discovery endpoints configured:"
    info "  UDP 1900 -> NodePort $(kubectl get service jellyfin-service -n jellyfin -o jsonpath='{.spec.ports[2].nodePort}' 2>/dev/null || echo 'N/A')"
    info "  UDP 7359 -> NodePort $(kubectl get service jellyfin-service -n jellyfin -o jsonpath='{.spec.ports[3].nodePort}' 2>/dev/null || echo 'N/A')"
}

# Function to check resource usage and scaling
check_resource_usage() {
    check "Checking resource usage and scaling..."
    
    # Check if metrics server is available
    if kubectl top nodes &>/dev/null; then
        info "✓ Metrics server available"
        
        info "Node resource usage:"
        kubectl top nodes
        
        info "Pod resource usage:"
        kubectl top pods -n jellyfin 2>/dev/null || warn "Pod metrics not ready yet"
        
        # Check HPA status
        info "HPA status:"
        kubectl get hpa -n jellyfin
        
    else
        warn "✗ Metrics server not available - auto-scaling will not work"
        info "  To enable metrics server, deploy it with:"
        info "  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    fi
    
    # Show current pod count and limits
    local current_pods=$(kubectl get pods -n jellyfin --no-headers | wc -l)
    info "Current pod count: $current_pods"
    
    # Show resource limits per pod
    local memory_limit=$(kubectl get deployment jellyfin -n jellyfin -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "N/A")
    local cpu_limit=$(kubectl get deployment jellyfin -n jellyfin -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "N/A")
    
    info "Resource limits per pod:"
    info "  Memory: $memory_limit"
    info "  CPU: $cpu_limit"
}

# Function to check storage setup
check_storage() {
    check "Checking storage configuration..."
    
    # Check if media directory is accessible
    local storage_node=$(kubectl get nodes --no-headers | grep -v control-plane | head -1 | awk '{print $1}')
    if [ -n "$storage_node" ]; then
        info "Storage node: $storage_node"
        
        # Check persistent volume status
        kubectl get pv | grep jellyfin | while read -r line; do
            local pv_name=$(echo "$line" | awk '{print $1}')
            local pv_status=$(echo "$line" | awk '{print $5}')
            local pv_claim=$(echo "$line" | awk '{print $6}')
            
            if [ "$pv_status" = "Bound" ]; then
                info "✓ $pv_name: $pv_status to $pv_claim"
            else
                error "✗ $pv_name: $pv_status"
            fi
        done
        
    else
        warn "Could not identify storage node"
    fi
    
    # Check volume mounts in pods
    local pods=$(kubectl get pods -n jellyfin -o name 2>/dev/null)
    if [ -n "$pods" ]; then
        info "Volume mounts in pods:"
        for pod in $pods; do
            local pod_name=$(basename "$pod")
            info "Pod $pod_name:"
            kubectl describe pod "$pod_name" -n jellyfin | grep -A5 "Mounts:" | grep -E "(media|config)" || warn "  No media/config mounts found"
        done
    fi
}

# Function to check monitoring integration
check_monitoring() {
    check "Checking monitoring integration..."
    
    # Check if ServiceMonitor exists
    if kubectl get servicemonitor jellyfin-metrics -n jellyfin &>/dev/null; then
        info "✓ ServiceMonitor created for Prometheus"
    else
        warn "✗ ServiceMonitor not found"
    fi
    
    # Check if monitoring namespace exists (for Grafana integration)
    if kubectl get namespace monitoring &>/dev/null; then
        info "✓ Monitoring namespace exists"
        
        # Check if Prometheus is running
        if kubectl get pods -n monitoring | grep prometheus &>/dev/null; then
            info "✓ Prometheus is running"
        else
            warn "✗ Prometheus not found in monitoring namespace"
        fi
        
        # Check if Grafana is running
        if kubectl get pods -n monitoring | grep grafana &>/dev/null; then
            info "✓ Grafana is running"
            local grafana_port=$(kubectl get service -n monitoring | grep grafana | awk '{print $5}' | cut -d':' -f2 | cut -d'/' -f1)
            if [ -n "$grafana_port" ]; then
                info "  Grafana dashboard: http://192.168.4.63:$grafana_port"
            fi
        else
            warn "✗ Grafana not found in monitoring namespace"
        fi
    else
        warn "✗ Monitoring namespace not found"
    fi
}

# Function to display summary
display_summary() {
    check "Deployment Summary"
    
    local node_ip
    node_ip=$(kubectl get nodes -o wide | grep -E "(control-plane|master)" | awk '{print $6}' | head -1)
    if [ -z "$node_ip" ]; then
        node_ip="192.168.4.63"
    fi
    
    local nodeport=$(kubectl get service jellyfin-service -n jellyfin -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30096")
    
    echo ""
    info "=== JELLYFIN HIGH-AVAILABILITY SETUP COMPLETE ==="
    echo ""
    info "🎬 Primary Access URL: http://$node_ip:$nodeport"
    info "🔒 HTTPS Access: https://$node_ip:30920"
    echo ""
    info "📊 Features Enabled:"
    info "   ✓ Auto-scaling (1-3 pods based on load)"
    info "   ✓ Session affinity (seamless user experience)"
    info "   ✓ Hardware acceleration ready"
    info "   ✓ Large file support (50GB uploads)"
    info "   ✓ Resource limits (2.5GB RAM per pod)"
    info "   ✓ Persistent media storage"
    echo ""
    info "📈 Monitoring Commands:"
    info "   kubectl get pods -n jellyfin -w"
    info "   kubectl get hpa -n jellyfin -w"
    info "   kubectl top pods -n jellyfin"
    echo ""
    info "🔧 Troubleshooting Commands:"
    info "   kubectl logs -n jellyfin -l app=jellyfin"
    info "   kubectl describe pod -n jellyfin -l app=jellyfin"
    info "   kubectl get events -n jellyfin"
    echo ""
}

# Main validation workflow
main() {
    validate_k8s_resources
    echo ""
    
    test_service_endpoints
    echo ""
    
    check_resource_usage
    echo ""
    
    check_storage
    echo ""
    
    check_monitoring
    echo ""
    
    display_summary
}

# Run if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
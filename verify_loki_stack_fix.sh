#!/bin/bash

# Verification script for Loki Stack CrashLoopBackOff fix
# Checks pod status and validates that working pods remain unaffected

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MONITORING_NAMESPACE="monitoring"

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check cluster access
check_cluster_access() {
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not available"
        return 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot access Kubernetes cluster"
        return 1
    fi
    
    return 0
}

# Check Loki stack pod status
check_loki_stack_status() {
    info "Checking Loki stack pod status..."
    
    echo -e "\n=== Loki Pods ==="
    local loki_status=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=loki --no-headers 2>/dev/null || echo "No loki pods found")
    echo "$loki_status"
    
    echo -e "\n=== Promtail Pods ==="
    local promtail_status=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=promtail --no-headers 2>/dev/null || echo "No promtail pods found")
    echo "$promtail_status"
    
    # Check for CrashLoopBackOff or ContainerCreating issues
    local crash_count=$(echo "$loki_status $promtail_status" | grep -c "CrashLoopBackOff\|ContainerCreating\|Error" || echo "0")
    
    if [[ "$crash_count" -gt 0 ]]; then
        warn "Found $crash_count pods with issues"
        return 1
    else
        info "No CrashLoopBackOff or ContainerCreating issues found"
        return 0
    fi
}

# Check working pods status
check_working_pods() {
    info "Checking working pods status..."
    
    echo -e "\n=== Jellyfin Pods ==="
    local jellyfin_status=$(kubectl get pods -n jellyfin --no-headers 2>/dev/null || echo "No jellyfin namespace found")
    echo "$jellyfin_status"
    
    if echo "$jellyfin_status" | grep -q "Running"; then
        info "✅ Jellyfin pods are running properly"
    else
        warn "⚠️  Jellyfin pods status unclear"
    fi
    
    echo -e "\n=== All Running Pods (excluding monitoring) ==="
    kubectl get pods --all-namespaces --no-headers | grep Running | grep -v "$MONITORING_NAMESPACE" || echo "No other running pods found"
}

# Check services and connectivity
check_services() {
    info "Checking Loki stack services..."
    
    echo -e "\n=== Loki Services ==="
    kubectl get svc -n "$MONITORING_NAMESPACE" | grep loki || echo "No loki services found"
    
    echo -e "\n=== Service Endpoints ==="
    kubectl get endpoints -n "$MONITORING_NAMESPACE" | grep loki || echo "No loki endpoints found"
}

# Check recent events
check_events() {
    info "Checking recent events..."
    
    echo -e "\n=== Recent Events in Monitoring Namespace ==="
    kubectl get events -n "$MONITORING_NAMESPACE" --sort-by=.metadata.creationTimestamp | tail -15 || echo "No events found"
}

# Check persistent volumes
check_storage() {
    info "Checking storage configuration..."
    
    echo -e "\n=== PVCs in Monitoring Namespace ==="
    kubectl get pvc -n "$MONITORING_NAMESPACE" || echo "No PVCs found"
    
    echo -e "\n=== Storage Classes ==="
    kubectl get storageclass || echo "No storage classes found"
}

# Test Loki connectivity
test_loki_connectivity() {
    info "Testing Loki connectivity..."
    
    # Get Loki service details
    local loki_service=$(kubectl get svc -n "$MONITORING_NAMESPACE" -l app=loki --no-headers 2>/dev/null | head -1)
    
    if [[ -n "$loki_service" ]]; then
        local service_name=$(echo "$loki_service" | awk '{print $1}')
        local node_port=$(echo "$loki_service" | grep -o '[0-9]\{5\}' || echo "")
        
        if [[ -n "$node_port" ]]; then
            info "Found Loki service $service_name with NodePort $node_port"
            
            # Try to get a node IP
            local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")
            
            if [[ -n "$node_ip" ]]; then
                info "Testing connectivity to Loki at $node_ip:$node_port"
                if curl -s --connect-timeout 5 "http://$node_ip:$node_port/ready" &>/dev/null; then
                    info "✅ Loki is responding to health checks"
                else
                    warn "⚠️  Loki is not responding to health checks"
                fi
            else
                warn "Cannot determine node IP for connectivity test"
            fi
        else
            warn "Cannot determine NodePort for Loki service"
        fi
    else
        warn "No Loki service found"
    fi
}

# Main verification function
main() {
    echo -e "${BLUE}=== VMStation Loki Stack Status Verification ===${NC}"
    echo "Checking status after CrashLoopBackOff fix..."
    echo ""
    
    if ! check_cluster_access; then
        error "Cannot access cluster. Exiting."
        exit 1
    fi
    
    echo -e "\n${YELLOW}=== Loki Stack Status Check ===${NC}"
    local loki_ok=0
    if check_loki_stack_status; then
        loki_ok=1
    fi
    
    echo -e "\n${YELLOW}=== Working Pods Status Check ===${NC}"
    check_working_pods
    
    echo -e "\n${YELLOW}=== Services Check ===${NC}"
    check_services
    
    echo -e "\n${YELLOW}=== Storage Check ===${NC}"
    check_storage
    
    echo -e "\n${YELLOW}=== Recent Events ===${NC}"
    check_events
    
    echo -e "\n${YELLOW}=== Connectivity Test ===${NC}"
    test_loki_connectivity
    
    echo -e "\n${BLUE}=== Summary ===${NC}"
    if [[ "$loki_ok" -eq 1 ]]; then
        info "✅ Loki stack appears to be healthy"
        info "✅ No CrashLoopBackOff issues detected"
    else
        warn "⚠️  Loki stack may still have issues"
        warn "Review the logs and events above for troubleshooting"
    fi
    
    info "Working pods preservation check completed"
    
    echo -e "\n${BLUE}=== Next Steps ===${NC}"
    info "1. Monitor pod status: kubectl get pods -n $MONITORING_NAMESPACE -w"
    info "2. Check logs if issues persist: kubectl logs -n $MONITORING_NAMESPACE -l app=loki"
    info "3. Verify Jellyfin remains unaffected: kubectl get pods -n jellyfin"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
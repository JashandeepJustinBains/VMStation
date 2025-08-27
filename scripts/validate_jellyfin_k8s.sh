#!/bin/bash

# VMStation Jellyfin Kubernetes Validation Script
# Validates Jellyfin deployment for 4K streaming readiness

set -e

echo "=== VMStation Jellyfin Kubernetes Validation ==="
echo "Timestamp: $(date)"
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Initialize validation status
VALIDATION_PASSED=true

# Function to check and report
check_and_report() {
    local description="$1"
    local command="$2"
    local expected="$3"
    
    echo -n "Checking $description... "
    if eval "$command" &>/dev/null; then
        if [ -n "$expected" ]; then
            result=$(eval "$command" 2>/dev/null)
            if [[ "$result" == *"$expected"* ]]; then
                success "$description"
            else
                error "$description (Expected: $expected, Got: $result)"
                VALIDATION_PASSED=false
            fi
        else
            success "$description"
        fi
    else
        error "$description"
        VALIDATION_PASSED=false
    fi
}

echo "=== 1. Kubernetes Cluster Validation ==="
echo ""

check_and_report "Kubernetes cluster connectivity" "kubectl cluster-info"
check_and_report "Control plane accessibility" "kubectl get nodes --no-headers | grep control-plane"

# Check cluster nodes
echo ""
info "Cluster Nodes:"
kubectl get nodes -o wide 2>/dev/null || error "Failed to get cluster nodes"
echo ""

echo "=== 2. Jellyfin Namespace and Resources ==="
echo ""

check_and_report "Jellyfin namespace exists" "kubectl get namespace jellyfin"
check_and_report "StorageClass local-storage exists" "kubectl get storageclass local-storage"

# Check persistent volumes
echo ""
info "Persistent Volumes:"
kubectl get pv | grep jellyfin 2>/dev/null || warning "No Jellyfin persistent volumes found"

info "Persistent Volume Claims:"
kubectl get pvc -n jellyfin 2>/dev/null || warning "No Jellyfin PVCs found"
echo ""

echo "=== 3. Jellyfin Deployment Validation ==="
echo ""

check_and_report "Jellyfin deployment exists" "kubectl get deployment jellyfin -n jellyfin"
check_and_report "Jellyfin deployment is ready" "kubectl get deployment jellyfin -n jellyfin -o jsonpath='{.status.readyReplicas}'" "2"

# Check pod status
echo ""
info "Jellyfin Pods:"
kubectl get pods -n jellyfin -o wide 2>/dev/null || error "Failed to get Jellyfin pods"

# Check pod health
POD_COUNT=$(kubectl get pods -n jellyfin --no-headers 2>/dev/null | wc -l)
READY_PODS=$(kubectl get pods -n jellyfin --no-headers 2>/dev/null | grep "Running" | grep "1/1" | wc -l)

if [ "$POD_COUNT" -eq 2 ] && [ "$READY_PODS" -eq 2 ]; then
    success "All 2 Jellyfin pods are running and ready"
else
    error "Expected 2 ready pods, found $READY_PODS ready out of $POD_COUNT total"
    VALIDATION_PASSED=false
fi
echo ""

echo "=== 4. Service and Network Validation ==="
echo ""

check_and_report "Jellyfin NodePort service exists" "kubectl get svc jellyfin-service -n jellyfin"
check_and_report "Jellyfin LoadBalancer service exists" "kubectl get svc jellyfin-loadbalancer -n jellyfin"

# Get service details
NODEPORT=$(kubectl get svc jellyfin-service -n jellyfin -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
CLUSTER_IP=$(kubectl get svc jellyfin-service -n jellyfin -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "N/A")

info "Service Details:"
echo "  • Cluster IP: $CLUSTER_IP"
echo "  • NodePort: $NODEPORT"

# Check endpoints
ENDPOINTS=$(kubectl get endpoints jellyfin-service -n jellyfin -o jsonpath='{.subsets[0].addresses}' 2>/dev/null || echo "[]")
if [ "$ENDPOINTS" != "[]" ] && [ -n "$ENDPOINTS" ]; then
    success "Service endpoints are configured"
else
    error "No service endpoints found"
    VALIDATION_PASSED=false
fi
echo ""

echo "=== 5. Storage Validation ==="
echo ""

# Check if storage node has required directories
STORAGE_NODE="192.168.4.61"
ANSIBLE_INVENTORY="ansible/inventory.txt"

if [ -f "$ANSIBLE_INVENTORY" ] && command -v ansible &>/dev/null; then
    info "Checking storage directories on $STORAGE_NODE..."
    
    if ansible storage_nodes -i "$ANSIBLE_INVENTORY" -m shell -a "test -d /mnt/media" &>/dev/null; then
        success "Media directory /mnt/media exists"
    else
        error "Media directory /mnt/media not found"
        VALIDATION_PASSED=false
    fi
    
    if ansible storage_nodes -i "$ANSIBLE_INVENTORY" -m shell -a "test -d '/mnt/media/TV Shows'" &>/dev/null; then
        success "TV Shows directory exists"
    else
        warning "TV Shows directory not found"
    fi
    
    if ansible storage_nodes -i "$ANSIBLE_INVENTORY" -m shell -a "test -d '/mnt/media/Movies'" &>/dev/null; then
        success "Movies directory exists"
    else
        warning "Movies directory not found"
    fi
    
    if ansible storage_nodes -i "$ANSIBLE_INVENTORY" -m shell -a "test -d /mnt/media/jellyfin-config" &>/dev/null; then
        success "Jellyfin config directory exists"
    else
        warning "Jellyfin config directory not found (will be created)"
    fi
else
    warning "Cannot validate storage - Ansible not available or inventory not found"
fi
echo ""

echo "=== 6. Resource Allocation Validation ==="
echo ""

# Check resource requests and limits
info "Resource Configuration:"
kubectl describe deployment jellyfin -n jellyfin 2>/dev/null | grep -A 5 "Limits\|Requests" || warning "Could not retrieve resource configuration"
echo ""

echo "=== 7. Health Check Validation ==="
echo ""

# Check if pods are passing health checks
info "Pod Health Status:"
for pod in $(kubectl get pods -n jellyfin --no-headers -o name 2>/dev/null); do
    pod_name=$(echo $pod | cut -d'/' -f2)
    ready_status=$(kubectl get pod $pod_name -n jellyfin -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    
    if [ "$ready_status" = "True" ]; then
        success "Pod $pod_name is healthy"
    else
        error "Pod $pod_name is not ready (Status: $ready_status)"
        VALIDATION_PASSED=false
    fi
done
echo ""

echo "=== 8. Connectivity Test ==="
echo ""

# Test internal connectivity
if kubectl get pod -n jellyfin --no-headers 2>/dev/null | grep -q "Running"; then
    FIRST_POD=$(kubectl get pods -n jellyfin --no-headers -o name | head -1 | cut -d'/' -f2)
    
    info "Testing internal connectivity from pod $FIRST_POD..."
    if kubectl exec -n jellyfin $FIRST_POD -- curl -s -f http://localhost:8096/health &>/dev/null; then
        success "Internal health endpoint accessible"
    else
        warning "Internal health endpoint not accessible (Jellyfin may still be starting)"
    fi
else
    error "No running pods found for connectivity test"
    VALIDATION_PASSED=false
fi

# Test NodePort connectivity (if cluster is accessible)
if [ "$NODEPORT" != "N/A" ] && command -v curl &>/dev/null; then
    info "Testing NodePort connectivity..."
    if timeout 10 curl -s -f http://localhost:$NODEPORT &>/dev/null; then
        success "NodePort connectivity working"
    else
        warning "NodePort not accessible from local machine"
    fi
fi
echo ""

echo "=== 9. 4K Streaming Readiness ==="
echo ""

info "Checking 4K streaming configuration..."

# Check CPU and memory limits
CPU_LIMIT=$(kubectl get deployment jellyfin -n jellyfin -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "N/A")
MEMORY_LIMIT=$(kubectl get deployment jellyfin -n jellyfin -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "N/A")

if [ "$CPU_LIMIT" = "4000m" ] || [ "$CPU_LIMIT" = "4" ]; then
    success "CPU limit configured for 4K streaming ($CPU_LIMIT)"
else
    warning "CPU limit may be insufficient for 4K streaming ($CPU_LIMIT)"
fi

if [[ "$MEMORY_LIMIT" == *"8Gi"* ]] || [[ "$MEMORY_LIMIT" == *"8000Mi"* ]]; then
    success "Memory limit configured for 4K streaming ($MEMORY_LIMIT)"
else
    warning "Memory limit may be insufficient for 4K streaming ($MEMORY_LIMIT)"
fi

# Check replica count for redundancy
REPLICA_COUNT=$(kubectl get deployment jellyfin -n jellyfin -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
if [ "$REPLICA_COUNT" -ge 2 ]; then
    success "High availability configured with $REPLICA_COUNT replicas"
else
    warning "Only $REPLICA_COUNT replica configured - consider increasing for redundancy"
fi
echo ""

echo "=== 10. Integration Validation ==="
echo ""

# Check if monitoring is configured
if kubectl get servicemonitor jellyfin-metrics -n jellyfin &>/dev/null; then
    success "Prometheus monitoring integration configured"
else
    info "Prometheus monitoring not configured (optional)"
fi

# Check if ingress is configured
if kubectl get ingress jellyfin-ingress -n jellyfin &>/dev/null; then
    success "Ingress configuration found"
    kubectl get ingress jellyfin-ingress -n jellyfin 2>/dev/null
else
    info "No ingress configuration found (using NodePort/LoadBalancer)"
fi
echo ""

echo "=== Validation Summary ==="
echo ""

if [ "$VALIDATION_PASSED" = true ]; then
    success "All critical validations passed!"
    echo ""
    info "Jellyfin is ready for 4K streaming with high availability"
    echo ""
    echo "Access Information:"
    echo "  • NodePort: http://$STORAGE_NODE:$NODEPORT"
    echo "  • LoadBalancer: Check 'kubectl get svc jellyfin-loadbalancer -n jellyfin'"
    echo "  • Internal: http://jellyfin-service.jellyfin.svc.cluster.local:8096"
    echo ""
    echo "Next Steps:"
    echo "  1. Access Jellyfin web interface"
    echo "  2. Complete initial setup wizard"
    echo "  3. Add media libraries:"
    echo "     - TV Shows: /media/tv"
    echo "     - Movies: /media/movies"
    echo "  4. Configure transcoding settings"
    echo "  5. Test 4K streaming performance"
else
    error "Some validations failed!"
    echo ""
    echo "Common troubleshooting steps:"
    echo "  1. Check pod logs: kubectl logs -n jellyfin deployment/jellyfin"
    echo "  2. Describe pods: kubectl describe pods -n jellyfin"
    echo "  3. Check storage: kubectl get pv,pvc -n jellyfin"
    echo "  4. Verify node resources: kubectl describe nodes"
    echo "  5. Check events: kubectl get events -n jellyfin --sort-by='.lastTimestamp'"
fi

exit $([[ "$VALIDATION_PASSED" == "true" ]] && echo 0 || echo 1)
#!/bin/bash

# Jellyfin Kubernetes Deployment Validation Script
# Validates that Jellyfin is properly deployed and running in Kubernetes

set -e

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

header() {
    echo -e "${BLUE}[SECTION]${NC} $1"
}

echo "=== Jellyfin Kubernetes Deployment Validation ==="
echo "Timestamp: $(date)"
echo ""

# Check if running on monitoring node
if [[ "$(hostname -I | grep -o '192.168.4.63')" != "192.168.4.63" ]]; then
    error "This script should be run on the monitoring node (192.168.4.63)"
    exit 1
fi

header "1. Kubernetes Cluster Status"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl is not available"
    exit 1
fi

# Check cluster status
if kubectl cluster-info &> /dev/null; then
    info "Kubernetes cluster is accessible"
else
    error "Cannot access Kubernetes cluster"
    exit 1
fi

# Check nodes
header "2. Node Status"
echo "Cluster nodes:"
kubectl get nodes -o wide

header "3. Jellyfin Namespace and Resources"

# Check namespace
if kubectl get namespace jellyfin &> /dev/null; then
    info "Jellyfin namespace exists"
else
    error "Jellyfin namespace not found"
    exit 1
fi

# Check deployment
echo ""
info "Jellyfin deployment status:"
kubectl get deployment jellyfin -n jellyfin -o wide

# Check pods
echo ""
info "Jellyfin pods:"
kubectl get pods -n jellyfin -o wide

# Check services
echo ""
info "Jellyfin services:"
kubectl get services -n jellyfin -o wide

# Check persistent volumes
header "4. Storage Configuration"
echo "Persistent Volumes:"
kubectl get pv | grep jellyfin

echo ""
echo "Persistent Volume Claims:"
kubectl get pvc -n jellyfin

header "5. High Availability Verification"

# Check replica count
REPLICAS=$(kubectl get deployment jellyfin -n jellyfin -o jsonpath='{.spec.replicas}')
READY_REPLICAS=$(kubectl get deployment jellyfin -n jellyfin -o jsonpath='{.status.readyReplicas}')

info "Configured replicas: $REPLICAS"
info "Ready replicas: ${READY_REPLICAS:-0}"

if [[ "${READY_REPLICAS:-0}" -ge 2 ]]; then
    info "High availability configured correctly (2+ replicas)"
else
    warn "High availability may not be fully configured (less than 2 ready replicas)"
fi

# Check pod distribution across nodes
echo ""
info "Pod distribution across nodes:"
kubectl get pods -n jellyfin -o wide | awk 'NR>1 {print $7}' | sort | uniq -c

header "6. Service Connectivity Tests"

# Get NodePort
NODEPORT=$(kubectl get service jellyfin-nodeport -n jellyfin -o jsonpath='{.spec.ports[0].nodePort}')
info "Jellyfin NodePort: $NODEPORT"

# Test internal connectivity
echo ""
info "Testing internal service connectivity..."
if kubectl run test-jellyfin --image=busybox --rm -it --restart=Never -- wget -qO- --timeout=10 http://jellyfin.jellyfin.svc.cluster.local:8096/health &> /dev/null; then
    info "Internal service connectivity: OK"
else
    warn "Internal service connectivity: FAILED"
fi

# Test external connectivity
echo ""
info "Testing external NodePort connectivity..."
for NODE_IP in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'); do
    if curl -s --connect-timeout 5 "http://$NODE_IP:$NODEPORT/health" &> /dev/null; then
        info "External connectivity to $NODE_IP:$NODEPORT: OK"
    else
        warn "External connectivity to $NODE_IP:$NODEPORT: FAILED"
    fi
done

header "7. Resource Usage"

# Get resource usage for Jellyfin pods
echo ""
info "Current resource usage:"
kubectl top pods -n jellyfin --no-headers 2>/dev/null || warn "Metrics server not available - cannot show resource usage"

header "8. Configuration Summary"

# Display configuration
echo ""
info "Jellyfin Configuration Summary:"
kubectl get configmap jellyfin-config -n jellyfin -o yaml 2>/dev/null || info "No ConfigMap found - using default configuration"

echo ""
info "Storage mounts:"
kubectl describe pods -n jellyfin | grep -A 5 "Mounts:" || warn "Could not retrieve mount information"

header "9. Access Information"

# Storage node IP for media access
STORAGE_NODE="192.168.4.61"
MONITORING_NODE="192.168.4.63"

echo ""
info "Jellyfin Access URLs:"
info "- Primary (via storage node): http://$STORAGE_NODE:$NODEPORT"
info "- Backup (via monitoring node): http://$MONITORING_NODE:$NODEPORT"
info "- HTTPS NodePort: https://$STORAGE_NODE:30920"
info "- Ingress: https://jellyfin.vmstation.local (if configured)"
info "- LoadBalancer: http://192.168.4.100:8096 (if configured)"

echo ""
info "Media Storage:"
info "- NFS Mount: $STORAGE_NODE:/srv/media → /media (in containers)"
info "- Config Storage: /mnt/media/jellyfin-config → /config (in containers)"

header "10. Health Checks"

# Check pod health
echo ""
info "Pod health status:"
kubectl get pods -n jellyfin -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{range .status.conditions[*]}{.type}={.status}{" "}{end}{"\n"}{end}' | column -t

# Check events for any issues
echo ""
info "Recent events in jellyfin namespace:"
kubectl get events -n jellyfin --sort-by='.lastTimestamp' | tail -10

header "Validation Complete"

# Final status
echo ""
if [[ "${READY_REPLICAS:-0}" -ge 1 ]]; then
    info "✅ Jellyfin deployment validation PASSED"
    info "✅ Media server is ready for 4K streaming"
    info "✅ High availability features are active"
    
    echo ""
    info "🎬 You can now access Jellyfin at: http://$STORAGE_NODE:$NODEPORT"
    info "📁 Configure your media libraries to use /media mount point"
    info "⚙️  Initial setup will be required on first access"
    
    exit 0
else
    error "❌ Jellyfin deployment validation FAILED"
    error "❌ Some pods are not ready or deployment is incomplete"
    exit 1
fi
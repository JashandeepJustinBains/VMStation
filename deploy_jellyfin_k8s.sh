#!/bin/bash

# VMStation Jellyfin Kubernetes Deployment Script
# Deploys high-availability Jellyfin with containerd runtime for 4K streaming

set -e

echo "=== VMStation Jellyfin Kubernetes Deployment ==="
echo "Timestamp: $(date)"
echo ""

# Configuration
ANSIBLE_INVENTORY="ansible/inventory.txt"
JELLYFIN_PLAYBOOK="ansible/plays/kubernetes/deploy_jellyfin.yaml"
STORAGE_NODE="192.168.4.61"

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

highlight() {
    echo -e "${BLUE}[HIGHLIGHT]${NC} $1"
}

# Pre-flight checks
info "Performing pre-flight checks..."

if [ ! -f "$ANSIBLE_INVENTORY" ]; then
    error "Ansible inventory file not found: $ANSIBLE_INVENTORY"
    exit 1
fi

if [ ! -f "$JELLYFIN_PLAYBOOK" ]; then
    error "Jellyfin playbook not found: $JELLYFIN_PLAYBOOK"
    exit 1
fi

# Check if Kubernetes cluster is running
info "Checking Kubernetes cluster status..."
if ! kubectl cluster-info &>/dev/null; then
    error "Kubernetes cluster is not accessible. Please ensure the cluster is running."
    exit 1
fi

# Check if storage node has required directories
info "Checking storage node requirements..."
if ! ansible storage_nodes -i "$ANSIBLE_INVENTORY" -m shell -a "test -d /mnt/media" &>/dev/null; then
    error "Media directory /mnt/media not found on storage node"
    exit 1
fi

info "Pre-flight checks completed successfully"
echo ""

# Display current cluster status
info "Current Kubernetes cluster status:"
kubectl get nodes -o wide
echo ""

# Check for existing Jellyfin deployment
info "Checking for existing Jellyfin deployments..."
if kubectl get namespace jellyfin &>/dev/null; then
    warn "Jellyfin namespace already exists"
    kubectl get pods -n jellyfin 2>/dev/null || true
    echo ""
    warn "Continue with deployment? This may update existing resources. (y/N)"
    read -r response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        info "Deployment cancelled"
        exit 0
    fi
fi

# Syntax check
info "Performing syntax check..."
if ansible-playbook --syntax-check -i "$ANSIBLE_INVENTORY" "$JELLYFIN_PLAYBOOK" &>/dev/null; then
    info "Syntax check passed"
else
    error "Syntax check failed"
    exit 1
fi

# Deploy Jellyfin
highlight "Deploying Jellyfin to Kubernetes cluster..."
echo ""
warn "This will deploy Jellyfin with the following configuration:"
echo "  - High Availability: 2 replicas with anti-affinity"
echo "  - Resources: 1-4 CPU cores, 2-8GB RAM per pod"
echo "  - Storage: /mnt/media (500GB), /mnt/media/jellyfin-config (10GB)"
echo "  - Media Libraries: /mnt/media/TV Shows, /mnt/media/Movies"
echo "  - External Access: NodePort 30096, LoadBalancer, Ingress"
echo "  - Runtime: containerd (already configured)"
echo ""
warn "Continue with deployment? (y/N)"
read -r response
if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    info "Deployment cancelled"
    exit 0
fi

# Run the deployment
if ansible-playbook -i "$ANSIBLE_INVENTORY" "$JELLYFIN_PLAYBOOK" -v; then
    echo ""
    info "Jellyfin deployment completed successfully!"
    echo ""
    
    # Wait a moment for services to stabilize
    sleep 5
    
    # Display access information
    highlight "=== Jellyfin Access Information ==="
    echo ""
    
    # Get NodePort information
    NODEPORT=$(kubectl get svc jellyfin-service -n jellyfin -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")
    
    # Get LoadBalancer IP if available
    LOADBALANCER_IP=$(kubectl get svc jellyfin-loadbalancer -n jellyfin -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Pending")
    
    info "Access URLs:"
    echo "  • NodePort (all nodes): http://$STORAGE_NODE:$NODEPORT"
    echo "  • LoadBalancer: http://$LOADBALANCER_IP:8096"
    echo "  • Ingress: http://jellyfin.local (if nginx-ingress is installed)"
    echo ""
    
    info "Media Configuration:"
    echo "  • Media Root: /mnt/media"
    echo "  • TV Shows: /mnt/media/TV Shows"
    echo "  • Movies: /mnt/media/Movies"
    echo "  • Configuration: /mnt/media/jellyfin-config"
    echo ""
    
    info "High Availability Features:"
    echo "  • Replicas: 2 pods with anti-affinity"
    echo "  • Rolling updates with zero downtime"
    echo "  • Resource limits for 4K streaming"
    echo "  • Health checks and auto-restart"
    echo ""
    
    # Display pod status
    info "Current Pod Status:"
    kubectl get pods -n jellyfin -o wide
    echo ""
    
    # Display service status
    info "Service Status:"
    kubectl get svc -n jellyfin
    echo ""
    
    # Performance and monitoring information
    highlight "=== Performance & Monitoring ==="
    echo ""
    info "Resource Allocation per Pod:"
    echo "  • CPU Request: 1000m (1 core)"
    echo "  • CPU Limit: 4000m (4 cores)"
    echo "  • Memory Request: 2Gi"
    echo "  • Memory Limit: 8Gi"
    echo ""
    
    info "4K Streaming Optimizations:"
    echo "  • Hardware decoding enabled for H.264, HEVC, VP9, AV1"
    echo "  • Transcoding temp path: /tmp/jellyfin"
    echo "  • Network subnets: 192.168.4.0/24, 10.244.0.0/16"
    echo "  • Large client body size: 50GB for uploads"
    echo ""
    
    info "Monitoring Integration:"
    echo "  • Health endpoints: /health on port 8096"
    echo "  • Liveness probe: 30s intervals"
    echo "  • Readiness probe: 10s intervals"
    echo "  • Pod metrics available via Prometheus"
    echo ""
    
    # Next steps
    highlight "=== Next Steps ==="
    echo ""
    info "1. Access Jellyfin and complete initial setup"
    info "2. Add media libraries pointing to /media/tv and /media/movies"
    info "3. Configure transcoding settings for your hardware"
    info "4. Test 4K streaming performance"
    info "5. Set up external access via ingress if needed"
    echo ""
    
    info "Monitoring Commands:"
    echo "  • Check pods: kubectl get pods -n jellyfin"
    echo "  • View logs: kubectl logs -n jellyfin deployment/jellyfin"
    echo "  • Port forward: kubectl port-forward -n jellyfin svc/jellyfin-service 8096:8096"
    echo "  • Scale replicas: kubectl scale deployment jellyfin -n jellyfin --replicas=3"
    echo ""
    
    warn "Note: If this is a migration from Podman, your existing configuration and library should be preserved."
    
else
    error "Jellyfin deployment failed"
    echo ""
    error "Troubleshooting steps:"
    echo "  1. Check cluster status: kubectl get nodes"
    echo "  2. Check storage: ansible storage_nodes -i $ANSIBLE_INVENTORY -m shell -a 'df -h /mnt/media'"
    echo "  3. Check logs: ansible-playbook -i $ANSIBLE_INVENTORY $JELLYFIN_PLAYBOOK -v"
    echo "  4. Verify permissions: ansible storage_nodes -i $ANSIBLE_INVENTORY -m shell -a 'ls -la /mnt/media'"
    exit 1
fi
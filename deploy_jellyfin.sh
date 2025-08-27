#!/bin/bash

# Jellyfin High-Availability Kubernetes Deployment Script
# Implements auto-scaling media server with session affinity

set -e

echo "=== Jellyfin HA Kubernetes Deployment ==="
echo "Timestamp: $(date)"
echo ""

# Configuration
ANSIBLE_INVENTORY="ansible/inventory.txt"
JELLYFIN_PLAYBOOK="ansible/plays/kubernetes/deploy_jellyfin.yaml"

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
    echo -e "${BLUE}[FEATURE]${NC} $1"
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

# Check if ansible-playbook is available
if ! command -v ansible-playbook &> /dev/null; then
    error "ansible-playbook command not found. Please install Ansible."
    exit 1
fi

# Check Kubernetes cluster
info "Verifying Kubernetes cluster is available..."
if kubectl cluster-info &>/dev/null; then
    info "Kubernetes cluster is accessible"
else
    error "Kubernetes cluster is not accessible. Please ensure cluster is running."
    exit 1
fi

# Check if metrics server is available for HPA
info "Checking metrics server for auto-scaling..."
if kubectl top nodes &>/dev/null; then
    info "Metrics server is running - auto-scaling will work"
else
    warn "Metrics server not found - auto-scaling may not work properly"
fi

info "Pre-flight checks completed successfully"
echo ""

# Display deployment information
highlight "High-Availability Jellyfin Features:"
highlight "✓ Auto-scaling: 1-3 pods based on CPU/Memory usage"
highlight "✓ Session affinity: Users stick to same pod during streaming"
highlight "✓ Hardware acceleration: Intel/AMD GPU support for transcoding"
highlight "✓ Resource limits: 2-2.5GB RAM per pod (8GB total system)"
highlight "✓ Large file support: 50GB uploads for media management"
highlight "✓ Load balancing: Automatic traffic distribution"
highlight "✓ Persistent storage: Configurable media directory path"
highlight "✓ Monitoring: Grafana dashboard integration"
echo ""

# Check existing Podman setup
info "Checking for existing Podman Jellyfin..."
STORAGE_NODE=$(grep -A1 "\[storage_nodes\]" "$ANSIBLE_INVENTORY" | tail -1 | awk '{print $1}')
if [ -n "$STORAGE_NODE" ]; then
    info "Storage node identified: $STORAGE_NODE"
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$STORAGE_NODE" "podman ps | grep jellyfin" 2>/dev/null; then
        warn "Existing Podman Jellyfin container found on storage node"
        warn "This deployment will create a parallel Kubernetes version"
        warn "Test the K8s version before stopping the Podman container"
    fi
fi

# Syntax check
info "Performing syntax check..."
if ansible-playbook --syntax-check -i "$ANSIBLE_INVENTORY" "$JELLYFIN_PLAYBOOK"; then
    info "Syntax check passed"
else
    error "Syntax check failed"
    exit 1
fi
echo ""

# Test connectivity
info "Testing connectivity to cluster nodes..."
if ansible all -i "$ANSIBLE_INVENTORY" -m ping; then
    info "All nodes are reachable"
else
    error "Some nodes are not reachable"
    exit 1
fi
echo ""

# Confirm deployment
warn "This will deploy Jellyfin with the following configuration:"
warn "- Namespace: jellyfin"
warn "- NodePort: 30096 (HTTP), 30920 (HTTPS)"
warn "- Storage: configurable media path, /mnt/jellyfin-config (read-write)"
warn "- Auto-scaling: 1-3 pods based on load"
warn "- Memory limit: 2.5GB per pod"
echo ""
warn "Continue with deployment? (y/N)"
read -r response
if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    info "Deployment cancelled"
    exit 0
fi

# Deploy Jellyfin
info "Starting Jellyfin HA deployment..."
echo ""

if ansible-playbook -i "$ANSIBLE_INVENTORY" "$JELLYFIN_PLAYBOOK" -v; then
    echo ""
    info "Jellyfin HA deployment completed successfully!"
    echo ""
    
    # Display access information
    CONTROL_PLANE_IP=$(kubectl get nodes -o wide | grep control-plane | awk '{print $6}' | head -1)
    if [ -z "$CONTROL_PLANE_IP" ]; then
        CONTROL_PLANE_IP="192.168.4.63"  # Fallback to monitoring node
    fi
    
    highlight "Access Information:"
    highlight "Primary URL: http://$CONTROL_PLANE_IP:30096"
    highlight "HTTPS URL: https://$CONTROL_PLANE_IP:30920"
    highlight "Direct Storage: http://$STORAGE_NODE:30096"
    echo ""
    
    highlight "Auto-Scaling Configuration:"
    highlight "• Minimum pods: 1 (single user)"
    highlight "• Maximum pods: 3 (multiple users)"
    highlight "• Scale trigger: >60% CPU or >70% memory"
    highlight "• Session persistence: 3 hours"
    echo ""
    
    info "Monitoring Integration:"
    info "• ServiceMonitor created for Prometheus"
    info "• Access metrics in Grafana dashboard"
    info "• Monitor scaling in real-time"
    echo ""
    
    info "Next Steps:"
    info "1. Access Jellyfin at http://$CONTROL_PLANE_IP:30096"
    info "2. Configure media libraries (should auto-detect existing)"
    info "3. Test streaming with multiple users to verify auto-scaling"
    info "4. Monitor resource usage: kubectl top pods -n jellyfin"
    info "5. Check auto-scaling: kubectl get hpa -n jellyfin"
    info "6. Stop old Podman container when satisfied: ssh $STORAGE_NODE 'podman stop jellyfin'"
    
    # Run quick validation
    echo ""
    info "Running post-deployment validation..."
    kubectl get pods -n jellyfin
    kubectl get svc -n jellyfin
    kubectl get hpa -n jellyfin
    
else
    error "Jellyfin HA deployment failed"
    echo ""
    error "Troubleshooting tips:"
    error "1. Check cluster status: kubectl get nodes"
    error "2. Check storage availability: kubectl get pv,pvc"
    error "3. Check pod logs: kubectl logs -n jellyfin -l app=jellyfin"
    error "4. Check events: kubectl get events -n jellyfin"
    exit 1
fi
#!/bin/bash

# VMStation Kubernetes Deployment Script
# Deploys the VMStation monitoring stack with proper node targeting

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

echo "=== VMStation Kubernetes Deployment ==="
echo "Timestamp: $(date)"
echo ""

info "Deploying Kubernetes-based VMStation with monitoring on masternode"

# Verify we're running on the correct node (monitoring node)
EXPECTED_MONITORING_IP="192.168.4.63"
CURRENT_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+' 2>/dev/null || hostname -I | awk '{print $1}')

if [[ "$CURRENT_IP" != "$EXPECTED_MONITORING_IP" ]]; then
    warn "Current IP ($CURRENT_IP) does not match expected monitoring node IP ($EXPECTED_MONITORING_IP)"
    warn "This deployment should be run from the masternode (192.168.4.63)"
    warn "Continuing anyway, but monitoring may not be scheduled correctly..."
fi

# Check if kubectl is available and can connect
if ! command -v kubectl &> /dev/null; then
    error "kubectl not found. Please ensure Kubernetes is installed and configured."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    error "Cannot connect to Kubernetes cluster. Please check kubeconfig."
    exit 1
fi

info "Connected to Kubernetes cluster successfully"

# Deploy monitoring stack using the dedicated playbook
info "Deploying monitoring stack (Prometheus, Alertmanager, Grafana, Loki)..."

if [ -f "ansible/plays/kubernetes/deploy_monitoring.yaml" ]; then
    # Run the monitoring deployment playbook
    if ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml; then
        info "✓ Monitoring stack deployment completed successfully"
    else
        error "Failed to deploy monitoring stack"
        exit 1
    fi
else
    error "Monitoring deployment playbook not found at ansible/plays/kubernetes/deploy_monitoring.yaml"
    exit 1
fi

# Verify deployment
info "Verifying monitoring pod deployment..."

# Wait a bit for pods to start
sleep 10

# Check monitoring namespace
if kubectl get namespace monitoring &> /dev/null; then
    info "✓ Monitoring namespace exists"
    
    # Show pod status
    echo ""
    info "Current monitoring pod status:"
    kubectl get pods -n monitoring -o wide
    
    echo ""
    info "Node labels and monitoring pod placement:"
    kubectl get nodes --show-labels | grep -E "(NAME|monitoring)" || true
    
    # Check if any pods are on the wrong nodes
    HOMELAB_NODE_IP="192.168.4.62"
    HOMELAB_PODS=$(kubectl get pods -n monitoring -o wide | grep "$HOMELAB_NODE_IP" || true)
    
    if [[ -n "$HOMELAB_PODS" ]]; then
        warn "Found monitoring pods scheduled on homelab node ($HOMELAB_NODE_IP):"
        echo "$HOMELAB_PODS"
        warn "This indicates incorrect node labeling. Monitoring should only run on masternode."
        warn "Run ./scripts/setup_monitoring_node_labels.sh to fix labeling issues."
    else
        info "✓ No monitoring pods found on homelab node - correct scheduling"
    fi
    
    # Show service endpoints
    echo ""
    info "Monitoring service endpoints:"
    kubectl get services -n monitoring -o wide
    
else
    warn "Monitoring namespace not found - deployment may have failed"
fi

echo ""
info "Kubernetes deployment completed!"
info "Access URLs (from masternode $EXPECTED_MONITORING_IP):"
info "  - Grafana: http://$EXPECTED_MONITORING_IP:30300"
info "  - Prometheus: http://$EXPECTED_MONITORING_IP:30090"
info "  - AlertManager: http://$EXPECTED_MONITORING_IP:30903"
info "  - Loki: http://$EXPECTED_MONITORING_IP:31100"
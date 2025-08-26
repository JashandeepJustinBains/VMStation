#!/bin/bash

# VMStation Kubernetes Deployment Script
# Replaces the Podman-based deployment with Kubernetes cluster setup

set -e

echo "=== VMStation Kubernetes Deployment ==="
echo "Timestamp: $(date)"
echo ""

# Configuration
ANSIBLE_INVENTORY="ansible/inventory.txt"
KUBERNETES_PLAYBOOK="ansible/plays/kubernetes_stack.yaml"

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

# Pre-flight checks
info "Performing pre-flight checks..."

if [ ! -f "$ANSIBLE_INVENTORY" ]; then
    error "Ansible inventory file not found: $ANSIBLE_INVENTORY"
    exit 1
fi

if [ ! -f "$KUBERNETES_PLAYBOOK" ]; then
    error "Kubernetes playbook not found: $KUBERNETES_PLAYBOOK"
    exit 1
fi

# Check if ansible-playbook is available
if ! command -v ansible-playbook &> /dev/null; then
    error "ansible-playbook command not found. Please install Ansible."
    exit 1
fi

# Check if group_vars/all.yml exists
if [ ! -f "ansible/group_vars/all.yml" ]; then
    warn "ansible/group_vars/all.yml not found"
    if [ -f "ansible/group_vars/all.yml.template" ]; then
        info "Creating all.yml from template..."
        cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml
        warn "Please review and customize ansible/group_vars/all.yml before continuing"
        warn "Press Enter to continue or Ctrl+C to abort..."
        read
    else
        error "No configuration template found"
        exit 1
    fi
fi

info "Pre-flight checks completed successfully"
echo ""

# Syntax check
info "Performing syntax check..."
if ansible-playbook --syntax-check -i "$ANSIBLE_INVENTORY" "$KUBERNETES_PLAYBOOK"; then
    info "Syntax check passed"
else
    error "Syntax check failed"
    exit 1
fi
echo ""

# Test connectivity to all nodes
info "Testing connectivity to all nodes..."
if ansible all -i "$ANSIBLE_INVENTORY" -m ping; then
    info "All nodes are reachable"
else
    error "Some nodes are not reachable"
    exit 1
fi
echo ""

# Confirm deployment
warn "This will set up a Kubernetes cluster and replace any existing Podman-based monitoring"
warn "Continue with deployment? (y/N)"
read -r response
if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    info "Deployment cancelled"
    exit 0
fi

# Deploy Kubernetes stack
info "Starting Kubernetes deployment..."
echo ""

if ansible-playbook -i "$ANSIBLE_INVENTORY" "$KUBERNETES_PLAYBOOK" -v; then
    echo ""
    info "Kubernetes deployment completed successfully!"
    echo ""
    
    info "Running validation..."
    if [ -f "scripts/validate_k8s_monitoring.sh" ]; then
        ./scripts/validate_k8s_monitoring.sh
    else
        warn "Validation script not found"
    fi
    
    echo ""
    info "Deployment Summary:"
    info "- Kubernetes cluster set up with monitoring_nodes as control plane"
    info "- cert-manager installed for TLS certificate management"
    info "- Monitoring stack deployed with Helm (Prometheus, Grafana, Loki)"
    info "- All services available via NodePort"
    echo ""
    info "Next steps:"
    info "1. Access Grafana at http://192.168.4.63:30300 (admin/admin)"
    info "2. Access Prometheus at http://192.168.4.63:30090"
    info "3. Access Loki at http://192.168.4.63:31100"
    info "4. Configure firewall rules if needed"
    info "5. Set up ingress for external access (optional)"
    
else
    error "Kubernetes deployment failed"
    exit 1
fi
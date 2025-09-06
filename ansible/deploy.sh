#!/bin/bash

# VMStation Deployment Script
# Supports both legacy Podman and new Kubernetes deployments

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

echo "=== VMStation Deployment ==="
echo "Timestamp: $(date)"
echo ""

# Check if configuration exists
if [ ! -f "ansible/group_vars/all.yml" ]; then
    if [ -f "ansible/group_vars/all.yml.template" ]; then
        warn "Configuration file not found. Creating from template..."
        cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml
        info "✓ Created ansible/group_vars/all.yml from template"
        info "Using default configuration - you may customize it if needed"
    else
        error "No configuration template found"
        exit 1
    fi
fi

# Setup monitoring prerequisites if Kubernetes mode
if [ -f "scripts/fix_monitoring_permissions.sh" ]; then
    info "Setting up monitoring directories and permissions..."
    chmod +x scripts/fix_monitoring_permissions.sh
    if sudo -n true 2>/dev/null; then
        info "Running monitoring permission setup with sudo..."
        sudo ./scripts/fix_monitoring_permissions.sh
    else
        warn "Cannot run sudo commands automatically."
        warn "You may need to run this manually before deployment:"
        warn "  sudo ./scripts/fix_monitoring_permissions.sh"
        warn ""
        warn "Continuing with deployment - some monitoring components may fail without proper permissions..."
    fi
else
    warn "Monitoring permission script not found at scripts/fix_monitoring_permissions.sh"
fi

# Setup monitoring node labels for proper scheduling
if [ -f "scripts/setup_monitoring_node_labels.sh" ]; then
    info "Setting up monitoring node labels for proper scheduling..."
    chmod +x scripts/setup_monitoring_node_labels.sh
    if ./scripts/setup_monitoring_node_labels.sh; then
        info "✓ Monitoring node labels configured successfully"
    else
        warn "Failed to setup monitoring node labels"
        warn "You may need to run this manually before deployment:"
        warn "  ./scripts/setup_monitoring_node_labels.sh"
        warn ""
        warn "Continuing with deployment - monitoring may deploy on wrong nodes without proper labels..."
    fi
else
    warn "Monitoring node label script not found at scripts/setup_monitoring_node_labels.sh"
fi

# Detect deployment mode
INFRASTRUCTURE_MODE="kubernetes"  # Default to Kubernetes
if grep -q "infrastructure_mode:.*podman" ansible/group_vars/all.yml 2>/dev/null; then
    INFRASTRUCTURE_MODE="podman"
elif grep -q "infrastructure_mode:.*kubernetes" ansible/group_vars/all.yml 2>/dev/null; then
    INFRASTRUCTURE_MODE="kubernetes"
fi

info "Detected infrastructure mode: $INFRASTRUCTURE_MODE"
echo ""

case "$INFRASTRUCTURE_MODE" in
    "kubernetes")
        info "Deploying Kubernetes-based VMStation..."
        if [ -f "./deploy_kubernetes.sh" ]; then
            ./deploy_kubernetes.sh
        else
            error "Kubernetes deployment script not found"
            exit 1
        fi
        ;;
    "podman")
        warn "Using legacy Podman deployment mode"
        warn "Consider migrating to Kubernetes for better features"
        info "Deploying Podman-based VMStation..."
        
        # Legacy deployment
        PLAYBOOK="ansible/plays/site.yaml"
        if [ ! -f "$PLAYBOOK" ]; then
            PLAYBOOK="ansible/plays/monitoring_stack.yaml"
        fi
        
        if [ -f ~/.vault_pass.txt ]; then
            ansible-playbook -i ansible/inventory.txt --vault-password-file ~/.vault_pass.txt "$PLAYBOOK"
        else
            ansible-playbook -i ansible/inventory.txt "$PLAYBOOK"
        fi
        ;;
    *)
        error "Unknown infrastructure mode: $INFRASTRUCTURE_MODE"
        error "Please set infrastructure_mode to 'kubernetes' or 'podman' in ansible/group_vars/all.yml"
        exit 1
        ;;
esac

echo ""
info "Deployment completed for mode: $INFRASTRUCTURE_MODE"
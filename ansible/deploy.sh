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
        warn "Please review and customize ansible/group_vars/all.yml"
        warn "Set infrastructure_mode to either 'kubernetes' or 'podman'"
        exit 1
    else
        error "No configuration template found"
        exit 1
    fi
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
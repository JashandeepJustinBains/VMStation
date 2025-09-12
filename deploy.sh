#!/bin/bash

# VMStation Simplified Deployment Script
# Replaces the complex update_and_deploy.sh with clean, minimal deployment

set -e

echo "=== VMStation Simplified Deployment ==="
echo "Timestamp: $(date)"
echo

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Navigate to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
INVENTORY="ansible/inventory.txt"
CONFIG_FILE="ansible/group_vars/all.yml"

info "Simplified VMStation deployment starting..."

# Create config from template if needed
if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "ansible/group_vars/all.yml.template" ]; then
        info "Creating config from template..."
        cp ansible/group_vars/all.yml.template "$CONFIG_FILE"
    else
        error "No configuration template found"
        exit 1
    fi
fi

# Check basic requirements
if ! command -v ansible-playbook >/dev/null 2>&1; then
    error "ansible-playbook not found. Please install Ansible."
    exit 1
fi

if [ ! -f "$INVENTORY" ]; then
    error "Inventory file not found: $INVENTORY"
    exit 1
fi

# Deployment options
case "${1:-full}" in
    "cluster")
        info "Deploying Kubernetes cluster only..."
        ansible-playbook -i "$INVENTORY" ansible/plays/setup-cluster.yaml
        ;;
    "apps")
        info "Deploying applications only..."
        ansible-playbook -i "$INVENTORY" ansible/plays/deploy-apps.yaml
        ;;
    "jellyfin")
        info "Deploying Jellyfin only..."
        ansible-playbook -i "$INVENTORY" ansible/plays/jellyfin.yml
        ;;
    "spindown")
        warn "WARNING: This will completely remove Kubernetes and container infrastructure!"
        echo "This action will:"
        echo "  - Stop all Kubernetes services and containers"
        echo "  - Remove all Kubernetes packages and data"
        echo "  - Clean up network interfaces and iptables rules"
        echo "  - Remove container runtimes and configurations"
        echo "  - Clean up user configurations and caches"
        echo
        read -p "Are you sure you want to proceed? Type 'yes' to continue: " confirm
        if [ "$confirm" = "yes" ]; then
            info "Proceeding with destructive spindown..."
            ansible-playbook -i "$INVENTORY" ansible/subsites/00-spindown.yaml -e confirm_spindown=true
        else
            info "Spindown cancelled."
            exit 0
        fi
        ;;
    "spindown-check")
        info "Running spindown in check mode (safe dry-run)..."
        ansible-playbook -i "$INVENTORY" ansible/subsites/00-spindown.yaml --check
        ;;
    "full"|"")
        info "Deploying complete VMStation stack..."
        ansible-playbook -i "$INVENTORY" ansible/simple-deploy.yaml
        ;;
    "check")
        info "Running deployment checks..."
        ansible-playbook -i "$INVENTORY" ansible/simple-deploy.yaml --check
        ;;
    *)
        echo "Usage: $0 [cluster|apps|jellyfin|full|check|spindown|spindown-check]"
        echo
        echo "Options:"
        echo "  cluster       - Deploy Kubernetes cluster only"
        echo "  apps          - Deploy applications only (requires existing cluster)"
        echo "  jellyfin      - Deploy Jellyfin only"
        echo "  full          - Deploy complete stack (default)"
        echo "  check         - Run in check mode (dry run)"
        echo "  spindown      - DESTRUCTIVE: Remove all Kubernetes infrastructure"
        echo "  spindown-check - Show what spindown would remove (safe)"
        exit 1
        ;;
esac

info "Running post-deployment cluster validation..."

# Check for CoreDNS issues that can occur after flannel regeneration
if ! ./scripts/check_coredns_status.sh >/dev/null 2>&1; then
    warn "CoreDNS networking issues detected after deployment"
    info "Automatically applying CoreDNS fix..."
    
    if ./scripts/fix_coredns_unknown_status.sh; then
        info "CoreDNS fix applied successfully"
    else
        warn "CoreDNS fix failed - trying enhanced homelab node fix..."
        if ./scripts/fix_homelab_node_issues.sh; then
            info "Homelab node issues resolved"
        else
            warn "Standard fixes failed - checking for CNI bridge conflicts..."
            
            # Check for ContainerCreating pods as indicator of CNI issues
            STUCK_PODS=$(kubectl get pods --all-namespaces | grep "ContainerCreating" | wc -l)
            if [ "$STUCK_PODS" -gt 0 ]; then
                warn "Found $STUCK_PODS pods stuck in ContainerCreating - applying CNI bridge fix"
                if ./scripts/fix_cni_bridge_conflict.sh; then
                    info "CNI bridge conflict resolved"
                else
                    error "CNI bridge fix failed - manual intervention required"
                fi
            else
                warn "Cluster networking issues persist - manual intervention may be needed"
                echo "Run: ./scripts/fix_homelab_node_issues.sh"
            fi
        fi
    fi
else
    info "CoreDNS status check passed"
fi

info "Deployment completed successfully!"
echo
info "Access URLs:"
info "  - Grafana: http://192.168.4.63:30300"
info "  - Prometheus: http://192.168.4.63:30090"
info "  - Jellyfin: http://192.168.4.61:30096"

echo
info "To check status: kubectl get pods --all-namespaces"
info "To check CoreDNS: ./scripts/check_coredns_status.sh"
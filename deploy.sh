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

# Function to collect deployment logs
collect_deployment_logs() {
    local operation="$1"
    local log_file="deployment_logs_$(date +%Y%m%d_%H%M%S).txt"
    
    info "Collecting deployment logs for $operation..."
    echo "=== VMStation Deployment Logs ===" > "$log_file"
    echo "Operation: $operation" >> "$log_file"
    echo "Timestamp: $(date)" >> "$log_file"
    echo "Hostname: $(hostname)" >> "$log_file"
    echo "" >> "$log_file"
    
    # Collect system and Kubernetes service logs
    echo "=== System Service Logs ===" >> "$log_file"
    for service in kubelet containerd; do
        echo "--- $service logs (last 50 lines) ---" >> "$log_file"
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            journalctl -u "$service" --no-pager -l --since='5 minutes ago' 2>/dev/null | tail -50 >> "$log_file" || echo "Could not retrieve $service logs" >> "$log_file"
        else
            echo "$service service not active" >> "$log_file"
        fi
        echo "" >> "$log_file"
    done
    
    # Collect cluster status if available
    echo "=== Cluster Status ===" >> "$log_file"
    if command -v kubectl >/dev/null 2>&1; then
        kubectl cluster-info 2>/dev/null >> "$log_file" || echo "Cluster info not available" >> "$log_file"
        echo "" >> "$log_file"
        kubectl get nodes -o wide 2>/dev/null >> "$log_file" || echo "Node information not available" >> "$log_file"
        echo "" >> "$log_file"
    else
        echo "kubectl not available" >> "$log_file"
    fi
    
    info "Deployment logs saved to: $log_file"
}

# Deployment options
case "${1:-full}" in
    "cluster")
        info "Deploying Kubernetes cluster only..."
        
        # Start log collection in background if on control plane
        if [[ $(hostname -I | awk '{print $1}') =~ ^192\.168\.4\.(63|61|62)$ ]]; then
            collect_deployment_logs "cluster" &
            LOG_PID=$!
        fi
        
        ansible-playbook -i "$INVENTORY" ansible/plays/setup-cluster.yaml
        
        # Wait for log collection to complete
        if [ ! -z "$LOG_PID" ]; then
            wait $LOG_PID
        fi
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

info "Deployment completed successfully!"
echo
info "Access URLs:"
info "  - Grafana: http://192.168.4.63:30300"
info "  - Prometheus: http://192.168.4.63:30090"
info "  - Jellyfin: http://192.168.4.61:30096"

echo
info "To check status: kubectl get pods --all-namespaces"
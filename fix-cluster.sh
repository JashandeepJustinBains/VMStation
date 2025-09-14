#!/bin/bash

# VMStation One-Command Fix Script
# Fixes CNI bridge issues and deploys working cluster

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"  # Ensure we're in the script's directory for relative paths
ANSIBLE_DIR="ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory/hosts.yml"
PLAYBOOK="$ANSIBLE_DIR/playbooks/minimal-network-fix.yml"

echo "=== VMStation One-Command Fix ==="
echo "Timestamp: $(date)"
echo "Purpose: Fix CNI bridge issues and deploy working Kubernetes cluster"
echo ""

# Check prerequisites
info "Checking prerequisites..."

if [ ! -f "$INVENTORY_FILE" ]; then
    error "Ansible inventory not found: $INVENTORY_FILE"
    exit 1
fi

if [ ! -f "$PLAYBOOK" ]; then
    error "Ansible playbook not found: $PLAYBOOK"
    exit 1
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
    error "ansible-playbook not found. Please install Ansible."
    exit 1
fi

# Check if kubernetes.core collection is available
if ! ansible-galaxy collection list kubernetes.core >/dev/null 2>&1; then
    info "Installing kubernetes.core collection..."
    ansible-galaxy collection install kubernetes.core
fi

success "Prerequisites check passed"

# Run the minimal network fix playbook
info "Running minimal network fix playbook..."
echo "Playbook: $PLAYBOOK"
echo "Inventory: $INVENTORY_FILE"
echo ""

if ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK"; then
    success "🎉 VMStation cluster fix completed successfully!"
    echo ""
    info "=== Next Steps ==="
    echo "1. Check pod status: kubectl get pods --all-namespaces"
    echo "2. Access Jellyfin: http://192.168.4.61:30096"
    echo "3. If monitoring is needed, run: ansible-playbook -i $INVENTORY_FILE $ANSIBLE_DIR/plays/deploy-apps.yaml"
    echo ""
    success "Your cluster should now have working pod networking!"
else
    error "❌ Cluster fix failed!"
    echo ""
    error "=== Troubleshooting ==="
    echo "1. Check if you're running this on the control plane (masternode)"
    echo "2. Verify SSH access to all nodes"
    echo "3. Check kubelet status: systemctl status kubelet"
    echo "4. Check for CNI bridge issues: ip addr show cni0"
    echo "5. Check recent events: kubectl get events --all-namespaces"
    echo "6. If namespace termination issues persist, check: kubectl get namespace kube-flannel"
    echo "7. Manual namespace cleanup: kubectl patch namespace kube-flannel -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge"
    exit 1
fi
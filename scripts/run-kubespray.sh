#!/usr/bin/env bash
# VMStation Kubespray Integration Wrapper
# This script stages Kubespray for deployment without making actual cluster changes
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$REPO_ROOT/.cache"
KUBESPRAY_DIR="$CACHE_DIR/kubespray"
VENV_DIR="$KUBESPRAY_DIR/.venv"
KUBESPRAY_VERSION="${KUBESPRAY_VERSION:-v2.24.1}"

# Logging functions
log_info() { echo "[INFO] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_err() { echo "[ERROR] $*" >&2; exit 1; }

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# Clone or update Kubespray
if [[ -d "$KUBESPRAY_DIR/.git" ]]; then
    log_info "Updating existing Kubespray repository..."
    cd "$KUBESPRAY_DIR"
    git fetch --tags
    git checkout "$KUBESPRAY_VERSION" 2>/dev/null || {
        log_warn "Version $KUBESPRAY_VERSION not found, using latest main"
        git checkout main
        git pull
    }
else
    log_info "Cloning Kubespray repository..."
    git clone https://github.com/kubernetes-sigs/kubespray.git "$KUBESPRAY_DIR"
    cd "$KUBESPRAY_DIR"
    git checkout "$KUBESPRAY_VERSION" 2>/dev/null || {
        log_warn "Version $KUBESPRAY_VERSION not found, using latest main"
    }
fi

# Create virtual environment
log_info "Setting up Python virtual environment..."
if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
fi

# Activate virtual environment
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# Install requirements
log_info "Installing Kubespray requirements..."
pip install --upgrade pip setuptools wheel
pip install -r "$KUBESPRAY_DIR/requirements.txt"

# Create inventory template directory if not exists
INVENTORY_TEMPLATE_DIR="$KUBESPRAY_DIR/inventory/mycluster"
if [[ ! -d "$INVENTORY_TEMPLATE_DIR" ]]; then
    log_info "Creating inventory template..."
    cp -r "$KUBESPRAY_DIR/inventory/sample" "$INVENTORY_TEMPLATE_DIR"
fi

log_info "✅ Kubespray setup complete!"
echo ""
echo "=========================================="
echo "Next Steps for Kubespray Deployment"
echo "=========================================="
echo ""
echo "1. Edit the inventory file:"
echo "   $INVENTORY_TEMPLATE_DIR/inventory.ini"
echo ""
echo "2. Customize cluster variables:"
echo "   $INVENTORY_TEMPLATE_DIR/group_vars/all/all.yml"
echo "   $INVENTORY_TEMPLATE_DIR/group_vars/k8s_cluster/k8s-cluster.yml"
echo ""
echo "3. Run preflight checks on RHEL10 node:"
echo "   ansible-playbook -i ansible/inventory/hosts.yml \\"
echo "     -l compute_nodes \\"
echo "     -e 'target_hosts=compute_nodes' \\"
echo "     ansible/playbooks/run-preflight-rhel10.yml"
echo ""
echo "4. Deploy cluster with Kubespray:"
echo "   cd $KUBESPRAY_DIR"
echo "   source $VENV_DIR/bin/activate"
echo "   ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml"
echo ""
echo "5. Access your cluster:"
echo "   export KUBECONFIG=\$HOME/.kube/config"
echo "   kubectl get nodes"
echo ""
echo "=========================================="
echo "Kubespray Documentation:"
echo "  https://kubespray.io/"
echo "  $KUBESPRAY_DIR/docs/"
echo "=========================================="

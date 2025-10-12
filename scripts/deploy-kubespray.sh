#!/usr/bin/env bash
# VMStation Kubespray Deployment Script
# Automates Kubespray deployment for VMStation nodes
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$REPO_ROOT/.cache"
KUBESPRAY_DIR="$CACHE_DIR/kubespray"
VENV_DIR="$KUBESPRAY_DIR/.venv"
KUBESPRAY_VERSION="${KUBESPRAY_VERSION:-v2.24.1}"
INVENTORY_FILE="$REPO_ROOT/ansible/inventory/hosts.yml"
KUBESPRAY_INVENTORY_DIR="$KUBESPRAY_DIR/inventory/vmstation"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/ansible/artifacts}"

# Logging functions
log_info() { echo "[INFO] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_err() { echo "[ERROR] $*" >&2; exit 1; }

# Parse arguments
SKIP_SETUP=false
DRY_RUN=false
AUTO_YES=false
TARGET_NODES="${TARGET_NODES:-monitoring_nodes,storage_nodes}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-setup)
      SKIP_SETUP=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --yes)
      AUTO_YES=true
      shift
      ;;
    --target)
      TARGET_NODES="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"
mkdir -p "$LOG_DIR"

# Setup Kubespray if not skipped
if [[ "$SKIP_SETUP" != "true" ]]; then
  log_info "Setting up Kubespray..."
  
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
  
  # Create virtual environment if missing
  log_info "Setting up Python virtual environment..."
  if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
  fi
  
  # Install requirements
  "$VENV_DIR/bin/pip" install -U pip setuptools wheel >/dev/null 2>&1
  if [ -f "$KUBESPRAY_DIR/requirements.txt" ]; then
    log_info "Installing Kubespray requirements..."
    "$VENV_DIR/bin/pip" install -r "$KUBESPRAY_DIR/requirements.txt" >/dev/null 2>&1
  fi
fi

# Activate virtual environment
. "$VENV_DIR/bin/activate"

# Generate Kubespray inventory from VMStation hosts.yml
log_info "Generating Kubespray inventory from $INVENTORY_FILE..."
mkdir -p "$KUBESPRAY_INVENTORY_DIR/group_vars"

# Create inventory.ini from hosts.yml
python3 - "$INVENTORY_FILE" "$KUBESPRAY_INVENTORY_DIR" <<'PYTHON'
import sys
import yaml
import os

hosts_yml = sys.argv[1]
inv_dir = sys.argv[2]

with open(hosts_yml, 'r') as f:
    inventory = yaml.safe_load(f)

# Extract nodes
monitoring_nodes = inventory.get('monitoring_nodes', {}).get('hosts', {})
storage_nodes = inventory.get('storage_nodes', {}).get('hosts', {})

# Combine for Kubespray cluster
all_nodes = {}
all_nodes.update(monitoring_nodes)
all_nodes.update(storage_nodes)

# Generate inventory.ini
inventory_ini = os.path.join(inv_dir, 'inventory.ini')
with open(inventory_ini, 'w') as f:
    # Write nodes
    f.write("[all]\n")
    for name, config in all_nodes.items():
        ansible_host = config.get('ansible_host', name)
        ansible_user = config.get('ansible_user', 'root')
        f.write(f"{name} ansible_host={ansible_host} ip={ansible_host} ansible_user={ansible_user}\n")
    f.write("\n")
    
    # Kube control plane (masternode)
    f.write("[kube_control_plane]\n")
    for name in monitoring_nodes.keys():
        f.write(f"{name}\n")
    f.write("\n")
    
    # Kube nodes (all nodes)
    f.write("[kube_node]\n")
    for name in all_nodes.keys():
        f.write(f"{name}\n")
    f.write("\n")
    
    # Etcd (masternode)
    f.write("[etcd]\n")
    for name in monitoring_nodes.keys():
        f.write(f"{name}\n")
    f.write("\n")
    
    # K8s cluster
    f.write("[k8s_cluster:children]\n")
    f.write("kube_control_plane\n")
    f.write("kube_node\n")
    f.write("\n")
    
    # Calico RR (optional)
    f.write("[calico_rr]\n")
    f.write("\n")

print(f"Generated Kubespray inventory at {inventory_ini}")
PYTHON

# Copy sample group_vars if they don't exist
if [[ ! -d "$KUBESPRAY_INVENTORY_DIR/group_vars/all" ]]; then
  log_info "Copying sample group_vars..."
  cp -r "$KUBESPRAY_DIR/inventory/sample/group_vars" "$KUBESPRAY_INVENTORY_DIR/"
fi

# Customize k8s-cluster.yml for VMStation
log_info "Customizing Kubespray configuration..."
cat > "$KUBESPRAY_INVENTORY_DIR/group_vars/k8s_cluster/vmstation.yml" <<EOF
---
# VMStation Kubespray Configuration Overrides

# Use Flannel CNI to match previous deployment
kube_network_plugin: flannel
kube_network_plugin_multus: false

# Kubernetes version
kube_version: v1.29.0

# Service and pod network CIDRs
kube_service_addresses: 10.96.0.0/12
kube_pods_subnet: 10.244.0.0/16

# Enable metrics server
metrics_server_enabled: true

# Container runtime
container_manager: containerd

# Enable kubectl on all nodes
kubectl_localhost: false
kubeconfig_localhost: true

# Persistent storage for monitoring
helm_enabled: true
EOF

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "DRY-RUN: Would execute Kubespray deployment"
  log_info "  Inventory: $KUBESPRAY_INVENTORY_DIR/inventory.ini"
  log_info "  Playbook: $KUBESPRAY_DIR/cluster.yml"
  log_info "  Log: $LOG_DIR/deploy-kubespray.log"
  exit 0
fi

# Run Kubespray deployment
log_info "Starting Kubespray deployment (this may take 15-20 minutes)..."
log_info "Log: $LOG_DIR/deploy-kubespray.log"

cd "$KUBESPRAY_DIR"

# Run cluster.yml playbook
ANSIBLE_FORCE_COLOR=true ansible-playbook \
  -i "$KUBESPRAY_INVENTORY_DIR/inventory.ini" \
  cluster.yml \
  2>&1 | tee "$LOG_DIR/deploy-kubespray.log"

deploy_result=${PIPESTATUS[0]}

if [[ $deploy_result -eq 0 ]]; then
  log_info "✓ Kubespray deployment completed successfully"
  
  # Copy kubeconfig to standard location
  if [[ -f "$HOME/.kube/config" ]]; then
    log_info "Kubeconfig available at: $HOME/.kube/config"
  fi
  
  exit 0
else
  log_err "Kubespray deployment failed - check logs: $LOG_DIR/deploy-kubespray.log"
fi

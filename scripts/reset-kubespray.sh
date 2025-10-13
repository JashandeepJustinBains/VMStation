#!/usr/bin/env bash
# VMStation Kubespray Reset Script
# Resets Kubespray-deployed Kubernetes cluster
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$REPO_ROOT/.cache"
KUBESPRAY_DIR="$CACHE_DIR/kubespray"
VENV_DIR="$KUBESPRAY_DIR/.venv"
INVENTORY_FILE="$REPO_ROOT/ansible/inventory/hosts.yml"
KUBESPRAY_INVENTORY_DIR="$KUBESPRAY_DIR/inventory/vmstation"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/ansible/artifacts}"

# Logging functions
log_info() { echo "[INFO] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_err() { echo "[ERROR] $*" >&2; exit 1; }

# Parse arguments
DRY_RUN=false
AUTO_YES=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --yes)
      AUTO_YES=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Ensure cache directory exists
mkdir -p "$LOG_DIR"

# Check if Kubespray is available
if [[ ! -d "$KUBESPRAY_DIR" ]]; then
  log_info "Kubespray not found - cluster may not have been deployed with Kubespray"
  log_info "Falling back to standard reset playbook..."
  exit 0
fi

# Check if inventory exists
if [[ ! -f "$KUBESPRAY_INVENTORY_DIR/inventory.ini" ]]; then
  log_info "Kubespray inventory not found - generating from hosts.yml..."
  
  # Generate inventory
  mkdir -p "$KUBESPRAY_INVENTORY_DIR/group_vars"
  
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

print(f"Generated inventory at {inventory_ini}")
PYTHON
fi

# Activate virtual environment if it exists
if [[ -f "$VENV_DIR/bin/activate" ]]; then
  . "$VENV_DIR/bin/activate"
else
  log_warn "Virtual environment not found - using system Python"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log_info "DRY-RUN: Would execute Kubespray reset"
  log_info "  Inventory: $KUBESPRAY_INVENTORY_DIR/inventory.ini"
  log_info "  Playbook: $KUBESPRAY_DIR/reset.yml"
  log_info "  Log: $LOG_DIR/reset-kubespray.log"
  exit 0
fi

# Run Kubespray reset
log_info "Resetting Kubespray cluster..."
log_info "Log: $LOG_DIR/reset-kubespray.log"

cd "$KUBESPRAY_DIR"

# Run reset.yml playbook
ANSIBLE_FORCE_COLOR=true ansible-playbook \
  -i "$KUBESPRAY_INVENTORY_DIR/inventory.ini" \
  reset.yml \
  --become \
  -e "reset_confirmation=yes" \
  2>&1 | tee "$LOG_DIR/reset-kubespray.log"

reset_result=${PIPESTATUS[0]}

if [[ $reset_result -eq 0 ]]; then
  log_info "✓ Kubespray cluster reset completed successfully"
  exit 0
else
  log_err "Kubespray cluster reset failed - check logs: $LOG_DIR/reset-kubespray.log"
fi

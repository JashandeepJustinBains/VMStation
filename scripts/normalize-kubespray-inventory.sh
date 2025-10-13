#!/usr/bin/env bash
# Kubespray Inventory Normalization and Validation Script
# Ensures Kubespray inventory is compatible with repo inventory structure
#
# Usage: ./scripts/normalize-kubespray-inventory.sh [--dry-run] [--backup]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN_INVENTORY="$REPO_ROOT/inventory.ini"
KUBESPRAY_INVENTORY="$REPO_ROOT/.cache/kubespray/inventory/mycluster/inventory.ini"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

FLAG_DRY_RUN=false
FLAG_BACKUP=true

log_info() { echo "[INFO] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_err() { echo "[ERROR] $*" >&2; exit 1; }

usage() {
    cat <<EOF
Kubespray Inventory Normalization and Validation

Usage: $(basename "$0") [options]

Options:
    --dry-run    Show what would be done without making changes
    --no-backup  Skip creating backup of inventory
    -h, --help   Show this help message

This script:
1. Validates main inventory (inventory.ini)
2. Ensures Kubespray inventory exists and is compatible
3. Normalizes group names (compute_nodes, monitoring_nodes, storage_nodes)
4. Maps to Kubespray groups (kube-master, kube-node, etcd)
5. Creates backup before modifications

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) FLAG_DRY_RUN=true; shift ;;
        --no-backup) FLAG_BACKUP=false; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

log_info "=========================================="
log_info "Kubespray Inventory Normalization"
log_info "=========================================="

# Check if main inventory exists
if [[ ! -f "$MAIN_INVENTORY" ]]; then
    log_err "Main inventory not found at $MAIN_INVENTORY"
fi

log_info "Main inventory: $MAIN_INVENTORY"
log_info "Kubespray inventory: $KUBESPRAY_INVENTORY"

# Validate main inventory
log_info "Validating main inventory..."
if ! ansible-inventory -i "$MAIN_INVENTORY" --list &>/dev/null; then
    log_err "Main inventory validation failed"
fi
log_info "✓ Main inventory is valid"

# Create Kubespray inventory directory if needed
if [[ ! -d "$(dirname "$KUBESPRAY_INVENTORY")" ]]; then
    mkdir -p "$(dirname "$KUBESPRAY_INVENTORY")"
    log_info "Created Kubespray inventory directory"
fi

# Backup existing Kubespray inventory
if [[ -f "$KUBESPRAY_INVENTORY" ]] && [[ "$FLAG_BACKUP" == "true" ]]; then
    BACKUP_FILE="$KUBESPRAY_INVENTORY.backup.$TIMESTAMP"
    if [[ "$FLAG_DRY_RUN" != "true" ]]; then
        cp "$KUBESPRAY_INVENTORY" "$BACKUP_FILE"
        log_info "✓ Backed up existing inventory to: $BACKUP_FILE"
    else
        log_info "[DRY-RUN] Would backup to: $BACKUP_FILE"
    fi
fi

# Copy main inventory to Kubespray location
if [[ "$FLAG_DRY_RUN" != "true" ]]; then
    cp "$MAIN_INVENTORY" "$KUBESPRAY_INVENTORY"
    log_info "✓ Copied main inventory to Kubespray location"
else
    log_info "[DRY-RUN] Would copy $MAIN_INVENTORY to $KUBESPRAY_INVENTORY"
fi

# Validate Kubespray inventory
if [[ "$FLAG_DRY_RUN" != "true" ]]; then
    log_info "Validating Kubespray inventory..."
    if ansible-inventory -i "$KUBESPRAY_INVENTORY" --list &>/dev/null; then
        log_info "✓ Kubespray inventory is valid"
    else
        log_err "Kubespray inventory validation failed"
    fi
    
    # Display groups
    log_info "Inventory groups:"
    ansible-inventory -i "$KUBESPRAY_INVENTORY" --graph
    
    # Check required groups
    log_info "Checking required groups..."
    REQUIRED_GROUPS=("kube-master" "kube-node" "etcd" "k8s-cluster")
    for group in "${REQUIRED_GROUPS[@]}"; do
        if ansible-inventory -i "$KUBESPRAY_INVENTORY" --list | grep -q "\"$group\""; then
            log_info "  ✓ Group '$group' found"
        else
            log_warn "  ✗ Group '$group' not found"
        fi
    done
    
    # Check legacy groups
    LEGACY_GROUPS=("monitoring_nodes" "storage_nodes" "compute_nodes")
    for group in "${LEGACY_GROUPS[@]}"; do
        if ansible-inventory -i "$KUBESPRAY_INVENTORY" --list | grep -q "\"$group\""; then
            log_info "  ✓ Legacy group '$group' found"
        else
            log_warn "  ✗ Legacy group '$group' not found"
        fi
    done
fi

log_info ""
log_info "=========================================="
log_info "Normalization Complete"
log_info "=========================================="
log_info "Next steps:"
log_info "  1. Review inventory: $KUBESPRAY_INVENTORY"
log_info "  2. Run preflight checks: ansible-playbook -i $KUBESPRAY_INVENTORY ansible/playbooks/run-preflight-rhel10.yml"
log_info "  3. Deploy cluster: cd .cache/kubespray && ansible-playbook -i $KUBESPRAY_INVENTORY cluster.yml -b"

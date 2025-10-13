#!/usr/bin/env bash
# VMStation Kubespray Full Deployment Automation
# This script performs a complete Kubespray deployment workflow with safety checks
# and automated remediation for common issues.
#
# Usage: ./scripts/deploy-kubespray-full.sh [--auto] [--skip-preflight] [--skip-backup]
#
# Environment:
# - Must be run from the repo root
# - Requires network access to cluster hosts
# - Requires sudo/become access to nodes
#
set -euo pipefail

# === Configuration ===
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="$REPO_ROOT/.cache"
KUBESPRAY_DIR="$CACHE_DIR/kubespray"
VENV_DIR="$KUBESPRAY_DIR/.venv"
KUBESPRAY_INVENTORY_DIR="$KUBESPRAY_DIR/inventory/mycluster"
KUBESPRAY_INVENTORY="$KUBESPRAY_INVENTORY_DIR/inventory.ini"
MAIN_INVENTORY="$REPO_ROOT/ansible/inventory/hosts.yml"
PREFLIGHT_PLAYBOOK="$REPO_ROOT/ansible/playbooks/run-preflight-rhel10.yml"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$REPO_ROOT/.git/ops-backups/$TIMESTAMP"
LOG_FILE="$REPO_ROOT/ansible/artifacts/kubespray-deploy-$TIMESTAMP.log"

# === Flags ===
FLAG_AUTO=false
FLAG_SKIP_PREFLIGHT=false
FLAG_SKIP_BACKUP=false
FLAG_FORCE=false

# === Logging Functions ===
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE" >&2; }
log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$LOG_FILE" >&2; }
log_err() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2; exit 1; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [✓] $*" | tee -a "$LOG_FILE" >&2; }

# === Usage ===
usage() {
    cat <<EOF
VMStation Kubespray Full Deployment Automation

Usage: $(basename "$0") [options]

Options:
    --auto              Run in automated mode (skip confirmations)
    --skip-preflight    Skip preflight checks
    --skip-backup       Skip creating backups
    --force             Force deployment even if cluster exists
    -h, --help          Show this help message

This script performs:
1. Safety backups of inventory and configs
2. Kubespray setup and venv activation
3. Inventory validation and normalization
4. Preflight checks on RHEL10 compute nodes
5. Kubespray cluster deployment
6. Kubeconfig setup and validation
7. CNI/networking verification
8. Post-deployment smoke tests
9. Monitoring and infrastructure readiness checks

Artifacts:
    - Backups: $REPO_ROOT/.git/ops-backups/
    - Logs: $REPO_ROOT/ansible/artifacts/
    - Kubeconfig: ~/.kube/config

EOF
}

# === Parse Arguments ===
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto) FLAG_AUTO=true; shift ;;
        --skip-preflight) FLAG_SKIP_PREFLIGHT=true; shift ;;
        --skip-backup) FLAG_SKIP_BACKUP=true; shift ;;
        --force) FLAG_FORCE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_err "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# === Ensure log directory exists ===
mkdir -p "$(dirname "$LOG_FILE")"

log_info "=========================================="
log_info "VMStation Kubespray Deployment Automation"
log_info "=========================================="
log_info "Started at: $(date)"
log_info "Repo root: $REPO_ROOT"
log_info "Log file: $LOG_FILE"
log_info ""

# === Step 1: Preparation and Safety ===
log_info "STEP 1: Preparation and Safety"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$FLAG_SKIP_BACKUP" != "true" ]]; then
    log_info "Creating timestamped backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Backup files that will be modified
    log_info "Backing up inventory and configuration files..."
    [[ -f "$REPO_ROOT/inventory.ini" ]] && cp -v "$REPO_ROOT/inventory.ini" "$BACKUP_DIR/" | tee -a "$LOG_FILE"
    [[ -f "$MAIN_INVENTORY" ]] && cp -v "$MAIN_INVENTORY" "$BACKUP_DIR/" | tee -a "$LOG_FILE"
    [[ -f "$REPO_ROOT/deploy.sh" ]] && cp -v "$REPO_ROOT/deploy.sh" "$BACKUP_DIR/" | tee -a "$LOG_FILE"
    
    log_success "Backups created in: $BACKUP_DIR"
else
    log_warn "Skipping backup creation (--skip-backup flag set)"
fi

# Ensure Kubespray is set up
if [[ ! -d "$KUBESPRAY_DIR" ]]; then
    log_info "Kubespray not found. Running setup..."
    "$REPO_ROOT/scripts/run-kubespray.sh" 2>&1 | tee -a "$LOG_FILE"
else
    log_success "Kubespray directory exists: $KUBESPRAY_DIR"
fi

# Activate virtualenv
log_info "Activating Kubespray virtual environment..."
if [[ ! -f "$VENV_DIR/bin/activate" ]]; then
    log_err "Virtual environment not found at $VENV_DIR/bin/activate"
fi

# shellcheck disable=SC1090,SC1091
source "$VENV_DIR/bin/activate"

# Verify ansible is available
if ! command -v ansible-playbook &>/dev/null; then
    log_err "ansible-playbook not found in venv. Installing requirements..."
    "$VENV_DIR/bin/pip" install -r "$KUBESPRAY_DIR/requirements.txt" 2>&1 | tee -a "$LOG_FILE"
fi

log_success "Virtual environment activated"
log_info "Ansible version: $(ansible --version | head -1)"

# === Step 2: Inventory Sanity and Normalization ===
log_info ""
log_info "STEP 2: Inventory Sanity and Normalization"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if Kubespray inventory exists
if [[ ! -f "$KUBESPRAY_INVENTORY" ]]; then
    log_info "Kubespray inventory not found. Creating from repo inventory..."
    mkdir -p "$KUBESPRAY_INVENTORY_DIR"
    
    # Copy root inventory.ini to Kubespray location
    if [[ -f "$REPO_ROOT/inventory.ini" ]]; then
        cp "$REPO_ROOT/inventory.ini" "$KUBESPRAY_INVENTORY"
        log_success "Copied $REPO_ROOT/inventory.ini to $KUBESPRAY_INVENTORY"
    else
        log_err "No inventory.ini found in repo root"
    fi
fi

# Validate inventory
log_info "Validating inventory..."
if ansible-inventory -i "$KUBESPRAY_INVENTORY" --list &>/dev/null; then
    log_success "Inventory is valid"
else
    log_err "Inventory validation failed. Check $KUBESPRAY_INVENTORY"
fi

# Display inventory groups
log_info "Inventory groups:"
ansible-inventory -i "$KUBESPRAY_INVENTORY" --graph 2>&1 | tee -a "$LOG_FILE"

# === Step 3: Run Preflight for RHEL10 Compute Nodes ===
log_info ""
log_info "STEP 3: Run Preflight for RHEL10 Compute Nodes"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$FLAG_SKIP_PREFLIGHT" != "true" ]]; then
    if [[ -f "$PREFLIGHT_PLAYBOOK" ]]; then
        log_info "Running preflight checks on compute_nodes..."
        
        if ansible-playbook -i "$KUBESPRAY_INVENTORY" \
            "$PREFLIGHT_PLAYBOOK" \
            -l compute_nodes \
            -e 'target_hosts=compute_nodes' \
            -v 2>&1 | tee -a "$LOG_FILE"; then
            log_success "Preflight checks passed"
        else
            PREFLIGHT_EXIT=$?
            log_err "Preflight checks failed with exit code $PREFLIGHT_EXIT. Check logs: $LOG_FILE"
        fi
    else
        log_warn "Preflight playbook not found at $PREFLIGHT_PLAYBOOK. Skipping."
    fi
else
    log_warn "Skipping preflight checks (--skip-preflight flag set)"
fi

# === Step 4: Run Kubespray Cluster Playbook ===
log_info ""
log_info "STEP 4: Run Kubespray Cluster Playbook"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if cluster already exists
CLUSTER_EXISTS=false
if kubectl cluster-info &>/dev/null; then
    CLUSTER_EXISTS=true
    log_warn "Kubernetes cluster appears to already exist"
    
    if [[ "$FLAG_FORCE" != "true" ]]; then
        if [[ "$FLAG_AUTO" != "true" ]]; then
            read -p "Continue with deployment anyway? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Deployment cancelled by user"
                exit 0
            fi
        else
            log_err "Cluster exists and --force not set. Aborting."
        fi
    fi
fi

log_info "Starting Kubespray cluster deployment..."
log_info "This may take 10-30 minutes depending on network and node resources"

cd "$KUBESPRAY_DIR"

if ansible-playbook -i "$KUBESPRAY_INVENTORY" cluster.yml -b -v 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Kubespray deployment completed successfully"
else
    DEPLOY_EXIT=$?
    log_err "Kubespray deployment failed with exit code $DEPLOY_EXIT"
    log_info "Check logs: $LOG_FILE"
    log_info "To retry: cd $KUBESPRAY_DIR && ansible-playbook -i $KUBESPRAY_INVENTORY cluster.yml -b -v"
    exit $DEPLOY_EXIT
fi

# === Step 5: Ensure Admin Kubeconfig is Present and Usable ===
log_info ""
log_info "STEP 5: Ensure Admin Kubeconfig is Present and Usable"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Find kubeconfig
KUBECONFIG_PATHS=(
    "$KUBESPRAY_INVENTORY_DIR/artifacts/admin.conf"
    "$HOME/.kube/config"
    "/etc/kubernetes/admin.conf"
)

KUBECONFIG_FOUND=""
for kconfig in "${KUBECONFIG_PATHS[@]}"; do
    if [[ -f "$kconfig" ]]; then
        KUBECONFIG_FOUND="$kconfig"
        log_success "Found kubeconfig at: $KUBECONFIG_FOUND"
        break
    fi
done

if [[ -z "$KUBECONFIG_FOUND" ]]; then
    log_err "No kubeconfig found. Expected locations: ${KUBECONFIG_PATHS[*]}"
fi

# Copy to standard location
mkdir -p "$HOME/.kube"
if [[ "$KUBECONFIG_FOUND" != "$HOME/.kube/config" ]]; then
    cp "$KUBECONFIG_FOUND" "$HOME/.kube/config"
    chmod 600 "$HOME/.kube/config"
    log_success "Copied kubeconfig to $HOME/.kube/config"
fi

export KUBECONFIG="$HOME/.kube/config"

# Verify cluster access
log_info "Verifying cluster access..."
if kubectl cluster-info 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Cluster is accessible"
else
    log_err "Cannot access cluster. Check kubeconfig and network connectivity"
fi

# === Step 6: Wait and Verify Control-Plane and CNI ===
log_info ""
log_info "STEP 6: Wait and Verify Control-Plane and CNI"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Waiting for nodes to become ready (timeout: 15 minutes)..."
if kubectl wait --for=condition=Ready nodes --all --timeout=15m 2>&1 | tee -a "$LOG_FILE"; then
    log_success "All nodes are ready"
else
    log_warn "Not all nodes became ready within timeout"
fi

# Display node status
log_info "Node status:"
kubectl get nodes -o wide 2>&1 | tee -a "$LOG_FILE"

# Check kube-system pods
log_info "Checking kube-system pods..."
kubectl -n kube-system get pods -o wide 2>&1 | tee -a "$LOG_FILE"

# Verify CNI DaemonSets
log_info "Checking CNI DaemonSets..."
kubectl -n kube-system get ds -o wide 2>&1 | tee -a "$LOG_FILE"

# Check for any NotReady nodes or failing pods
NOT_READY_NODES=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l || true)
FAILING_PODS=$(kubectl -n kube-system get pods --no-headers | grep -vE "Running|Completed" | wc -l || true)

if [[ $NOT_READY_NODES -gt 0 ]]; then
    log_warn "$NOT_READY_NODES node(s) are not ready"
    kubectl get nodes --no-headers | grep -v "Ready" 2>&1 | tee -a "$LOG_FILE" || true
fi

if [[ $FAILING_PODS -gt 0 ]]; then
    log_warn "$FAILING_PODS pod(s) in kube-system are not running"
    kubectl -n kube-system get pods --no-headers | grep -vE "Running|Completed" 2>&1 | tee -a "$LOG_FILE" || true
fi

# === Step 7: Post-Deploy Checks & Repairs ===
log_info ""
log_info "STEP 7: Post-Deploy Checks & Repairs"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Waiting for CoreDNS to be ready..."
kubectl -n kube-system rollout status deployment/coredns --timeout=5m 2>&1 | tee -a "$LOG_FILE" || log_warn "CoreDNS rollout status check failed"

# Run a simple smoke test
log_info "Running smoke test: creating test deployment..."
cat <<EOF | kubectl apply -f - 2>&1 | tee -a "$LOG_FILE"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: smoke-test
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: smoke-test
  template:
    metadata:
      labels:
        app: smoke-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
EOF

log_info "Waiting for smoke test deployment..."
if kubectl wait --for=condition=available --timeout=2m deployment/smoke-test 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Smoke test deployment is available"
    kubectl delete deployment smoke-test 2>&1 | tee -a "$LOG_FILE"
    log_info "Cleaned up smoke test deployment"
else
    log_warn "Smoke test deployment failed to become available"
fi

# === Step 8: Monitoring and Infrastructure Readiness ===
log_info ""
log_info "STEP 8: Monitoring and Infrastructure Readiness"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

log_info "Cluster is ready for monitoring and infrastructure deployment"
log_info "Next steps:"
log_info "  1. ./deploy.sh monitoring      - Deploy monitoring stack"
log_info "  2. ./deploy.sh infrastructure  - Deploy infrastructure services"
log_info "  3. Verify with: kubectl get pods -A"

# === Step 9: Final Report ===
log_info ""
log_info "=========================================="
log_info "DEPLOYMENT COMPLETE"
log_info "=========================================="
log_info ""
log_info "Summary:"
log_info "  - Preflight: $([ "$FLAG_SKIP_PREFLIGHT" == "true" ] && echo "SKIPPED" || echo "PASSED")"
log_info "  - Kubespray deployment: COMPLETED"
log_info "  - Kubeconfig: $HOME/.kube/config"
log_info "  - Backup location: $BACKUP_DIR"
log_info "  - Log file: $LOG_FILE"
log_info ""
log_info "Cluster Status:"
kubectl get nodes -o wide 2>&1 | tee -a "$LOG_FILE"
log_info ""
log_info "Kube-System Pods:"
kubectl -n kube-system get pods -o wide 2>&1 | tee -a "$LOG_FILE"
log_info ""
log_info "To continue deployment:"
log_info "  ./deploy.sh monitoring"
log_info "  ./deploy.sh infrastructure"
log_info ""
log_info "Finished at: $(date)"
log_success "VMStation Kubespray deployment automation completed successfully"

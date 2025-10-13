#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Kubespray-only deployment: Use inventory.ini as the canonical inventory
INVENTORY_FILE="${KUBESPRAY_INVENTORY:-$REPO_ROOT/inventory.ini}"
SPIN_PLAYBOOK="$REPO_ROOT/ansible/playbooks/spin-down-cluster.yaml"
DEPLOY_PLAYBOOK="$REPO_ROOT/ansible/playbooks/deploy-cluster.yaml"
RESET_PLAYBOOK="$REPO_ROOT/ansible/playbooks/reset-cluster.yaml"
AUTOSLEEP_SETUP_PLAYBOOK="$REPO_ROOT/ansible/playbooks/setup-autosleep.yaml"
CLEANUP_HOMELAB_PLAYBOOK="$REPO_ROOT/ansible/playbooks/cleanup-homelab.yml"
# Legacy RKE2 playbooks removed - use Kubespray instead
# INSTALL_RKE2_PLAYBOOK="$REPO_ROOT/ansible/playbooks/install-rke2-homelab.yml"
# UNINSTALL_RKE2_PLAYBOOK="$REPO_ROOT/ansible/playbooks/uninstall-rke2-homelab.yml"
MONITORING_STACK_PLAYBOOK="$REPO_ROOT/ansible/playbooks/deploy-monitoring-stack.yaml"
INFRASTRUCTURE_SERVICES_PLAYBOOK="$REPO_ROOT/ansible/playbooks/deploy-infrastructure-services.yaml"
ARTIFACTS_DIR="$REPO_ROOT/ansible/artifacts"
KUBESPRAY_DIR="$REPO_ROOT/.cache/kubespray"
KUBESPRAY_VENV="$KUBESPRAY_DIR/.venv"
KUBESPRAY_INVENTORY_DIR="$KUBESPRAY_DIR/inventory/mycluster"
PREFLIGHT_PLAYBOOK="$REPO_ROOT/ansible/playbooks/run-preflight-rhel10.yml"

# Logging functions with timestamps
log_timestamp(){ date '+%Y-%m-%d %H:%M:%S'; }
info(){ echo "[$(log_timestamp)] [INFO] $*" >&2; }
warn(){ echo "[$(log_timestamp)] [WARN] $*" >&2; }
err(){ echo "[$(log_timestamp)] [ERROR] $*" >&2; exit 1; }

# Global flags
FLAG_YES=false
FLAG_CHECK=false
FLAG_WITH_RKE2=false
LOG_DIR="$ARTIFACTS_DIR"

usage(){
  cat <<EOF
Usage: $(basename "$0") [command] [flags]

Commands:
  debian          Deploy kubeadm/Kubernetes to Debian nodes (monitoring_nodes + storage_nodes) [DEPRECATED: use 'kubespray']
  kubespray       Deploy Kubernetes via Kubespray to all nodes (RECOMMENDED)
  monitoring      Deploy monitoring stack (Prometheus, Grafana, Loki, exporters)
  infrastructure  Deploy infrastructure services (NTP/Chrony, Syslog, Kerberos)
  reset           Comprehensive cluster reset - removes all K8s config/network
  setup           Setup auto-sleep monitoring (one-time setup)
  spindown        Cordon/drain and scale to zero on all nodes, then cleanup CNI/flannel artifacts (does NOT power off)
  help            Show this message

Flags:
  --yes        Skip interactive confirmations (for automation)
  --check      Dry-run mode - show planned actions without executing
  --log-dir    Specify custom log directory (default: ansible/artifacts)

Examples:
  ./deploy.sh kubespray                 # Deploy Kubernetes via Kubespray (RECOMMENDED)
  ./deploy.sh monitoring                # Deploy monitoring stack
  ./deploy.sh infrastructure            # Deploy infrastructure services (NTP, Syslog, Kerberos)
  ./deploy.sh reset                     # Full cluster reset
  ./deploy.sh debian --check            # Show what would be deployed (legacy Debian-only)
  ./deploy.sh setup                     # Setup auto-sleep monitoring

Recommended Workflow (Kubespray-only):
  1. ./deploy.sh reset                  # Clean slate
  2. ./deploy.sh setup                  # Setup auto-sleep
  3. ./deploy.sh kubespray              # Deploy Kubernetes via Kubespray
  4. ./deploy.sh monitoring             # Deploy monitoring stack
  5. ./deploy.sh infrastructure         # Deploy infrastructure services
  6. ./scripts/validate-monitoring-stack.sh   # Validate deployment
  7. ./tests/test-complete-validation.sh      # Complete validation

Artifacts:
  - Logs: ansible/artifacts/*.log
  - Kubeconfig: ~/.kube/config or .cache/kubespray/inventory/mycluster/artifacts/admin.conf

Legacy Commands (DEPRECATED):
  - debian: Legacy kubeadm deployment (use 'kubespray' instead)
  - rke2: Removed (use 'kubespray' instead)

EOF
}

require_bin(){ 
  command -v "$1" >/dev/null 2>&1 || err "required binary '$1' not found - please install it first"
}

# Validate required dependencies at startup
validate_dependencies(){
  local required_bins=("ansible" "ansible-playbook")
  local missing_bins=()
  
  for bin in "${required_bins[@]}"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      missing_bins+=("$bin")
    fi
  done
  
  if [[ ${#missing_bins[@]} -gt 0 ]]; then
    err "Missing required dependencies: ${missing_bins[*]}"
  fi
}

# Retry wrapper for network operations
retry_cmd(){
  local max_attempts="${1:-3}"
  local delay="${2:-5}"
  shift 2
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    if "$@"; then
      return 0
    fi
    warn "Command failed (attempt $attempt/$max_attempts): $*"
    if [[ $attempt -lt $max_attempts ]]; then
      info "Retrying in ${delay}s..."
      sleep "$delay"
    fi
    attempt=$((attempt + 1))
  done
  
  return 1
}

confirm(){
  local prompt="$1"
  if [[ "$FLAG_YES" == "true" ]]; then
    return 0
  fi
  echo -n "${prompt} [y/N]: " >&2
  read -r response
  [[ "$response" =~ ^[Yy]$ ]] || return 1
}

verify_ssh_homelab(){
  info "Verifying SSH connectivity to homelab..."
  
  # Retry SSH connectivity check
  if retry_cmd 3 5 ansible homelab -i "$INVENTORY_FILE" -m ping >/dev/null 2>&1; then
    info "✓ SSH connectivity to homelab verified"
    return 0
  else
    err "✗ Cannot reach homelab via SSH after 3 attempts. Check inventory and SSH keys."
  fi
}

verify_debian_cluster_health(){
  info "Verifying Debian cluster health..."
  local kubeconfig="/etc/kubernetes/admin.conf"
  
  # Check if we're on the control plane or need to SSH
  if [[ -f "$kubeconfig" ]]; then
    # We're on the masternode
    if kubectl --kubeconfig="$kubeconfig" get nodes >/dev/null 2>&1; then
      # Only count Debian nodes (monitoring_nodes + storage_nodes)
      local nodes_ready=$(kubectl --kubeconfig="$kubeconfig" get nodes --no-headers 2>/dev/null | grep -E "(masternode|storagenodet3500)" | grep -c " Ready" || echo "0")
      if [[ "$nodes_ready" -ge 1 ]]; then
        info "✓ Debian cluster is healthy ($nodes_ready Debian nodes Ready)"
        return 0
      fi
    fi
  else
    # Try via ansible to masternode (only check Debian nodes)
    if ansible monitoring_nodes -i "$INVENTORY_FILE" -m shell \
       -a "kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --no-headers | grep -E '(masternode|storagenodet3500)'" \
       >/dev/null 2>&1; then
      info "✓ Debian cluster appears healthy"
      return 0
    fi
  fi
  
  warn "Debian cluster health check failed or cluster not initialized"
  return 1
}

check_homelab_clean(){
  info "Checking if homelab is clean (no kubeadm artifacts)..."
  # Check if kubeadm/kubelet exist on homelab
  if ansible homelab -i "$INVENTORY_FILE" -m shell \
     -a "test -f /usr/bin/kubelet -o -f /usr/local/bin/kubelet" \
     2>/dev/null | grep -q SUCCESS 2>/dev/null; then
    warn "⚠ homelab has kubeadm/kubelet artifacts"
    return 1
  fi
  info "✓ homelab appears clean"
  return 0
}

generate_spin_targets(){
  # produce /tmp/spin_targets.yml listing all kube nodes
  local out=/tmp/spin_targets.yml
  info "Generating node list into ${out}"
  if ! command -v kubectl >/dev/null 2>&1; then
    err "kubectl not found; cannot generate node list"
  fi
  nodes=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
  if [[ -z "$nodes" ]]; then
    err "No nodes returned by kubectl get nodes; please check kubeconfig/context"
  fi
  {
    echo "spin_targets:"
    for n in $nodes; do
      echo "  - $n"
    done
  } > "$out"
  echo "$out"
}

hosts_csv_from_yaml(){
  # read /tmp/spin_targets.yml and output comma-separated host list
  local yamlfile="$1"
  python3 - <<'PY' "$yamlfile"
import sys, yaml
f=sys.argv[1]
with open(f) as fh:
    data=yaml.safe_load(fh)
hosts=data.get('spin_targets', []) if isinstance(data, dict) else []
print(','.join(hosts))
PY
}

cleanup_script_local(){
  # create a cleanup script on controller to be shipped to nodes via ansible script module
  cat > /tmp/ansible_spin_cleanup.sh <<'BASH'
#!/usr/bin/env bash
set -eux
# find likely CNI/flannel interfaces and attempt to bring them down and delete them
IFACES=$(ip -o link show | awk -F': ' '{print $2}' | egrep 'flannel|^cni|^cali|^docker|^vxlan' || true)
for ifc in $IFACES; do
  /sbin/ip link set "$ifc" down 2>/dev/null || true
  /sbin/ip link delete "$ifc" 2>/dev/null || true
done
# remove common CNI config and flannel data
rm -rf /etc/cni/net.d/* /var/lib/cni/* /run/flannel/* /var/lib/flannel/* /var/run/flannel/* 2>/dev/null || true
# restart kubelet to allow fresh CNI setup on next deploy
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart kubelet || true
fi
BASH
  chmod +x /tmp/ansible_spin_cleanup.sh
  echo /tmp/ansible_spin_cleanup.sh
}

run_cleanup_on_hosts(){
  local hosts_csv="$1"
  local cleanup_script=$(cleanup_script_local)
  info "Cleaning up CNI/Flannel on: ${hosts_csv}"
  if command -v ansible >/dev/null 2>&1; then
    # use ansible script module to copy and run the cleanup script
    ansible -i "$INVENTORY_FILE" "$hosts_csv" -m script -a "$cleanup_script" --become || warn "Ansible cleanup had warnings/errors"
  else
    warn "ansible not found; falling back to SSH loop"
    IFS=',' read -r -a hosts <<< "$hosts_csv"
    for h in "${hosts[@]}"; do
      info "Running cleanup on $h via SSH"
      scp /tmp/ansible_spin_cleanup.sh "$h":/tmp/ansible_spin_cleanup.sh || warn "scp to $h failed"
      ssh -o BatchMode=yes -o ConnectTimeout=10 "$h" 'sudo /tmp/ansible_spin_cleanup.sh' || warn "ssh cleanup on $h failed"
    done
  fi
}

cmd_debian(){
  info "========================================"
  info " Deploying Kubernetes to Debian Nodes  "
  info "========================================"
  info "Target: monitoring_nodes + storage_nodes"
  info "Playbook: $DEPLOY_PLAYBOOK"
  info "Log: $LOG_DIR/deploy-debian.log"
  info ""
  
  require_bin ansible-playbook
  
  # Validate inventory file exists
  if [ ! -f "$INVENTORY_FILE" ]; then
    err "Inventory file not found: $INVENTORY_FILE"
  fi
  
  # Ensure artifacts directory exists
  mkdir -p "$LOG_DIR"
  
  if [[ "$FLAG_CHECK" == "true" ]]; then
    info "DRY-RUN: Would execute:"
    local dry_run_cmd="ansible-playbook -i $INVENTORY_FILE $DEPLOY_PLAYBOOK --limit monitoring_nodes,storage_nodes"
    if [[ "$FLAG_YES" == "true" ]]; then
      dry_run_cmd="$dry_run_cmd -e skip_ansible_confirm=true"
    fi
    echo "  $dry_run_cmd | tee $LOG_DIR/deploy-debian.log"
    return 0
  fi
  
  # Run deployment with --limit to exclude homelab (compute_nodes)
  info "Starting Debian deployment (this may take 10-15 minutes)..."
  
  # Build ansible-playbook command with proper flags
  local ansible_cmd="ansible-playbook -i $INVENTORY_FILE $DEPLOY_PLAYBOOK --limit monitoring_nodes,storage_nodes"
  
  # Add skip_ansible_confirm when FLAG_YES is true
  if [[ "$FLAG_YES" == "true" ]]; then
    ansible_cmd="$ansible_cmd -e skip_ansible_confirm=true"
  fi
  
  # Force color output for better readability
  ANSIBLE_FORCE_COLOR=true eval "$ansible_cmd" 2>&1 | tee "$LOG_DIR/deploy-debian.log"
  local deploy_result=${PIPESTATUS[0]}
  
  if [[ $deploy_result -eq 0 ]]; then
    info ""
    info "✓ Debian deployment completed successfully"
    info ""
    
    # Verify deployment
    info "Running post-deployment verification..."
    sleep 5
    
    if verify_debian_cluster_health; then
      info ""
      info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      info "  Debian Kubernetes Cluster Ready!"
      info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      info ""
      info "Verification commands:"
      info "  kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes"
      info "  kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A"
      info ""
      info "Log saved to: $LOG_DIR/deploy-debian.log"
      info ""
    else
      warn "Deployment completed but verification had warnings"
    fi
  else
    err "Debian deployment failed - check logs: $LOG_DIR/deploy-debian.log"
  fi
}

cmd_kubespray(){
  info "=========================================="
  info " Deploying Kubernetes via Kubespray      "
  info "=========================================="
  info "Target: All nodes (kube-master, kube-node)"
  info "Workflow: Kubespray staging → preflight → cluster.yml → monitoring → infrastructure"
  info "Log: $LOG_DIR/kubespray-deployment.log"
  info ""
  
  require_bin ansible-playbook
  
  if [[ "$FLAG_CHECK" == "true" ]]; then
    info "DRY-RUN: Would execute:"
    echo "  1. ./scripts/run-kubespray.sh (stage Kubespray repo and venv)"
    echo "  2. ansible-playbook -i $INVENTORY_FILE $PREFLIGHT_PLAYBOOK -l compute_nodes"
    echo "  3. cd $KUBESPRAY_DIR && source $KUBESPRAY_VENV/bin/activate"
    echo "  4. ansible-playbook -i $KUBESPRAY_INVENTORY_DIR/inventory.ini cluster.yml -b"
    echo "  5. export KUBECONFIG=<path-to-kubeconfig>"
    echo "  6. ./deploy.sh monitoring"
    echo "  7. ./deploy.sh infrastructure"
    return 0
  fi
  
  # Ensure artifacts directory exists
  mkdir -p "$LOG_DIR"
  
  # Step 1: Stage Kubespray
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  STEP 1: Staging Kubespray"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if ! "$REPO_ROOT/scripts/run-kubespray.sh" 2>&1 | tee -a "$LOG_DIR/kubespray-deployment.log"; then
    err "Kubespray staging failed - check logs: $LOG_DIR/kubespray-deployment.log"
  fi
  
  info ""
  info "✓ Kubespray staged successfully"
  info ""
  
  # Step 2: Run preflight checks on RHEL10 nodes (compute_nodes)
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  STEP 2: Running Preflight Checks on RHEL10 Nodes"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if ! ansible-playbook -i "$INVENTORY_FILE" "$PREFLIGHT_PLAYBOOK" -l compute_nodes 2>&1 | tee -a "$LOG_DIR/kubespray-deployment.log"; then
    warn "Preflight checks had warnings - review logs before proceeding"
  fi
  
  info ""
  info "✓ Preflight checks completed"
  info ""
  
  # Step 3: Deploy Kubernetes cluster with Kubespray
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  STEP 3: Deploying Kubernetes Cluster with Kubespray"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info ""
  info "⚠️  OPERATOR ACTION REQUIRED:"
  info "    The Kubespray cluster deployment requires manual execution due to:"
  info "    - Potential credential/network access requirements"
  info "    - Long-running deployment (10-30 minutes)"
  info "    - Interactive prompts may be needed"
  info ""
  info "Please run the following commands manually:"
  info ""
  info "  cd $KUBESPRAY_DIR"
  info "  source $KUBESPRAY_VENV/bin/activate"
  info "  ansible-playbook -i $KUBESPRAY_INVENTORY_DIR/inventory.ini cluster.yml -b -v"
  info ""
  info "After successful deployment, the KUBECONFIG will be available at:"
  info "  $KUBESPRAY_INVENTORY_DIR/artifacts/admin.conf"
  info ""
  info "Then set KUBECONFIG:"
  info "  export KUBECONFIG=$KUBESPRAY_INVENTORY_DIR/artifacts/admin.conf"
  info ""
  info "Or use the activation script:"
  info "  source $REPO_ROOT/scripts/activate-kubespray-env.sh"
  info ""
  
  # Check if we should attempt automated deployment
  if [[ "$FLAG_YES" != "true" ]]; then
    echo ""
    read -p "Would you like to attempt automated Kubespray deployment now? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      info "Skipping automated deployment. Run the commands above manually."
      info ""
      info "After deploying the cluster, continue with:"
      info "  ./deploy.sh monitoring"
      info "  ./deploy.sh infrastructure"
      return 0
    fi
  fi
  
  info "Attempting automated Kubespray deployment..."
  info "(This may take 10-30 minutes depending on cluster size and network)"
  info ""
  
  # Attempt automated deployment
  cd "$KUBESPRAY_DIR" || err "Failed to cd to $KUBESPRAY_DIR"
  
  # Activate venv and run cluster.yml
  if ! (source "$KUBESPRAY_VENV/bin/activate" && \
        ansible-playbook -i "$KUBESPRAY_INVENTORY_DIR/inventory.ini" cluster.yml -b -v 2>&1 | tee -a "$LOG_DIR/kubespray-deployment.log"); then
    warn "Kubespray cluster deployment encountered errors. Check logs: $LOG_DIR/kubespray-deployment.log"
    info ""
    info "If deployment failed due to credentials or network access:"
    info "  1. Review the error messages above"
    info "  2. Ensure SSH access to all nodes is configured"
    info "  3. Ensure sudo access is available (homelab uses NOPASSWD sudo)"
    info "  4. Run the deployment manually using the commands shown earlier"
    return 1
  fi
  
  cd "$REPO_ROOT" || err "Failed to cd back to $REPO_ROOT"
  
  info ""
  info "✓ Kubespray cluster deployment completed"
  info ""
  
  # Step 4: Set KUBECONFIG
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  STEP 4: Configuring KUBECONFIG"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Try to find kubeconfig
  KUBECONFIG_PATHS=(
    "$KUBESPRAY_INVENTORY_DIR/artifacts/admin.conf"
    "$HOME/.kube/config"
    "/etc/kubernetes/admin.conf"
  )
  
  KUBECONFIG_FOUND=""
  for kconfig in "${KUBECONFIG_PATHS[@]}"; do
    if [[ -f "$kconfig" ]]; then
      KUBECONFIG_FOUND="$kconfig"
      break
    fi
  done
  
  if [[ -n "$KUBECONFIG_FOUND" ]]; then
    export KUBECONFIG="$KUBECONFIG_FOUND"
    info "✓ KUBECONFIG set to: $KUBECONFIG"
    
    # Verify cluster access
    if command -v kubectl &>/dev/null; then
      if kubectl cluster-info &>/dev/null; then
        info "✓ Kubernetes cluster is accessible"
      else
        warn "kubectl found but cluster is not accessible"
      fi
    fi
  else
    warn "No kubeconfig file found - cluster may not be fully deployed"
  fi
  
  info ""
  
  # Step 5: Deploy monitoring stack
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  STEP 5: Deploying Monitoring Stack"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  cmd_monitoring
  
  info ""
  
  # Step 6: Deploy infrastructure services
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  STEP 6: Deploying Infrastructure Services"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  cmd_infrastructure
  
  info ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  KUBESPRAY DEPLOYMENT COMPLETE!"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info ""
  info "Summary:"
  info "  ✓ Kubespray cluster deployed"
  info "  ✓ Monitoring stack deployed"
  info "  ✓ Infrastructure services deployed"
  info ""
  info "Next steps:"
  info "  1. Validate deployment:"
  info "     $REPO_ROOT/scripts/validate-monitoring-stack.sh"
  info ""
  info "  2. Run complete validation:"
  info "     $REPO_ROOT/tests/test-complete-validation.sh"
  info ""
  info "  3. Test sleep/wake cycle:"
  info "     $REPO_ROOT/tests/test-sleep-wake-cycle.sh"
  info ""
  info "Logs saved to: $LOG_DIR/kubespray-deployment.log"
  info ""
}

# Legacy cmd_rke2 removed - replaced by cmd_kubespray
# RKE2 deployment is deprecated in favor of Kubespray
cmd_rke2(){
  err "RKE2 deployment has been removed. Use './deploy.sh kubespray' instead."
}

cmd_all(){
  info "========================================"
  info " Full Deployment (Deprecated)           "
  info "========================================"
  info ""
  warn "'all' command is deprecated - use 'kubespray' instead"
  info ""
  info "Redirecting to: ./deploy.sh kubespray"
  info ""
  cmd_kubespray
}

cmd_reset(){
  require_bin ansible-playbook
  
  info "========================================"
  info " Comprehensive Cluster Reset            "
  info "========================================"
  info "This will reset:"
  info "  - Kubernetes cluster (all nodes)"
  info "  - All network interfaces and configs"
  info "  - Note: RKE2-specific reset removed (use Kubespray reset)"
  info ""
  info "SSH keys and physical ethernet will be preserved"
  info ""
  
  if [[ "$FLAG_CHECK" == "true" ]]; then
    info "DRY-RUN: Would execute:"
    local dry_run_reset="ansible-playbook $RESET_PLAYBOOK (all nodes)"
    if [[ "$FLAG_YES" == "true" ]]; then
      dry_run_reset="$dry_run_reset with -e skip_ansible_confirm=true"
    fi
    echo "  1. $dry_run_reset"
    return 0
  fi
  
  if ! confirm "Proceed with comprehensive reset?"; then
    err "Aborted by user"
  fi
  
  info ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  Resetting Cluster"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Build ansible-playbook command with proper flags
  local ansible_cmd="ansible-playbook -i $INVENTORY_FILE $RESET_PLAYBOOK"
  
  # Add skip_ansible_confirm when FLAG_YES is true
  if [[ "$FLAG_YES" == "true" ]]; then
    ansible_cmd="$ansible_cmd -e skip_ansible_confirm=true"
  fi
  
  # Force color output for better readability
  ANSIBLE_FORCE_COLOR=true eval "$ansible_cmd" 2>&1 | tee "$LOG_DIR/reset-cluster.log"
  local reset_result=${PIPESTATUS[0]}
  
  if [[ $reset_result -eq 0 ]]; then
    info "✓ Cluster reset completed"
  else
    warn "Cluster reset had errors (see log)"
  fi
  
  info ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  Reset Complete!"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info ""
  info "Cluster is ready for fresh deployment"
  info ""
  info "Log: $LOG_DIR/reset-cluster.log"
  info ""
  info "Next steps:"
  info "  ./deploy.sh kubespray              # Full Kubespray deployment"
  info ""
}

cmd_monitoring(){
  info "========================================"
  info " Deploy Monitoring Stack                "
  info "========================================"
  info "Target: monitoring_nodes"
  info "Playbook: $MONITORING_STACK_PLAYBOOK"
  info "Log: $LOG_DIR/deploy-monitoring-stack.log"
  info ""
  
  require_bin ansible-playbook
  
  # Validate inventory file exists
  if [ ! -f "$INVENTORY_FILE" ]; then
    err "Inventory file not found: $INVENTORY_FILE"
  fi
  
  # Ensure artifacts directory exists
  mkdir -p "$LOG_DIR"
  
  if [[ "$FLAG_CHECK" == "true" ]]; then
    info "DRY-RUN: Would execute:"
    local dry_run_cmd="ansible-playbook -i $INVENTORY_FILE $MONITORING_STACK_PLAYBOOK"
    if [[ "$FLAG_YES" == "true" ]]; then
      dry_run_cmd="$dry_run_cmd -e skip_ansible_confirm=true"
    fi
    echo "  $dry_run_cmd | tee $LOG_DIR/deploy-monitoring-stack.log"
    return 0
  fi
  
  info "Starting monitoring stack deployment..."
  info "Components: Prometheus, Grafana, Loki, Promtail, Kube-state-metrics, Node-exporter, IPMI-exporter"
  info ""
  
  # Build ansible-playbook command with proper flags
  local ansible_cmd="ansible-playbook -i $INVENTORY_FILE $MONITORING_STACK_PLAYBOOK"
  
  # Add skip_ansible_confirm when FLAG_YES is true
  if [[ "$FLAG_YES" == "true" ]]; then
    ansible_cmd="$ansible_cmd -e skip_ansible_confirm=true"
  fi
  
  # Force color output for better readability
  ANSIBLE_FORCE_COLOR=true eval "$ansible_cmd" 2>&1 | tee "$LOG_DIR/deploy-monitoring-stack.log"
  local deploy_result=${PIPESTATUS[0]}
  
  if [[ $deploy_result -eq 0 ]]; then
    info ""
    info "✓ Monitoring stack deployment completed successfully"
    info ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info "  Monitoring Stack Ready!"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info ""
    info "Access URLs (assuming masternode at 192.168.4.63):"
    info "  - Prometheus: http://192.168.4.63:30090"
    info "  - Grafana: http://192.168.4.63:30300"
    info "  - Loki: http://192.168.4.63:31100"
    info ""
    info "Verification:"
    info "  kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring"
    info "  kubectl --kubeconfig=/etc/kubernetes/admin.conf get svc -n monitoring"
    info ""
    info "Log saved to: $LOG_DIR/deploy-monitoring-stack.log"
    info ""
  else
    err "Monitoring stack deployment failed - check logs: $LOG_DIR/deploy-monitoring-stack.log"
  fi
}

cmd_infrastructure(){
  info "========================================"
  info " Deploy Infrastructure Services         "
  info "========================================"
  info "Target: monitoring_nodes"
  info "Playbook: $INFRASTRUCTURE_SERVICES_PLAYBOOK"
  info "Log: $LOG_DIR/deploy-infrastructure-services.log"
  info ""
  
  require_bin ansible-playbook
  
  # Validate inventory file exists
  if [ ! -f "$INVENTORY_FILE" ]; then
    err "Inventory file not found: $INVENTORY_FILE"
  fi
  
  # Ensure artifacts directory exists
  mkdir -p "$LOG_DIR"
  
  if [[ "$FLAG_CHECK" == "true" ]]; then
    info "DRY-RUN: Would execute:"
    local dry_run_cmd="ansible-playbook -i $INVENTORY_FILE $INFRASTRUCTURE_SERVICES_PLAYBOOK"
    if [[ "$FLAG_YES" == "true" ]]; then
      dry_run_cmd="$dry_run_cmd -e skip_ansible_confirm=true"
    fi
    echo "  $dry_run_cmd | tee $LOG_DIR/deploy-infrastructure-services.log"
    return 0
  fi
  
  info "Starting infrastructure services deployment..."
  info "Services: NTP/Chrony (time sync), Syslog Server, FreeIPA/Kerberos (optional)"
  info ""
  
  # Build ansible-playbook command with proper flags
  local ansible_cmd="ansible-playbook -i $INVENTORY_FILE $INFRASTRUCTURE_SERVICES_PLAYBOOK"
  
  # Add skip_ansible_confirm when FLAG_YES is true
  if [[ "$FLAG_YES" == "true" ]]; then
    ansible_cmd="$ansible_cmd -e skip_ansible_confirm=true"
  fi
  
  # Force color output for better readability
  ANSIBLE_FORCE_COLOR=true eval "$ansible_cmd" 2>&1 | tee "$LOG_DIR/deploy-infrastructure-services.log"
  local deploy_result=${PIPESTATUS[0]}
  
  if [[ $deploy_result -eq 0 ]]; then
    info ""
    info "✓ Infrastructure services deployment completed successfully"
    info ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info "  Infrastructure Services Ready!"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info ""
    info "Deployed services:"
    info "  - NTP/Chrony: Cluster-wide time synchronization"
    info "  - Syslog Server: Centralized log aggregation"
    info "  - FreeIPA/Kerberos: Identity management (if enabled)"
    info ""
    info "Verification:"
    info "  kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n infrastructure"
    info "  kubectl --kubeconfig=/etc/kubernetes/admin.conf get svc -n infrastructure"
    info "  ./tests/validate-time-sync.sh"
    info ""
    info "Log saved to: $LOG_DIR/deploy-infrastructure-services.log"
    info ""
  else
    err "Infrastructure services deployment failed - check logs: $LOG_DIR/deploy-infrastructure-services.log"
  fi
}

cmd_setup_autosleep(){
  require_bin ansible-playbook
  info "Setting up auto-sleep monitoring..."
  
  # Build ansible-playbook command with proper flags
  local ansible_cmd="ansible-playbook -i $INVENTORY_FILE $AUTOSLEEP_SETUP_PLAYBOOK"
  
  # Add skip_ansible_confirm when FLAG_YES is true
  if [[ "$FLAG_YES" == "true" ]]; then
    ansible_cmd="$ansible_cmd -e skip_ansible_confirm=true"
  fi
  
  # Force color output for better readability
  ANSIBLE_FORCE_COLOR=true eval "$ansible_cmd"
  local setup_result=$?
  
  if [[ $setup_result -eq 0 ]]; then
    info "Auto-sleep monitoring setup complete"
    info "Cluster will automatically sleep after 2 hours of inactivity"
  else
    err "Setup failed - check logs above for details"
  fi
}

cmd_spindown(){
  require_bin ansible-playbook
  local tmpvars
  tmpvars=$(generate_spin_targets)
  info "Running spin-down playbook (no power-off)"
  # Force color output for better readability
  ANSIBLE_FORCE_COLOR=true ansible-playbook "$SPIN_PLAYBOOK" -e "@${tmpvars}" -e 'allow_power_down=false' -e 'spin_confirm=true'
  # generate hosts CSV
  hosts_csv=$(hosts_csv_from_yaml "$tmpvars")
  if [[ -z "$hosts_csv" ]]; then
    warn "No hosts found to cleanup"; return
  fi
  run_cleanup_on_hosts "$hosts_csv"
}

parse_flags(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|-y)
        FLAG_YES=true
        shift
        ;;
      --check|--dry-run)
        FLAG_CHECK=true
        shift
        ;;
      --with-rke2)
        FLAG_WITH_RKE2=true
        shift
        ;;
      --log-dir)
        LOG_DIR="$2"
        shift 2
        ;;
      --log-dir=*)
        LOG_DIR="${1#*=}"
        shift
        ;;
      *)
        # Not a flag, return it
        echo "$1"
        shift
        return
        ;;
    esac
  done
}

main(){
  # Parse flags and get command
  local cmd=""
  local remaining_args=()
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes|-y|--check|--dry-run|--with-rke2)
        parse_flags "$1"
        shift
        ;;
      --log-dir)
        LOG_DIR="$2"
        shift 2
        ;;
      --log-dir=*)
        LOG_DIR="${1#*=}"
        shift
        ;;
      help|-h|--help)
        usage
        exit 0
        ;;
      debian|kubespray|rke2|all|reset|setup|spindown|monitoring|infrastructure)
        cmd="$1"
        shift
        ;;
      *)
        err "Unknown argument: $1. Use 'help' for usage."
        ;;
    esac
  done
  
  # Ensure artifacts directory exists
  mkdir -p "$LOG_DIR"
  
  # If no command, show usage
  if [[ -z "$cmd" ]]; then
    info "No command specified. Use './deploy.sh help' for usage."
    info ""
    info "Quick start:"
    info "  ./deploy.sh all --with-rke2    # Deploy both Debian and RKE2"
    info "  ./deploy.sh debian             # Deploy Debian cluster only"
    info "  ./deploy.sh monitoring         # Deploy monitoring stack"
    info "  ./deploy.sh infrastructure     # Deploy infrastructure services"
    info ""
    usage
    exit 1
  fi
  
  # Execute command
  case "$cmd" in
    debian)
      cmd_debian
      ;;
    kubespray)
      cmd_kubespray
      ;;
    rke2)
      cmd_rke2
      ;;
    all)
      cmd_all
      ;;
    reset)
      cmd_reset
      ;;
    setup)
      cmd_setup_autosleep
      ;;
    spindown)
      cmd_spindown
      ;;
    monitoring)
      cmd_monitoring
      ;;
    infrastructure)
      cmd_infrastructure
      ;;
    *)
      usage
      err "unknown command: $cmd"
      ;;
  esac
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="$REPO_ROOT/ansible/inventory/hosts.yml"
SPIN_PLAYBOOK="$REPO_ROOT/ansible/playbooks/spin-down-cluster.yaml"
DEPLOY_PLAYBOOK="$REPO_ROOT/ansible/playbooks/deploy-cluster.yaml"
RESET_PLAYBOOK="$REPO_ROOT/ansible/playbooks/reset-cluster.yaml"
AUTOSLEEP_SETUP_PLAYBOOK="$REPO_ROOT/ansible/playbooks/setup-autosleep.yaml"
CLEANUP_HOMELAB_PLAYBOOK="$REPO_ROOT/ansible/playbooks/cleanup-homelab.yml"
INSTALL_RKE2_PLAYBOOK="$REPO_ROOT/ansible/playbooks/install-rke2-homelab.yml"
UNINSTALL_RKE2_PLAYBOOK="$REPO_ROOT/ansible/playbooks/uninstall-rke2-homelab.yml"
MONITORING_STACK_PLAYBOOK="$REPO_ROOT/ansible/playbooks/deploy-monitoring-stack.yaml"
INFRASTRUCTURE_SERVICES_PLAYBOOK="$REPO_ROOT/ansible/playbooks/deploy-infrastructure-services.yaml"
ARTIFACTS_DIR="$REPO_ROOT/ansible/artifacts"

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
  debian          Deploy Kubespray/Kubernetes to Debian nodes only (monitoring_nodes + storage_nodes)
  kubespray       Deploy Kubespray/Kubernetes to Debian nodes (alias for 'debian')
  rke2            Deploy RKE2 to homelab RHEL10 node with pre-checks
  all             Deploy both Debian and RKE2 (requires --with-rke2 or confirmation)
  monitoring      Deploy monitoring stack (Prometheus, Grafana, Loki, exporters)
  infrastructure  Deploy infrastructure services (NTP/Chrony, Syslog, Kerberos)
  reset           Comprehensive cluster reset - removes all K8s config/network (Debian + RKE2)
  setup           Setup auto-sleep monitoring (one-time setup)
  spindown        Cordon/drain and scale to zero on all nodes, then cleanup CNI/flannel artifacts (does NOT power off)
  help            Show this message

Flags:
  --yes        Skip interactive confirmations (for automation)
  --check      Dry-run mode - show planned actions without executing
  --with-rke2  Auto-proceed with RKE2 deployment in 'all' command
  --log-dir    Specify custom log directory (default: ansible/artifacts)

Examples:
  ./deploy.sh debian                    # Deploy Kubespray to Debian nodes only
  ./deploy.sh kubespray                 # Deploy Kubespray to Debian nodes (same as debian)
  ./deploy.sh monitoring                # Deploy monitoring stack
  ./deploy.sh infrastructure            # Deploy infrastructure services (NTP, Syslog, Kerberos)
  ./deploy.sh rke2                      # Deploy RKE2 to homelab (with pre-checks)
  ./deploy.sh all --with-rke2           # Deploy both phases non-interactively
  ./deploy.sh reset                     # Full reset (Debian + RKE2)
  ./deploy.sh debian --check            # Show what would be deployed
  ./deploy.sh setup                     # Setup auto-sleep monitoring

Recommended Workflow:
  1. ./deploy.sh reset                  # Clean slate
  2. ./deploy.sh setup                  # Setup auto-sleep
  3. ./deploy.sh debian                 # Deploy Kubespray cluster on Debian nodes
  4. ./deploy.sh monitoring             # Deploy monitoring stack
  5. ./deploy.sh infrastructure         # Deploy infrastructure services
  6. ./deploy.sh rke2                   # Deploy RKE2 on homelab node (optional)

Artifacts:
  - Logs: ansible/artifacts/deploy-kubespray.log, install-rke2-homelab.log, etc.
  - Kubeconfig: ~/.kube/config (Kubespray default)
  - RKE2 kubeconfig: ansible/artifacts/homelab-rke2-kubeconfig.yaml

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
  info "Verifying cluster health..."
  
  # Try different kubeconfig locations
  local kubeconfigs=(
    "$HOME/.kube/config"
    "/etc/kubernetes/admin.conf"
  )
  
  for kubeconfig in "${kubeconfigs[@]}"; do
    if [[ -f "$kubeconfig" ]]; then
      if kubectl --kubeconfig="$kubeconfig" get nodes >/dev/null 2>&1; then
        # Count Ready nodes (monitoring_nodes + storage_nodes)
        local nodes_ready=$(kubectl --kubeconfig="$kubeconfig" get nodes --no-headers 2>/dev/null | grep -E "(masternode|storagenodet3500)" | grep -c " Ready" || echo "0")
        if [[ "$nodes_ready" -ge 1 ]]; then
          info "✓ Cluster is healthy ($nodes_ready nodes Ready) [kubeconfig: $kubeconfig]"
          return 0
        fi
      fi
    fi
  done
  
  # Try via ansible to masternode
  if ansible monitoring_nodes -i "$INVENTORY_FILE" -m shell \
     -a "kubectl get nodes --no-headers 2>/dev/null | grep -E '(masternode|storagenodet3500)'" \
     >/dev/null 2>&1; then
    info "✓ Cluster appears healthy"
    return 0
  fi
  
  warn "Cluster health check failed or cluster not initialized"
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
  cmd_kubespray
}

cmd_kubespray(){
  info "========================================"
  info " Deploying Kubespray to Debian Nodes   "
  info "========================================"
  info "Target: monitoring_nodes + storage_nodes"
  info "Method: Kubespray"
  info "Log: $LOG_DIR/deploy-kubespray.log"
  info ""
  
  require_bin ansible-playbook
  require_bin python3
  
  # Validate inventory file exists
  if [ ! -f "$INVENTORY_FILE" ]; then
    err "Inventory file not found: $INVENTORY_FILE"
  fi
  
  # Ensure artifacts directory exists
  mkdir -p "$LOG_DIR"
  
  if [[ "$FLAG_CHECK" == "true" ]]; then
    info "DRY-RUN: Would execute Kubespray deployment:"
    echo "  1. Setup Kubespray in .cache/kubespray"
    echo "  2. Generate inventory from $INVENTORY_FILE"
    echo "  3. Run cluster.yml playbook"
    echo "  Log: $LOG_DIR/deploy-kubespray.log"
    return 0
  fi
  
  # Run Kubespray deployment via helper script
  info "Starting Kubespray deployment (this may take 15-20 minutes)..."
  
  local kubespray_script="$REPO_ROOT/scripts/deploy-kubespray.sh"
  if [[ ! -x "$kubespray_script" ]]; then
    err "Kubespray deployment script not found or not executable: $kubespray_script"
  fi
  
  # Build command with flags
  local deploy_cmd="LOG_DIR=$LOG_DIR $kubespray_script"
  if [[ "$FLAG_YES" == "true" ]]; then
    deploy_cmd="$deploy_cmd --yes"
  fi
  
  # Execute deployment
  eval "$deploy_cmd"
  local deploy_result=$?
  
  if [[ $deploy_result -eq 0 ]]; then
    info ""
    info "✓ Kubespray deployment completed successfully"
    info ""
    
    # Verify deployment
    info "Running post-deployment verification..."
    sleep 5
    
    if verify_debian_cluster_health; then
      info ""
      info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      info "  Kubespray Kubernetes Cluster Ready!"
      info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      info ""
      info "Verification commands:"
      info "  kubectl get nodes"
      info "  kubectl get pods -A"
      info ""
      info "Kubeconfig: ~/.kube/config"
      info "Log saved to: $LOG_DIR/deploy-kubespray.log"
      info ""
    else
      warn "Deployment completed but verification had warnings"
    fi
  else
    err "Kubespray deployment failed - check logs: $LOG_DIR/deploy-kubespray.log"
  fi
}

cmd_rke2(){
  info "========================================"
  info " Deploying RKE2 to Homelab (RHEL10)    "
  info "========================================"
  info "Target: homelab (192.168.4.62)"
  info "Playbook: $INSTALL_RKE2_PLAYBOOK"
  info "Log: $LOG_DIR/install-rke2-homelab.log"
  info ""
  
  require_bin ansible-playbook
  
  if [[ "$FLAG_CHECK" == "true" ]]; then
    info "DRY-RUN: Would execute:"
    echo "  Pre-flight checks:"
    echo "    - Verify SSH connectivity to homelab"
    echo "    - Check if homelab needs cleanup"
    echo "    - Verify Debian cluster health"
    echo ""
    local dry_run_cmd="ansible-playbook -i $INVENTORY_FILE $INSTALL_RKE2_PLAYBOOK"
    if [[ "$FLAG_YES" == "true" ]]; then
      dry_run_cmd="$dry_run_cmd -e skip_ansible_confirm=true"
    fi
    echo "  $dry_run_cmd | tee $LOG_DIR/install-rke2-homelab.log"
    return 0
  fi
  
  # Pre-flight checks
  info "Running pre-flight checks..."
  
  # 1. Verify SSH connectivity to homelab
  if ! verify_ssh_homelab; then
    err "Pre-flight check failed: Cannot reach homelab"
  fi
  
  # 2. Check if homelab needs cleanup
  if ! check_homelab_clean; then
    warn "homelab has existing Kubernetes artifacts"
    
    if confirm "Run cleanup on homelab before RKE2 installation?"; then
      info "Running cleanup playbook..."
      ansible-playbook -i "$INVENTORY_FILE" "$CLEANUP_HOMELAB_PLAYBOOK" \
        2>&1 | tee "$LOG_DIR/cleanup-homelab.log" || warn "Cleanup had warnings"
    else
      warn "Proceeding without cleanup - this may cause issues"
    fi
  fi
  
  # 3. Verify Debian cluster health (optional but recommended for federation)
  if verify_debian_cluster_health; then
    info "✓ Debian cluster is healthy - RKE2 federation will work"
  else
    warn "Debian cluster not healthy - federation may not work properly"
    if ! confirm "Continue with RKE2 installation anyway?"; then
      err "Aborted by user"
    fi
  fi
  
  # Ensure artifacts directory exists
  mkdir -p "$LOG_DIR"
  
  # Run RKE2 installation
  info "Starting RKE2 installation (this may take 15-20 minutes)..."
  
  # Build ansible-playbook command with proper flags
  local ansible_cmd="ansible-playbook -i $INVENTORY_FILE $INSTALL_RKE2_PLAYBOOK"
  
  # Add skip_ansible_confirm when FLAG_YES is true
  if [[ "$FLAG_YES" == "true" ]]; then
    ansible_cmd="$ansible_cmd -e skip_ansible_confirm=true"
  fi
  
  # Force color output for better readability
  ANSIBLE_FORCE_COLOR=true eval "$ansible_cmd" 2>&1 | tee "$LOG_DIR/install-rke2-homelab.log"
  local install_result=${PIPESTATUS[0]}
  
  if [[ $install_result -eq 0 ]]; then
    info ""
    info "✓ RKE2 installation completed successfully"
    info ""
    
    # Verify artifacts
    local kubeconfig_artifact="$ARTIFACTS_DIR/homelab-rke2-kubeconfig.yaml"
    if [[ -f "$kubeconfig_artifact" ]]; then
      info "Verifying RKE2 cluster..."
      if kubectl --kubeconfig="$kubeconfig_artifact" get nodes >/dev/null 2>&1; then
        local nodes=$(kubectl --kubeconfig="$kubeconfig_artifact" get nodes --no-headers | wc -l)
        info "✓ RKE2 cluster has $nodes node(s) Ready"
        
        # Check monitoring pods
        local monitoring_pods=$(kubectl --kubeconfig="$kubeconfig_artifact" get pods -n monitoring-rke2 --no-headers 2>/dev/null | grep Running | wc -l || echo "0")
        if [[ "$monitoring_pods" -gt 0 ]]; then
          info "✓ Monitoring stack deployed ($monitoring_pods pods Running)"
        fi
      fi
    fi
    
    info ""
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info "  RKE2 Cluster Ready on Homelab!"
    info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info ""
    info "Artifacts:"
    info "  - Kubeconfig: $kubeconfig_artifact"
    info "  - Log: $LOG_DIR/install-rke2-homelab.log"
    info ""
    info "Verification commands:"
    info "  export KUBECONFIG=$kubeconfig_artifact"
    info "  kubectl get nodes"
    info "  kubectl get pods -A"
    info "  kubectl get pods -n monitoring-rke2"
    info ""
    info "Monitoring endpoints:"
    info "  - Node Exporter: http://192.168.4.62:9100/metrics"
    info "  - Prometheus: http://192.168.4.62:30090"
    info "  - Federation: http://192.168.4.62:30090/federate"
    info ""
    info "Federation test:"
    info "  curl -s 'http://192.168.4.62:30090/federate?match[]={job=~\".+\"}' | head -20"
    info ""
  else
    err "RKE2 installation failed - check logs: $LOG_DIR/install-rke2-homelab.log"
  fi
}

cmd_all(){
  info "========================================"
  info " Two-Phase Deployment: Kubespray + RKE2"
  info "========================================"
  info ""
  
  # Check if --with-rke2 flag is set
  if [[ "$FLAG_WITH_RKE2" != "true" ]] && [[ "$FLAG_YES" != "true" ]]; then
    info "This will deploy:"
    info "  1. Kubespray/Kubernetes to Debian nodes (monitoring + storage)"
    info "  2. RKE2 to homelab RHEL10 node"
    info ""
    if ! confirm "Proceed with two-phase deployment?"; then
      err "Aborted by user. Use --with-rke2 flag to skip confirmation."
    fi
  fi
  
  # Phase 1: Kubespray
  info ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  PHASE 1: Deploying Kubespray to Debian Nodes"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cmd_debian
  
  # Wait a bit between phases
  info ""
  info "Waiting 10 seconds before Phase 2..."
  sleep 10
  
  # Phase 2: RKE2
  info ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  PHASE 2: Deploying RKE2 to Homelab"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  cmd_rke2
  
  info ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  TWO-PHASE DEPLOYMENT COMPLETE!"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info ""
  info "Summary:"
  info "  ✓ Kubespray cluster: monitoring_nodes + storage_nodes"
  info "  ✓ RKE2 cluster: homelab"
  info ""
  info "Logs:"
  info "  - $LOG_DIR/deploy-kubespray.log"
  info "  - $LOG_DIR/install-rke2-homelab.log"
  info ""
}

cmd_reset(){
  require_bin ansible-playbook
  
  info "========================================"
  info " Comprehensive Cluster Reset            "
  info "========================================"
  info "This will reset:"
  info "  - Kubespray Kubernetes cluster (Debian nodes)"
  info "  - RKE2 cluster on homelab"
  info "  - All network interfaces and configs"
  info ""
  info "SSH keys and physical ethernet will be preserved"
  info ""
  
  if [[ "$FLAG_CHECK" == "true" ]]; then
    info "DRY-RUN: Would execute:"
    local dry_run_reset="Kubespray reset.yml (Debian nodes)"
    local dry_run_uninstall="ansible-playbook $UNINSTALL_RKE2_PLAYBOOK (homelab)"
    if [[ "$FLAG_YES" == "true" ]]; then
      dry_run_reset="$dry_run_reset with -e reset_confirmation=yes"
      dry_run_uninstall="$dry_run_uninstall with -e skip_ansible_confirm=true"
    fi
    echo "  1. $dry_run_reset"
    echo "  2. $dry_run_uninstall"
    return 0
  fi
  
  if ! confirm "Proceed with comprehensive reset?"; then
    err "Aborted by user"
  fi
  
  info ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  PHASE 1: Resetting Kubespray Cluster (Debian Nodes)"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Use Kubespray reset script
  local kubespray_reset_script="$REPO_ROOT/scripts/reset-kubespray.sh"
  if [[ -x "$kubespray_reset_script" ]]; then
    LOG_DIR="$LOG_DIR" "$kubespray_reset_script" --yes
    local reset_result=$?
  else
    # Fall back to legacy reset playbook if script not found
    warn "Kubespray reset script not found, using legacy reset playbook"
    local ansible_cmd="ansible-playbook -i $INVENTORY_FILE $RESET_PLAYBOOK"
    
    if [[ "$FLAG_YES" == "true" ]]; then
      ansible_cmd="$ansible_cmd -e skip_ansible_confirm=true"
    fi
    
    ANSIBLE_FORCE_COLOR=true eval "$ansible_cmd" 2>&1 | tee "$LOG_DIR/reset-debian.log"
    local reset_result=${PIPESTATUS[0]}
  fi
  
  if [[ $reset_result -eq 0 ]]; then
    info "✓ Debian nodes reset completed"
  else
    warn "Debian reset had errors (see log)"
  fi
  
  # Check if homelab has RKE2 installed
  info ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  PHASE 2: Resetting RKE2 on Homelab"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check if RKE2 is installed
  if ansible homelab -i "$INVENTORY_FILE" -m shell \
     -a "test -d /var/lib/rancher/rke2" 2>/dev/null | grep -q SUCCESS; then
    info "RKE2 detected on homelab, uninstalling..."
    
    # Build ansible-playbook command with proper flags
    local ansible_rke2_cmd="ansible-playbook -i $INVENTORY_FILE $UNINSTALL_RKE2_PLAYBOOK"
    
    # Add skip_ansible_confirm when FLAG_YES is true
    if [[ "$FLAG_YES" == "true" ]]; then
      ansible_rke2_cmd="$ansible_rke2_cmd -e skip_ansible_confirm=true"
    fi
    
    # Force color output for better readability
    ANSIBLE_FORCE_COLOR=true eval "$ansible_rke2_cmd" 2>&1 | tee "$LOG_DIR/uninstall-rke2.log"
    local uninstall_result=${PIPESTATUS[0]}
    
    if [[ $uninstall_result -eq 0 ]]; then
      info "✓ RKE2 uninstalled from homelab"
    else
      warn "RKE2 uninstall had errors (see log)"
    fi
  else
    info "No RKE2 installation found on homelab, skipping"
  fi
  
  info ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  Reset Complete!"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info ""
  info "Cluster is ready for fresh deployment"
  info ""
  info "Logs:"
  info "  - $LOG_DIR/reset-kubespray.log"
  info "  - $LOG_DIR/uninstall-rke2.log"
  info ""
  info "Next steps:"
  info "  ./deploy.sh setup              # Setup auto-sleep"
  info "  ./deploy.sh debian             # Deploy Kubespray cluster"
  info "  ./deploy.sh monitoring         # Deploy monitoring stack"
  info "  ./deploy.sh infrastructure     # Deploy infrastructure services"
  info "  ./deploy.sh rke2               # Deploy RKE2 on homelab (optional)"
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
  
  # Setup kubeconfig for playbook compatibility
  info "Setting up kubeconfig..."
  if [[ -x "$REPO_ROOT/scripts/setup-kubeconfig.sh" ]]; then
    eval "$("$REPO_ROOT/scripts/setup-kubeconfig.sh")" || warn "Kubeconfig setup had warnings"
  fi
  
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
    info "  kubectl get pods -n monitoring"
    info "  kubectl get svc -n monitoring"
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
  
  # Setup kubeconfig for playbook compatibility
  info "Setting up kubeconfig..."
  if [[ -x "$REPO_ROOT/scripts/setup-kubeconfig.sh" ]]; then
    eval "$("$REPO_ROOT/scripts/setup-kubeconfig.sh")" || warn "Kubeconfig setup had warnings"
  fi
  
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
    info "  kubectl get pods -n infrastructure"
    info "  kubectl get svc -n infrastructure"
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
    info "  ./deploy.sh all --with-rke2    # Deploy both Kubespray and RKE2"
    info "  ./deploy.sh debian             # Deploy Kubespray cluster only"
    info "  ./deploy.sh kubespray          # Deploy Kubespray cluster (same as debian)"
    info "  ./deploy.sh monitoring         # Deploy monitoring stack"
    info "  ./deploy.sh infrastructure     # Deploy infrastructure services"
    info ""
    usage
    exit 1
  fi
  
  # Execute command
  case "$cmd" in
    debian|kubespray)
      cmd_debian
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

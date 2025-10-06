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
ARTIFACTS_DIR="$REPO_ROOT/ansible/artifacts"

info(){ echo "[INFO] $*" >&2; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERROR] $*" >&2; exit 1; }

# Global flags
FLAG_YES=false
FLAG_CHECK=false
FLAG_WITH_RKE2=false
LOG_DIR="$ARTIFACTS_DIR"

usage(){
  cat <<EOF
Usage: $(basename "$0") [command] [flags]

Commands:
  debian       Deploy kubeadm/Kubernetes to Debian nodes only (monitoring_nodes + storage_nodes)
  rke2         Deploy RKE2 to homelab RHEL10 node with pre-checks
  all          Deploy both Debian and RKE2 (requires --with-rke2 or confirmation)
  reset        Comprehensive cluster reset - removes all K8s config/network (Debian + RKE2)
  setup        Setup auto-sleep monitoring (one-time setup)
  spindown     Cordon/drain and scale to zero on all nodes, then cleanup CNI/flannel artifacts (does NOT power off)
  help         Show this message

Flags:
  --yes        Skip interactive confirmations (for automation)
  --check      Dry-run mode - show planned actions without executing
  --with-rke2  Auto-proceed with RKE2 deployment in 'all' command
  --log-dir    Specify custom log directory (default: ansible/artifacts)

Examples:
  ./deploy.sh debian                    # Deploy kubeadm to Debian nodes only
  ./deploy.sh rke2                      # Deploy RKE2 to homelab (with pre-checks)
  ./deploy.sh all --with-rke2           # Deploy both phases non-interactively
  ./deploy.sh reset                     # Full reset (Debian + RKE2)
  ./deploy.sh debian --check            # Show what would be deployed
  ./deploy.sh setup                     # Setup auto-sleep monitoring

Workflow:
  1. ./deploy.sh debian    # Deploy Debian control-plane and worker
  2. Verify Debian cluster is healthy
  3. ./deploy.sh rke2      # Deploy RKE2 on homelab node
  4. Configure Prometheus federation between clusters

Artifacts:
  - Logs: ansible/artifacts/deploy-debian.log, install-rke2-homelab.log
  - RKE2 kubeconfig: ansible/artifacts/homelab-rke2-kubeconfig.yaml

EOF
}

require_bin(){ command -v "$1" >/dev/null 2>&1 || err "required binary '$1' not found"; }

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
  if ansible homelab -i "$INVENTORY_FILE" -m ping >/dev/null 2>&1; then
    info "✓ SSH connectivity to homelab verified"
    return 0
  else
    err "✗ Cannot reach homelab via SSH. Check inventory and SSH keys."
  fi
}

verify_debian_cluster_health(){
  info "Verifying Debian cluster health..."
  local kubeconfig="/etc/kubernetes/admin.conf"
  
  # Check if we're on the control plane or need to SSH
  if [[ -f "$kubeconfig" ]]; then
    # We're on the masternode
    if kubectl --kubeconfig="$kubeconfig" get nodes >/dev/null 2>&1; then
      local nodes_ready=$(kubectl --kubeconfig="$kubeconfig" get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
      if [[ "$nodes_ready" -ge 1 ]]; then
        info "✓ Debian cluster is healthy ($nodes_ready nodes Ready)"
        return 0
      fi
    fi
  else
    # Try via ansible to masternode
    if ansible monitoring_nodes -i "$INVENTORY_FILE" -m shell \
       -a "kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --no-headers" \
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
    echo "  ansible-playbook -i $INVENTORY_FILE $DEPLOY_PLAYBOOK \\"
    echo "    --limit monitoring_nodes,storage_nodes \\"
    echo "    | tee $LOG_DIR/deploy-debian.log"
    return 0
  fi
  
  # Run deployment with --limit to exclude homelab (compute_nodes)
  info "Starting Debian deployment (this may take 10-15 minutes)..."
  if ansible-playbook -i "$INVENTORY_FILE" "$DEPLOY_PLAYBOOK" \
     --limit monitoring_nodes,storage_nodes \
     2>&1 | tee "$LOG_DIR/deploy-debian.log"; then
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
    echo "  ansible-playbook -i $INVENTORY_FILE $INSTALL_RKE2_PLAYBOOK \\"
    echo "    | tee $LOG_DIR/install-rke2-homelab.log"
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
  if ansible-playbook -i "$INVENTORY_FILE" "$INSTALL_RKE2_PLAYBOOK" \
     2>&1 | tee "$LOG_DIR/install-rke2-homelab.log"; then
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
        local monitoring_pods=$(kubectl --kubeconfig="$kubeconfig_artifact" get pods -n monitoring-rke2 --no-headers 2>/dev/null | grep -c Running || echo "0")
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
  info " Two-Phase Deployment: Debian + RKE2   "
  info "========================================"
  info ""
  
  # Check if --with-rke2 flag is set
  if [[ "$FLAG_WITH_RKE2" != "true" ]] && [[ "$FLAG_YES" != "true" ]]; then
    info "This will deploy:"
    info "  1. Kubernetes (kubeadm) to Debian nodes (monitoring + storage)"
    info "  2. RKE2 to homelab RHEL10 node"
    info ""
    if ! confirm "Proceed with two-phase deployment?"; then
      err "Aborted by user. Use --with-rke2 flag to skip confirmation."
    fi
  fi
  
  # Phase 1: Debian
  info ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  PHASE 1: Deploying to Debian Nodes"
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
  info "  ✓ Debian cluster: monitoring_nodes + storage_nodes"
  info "  ✓ RKE2 cluster: homelab"
  info ""
  info "Logs:"
  info "  - $LOG_DIR/deploy-debian.log"
  info "  - $LOG_DIR/install-rke2-homelab.log"
  info ""
}

cmd_reset(){
  require_bin ansible-playbook
  
  info "========================================"
  info " Comprehensive Cluster Reset            "
  info "========================================"
  info "This will reset:"
  info "  - Debian Kubernetes cluster (kubeadm)"
  info "  - RKE2 cluster on homelab"
  info "  - All network interfaces and configs"
  info ""
  info "SSH keys and physical ethernet will be preserved"
  info ""
  
  if [[ "$FLAG_CHECK" == "true" ]]; then
    info "DRY-RUN: Would execute:"
    echo "  1. ansible-playbook $RESET_PLAYBOOK (Debian nodes)"
    echo "  2. ansible-playbook $UNINSTALL_RKE2_PLAYBOOK (homelab)"
    return 0
  fi
  
  if ! confirm "Proceed with comprehensive reset?"; then
    err "Aborted by user"
  fi
  
  info ""
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  info "  PHASE 1: Resetting Debian Nodes"
  info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if ansible-playbook -i "$INVENTORY_FILE" "$RESET_PLAYBOOK" \
     2>&1 | tee "$LOG_DIR/reset-debian.log"; then
    info "✓ Debian cluster reset completed"
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
    if ansible-playbook -i "$INVENTORY_FILE" "$UNINSTALL_RKE2_PLAYBOOK" \
       2>&1 | tee "$LOG_DIR/uninstall-rke2.log"; then
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
  info "  - $LOG_DIR/reset-debian.log"
  info "  - $LOG_DIR/uninstall-rke2.log"
  info ""
  info "Next steps:"
  info "  ./deploy.sh all --with-rke2    # Full deployment"
  info "  ./deploy.sh debian             # Debian only"
  info "  ./deploy.sh rke2               # RKE2 only"
  info ""
}

cmd_setup_autosleep(){
  require_bin ansible-playbook
  info "Setting up auto-sleep monitoring..."
  
  if ansible-playbook -i "$INVENTORY_FILE" "$AUTOSLEEP_SETUP_PLAYBOOK"; then
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
  ansible-playbook "$SPIN_PLAYBOOK" -e "@${tmpvars}" -e 'allow_power_down=false' -e 'spin_confirm=true'
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
      debian|rke2|all|reset|setup|spindown)
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
    info "  ./deploy.sh debian             # Deploy Debian only"
    info "  ./deploy.sh rke2               # Deploy RKE2 only"
    info ""
    usage
    exit 1
  fi
  
  # Execute command
  case "$cmd" in
    debian)
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
    *)
      usage
      err "unknown command: $cmd"
      ;;
  esac
}

main "$@"

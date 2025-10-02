#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="$REPO_ROOT/ansible/inventory/hosts.yml"
SPIN_PLAYBOOK="$REPO_ROOT/ansible/playbooks/spin-down-cluster.yaml"
DEPLOY_PLAYBOOK="$REPO_ROOT/ansible/playbooks/deploy-cluster.yaml"

info(){ echo "[INFO] $*" >&2; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERROR] $*" >&2; exit 1; }

usage(){
  cat <<EOF
Usage: $(basename "$0") [command]

Commands:
  (no args)    Run main deploy playbook
  spindown     Cordon/drain and scale to zero on all nodes, then cleanup CNI/flannel artifacts (does NOT power off)
  help         Show this message

Examples:
  ./deploy.sh
  ./deploy.sh spindown

EOF
}

require_bin(){ command -v "$1" >/dev/null 2>&1 || err "required binary '$1' not found"; }

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

cmd_deploy(){
  info "Running deploy playbook: ${DEPLOY_PLAYBOOK}"
  require_bin ansible-playbook
  ansible-playbook "$DEPLOY_PLAYBOOK"
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

main(){
  if [[ ${#} -eq 0 ]]; then
    cmd_deploy
    exit 0
  fi
  case "$1" in
    help|-h|--help) usage; exit 0 ;;
    spindown) cmd_spindown ;;
    *) usage; err "unknown command: $1" ;;
  esac
}

main "$@"

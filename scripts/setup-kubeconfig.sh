#!/usr/bin/env bash
# VMStation Kubeconfig Setup Script
# Ensures kubeconfig is available at expected locations for playbooks
set -euo pipefail

# Logging functions
log_info() { echo "[INFO] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_err() { echo "[ERROR] $*" >&2; exit 1; }

# Kubeconfig locations to check
KUBECONFIG_LOCATIONS=(
  "$HOME/.kube/config"
  "/etc/kubernetes/admin.conf"
)

# Find the first valid kubeconfig
FOUND_KUBECONFIG=""
for kubeconfig in "${KUBECONFIG_LOCATIONS[@]}"; do
  if [[ -f "$kubeconfig" ]]; then
    if kubectl --kubeconfig="$kubeconfig" cluster-info >/dev/null 2>&1; then
      FOUND_KUBECONFIG="$kubeconfig"
      log_info "Found valid kubeconfig: $kubeconfig"
      break
    fi
  fi
done

if [[ -z "$FOUND_KUBECONFIG" ]]; then
  log_err "No valid kubeconfig found. Cluster may not be deployed yet."
fi

# Ensure both locations exist for compatibility
# This ensures playbooks work regardless of which path they use
KUBEADM_PATH="/etc/kubernetes/admin.conf"
KUBESPRAY_PATH="$HOME/.kube/config"

# Create .kube directory if it doesn't exist
mkdir -p "$HOME/.kube"

# If kubeconfig is at one location but not the other, create a symlink or copy
if [[ "$FOUND_KUBECONFIG" == "$KUBEADM_PATH" ]] && [[ ! -f "$KUBESPRAY_PATH" ]]; then
  log_info "Copying kubeconfig from $KUBEADM_PATH to $KUBESPRAY_PATH"
  cp "$KUBEADM_PATH" "$KUBESPRAY_PATH"
  chmod 600 "$KUBESPRAY_PATH"
elif [[ "$FOUND_KUBECONFIG" == "$KUBESPRAY_PATH" ]] && [[ ! -f "$KUBEADM_PATH" ]]; then
  log_info "Ensuring kubeconfig is available at $KUBEADM_PATH for playbook compatibility"
  if [[ ! -d "/etc/kubernetes" ]]; then
    sudo mkdir -p /etc/kubernetes
  fi
  sudo cp "$KUBESPRAY_PATH" "$KUBEADM_PATH"
  sudo chmod 600 "$KUBEADM_PATH"
fi

log_info "✓ Kubeconfig setup complete"
log_info "  Primary: $FOUND_KUBECONFIG"

# Export for current session
export KUBECONFIG="$FOUND_KUBECONFIG"
echo "export KUBECONFIG=\"$FOUND_KUBECONFIG\""

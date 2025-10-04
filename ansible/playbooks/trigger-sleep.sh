#!/usr/bin/env bash
# =============================================================================
# Trigger Sleep Mode - Gracefully drain and suspend worker nodes
# Preserves masternode for Wake-on-LAN and CoreDNS functionality
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INVENTORY_FILE="$REPO_ROOT/ansible/inventory/hosts"
LOG_FILE="/var/log/vmstation-autosleep.log"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "Starting graceful cluster sleep sequence"

# Cordon and drain worker nodes
log "Cordoning all worker nodes..."
kubectl --kubeconfig=/etc/kubernetes/admin.conf cordon storagenodet3500 homelab || true

log "Draining worker nodes (timeout: 300s)..."
kubectl --kubeconfig=/etc/kubernetes/admin.conf drain storagenodet3500 \
  --ignore-daemonsets --delete-emptydir-data --force --timeout=300s || true

kubectl --kubeconfig=/etc/kubernetes/admin.conf drain homelab \
  --ignore-daemonsets --delete-emptydir-data --force --timeout=300s || true

log "Waiting 30 seconds for pods to terminate gracefully..."
sleep 30

# Stop kubelet on worker nodes to prevent restart attempts
log "Stopping kubelet on worker nodes..."
ssh -o StrictHostKeyChecking=no storagenodet3500 'sudo systemctl stop kubelet' || true
ssh -o StrictHostKeyChecking=no homelab 'sudo systemctl stop kubelet' || true

# Suspend worker nodes (Wake-on-LAN enabled)
log "Suspending storagenodet3500 (192.168.4.61)..."
ssh -o StrictHostKeyChecking=no storagenodet3500 'sudo systemctl suspend' || true

log "Suspending homelab (192.168.4.62)..."
ssh -o StrictHostKeyChecking=no homelab 'sudo systemctl suspend' || true

log "Sleep mode activated - worker nodes suspended"
log "Masternode remains active for CoreDNS and Wake-on-LAN"
log "To wake cluster: /root/VMStation/ansible/playbooks/wake-cluster.sh"

exit 0

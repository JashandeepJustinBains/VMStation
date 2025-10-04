#!/usr/bin/env bash
# =============================================================================
# Wake Cluster - Send Wake-on-LAN magic packets to suspended worker nodes
# =============================================================================

set -euo pipefail

LOG_FILE="/var/log/vmstation-autosleep.log"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# Ensure wakeonlan is installed
if ! command -v wakeonlan &>/dev/null; then
  log "Installing wakeonlan package..."
  apt-get update -qq && apt-get install -y wakeonlan
fi

log "Sending Wake-on-LAN magic packets to worker nodes..."

# Wake storagenodet3500 (192.168.4.61)
log "Waking storagenodet3500 (MAC: b8:ac:6f:7e:6c:9d)..."
wakeonlan -i 192.168.4.255 b8:ac:6f:7e:6c:9d

# Wake homelab (192.168.4.62)
log "Waking homelab (MAC: d0:94:66:30:d6:63)..."
wakeonlan -i 192.168.4.255 d0:94:66:30:d6:63

log "Magic packets sent - waiting 60 seconds for nodes to boot..."
sleep 60

# Wait for nodes to be reachable via ping
log "Checking node availability..."

for i in {1..30}; do
  storage_up=false
  homelab_up=false
  
  if ping -c 1 -W 2 192.168.4.61 &>/dev/null; then
    storage_up=true
  fi
  
  if ping -c 1 -W 2 192.168.4.62 &>/dev/null; then
    homelab_up=true
  fi
  
  if $storage_up && $homelab_up; then
    log "All worker nodes are now reachable"
    break
  fi
  
  log "Waiting for nodes to wake... ($i/30)"
  sleep 10
done

# Start kubelet on worker nodes
log "Starting kubelet on worker nodes..."
ssh -o StrictHostKeyChecking=no storagenodet3500 'sudo systemctl start kubelet' || true
ssh -o StrictHostKeyChecking=no homelab 'sudo systemctl start kubelet' || true

sleep 10

# Uncordon worker nodes
log "Uncordoning worker nodes..."
kubectl --kubeconfig=/etc/kubernetes/admin.conf uncordon storagenodet3500 || true
kubectl --kubeconfig=/etc/kubernetes/admin.conf uncordon homelab || true

# Wait for nodes to become Ready
log "Waiting for nodes to become Ready..."
for i in {1..24}; do
  ready_count=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf \
    get nodes --no-headers | awk '$2 == "Ready"' | wc -l)
  
  if [ "$ready_count" -eq 3 ]; then
    log "All 3 nodes are Ready"
    kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide
    break
  fi
  
  log "Nodes Ready: $ready_count/3 ($i/24)"
  sleep 10
done

log "Cluster wake-up complete"
log "All worker nodes are active and ready for workloads"

exit 0

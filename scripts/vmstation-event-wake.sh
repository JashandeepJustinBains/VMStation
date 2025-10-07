#!/bin/bash
# vmstation-event-wake.sh: Event-driven autosleep/wake orchestrator
# Enterprise-grade Wake-on-LAN orchestration for storage and compute nodes
# Monitors Samba share access and Jellyfin NodePort traffic to wake nodes on-demand

set -euo pipefail

# Configuration - Update these MAC addresses based on your inventory
STORAGE_NODE_MAC="b8:ac:6f:7e:6c:9d"  # storagenodet3500 (from inventory)
STORAGE_NODE_IP="192.168.4.61"
HOMELAB_NODE_MAC="d0:94:66:30:d6:63"  # homelab RHEL 10 node (from inventory)
HOMELAB_NODE_IP="192.168.4.62"
JELLYFIN_PORT=30096
SAMBA_PATH="/srv/media"
LOG_FILE="/var/log/vmstation-event-wake.log"
STATE_DIR="/var/lib/vmstation"

# Create required directories
mkdir -p "$(dirname "$LOG_FILE")" "$STATE_DIR"

# Logging function with timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Validate and enable WOL on all network interfaces
enable_wol_on_interfaces() {
  log "Validating Wake-on-LAN configuration on network interfaces..."
  
  if ! command -v ethtool >/dev/null 2>&1; then
    log "WARNING: ethtool not found, cannot validate WOL settings"
    return 1
  fi
  
  # Get all network interfaces except loopback
  for iface in $(ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print $2}' | grep -v '^lo$'); do
    # Check if interface supports WOL
    if ethtool "$iface" 2>/dev/null | grep -q "Supports Wake-on"; then
      # Enable WOL with magic packet (g flag)
      if ethtool -s "$iface" wol g 2>/dev/null; then
        log "Enabled WOL on interface $iface"
      else
        log "WARNING: Could not enable WOL on interface $iface (may require root)"
      fi
      
      # Verify WOL is enabled
      WOL_STATUS=$(ethtool "$iface" 2>/dev/null | grep "Wake-on:" | awk '{print $2}')
      log "WOL status for $iface: $WOL_STATUS"
    fi
  done
}

# Enhanced Wake-on-LAN function with proper broadcast addressing
wake_node() {
  local mac="$1"
  local ip="$2"
  local node_name="${3:-unknown}"
  
  log "Initiating WOL for $node_name ($mac at $ip)..."
  
  # Try multiple WOL tools for reliability
  local wol_sent=false
  
  # Method 1: etherwake (most reliable)
  if command -v etherwake >/dev/null 2>&1; then
    # Use broadcast on all interfaces
    for iface in $(ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print $2}' | grep -v '^lo$'); do
      if etherwake -i "$iface" "$mac" 2>>/dev/null; then
        log "WOL packet sent via etherwake on interface $iface to $mac"
        wol_sent=true
      fi
    done
  fi
  
  # Method 2: wakeonlan (alternative)
  if command -v wakeonlan >/dev/null 2>&1 && [ "$wol_sent" = false ]; then
    if wakeonlan "$mac" 2>>/dev/null; then
      log "WOL packet sent via wakeonlan to $mac"
      wol_sent=true
    fi
  fi
  
  # Method 3: ether-wake (another alternative)
  if command -v ether-wake >/dev/null 2>&1 && [ "$wol_sent" = false ]; then
    if ether-wake "$mac" 2>>/dev/null; then
      log "WOL packet sent via ether-wake to $mac"
      wol_sent=true
    fi
  fi
  
  if [ "$wol_sent" = false ]; then
    log "ERROR: No WOL tool available or all methods failed for $mac"
    log "Install etherwake: apt-get install etherwake"
    return 1
  fi
  
  # Verify node is reachable after wake (with timeout)
  log "Waiting for $node_name to respond..."
  local timeout=60
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
      log "SUCCESS: $node_name is now reachable at $ip"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  
  log "WARNING: $node_name did not respond within ${timeout}s (may still be booting)"
  return 0
}

# Initialize WOL configuration
log "=========================================="
log "VMStation Event-Driven Wake Monitor Started"
log "=========================================="
enable_wol_on_interfaces

# Monitor Samba share access using inotify
if [ -d "$SAMBA_PATH" ]; then
  log "Starting Samba share monitoring on $SAMBA_PATH"
  
  while true; do
    if command -v inotifywait >/dev/null 2>&1; then
      inotifywait -e access,open,modify,attrib,close_write "$SAMBA_PATH" 2>>/dev/null |
      while read -r path action file; do
        log "Samba access detected: $action on $file"
        wake_node "$STORAGE_NODE_MAC" "$STORAGE_NODE_IP" "storagenodet3500"
        # Cooldown to prevent spam
        sleep 30
        break
      done
    else
      log "WARNING: inotifywait not found, Samba monitoring disabled"
      log "Install inotify-tools: apt-get install inotify-tools"
      sleep 300  # Check every 5 minutes if installed
    fi
  done &
else
  log "WARNING: Samba path $SAMBA_PATH does not exist, skipping Samba monitoring"
fi

# Monitor Jellyfin NodePort traffic
log "Starting Jellyfin NodePort monitoring on port $JELLYFIN_PORT"

while true; do
  if command -v nc >/dev/null 2>&1; then
    # Listen for connections on Jellyfin port
    if nc -l -p "$JELLYFIN_PORT" -w 2 < /dev/null 2>/dev/null; then
      log "Jellyfin access detected on port $JELLYFIN_PORT"
      wake_node "$STORAGE_NODE_MAC" "$STORAGE_NODE_IP" "storagenodet3500"
      # Cooldown to prevent spam
      sleep 30
    fi
  else
    log "WARNING: nc (netcat) not found, Jellyfin monitoring disabled"
    log "Install netcat: apt-get install netcat-openbsd"
    sleep 300  # Check every 5 minutes if installed
  fi
done &

# Monitor SSH access to homelab node (RHEL 10)
log "Starting SSH access monitoring for homelab node"

while true; do
  # Check if homelab node is down
  if ! ping -c 1 -W 1 "$HOMELAB_NODE_IP" >/dev/null 2>&1; then
    # Check for SSH connection attempts (from local logs)
    if [ -f /var/log/auth.log ] && tail -n 5 /var/log/auth.log | grep -q "$HOMELAB_NODE_IP"; then
      log "SSH access attempt to homelab node detected"
      wake_node "$HOMELAB_NODE_MAC" "$HOMELAB_NODE_IP" "homelab-rhel10"
    fi
  fi
  sleep 60  # Check every minute
done &

log "All monitoring tasks started"

# Wait for all background processes
wait

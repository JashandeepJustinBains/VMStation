#!/bin/bash
# vmstation-event-wake.sh: Event-driven autosleep/wake orchestrator
# Enterprise-grade Wake-on-LAN orchestration for storage and compute nodes
# Monitors Samba share access and Jellyfin NodePort traffic to wake nodes on-demand
# Automatically uncordons nodes after successful wake

set -euo pipefail

# Configuration - Update these MAC addresses based on your inventory
STORAGE_NODE_MAC="b8:ac:6f:7e:6c:9d"  # storagenodet3500 (from inventory)
STORAGE_NODE_IP="192.168.4.61"
STORAGE_NODE_USER="root"
STORAGE_NODE_NAME="storagenodet3500"
HOMELAB_NODE_MAC="d0:94:66:30:d6:63"  # homelab RHEL 10 node (from inventory)
HOMELAB_NODE_IP="192.168.4.62"
HOMELAB_NODE_USER="jashandeepjustinbains"
HOMELAB_NODE_NAME="homelab"
JELLYFIN_PORT=30096
SAMBA_PORT=445
SSH_PORT=22
SAMBA_PATH="/srv/media"
LOG_FILE="/var/log/vmstation-event-wake.log"
STATE_DIR="/var/lib/vmstation"
WAKE_COOLDOWN=120  # Seconds before checking if wake is needed again

# Kubernetes configuration
if [[ -f "/etc/kubernetes/admin.conf" ]]; then
  KUBECONFIG="/etc/kubernetes/admin.conf"
elif [[ -f "/etc/rancher/rke2/rke2.yaml" ]]; then
  KUBECONFIG="/etc/rancher/rke2/rke2.yaml"
else
  KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
fi
export KUBECONFIG

# Validate kubectl is available
KUBECTL="kubectl"
if [[ ! -x "/usr/bin/kubectl" ]] && [[ -x "/var/lib/rancher/rke2/bin/kubectl" ]]; then
  KUBECTL="/var/lib/rancher/rke2/bin/kubectl"
fi

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
  local node_user="${4:-root}"
  
  # Check if node is already awake
  if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
    log "Node $node_name is already awake at $ip"
    # Still uncordon if needed
    uncordon_node "$node_name"
    return 0
  fi
  
  log "Initiating WOL for $node_name ($mac at $ip)..."
  
  # Check if node was suspended
  local state_file="$STATE_DIR/${node_name}.state"
  if [[ -f "$state_file" ]]; then
    local state=$(cat "$state_file")
    log "Node state before wake: $state"
  else
    log "WARNING: No state file found for $node_name (may not have been properly suspended)"
  fi
  
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
  local timeout=180  # Increased timeout for actual hardware wake
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
      log "SUCCESS: $node_name is now reachable at $ip"
      
      # Wait for services to start
      log "Waiting for node services to initialize..."
      sleep 30
      
      # Uncordon the node in Kubernetes
      uncordon_node "$node_name"
      
      # Update state file
      echo "awake:$(date +%s)" > "$state_file"
      
      # Update last activity to prevent immediate re-sleep
      echo "$(date +%s)" > /var/lib/vmstation/last-activity
      
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  
  log "WARNING: $node_name did not respond within ${timeout}s (may still be booting)"
  return 1
}

# Uncordon a node in Kubernetes after wake
uncordon_node() {
  local node_name="$1"
  
  if ! command -v $KUBECTL >/dev/null 2>&1; then
    log "WARNING: kubectl not available, cannot uncordon $node_name"
    return 1
  fi
  
  # Check if node exists and is cordoned
  if $KUBECTL get node "$node_name" >/dev/null 2>&1; then
    local node_status=$($KUBECTL get node "$node_name" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || echo "false")
    
    if [[ "$node_status" == "true" ]]; then
      log "Uncordoning node: $node_name"
      if $KUBECTL uncordon "$node_name" 2>&1 | tee -a "$LOG_FILE"; then
        log "SUCCESS: Node $node_name is now schedulable"
        return 0
      else
        log "ERROR: Failed to uncordon $node_name"
        return 1
      fi
    else
      log "Node $node_name is already uncordoned"
      return 0
    fi
  else
    log "WARNING: Node $node_name not found in cluster"
    return 1
  fi
}

# Initialize WOL configuration
log "=========================================="
log "VMStation Event-Driven Wake Monitor Started"
log "==========================================" 
enable_wol_on_interfaces

# Track last wake time to prevent spam
declare -A LAST_WAKE_TIME
LAST_WAKE_TIME["storage"]=0
LAST_WAKE_TIME["homelab"]=0

# Function to check if cooldown period has passed
should_wake() {
  local node_type="$1"
  local current_time=$(date +%s)
  local last_wake=${LAST_WAKE_TIME[$node_type]}
  local elapsed=$((current_time - last_wake))
  
  if [ $elapsed -lt $WAKE_COOLDOWN ]; then
    log "Cooldown active for $node_type (${elapsed}s < ${WAKE_COOLDOWN}s)"
    return 1
  fi
  return 0
}

# Function to record wake event
record_wake() {
  local node_type="$1"
  LAST_WAKE_TIME[$node_type]=$(date +%s)
}

# Monitor TCP connection attempts to Samba port (445) - only external traffic
log "Starting Samba access monitoring (port $SAMBA_PORT)"

if command -v tcpdump >/dev/null 2>&1; then
  # Monitor for NEW connections to Samba port (not existing cluster traffic)
  tcpdump -i any -n "tcp port $SAMBA_PORT and tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0" 2>/dev/null | \
  while read line; do
    # Extract source IP
    src_ip=$(echo "$line" | grep -oP '\d+\.\d+\.\d+\.\d+(?=\.\d+ >)' || echo "")
    
    # Ignore internal cluster traffic (192.168.4.x is local network, but filter out node IPs)
    if [[ "$src_ip" =~ ^192\.168\.4\.(61|62|63)$ ]]; then
      # This is node-to-node traffic, ignore
      continue
    fi
    
    if [[ -n "$src_ip" ]] && should_wake "storage"; then
      log "External Samba access detected from $src_ip"
      wake_node "$STORAGE_NODE_MAC" "$STORAGE_NODE_IP" "$STORAGE_NODE_NAME" "$STORAGE_NODE_USER"
      record_wake "storage"
    fi
  done &
else
  log "WARNING: tcpdump not found, using fallback Samba monitoring"
  
  # Fallback: Monitor Samba share access using inotify
  if [ -d "$SAMBA_PATH" ]; then
    log "Starting Samba share monitoring on $SAMBA_PATH"
    
    while true; do
      if command -v inotifywait >/dev/null 2>&1; then
        inotifywait -e access,open,modify,attrib,close_write "$SAMBA_PATH" 2>>/dev/null |
        while read -r path action file; do
          if should_wake "storage"; then
            log "Samba access detected: $action on $file"
            wake_node "$STORAGE_NODE_MAC" "$STORAGE_NODE_IP" "$STORAGE_NODE_NAME" "$STORAGE_NODE_USER"
            record_wake "storage"
          fi
          sleep 5
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
fi

# Monitor Jellyfin NodePort traffic (external connections only)
log "Starting Jellyfin NodePort monitoring on port $JELLYFIN_PORT"

if command -v tcpdump >/dev/null 2>&1; then
  # Monitor for NEW connections to Jellyfin port
  tcpdump -i any -n "tcp port $JELLYFIN_PORT and tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0" 2>/dev/null | \
  while read line; do
    # Extract source IP
    src_ip=$(echo "$line" | grep -oP '\d+\.\d+\.\d+\.\d+(?=\.\d+ >)' || echo "")
    
    # Ignore internal cluster traffic
    if [[ "$src_ip" =~ ^192\.168\.4\.(61|62|63)$ ]]; then
      # This is node-to-node traffic, ignore
      continue
    fi
    
    if [[ -n "$src_ip" ]] && should_wake "storage"; then
      log "External Jellyfin access detected from $src_ip on port $JELLYFIN_PORT"
      wake_node "$STORAGE_NODE_MAC" "$STORAGE_NODE_IP" "$STORAGE_NODE_NAME" "$STORAGE_NODE_USER"
      record_wake "storage"
    fi
  done &
else
  log "WARNING: tcpdump not found, Jellyfin port monitoring disabled"
  log "Install tcpdump: apt-get install tcpdump"
fi

# Monitor SSH access to storage node
log "Starting SSH access monitoring for storage node (port $SSH_PORT)"

if command -v tcpdump >/dev/null 2>&1; then
  # Monitor for NEW SSH connections to storage node
  tcpdump -i any -n "dst host $STORAGE_NODE_IP and tcp port $SSH_PORT and tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0" 2>/dev/null | \
  while read line; do
    # Extract source IP
    src_ip=$(echo "$line" | grep -oP '\d+\.\d+\.\d+\.\d+(?=\.\d+ >)' || echo "")
    
    # Ignore masternode SSH checks
    if [[ "$src_ip" == "192.168.4.63" ]]; then
      # This is masternode checking, ignore
      continue
    fi
    
    if [[ -n "$src_ip" ]] && should_wake "storage"; then
      log "External SSH access attempt to storage node from $src_ip"
      wake_node "$STORAGE_NODE_MAC" "$STORAGE_NODE_IP" "$STORAGE_NODE_NAME" "$STORAGE_NODE_USER"
      record_wake "storage"
    fi
  done &
else
  log "WARNING: tcpdump not found, SSH monitoring disabled"
fi

# Monitor SSH access to homelab node
log "Starting SSH access monitoring for homelab node (port $SSH_PORT)"

if command -v tcpdump >/dev/null 2>&1; then
  # Monitor for NEW SSH connections to homelab node
  tcpdump -i any -n "dst host $HOMELAB_NODE_IP and tcp port $SSH_PORT and tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0" 2>/dev/null | \
  while read line; do
    # Extract source IP
    src_ip=$(echo "$line" | grep -oP '\d+\.\d+\.\d+\.\d+(?=\.\d+ >)' || echo "")
    
    # Ignore masternode SSH checks
    if [[ "$src_ip" == "192.168.4.63" ]]; then
      # This is masternode checking, ignore
      continue
    fi
    
    if [[ -n "$src_ip" ]] && should_wake "homelab"; then
      log "External SSH access attempt to homelab node from $src_ip"
      wake_node "$HOMELAB_NODE_MAC" "$HOMELAB_NODE_IP" "$HOMELAB_NODE_NAME" "$HOMELAB_NODE_USER"
      record_wake "homelab"
    fi
  done &
else
  log "WARNING: tcpdump not found, SSH monitoring disabled"
fi

log "All monitoring tasks started"

# Wait for all background processes
wait

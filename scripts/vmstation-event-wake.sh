#!/bin/bash
# vmstation-event-wake.sh: Event-driven autosleep/wake orchestrator
# Monitors Samba share access and Jellyfin NodePort traffic to wake storage/homelab nodes

# Storage node MAC address (for WOL)
STORAGE_NODE_MAC="AA:BB:CC:DD:EE:FF"
STORAGE_NODE_IP="192.168.4.61"
JELLYFIN_PORT=30096
SAMBA_PATH="/srv/media"


# Function to send Wake-on-LAN packet with error handling and logging
wake_node() {
  local mac="$1"
  if command -v etherwake >/dev/null 2>&1; then
    etherwake "$mac" && echo "[INFO] Sent WOL packet to $mac" >> /var/log/vmstation-event-wake.log
  else
    echo "[ERROR] etherwake not found" >> /var/log/vmstation-event-wake.log
  fi
}

# Monitor Samba share access using inotify
done &

# Idempotent inotify monitoring for Samba access
while true; do
  inotifywait -e access,open,modify,attrib,close_write "$SAMBA_PATH" 2>>/var/log/vmstation-event-wake.log |
  while read path action file; do
    echo "[INFO] Samba access detected: $action on $file" >> /var/log/vmstation-event-wake.log
    wake_node "$STORAGE_NODE_MAC"
    sleep 10
    break
  done
done &


# Idempotent TCP listener for Jellyfin NodePort
while true; do
  nc -l -p "$JELLYFIN_PORT" -w 2 < /dev/null && {
    echo "[INFO] Jellyfin access detected on port $JELLYFIN_PORT" >> /var/log/vmstation-event-wake.log
    wake_node "$STORAGE_NODE_MAC"
    sleep 10
  }
done &


# TODO: Add similar logic for homelab nodes (API/SSH access)
# ...existing code...


wait

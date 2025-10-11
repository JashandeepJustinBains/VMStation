#!/bin/bash
# vmstation-collect-wake-logs.sh: Collect and analyze wake/suspend logs from all nodes
# Helps debug Wake-on-LAN and sleep/wake cycle issues

set -euo pipefail

# Configuration
STORAGE_NODE_IP="192.168.4.61"
STORAGE_NODE_USER="root"
HOMELAB_NODE_IP="192.168.4.62"
HOMELAB_NODE_USER="jashandeepjustinbains"
LOG_DIR="/var/log/vmstation-wake-logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Create log directory
mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=========================================="
log "VMStation Wake/Sleep Log Collection"
log "Timestamp: $TIMESTAMP"
log "=========================================="

# Function to collect logs from a node
collect_node_logs() {
  local node_name="$1"
  local node_ip="$2"
  local node_user="$3"
  local output_dir="$LOG_DIR/${TIMESTAMP}-${node_name}"
  
  log "Collecting logs from $node_name ($node_ip)..."
  
  # Create output directory
  mkdir -p "$output_dir"
  
  # Check if node is reachable
  if ! ping -c 1 -W 2 "$node_ip" >/dev/null 2>&1; then
    log "WARNING: $node_name is not reachable at $node_ip (may be suspended)"
    echo "Node is not reachable" > "$output_dir/status.txt"
    return 1
  fi
  
  # Collect system logs related to suspend/resume
  log "  - Collecting suspend/resume logs..."
  ssh -o ConnectTimeout=10 "${node_user}@${node_ip}" \
    "sudo journalctl -u systemd-suspend.service -u systemd-hibernate.service --since '24 hours ago' --no-pager" \
    > "$output_dir/suspend-resume.log" 2>&1 || \
    log "  WARNING: Failed to collect suspend/resume logs"
  
  # Collect kernel messages about power management
  log "  - Collecting kernel power management messages..."
  ssh -o ConnectTimeout=10 "${node_user}@${node_ip}" \
    "sudo dmesg -T | grep -iE 'suspend|resume|wol|wake.*lan|power.*management|acpi.*wake' || true" \
    > "$output_dir/kernel-power.log" 2>&1 || \
    log "  WARNING: Failed to collect kernel messages"
  
  # Collect syslog entries related to VMStation
  log "  - Collecting VMStation-related syslogs..."
  ssh -o ConnectTimeout=10 "${node_user}@${node_ip}" \
    "sudo grep -i 'vmstation' /var/log/syslog 2>/dev/null || sudo journalctl --since '24 hours ago' | grep -i 'vmstation' || true" \
    > "$output_dir/vmstation-syslog.log" 2>&1 || \
    log "  WARNING: Failed to collect VMStation syslogs"
  
  # Collect authentication logs (for SSH wake triggers)
  log "  - Collecting authentication logs..."
  ssh -o ConnectTimeout=10 "${node_user}@${node_ip}" \
    "sudo tail -n 100 /var/log/auth.log 2>/dev/null || sudo journalctl -u ssh --since '24 hours ago' --no-pager || true" \
    > "$output_dir/auth.log" 2>&1 || \
    log "  WARNING: Failed to collect auth logs"
  
  # Check current power state
  log "  - Checking current power state..."
  ssh -o ConnectTimeout=10 "${node_user}@${node_ip}" \
    "cat /sys/power/state 2>/dev/null || echo 'N/A'" \
    > "$output_dir/power-state.txt" 2>&1 || \
    log "  WARNING: Failed to check power state"
  
  # Check Wake-on-LAN configuration
  log "  - Checking Wake-on-LAN configuration..."
  ssh -o ConnectTimeout=10 "${node_user}@${node_ip}" \
    "sudo ethtool \$(ip route get 8.8.8.8 | grep -oP 'dev \K\S+' | head -1) 2>/dev/null | grep -i 'wake-on' || echo 'ethtool not available'" \
    > "$output_dir/wol-config.txt" 2>&1 || \
    log "  WARNING: Failed to check WoL configuration"
  
  # Collect network interface information
  log "  - Collecting network interface information..."
  ssh -o ConnectTimeout=10 "${node_user}@${node_ip}" \
    "ip addr show && echo '---' && ip link show" \
    > "$output_dir/network-interfaces.txt" 2>&1 || \
    log "  WARNING: Failed to collect network interface info"
  
  # Check systemd service logs
  log "  - Collecting systemd service logs..."
  ssh -o ConnectTimeout=10 "${node_user}@${node_ip}" \
    "sudo systemctl status kubelet --no-pager -l || true" \
    > "$output_dir/kubelet-status.log" 2>&1 || \
    log "  WARNING: Failed to collect kubelet status"
  
  # Create summary
  cat > "$output_dir/summary.txt" <<EOF
Node: $node_name
IP: $node_ip
Collection Time: $(date)
Node Status: Reachable

Logs collected:
- suspend-resume.log: systemd suspend/resume service logs
- kernel-power.log: kernel power management messages
- vmstation-syslog.log: VMStation-related syslog entries
- auth.log: authentication logs (SSH access)
- power-state.txt: current power state
- wol-config.txt: Wake-on-LAN configuration
- network-interfaces.txt: network interface information
- kubelet-status.log: Kubernetes kubelet service status
EOF
  
  log "  SUCCESS: Logs collected to $output_dir"
}

# Collect from storage node
collect_node_logs "storagenodet3500" "$STORAGE_NODE_IP" "$STORAGE_NODE_USER"

# Collect from homelab node
collect_node_logs "homelab" "$HOMELAB_NODE_IP" "$HOMELAB_NODE_USER"

# Collect masternode event-wake logs
log "Collecting masternode event-wake monitor logs..."
mkdir -p "$LOG_DIR/${TIMESTAMP}-masternode"
if [[ -f /var/log/vmstation-event-wake.log ]]; then
  cp /var/log/vmstation-event-wake.log "$LOG_DIR/${TIMESTAMP}-masternode/"
  log "  SUCCESS: Event-wake log copied"
else
  log "  WARNING: Event-wake log not found"
fi

# Collect masternode sleep logs
if [[ -f /var/log/vmstation-sleep.log ]]; then
  cp /var/log/vmstation-sleep.log "$LOG_DIR/${TIMESTAMP}-masternode/"
  log "  SUCCESS: Sleep log copied"
else
  log "  WARNING: Sleep log not found"
fi

# Collect autosleep monitor logs
log "Collecting autosleep monitor logs..."
journalctl -u vmstation-autosleep --since '24 hours ago' --no-pager \
  > "$LOG_DIR/${TIMESTAMP}-masternode/autosleep-monitor.log" 2>&1 || \
  log "  WARNING: Failed to collect autosleep monitor logs"

# Create master summary
log "Creating summary report..."
cat > "$LOG_DIR/${TIMESTAMP}-summary.md" <<EOF
# VMStation Wake/Sleep Log Collection Report

**Collection Time:** $(date)

## Nodes Analyzed

1. **storagenodet3500** (192.168.4.61)
   - Logs: \`$LOG_DIR/${TIMESTAMP}-storagenodet3500/\`
   
2. **homelab** (192.168.4.62)
   - Logs: \`$LOG_DIR/${TIMESTAMP}-homelab/\`
   
3. **masternode** (192.168.4.63)
   - Logs: \`$LOG_DIR/${TIMESTAMP}-masternode/\`

## Log Files

Each node directory contains:
- \`suspend-resume.log\`: Suspend/resume service logs
- \`kernel-power.log\`: Kernel power management messages
- \`vmstation-syslog.log\`: VMStation-related syslog entries
- \`auth.log\`: Authentication logs
- \`power-state.txt\`: Current power state
- \`wol-config.txt\`: Wake-on-LAN configuration
- \`network-interfaces.txt\`: Network interface info
- \`kubelet-status.log\`: Kubelet service status

Masternode directory contains:
- \`vmstation-event-wake.log\`: Event-wake monitor logs
- \`vmstation-sleep.log\`: Sleep script logs
- \`autosleep-monitor.log\`: Autosleep monitor logs

## Analysis

To analyze wake events, look for:
- Suspend/resume timestamps in \`suspend-resume.log\`
- WoL magic packet reception in \`kernel-power.log\`
- VMStation trigger events in \`vmstation-syslog.log\`
- SSH access attempts in \`auth.log\`

## Viewing Logs

\`\`\`bash
# View all logs for a specific node
less $LOG_DIR/${TIMESTAMP}-storagenodet3500/*.log

# Search for wake events
grep -i 'wake\|resume' $LOG_DIR/${TIMESTAMP}-*/kernel-power.log

# Search for suspend events
grep -i 'suspend' $LOG_DIR/${TIMESTAMP}-*/suspend-resume.log

# View VMStation activity
cat $LOG_DIR/${TIMESTAMP}-masternode/vmstation-event-wake.log
\`\`\`

EOF

log "=========================================="
log "Log collection complete!"
log "Logs saved to: $LOG_DIR/${TIMESTAMP}-*/"
log "Summary: $LOG_DIR/${TIMESTAMP}-summary.md"
log "=========================================="
log ""
log "To view the summary:"
log "  cat $LOG_DIR/${TIMESTAMP}-summary.md"
log ""
log "To analyze wake events:"
log "  grep -i 'wake\\|resume' $LOG_DIR/${TIMESTAMP}-*/kernel-power.log"

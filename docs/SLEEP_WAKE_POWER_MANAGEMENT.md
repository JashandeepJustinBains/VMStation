# VMStation Sleep/Wake Cycle - Power Management Guide

## Overview

VMStation now implements **true power management** for worker nodes:
- **Sleep Mode**: Worker nodes are actually suspended (low power mode) to save electricity
- **Wake-on-LAN**: Nodes wake automatically when users access services (Samba, Jellyfin, SSH)
- **Smart Triggers**: Only legitimate user access wakes nodes, not internal cluster health checks
- **Auto-Recovery**: Nodes automatically uncordon and rejoin the cluster after wake

## How It Works

### Sleep Sequence

1. **Cordon & Drain**: Worker nodes are cordoned and pods are gracefully drained
2. **Scale Down**: Deployments are scaled to 0 replicas
3. **Suspend**: Worker nodes are put into suspend mode via `systemctl suspend`
4. **State Tracking**: Node state is recorded for wake debugging

### Wake Sequence

1. **Trigger Detection**: Event monitor detects legitimate user access
2. **WoL Packet**: Magic packet sent to wake the suspended node
3. **Wait for Boot**: Monitor waits for node to respond to ping (30-90 seconds)
4. **Service Start**: Wait for Kubernetes services to initialize
5. **Auto-Uncordon**: Node is automatically uncordoned and made schedulable
6. **Activity Update**: Last activity timestamp is updated to prevent immediate re-sleep

## Wake Triggers

The system **ONLY** wakes nodes for these events:

### Storage Node (storagenodet3500)
- **Samba Share Access**: External SMB/CIFS connection attempts (port 445)
- **Jellyfin Access**: External HTTP connections to Jellyfin NodePort (port 30096)
- **SSH Access**: External SSH connection attempts (port 22)

### Homelab Node
- **SSH Access**: External SSH connection attempts (port 22)

### What Does NOT Trigger Wake

✅ **These are filtered out:**
- Masternode health checks (NTP, monitoring scrapes, etc.)
- Inter-node cluster communication (192.168.4.61-63)
- Kubernetes API server polling
- Internal service discovery requests

## Configuration

### Enable Wake-on-LAN in BIOS

**Required for each worker node:**

1. Enter BIOS/UEFI setup (usually DEL, F2, or F12 during boot)
2. Find power management settings
3. Enable options like:
   - "Wake on LAN"
   - "Wake on Magic Packet"
   - "PME Event Wake Up"
4. Save and exit

### Verify WoL Support

On each worker node:

```bash
# Check if network interface supports WoL
sudo ethtool eth0 | grep "Wake-on"

# Should show:
#   Supports Wake-on: pumbg
#   Wake-on: g  (g = magic packet)

# If Wake-on shows 'd' (disabled), enable it:
sudo ethtool -s eth0 wol g

# Make persistent (add to /etc/network/interfaces or similar):
# post-up ethtool -s eth0 wol g
```

### Install Required Tools

**On masternode:**

```bash
# Install WoL sending tool
sudo apt-get install wakeonlan

# Install traffic monitoring tool (for event detection)
sudo apt-get install tcpdump

# Ensure both tools are available
which wakeonlan tcpdump
```

**On worker nodes:**

```bash
# Install ethtool for WoL configuration
sudo apt-get install ethtool
```

## Usage

### Manual Sleep

Trigger cluster sleep manually:

```bash
# On masternode
sudo /usr/local/bin/vmstation-sleep.sh

# This will:
# 1. Cordon and drain worker nodes
# 2. Scale down deployments
# 3. Suspend worker nodes
# 4. Log all actions to /var/log/vmstation-sleep.log
```

### Manual Wake

Wake a specific node:

```bash
# From masternode or any machine on the LAN
wakeonlan b8:ac:6f:7e:6c:9d  # storagenodet3500
wakeonlan d0:94:66:30:d6:63  # homelab

# Or use the event-wake script
sudo /usr/local/bin/vmstation-event-wake.sh
```

### Auto-Sleep Configuration

Auto-sleep remains the same as before:

```bash
# Check auto-sleep timer
systemctl status vmstation-autosleep.timer

# Disable auto-sleep
sudo systemctl stop vmstation-autosleep.timer

# Change threshold (default: 2 hours)
sudo systemctl edit vmstation-autosleep.service
# Add: Environment=VMSTATION_INACTIVITY_THRESHOLD=3600
```

### Event-Based Wake Monitoring

**Start the event-wake monitor:**

```bash
# As systemd service (recommended)
sudo systemctl start vmstation-event-wake.service
sudo systemctl enable vmstation-event-wake.service

# Or manually for testing
sudo /usr/local/bin/vmstation-event-wake.sh
```

**Monitor wake events:**

```bash
# View event-wake log
sudo tail -f /var/log/vmstation-event-wake.log

# You should see:
# [2025-10-11 15:30:45] External Samba access detected from 192.168.4.100
# [2025-10-11 15:30:45] Initiating WOL for storagenodet3500...
# [2025-10-11 15:31:20] SUCCESS: storagenodet3500 is now reachable at 192.168.4.61
# [2025-10-11 15:31:50] SUCCESS: Node storagenodet3500 is now schedulable
```

## Testing

### Run the Sleep/Wake Test

```bash
cd /path/to/VMStation
./tests/test-sleep-wake-cycle.sh
```

**What the test does:**

1. Records initial cluster state
2. Triggers cluster sleep (cordons, drains, suspends)
3. Sends WoL packets to worker nodes
4. Measures actual wake time (expect 30-90 seconds for real hardware)
5. Validates service restoration (kubelet, node-exporter, etc.)
6. Checks nodes are auto-uncordoned
7. Validates monitoring stack

**Expected results:**

- Wake time: 30-90 seconds (actual hardware boot from suspend)
- All services should be active
- Nodes should be uncordoned automatically
- Monitoring stack should be healthy

### Collect Wake Logs for Debugging

```bash
# Run the log collection script
sudo /usr/local/bin/vmstation-collect-wake-logs.sh

# Logs will be saved to:
# /var/log/vmstation-wake-logs/<timestamp>-*/

# View summary
cat /var/log/vmstation-wake-logs/<timestamp>-summary.md
```

**Logs collected:**

- Suspend/resume service logs
- Kernel power management messages
- VMStation syslog entries
- Authentication logs (SSH access)
- Power state information
- WoL configuration
- Network interface details
- Kubelet status

## Troubleshooting

### Node Doesn't Wake

**Check WoL is enabled:**

```bash
# On the node (before putting it to sleep)
sudo ethtool eth0 | grep "Wake-on"
# Should show: Wake-on: g

# If disabled, enable it:
sudo ethtool -s eth0 wol g
```

**Check BIOS settings:**

- Wake on LAN must be enabled in BIOS/UEFI
- Some systems have "Deep Sleep" or "S3/S5" power states - S3 (Suspend to RAM) is required for WoL

**Verify WoL packet is sent:**

```bash
# Check event-wake log
sudo tail /var/log/vmstation-event-wake.log

# Should show:
# WOL packet sent via etherwake on interface eth0 to b8:ac:6f:7e:6c:9d
```

**Test WoL manually:**

```bash
# From masternode, put node to sleep
ssh root@192.168.4.61 "sudo systemctl suspend"

# Wait 10 seconds, then send WoL
sleep 10
wakeonlan b8:ac:6f:7e:6c:9d

# Monitor ping
ping 192.168.4.61
```

### Node Wakes But Stays Cordoned

**Check uncordon in logs:**

```bash
sudo grep -i "uncordon" /var/log/vmstation-event-wake.log

# Should show:
# Uncordoning node: storagenodet3500
# SUCCESS: Node storagenodet3500 is now schedulable
```

**Manual uncordon:**

```bash
kubectl uncordon storagenodet3500
kubectl uncordon homelab
```

### Nodes Wake on Internal Traffic

**Check tcpdump is running:**

```bash
# On masternode
ps aux | grep tcpdump

# Should show multiple tcpdump processes monitoring different ports
```

**Review event-wake script:**

The script filters out internal IPs (192.168.4.61-63) automatically. If nodes are waking too frequently:

```bash
# Check the wake log for source IPs
sudo grep "access detected from" /var/log/vmstation-event-wake.log

# If internal IPs appear, update the script to filter them
```

### Services Don't Start After Wake

**Wait longer:**

Actual hardware wake can take 30-90 seconds. Services need additional time:

```bash
# Wait 2 minutes after wake, then check
sleep 120
ssh root@192.168.4.61 "systemctl status kubelet"
```

**Check node state files:**

```bash
# View node state
cat /var/lib/vmstation/storagenodet3500.state
cat /var/lib/vmstation/homelab.state

# Should show: awake:<timestamp>
```

**Collect diagnostic logs:**

```bash
sudo /usr/local/bin/vmstation-collect-wake-logs.sh
```

## Power Savings

### Estimated Power Consumption

**Active (both nodes running):**
- storagenodet3500: ~150W
- homelab: ~120W
- Total: ~270W

**Suspended (both nodes sleeping):**
- storagenodet3500: ~5-10W
- homelab: ~5-10W
- Total: ~10-20W

**Savings:**
- Per hour: ~250W = 0.25 kWh
- Per day (16h sleep): 4 kWh
- Per month (16h/day): 120 kWh
- Annual (16h/day): 1,460 kWh

**Cost savings** (at $0.12/kWh):
- Per month: $14.40
- Per year: $175.20

## Best Practices

1. **Test WoL before deploying to production**
   - Verify each node can wake from suspend
   - Test wake time is acceptable
   - Ensure services start reliably

2. **Set appropriate sleep threshold**
   - Default 2 hours works for most homelabs
   - Adjust based on usage patterns
   - Monitor logs to see actual usage

3. **Monitor wake events**
   - Review event-wake logs weekly
   - Ensure only legitimate access triggers wake
   - Adjust filters if needed

4. **Keep nodes awake during active hours**
   - Use cron to temporarily disable auto-sleep
   - Or deploy a keepalive pod during business hours

5. **Document your setup**
   - Note BIOS settings for each node
   - Record which services trigger wake
   - Keep track of any customizations

## Integration with Monitoring

### Prometheus Metrics (Future Enhancement)

Create custom metrics for sleep/wake state:

```bash
# Example metric exporter
cat > /usr/local/bin/vmstation-power-metrics.sh <<'EOF'
#!/bin/bash
cat <<METRICS
# HELP vmstation_node_suspended Node is in suspended state
# TYPE vmstation_node_suspended gauge
vmstation_node_suspended{node="storagenodet3500"} $([ -f /var/lib/vmstation/storagenodet3500.state ] && grep -q "suspended" /var/lib/vmstation/storagenodet3500.state && echo 1 || echo 0)
vmstation_node_suspended{node="homelab"} $([ -f /var/lib/vmstation/homelab.state ] && grep -q "suspended" /var/lib/vmstation/homelab.state && echo 1 || echo 0)
METRICS
EOF
```

### Grafana Dashboard

Add panels for:
- Node power state (awake/suspended)
- Wake events per day
- Power savings estimate
- Wake time distribution

## References

- [AUTOSLEEP_RUNBOOK.md](AUTOSLEEP_RUNBOOK.md) - Auto-sleep configuration
- [Wake-on-LAN Wikipedia](https://en.wikipedia.org/wiki/Wake-on-LAN)
- [systemd suspend documentation](https://www.freedesktop.org/software/systemd/man/systemd-suspend.service.html)

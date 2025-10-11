# Sleep/Wake Cycle Fix - Quick Reference

## What Was Fixed

The sleep/wake cycle now **actually works** - nodes are suspended to save power and wake on legitimate user access.

## Key Changes

### 1. ✅ True Hardware Sleep
- Nodes now **actually suspend** (low power mode) instead of just being cordoned
- Uses `systemctl suspend` to put nodes into S3 sleep state
- **Power savings: ~$175/year** (based on 16h/day sleep at $0.12/kWh)

### 2. ✅ Smart Wake Triggers
- **Only wakes on legitimate user access:**
  - Samba share access (port 445)
  - Jellyfin streaming (port 30096)
  - SSH access (port 22)
- **Filters out internal cluster traffic:**
  - NTP checks from masternode
  - Monitoring health checks
  - Inter-node communication

### 3. ✅ Automatic Recovery
- Nodes **automatically uncordon** after wake
- No manual intervention needed
- Services restart and cluster resumes normally

### 4. ✅ Better Debugging
- New log collection tool: `vmstation-collect-wake-logs.sh`
- Comprehensive syslog collection from all nodes
- Detailed wake/suspend events tracking

## How to Use

### Deploy the Changes

```bash
# On masternode
cd /path/to/VMStation

# Deploy updated sleep/wake scripts
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/setup-autosleep.yaml
```

### Enable Wake-on-LAN in BIOS

**Required for each worker node:**
1. Reboot and enter BIOS/UEFI (usually DEL, F2, or F12)
2. Find Power Management settings
3. Enable "Wake on LAN" or "Wake on Magic Packet"
4. Save and exit

### Verify WoL Configuration

```bash
# On each worker node
ssh root@192.168.4.61  # storagenodet3500
sudo ethtool eth0 | grep "Wake-on"
# Should show: Wake-on: g

# If disabled, enable it:
sudo ethtool -s eth0 wol g
```

### Test the Sleep/Wake Cycle

```bash
# On masternode
cd /path/to/VMStation
./tests/test-sleep-wake-cycle.sh
```

**Expected results:**
- Nodes cordon and drain: ✅
- Nodes suspend: ✅
- Wake time: 30-90 seconds (real hardware boot)
- Services start: ✅
- Nodes auto-uncordon: ✅

### Monitor Wake Events

```bash
# View real-time wake events
sudo tail -f /var/log/vmstation-event-wake.log

# You'll see events like:
# [2025-10-11 15:30:45] External Samba access detected from 192.168.4.100
# [2025-10-11 15:30:45] Initiating WOL for storagenodet3500...
# [2025-10-11 15:31:20] SUCCESS: storagenodet3500 is now reachable
# [2025-10-11 15:31:50] SUCCESS: Node storagenodet3500 is now schedulable
```

### Collect Diagnostic Logs

```bash
# If you have wake issues
sudo /usr/local/bin/vmstation-collect-wake-logs.sh

# View the summary
cat /var/log/vmstation-wake-logs/<timestamp>-summary.md
```

## Configuration

### Auto-Sleep Threshold (Default: 2 hours)

```bash
# Change threshold to 1 hour
sudo systemctl edit vmstation-autosleep.service

# Add:
# [Service]
# Environment=VMSTATION_INACTIVITY_THRESHOLD=3600

# Reload
sudo systemctl daemon-reload
sudo systemctl restart vmstation-autosleep.timer
```

### Disable Auto-Sleep

```bash
# Temporary (until reboot)
sudo systemctl stop vmstation-autosleep.timer

# Permanent
sudo systemctl disable vmstation-autosleep.timer
```

## Troubleshooting

### Node Doesn't Wake

**Check WoL is enabled:**
```bash
# On the node
sudo ethtool eth0 | grep "Wake-on"
# Should show: Wake-on: g
```

**Check BIOS settings:**
- Wake on LAN must be enabled
- Some systems need S3 (Suspend to RAM) mode enabled

**Test manually:**
```bash
# From masternode
ssh root@192.168.4.61 "sudo systemctl suspend"
sleep 10
wakeonlan b8:ac:6f:7e:6c:9d
ping 192.168.4.61  # Should respond after 30-90s
```

### Node Wakes on Internal Traffic

**Check the event-wake log:**
```bash
sudo grep "access detected from" /var/log/vmstation-event-wake.log

# Should NOT see 192.168.4.61, 62, or 63 (internal IPs)
# Should only see external IPs triggering wake
```

### Node Stays Cordoned After Wake

**Check uncordon in logs:**
```bash
sudo grep "Uncordoning" /var/log/vmstation-event-wake.log
```

**Manual uncordon:**
```bash
kubectl uncordon storagenodet3500
kubectl uncordon homelab
```

### Services Don't Start

**Wait longer:**
Real hardware needs 30-90 seconds to wake, plus service start time.

```bash
# Wait 2 minutes
sleep 120

# Check services
ssh root@192.168.4.61 "systemctl status kubelet"
```

## Files Changed

- `ansible/playbooks/setup-autosleep.yaml` - Added actual suspend
- `scripts/vmstation-event-wake.sh` - Smart wake triggers + auto-uncordon
- `scripts/vmstation-collect-wake-logs.sh` - NEW: Log collection tool
- `tests/test-sleep-wake-cycle.sh` - Updated for real hardware wake
- `docs/SLEEP_WAKE_POWER_MANAGEMENT.md` - NEW: Complete guide

## Documentation

- **Complete Guide**: `docs/SLEEP_WAKE_POWER_MANAGEMENT.md`
- **Implementation Details**: `SLEEP_WAKE_IMPLEMENTATION_SUMMARY.md`
- **Auto-Sleep Operations**: `docs/AUTOSLEEP_RUNBOOK.md`

## Expected Behavior

### Before (Old)
- ❌ Nodes never actually slept
- ❌ Wake time: 0 seconds (nodes were always on)
- ❌ Nodes stayed cordoned after "wake"
- ❌ Any traffic could trigger wake

### After (New)
- ✅ Nodes actually suspend (low power mode)
- ✅ Wake time: 30-90 seconds (real hardware)
- ✅ Nodes auto-uncordon after wake
- ✅ Only external user access triggers wake
- ✅ Power savings: ~$175/year

## Testing Checklist

- [ ] WoL enabled in BIOS for all worker nodes
- [ ] Network driver supports WoL (`ethtool eth0` shows `Wake-on: g`)
- [ ] Sleep test passes (`./tests/test-sleep-wake-cycle.sh`)
- [ ] Nodes wake in 30-90 seconds
- [ ] Services start after wake
- [ ] Nodes auto-uncordon after wake
- [ ] Only external access triggers wake (check logs)
- [ ] Log collection works (`vmstation-collect-wake-logs.sh`)

## Support

If you encounter issues:

1. **Run unit tests:**
   ```bash
   ./tests/test-sleep-wake-unit.sh
   ```

2. **Collect logs:**
   ```bash
   sudo /usr/local/bin/vmstation-collect-wake-logs.sh
   ```

3. **Review documentation:**
   - `docs/SLEEP_WAKE_POWER_MANAGEMENT.md`
   - `SLEEP_WAKE_IMPLEMENTATION_SUMMARY.md`

4. **Check common issues:**
   - WoL not enabled in BIOS
   - Network driver doesn't support WoL
   - Firewall blocking WoL packets
   - Nodes in wrong sleep state (need S3, not S5)

# Sleep/Wake Cycle Implementation - Changes Summary

## Problem Statement

The original sleep/wake cycle did not work correctly because:

1. **No actual hardware sleep**: The `vmstation-sleep.sh` script only cordoned and drained nodes but didn't actually put machines to sleep/hibernation
2. **Nodes responded in 0 seconds**: Because they were never actually suspended, they responded to ping immediately
3. **No wake discrimination**: The event-wake system didn't filter internal cluster traffic, causing accidental wakes from NTP checks, monitoring scrapes, etc.
4. **Manual uncordon required**: Nodes stayed cordoned after wake, requiring manual intervention
5. **No debugging capability**: No syslog collection to diagnose wake issues

## Solution Implemented

### 1. True Hardware Suspend (`vmstation-sleep.sh`)

**Changes to `ansible/playbooks/setup-autosleep.yaml`:**

- Added node configuration (IPs, MACs, usernames) to the sleep script
- Added state directory (`/var/lib/vmstation`) for tracking node states
- Implemented actual suspend via SSH:
  ```bash
  ssh user@node "logger 'VMStation: Entering suspend mode' && sudo systemctl suspend"
  ```
- Record suspend state to file: `echo "suspended:$(date +%s)" > /var/lib/vmstation/node.state`
- Added per-node suspend logic for storagenodet3500 and homelab

**Result:** Nodes now enter actual suspend mode (S3 sleep state), consuming ~5-10W instead of full power

### 2. Smart Wake Triggers (`vmstation-event-wake.sh`)

**Changes to `scripts/vmstation-event-wake.sh`:**

#### Enhanced wake_node() function:
- Check if node is already awake before sending WoL
- Read and log node state before wake
- Increased timeout to 180s for real hardware wake
- Wait for services to initialize (30s)
- **Auto-uncordon node after wake** ✨
- Update node state file: `echo "awake:$(date +%s)"`
- Update last activity timestamp to prevent immediate re-sleep

#### New uncordon_node() function:
- Checks if kubectl is available
- Verifies node exists in cluster
- Checks if node is cordoned
- Uncordons the node: `kubectl uncordon <node>`
- Logs success/failure

#### Intelligent traffic monitoring:
Replaced simple inotify/netcat with **tcpdump-based filtering**:

```bash
# Monitor NEW connections only (SYN packets without ACK)
tcpdump -i any -n "tcp port $PORT and tcp[tcpflags] & tcp-syn != 0 and tcp[tcpflags] & tcp-ack == 0"

# Filter out internal cluster IPs (192.168.4.61-63)
if [[ "$src_ip" =~ ^192\.168\.4\.(61|62|63)$ ]]; then
  continue  # Ignore internal traffic
fi
```

#### Wake cooldown:
- Track last wake time per node
- Enforce 120s cooldown between wake attempts
- Prevents spam from rapid connection attempts

**Result:** Nodes only wake on legitimate external access:
- ✅ Samba share access (port 445) from external IPs
- ✅ Jellyfin access (port 30096) from external IPs  
- ✅ SSH access (port 22) from external IPs
- ❌ Masternode NTP/monitoring checks (filtered)
- ❌ Inter-node cluster traffic (filtered)

### 3. Syslog Collection (`vmstation-collect-wake-logs.sh`)

**New script: `scripts/vmstation-collect-wake-logs.sh`**

Collects comprehensive diagnostics from all nodes:

**Per-node logs:**
- Suspend/resume service logs (`journalctl -u systemd-suspend.service`)
- Kernel power management messages (`dmesg | grep suspend/resume/wol`)
- VMStation syslog entries (`grep vmstation /var/log/syslog`)
- Authentication logs (SSH access attempts)
- Current power state (`/sys/power/state`)
- WoL configuration (`ethtool eth0 | grep Wake-on`)
- Network interface details
- Kubelet service status

**Masternode logs:**
- Event-wake monitor logs
- Sleep script logs
- Autosleep monitor logs

**Output format:**
```
/var/log/vmstation-wake-logs/
├── 20251011-152000-storagenodet3500/
│   ├── suspend-resume.log
│   ├── kernel-power.log
│   ├── vmstation-syslog.log
│   ├── auth.log
│   ├── power-state.txt
│   ├── wol-config.txt
│   ├── network-interfaces.txt
│   └── summary.txt
├── 20251011-152000-homelab/
│   └── ... (same structure)
├── 20251011-152000-masternode/
│   ├── vmstation-event-wake.log
│   ├── vmstation-sleep.log
│   └── autosleep-monitor.log
└── 20251011-152000-summary.md
```

**Result:** Easy debugging of wake issues with comprehensive log collection

### 4. Updated Test Script (`test-sleep-wake-cycle.sh`)

**Changes to `tests/test-sleep-wake-cycle.sh`:**

#### Enhanced warning message:
```
⚠️  WARNING: This test will:
  1. Cordon and drain worker nodes
  2. Actually SUSPEND worker nodes (low power mode)
  3. Send Wake-on-LAN packets to wake them
  4. Auto-uncordon nodes after successful wake
  5. Measure actual hardware wake time

📝 NOTE: This test requires:
  - Wake-on-LAN enabled in BIOS/UEFI
  - Network interfaces support WoL (check with ethtool)
  - SSH access to all nodes
  - Root/sudo privileges on all nodes
```

#### Realistic wake time expectations:
- Added note: "Actual hardware wake may take 30-90 seconds"
- More informative failure messages if nodes don't wake

#### Uncordon validation:
- Check if nodes are automatically uncordoned after wake
- Report failure if still cordoned with manual fix instructions

#### Better error guidance:
```
Common issues:
  - Nodes didn't wake: Check WoL enabled in BIOS and network driver supports it
  - Services not starting: Nodes may still be booting, wait and check again
  - Nodes still cordoned: Auto-uncordon may have failed, manually uncordon

To collect diagnostic logs:
  sudo /usr/local/bin/vmstation-collect-wake-logs.sh
```

**Result:** Test provides realistic expectations and better troubleshooting guidance

### 5. Comprehensive Documentation

**New document: `docs/SLEEP_WAKE_POWER_MANAGEMENT.md`**

Complete guide covering:
- How the sleep/wake cycle works (detailed sequence diagrams)
- Wake trigger configuration (which events wake which nodes)
- BIOS/UEFI setup for Wake-on-LAN
- Network driver WoL verification (`ethtool`)
- Manual sleep/wake procedures
- Auto-sleep configuration
- Event-based wake monitoring
- Testing procedures
- Troubleshooting common issues
- Power savings calculations (estimated $175/year for 16h/day sleep)
- Best practices and monitoring integration

**Result:** Operators have complete documentation for setup, operation, and troubleshooting

## Technical Details

### Wake-on-LAN Flow

```
[User Access] → [tcpdump detects] → [Filter internal IPs] → [Cooldown check]
     ↓
[Send WoL magic packet] → [Wait for ping response (180s)]
     ↓
[Wait for services (30s)] → [kubectl uncordon node]
     ↓
[Update state file] → [Update last activity] → [Node ready]
```

### State File Format

```bash
# Suspended state
suspended:1728666782  # Unix timestamp

# Awake state  
awake:1728667102      # Unix timestamp
```

### Traffic Filtering

**tcpdump filter breakdown:**
```bash
tcp port $PORT                           # Match port (445, 30096, 22)
and tcp[tcpflags] & tcp-syn != 0        # SYN flag set (new connection)
and tcp[tcpflags] & tcp-ack == 0        # ACK flag not set (not existing connection)
```

**IP filtering:**
```bash
# Extract source IP from tcpdump output
src_ip=$(echo "$line" | grep -oP '\d+\.\d+\.\d+\.\d+(?=\.\d+ >)')

# Filter internal node IPs
if [[ "$src_ip" =~ ^192\.168\.4\.(61|62|63)$ ]]; then
  continue  # Ignore masternode (63), storage (61), homelab (62)
fi
```

## Files Changed

1. **`ansible/playbooks/setup-autosleep.yaml`**
   - Added node configuration variables
   - Implemented actual suspend via SSH
   - Added state tracking

2. **`scripts/vmstation-event-wake.sh`**
   - Enhanced wake_node() with auto-uncordon
   - Added uncordon_node() function
   - Implemented tcpdump-based traffic monitoring
   - Added IP filtering for internal cluster traffic
   - Added wake cooldown mechanism

3. **`tests/test-sleep-wake-cycle.sh`**
   - Updated warnings and requirements
   - Added realistic wake time expectations
   - Added uncordon validation
   - Enhanced error messages and troubleshooting

4. **`scripts/vmstation-collect-wake-logs.sh`** (NEW)
   - Comprehensive syslog collection
   - Per-node diagnostics
   - Markdown summary report

5. **`docs/SLEEP_WAKE_POWER_MANAGEMENT.md`** (NEW)
   - Complete power management guide
   - Setup instructions
   - Troubleshooting procedures
   - Power savings calculations

## Testing Recommendations

### Pre-deployment Testing

1. **Verify WoL in BIOS:**
   ```bash
   # On each worker node
   sudo ethtool eth0 | grep "Wake-on"
   # Should show: Wake-on: g
   ```

2. **Test manual suspend/wake:**
   ```bash
   # Suspend node
   ssh root@192.168.4.61 "sudo systemctl suspend"
   
   # Wait 10 seconds
   sleep 10
   
   # Send WoL
   wakeonlan b8:ac:6f:7e:6c:9d
   
   # Monitor wake
   ping 192.168.4.61
   ```

3. **Run automated test:**
   ```bash
   ./tests/test-sleep-wake-cycle.sh
   ```

4. **Verify auto-uncordon:**
   ```bash
   kubectl get nodes
   # Nodes should NOT show SchedulingDisabled
   ```

5. **Collect and review logs:**
   ```bash
   sudo /usr/local/bin/vmstation-collect-wake-logs.sh
   cat /var/log/vmstation-wake-logs/<timestamp>-summary.md
   ```

### Production Monitoring

1. **Monitor event-wake logs:**
   ```bash
   sudo tail -f /var/log/vmstation-event-wake.log
   ```

2. **Check wake frequency:**
   ```bash
   grep "Initiating WOL" /var/log/vmstation-event-wake.log | wc -l
   ```

3. **Verify no accidental wakes:**
   ```bash
   grep "access detected from 192.168.4.6[123]" /var/log/vmstation-event-wake.log
   # Should return nothing (internal IPs filtered)
   ```

## Expected Behavior Changes

### Before (Old Implementation)

- ✅ Nodes cordoned and drained
- ❌ Nodes stayed powered on (no actual sleep)
- ❌ Wake test showed 0s wake time (nodes were never asleep)
- ❌ Nodes stayed cordoned after "wake"
- ❌ Any traffic could trigger wake attempts
- ❌ No way to debug wake issues

### After (New Implementation)

- ✅ Nodes cordoned and drained
- ✅ **Nodes actually suspend (low power mode)**
- ✅ **Wake test shows 30-90s wake time (realistic)**
- ✅ **Nodes automatically uncordon after wake**
- ✅ **Only legitimate external access triggers wake**
- ✅ **Comprehensive syslog collection for debugging**
- ✅ **Power savings of ~$175/year (16h/day sleep)**

## Breaking Changes

None. The changes are backward compatible:

- Auto-sleep timer/service unchanged
- Manual sleep/wake commands work the same
- API and interfaces remain the same
- Only behavior improvements (actual suspend, auto-uncordon, better filtering)

## Future Enhancements

1. **Prometheus metrics:**
   - Export node power state (awake/suspended)
   - Track wake events per day
   - Calculate real-time power savings

2. **Grafana dashboard:**
   - Visualize sleep/wake patterns
   - Alert on excessive wake frequency
   - Show power consumption estimates

3. **Webhook wake triggers:**
   - Allow wake via HTTP API
   - Integration with home automation
   - Scheduled wake times

4. **Intelligent pre-wake:**
   - Learn usage patterns
   - Pre-wake nodes before expected access
   - Reduce perceived wake latency

## Conclusion

The sleep/wake cycle now implements **true power management** with:

1. ✅ Actual hardware suspend (saving real power)
2. ✅ Intelligent wake triggers (only on legitimate user access)
3. ✅ Automatic recovery (auto-uncordon nodes)
4. ✅ Comprehensive debugging (syslog collection)
5. ✅ Complete documentation (setup and troubleshooting)

**Estimated annual savings:** ~$175 (assumes 16 hours/day sleep at $0.12/kWh)

**User experience:** Transparent - services wake on-demand within 30-90 seconds

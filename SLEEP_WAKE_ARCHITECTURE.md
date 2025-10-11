# Sleep/Wake Architecture and Design Decisions

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Masternode (Always On)                    │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Auto-Sleep Monitor (systemd timer, every 15 min)        │   │
│  │  - Checks for active pods                                 │   │
│  │  - If inactive > 2 hours: triggers vmstation-sleep.sh    │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Event-Wake Monitor (systemd service, always running)    │   │
│  │  - tcpdump monitors: Samba (445), Jellyfin (30096), SSH  │   │
│  │  - Filters internal IPs (192.168.4.61-63)                │   │
│  │  - Sends WoL packets when external access detected       │   │
│  │  - Auto-uncordons nodes after successful wake            │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ WoL Magic Packet
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    Worker Nodes (Can Sleep)                      │
│  ┌──────────────────┐              ┌──────────────────┐         │
│  │ storagenodet3500 │              │     homelab       │         │
│  │  State: AWAKE    │              │  State: SUSPENDED │         │
│  │  Power: ~150W    │              │  Power: ~5-10W    │         │
│  │  Cordoned: No    │              │  Cordoned: Yes    │         │
│  └──────────────────┘              └──────────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

## Design Decisions

### 1. Why `systemctl suspend` Instead of `shutdown`?

**Decision:** Use `systemctl suspend` (S3 sleep state) instead of full shutdown.

**Rationale:**
- **Wake-on-LAN requires suspend mode**: Most hardware only supports WoL from S3 (Suspend to RAM), not S5 (full shutdown)
- **Faster wake time**: Suspend wakes in 30-90 seconds vs. 2-5 minutes for full boot
- **State preservation**: RAM contents preserved, so kernel doesn't need full init
- **Power savings**: S3 still uses only 5-10W vs. 120-150W active

**Alternatives considered:**
- `systemctl hibernate` (S4): Requires swap space >= RAM size, slower wake
- `systemctl poweroff` (S5): Most hardware can't WoL from S5, requires full boot
- `shutdown -h now`: Same as poweroff, not WoL compatible

### 2. Why tcpdump Instead of iptables/netfilter?

**Decision:** Use tcpdump to monitor network traffic for wake triggers.

**Rationale:**
- **Read-only monitoring**: Doesn't interfere with existing firewall rules
- **Flexible filtering**: Can filter by source IP, flags, ports easily
- **SYN packet detection**: Accurately detects NEW connections (SYN without ACK)
- **No kernel module required**: Works on any Linux system with tcpdump

**Alternatives considered:**
- `iptables` with logging: Requires root, modifies firewall, harder to parse logs
- `inotifywait` for Samba: Only works for local filesystem access, not SMB protocol
- `netcat -l`: Blocks the port, prevents actual service from running
- BPF/XDP: Too complex, requires kernel 4.18+, harder to maintain

### 3. Why Filter Internal IPs (192.168.4.61-63)?

**Decision:** Explicitly filter out masternode and worker node IPs from wake triggers.

**Rationale:**
- **Prevent NTP wake spam**: Masternode runs chrony, frequently checks worker nodes
- **Prevent monitoring wake spam**: Prometheus scrapes node-exporter every 15s
- **Prevent cluster wake loops**: Kubelet API checks would constantly wake nodes
- **User intent**: Only external user access should wake nodes, not internal health checks

**Implementation:**
```bash
if [[ "$src_ip" =~ ^192\.168\.4\.(61|62|63)$ ]]; then
  continue  # Ignore internal cluster traffic
fi
```

**Alternatives considered:**
- Whitelist external IPs only: Harder to maintain, changes with users
- Use firewall zones: Requires firewall reconfiguration
- Port-based filtering: Doesn't distinguish internal vs. external on same port

### 4. Why Auto-Uncordon After Wake?

**Decision:** Automatically uncordon nodes after successful wake and service start.

**Rationale:**
- **Reduce operator burden**: No manual intervention needed
- **Faster service restoration**: Pods can be scheduled immediately
- **Better user experience**: Services available within 2 minutes of wake
- **Consistency**: Wake should fully restore node, not leave it half-broken

**Safety measures:**
- Wait for ping response before uncordoning
- Wait 30 seconds for services to initialize
- Log uncordon success/failure
- Manual uncordon still possible if auto-uncordon fails

**Alternatives considered:**
- Require manual uncordon: Too much operator burden, defeats automation
- Uncordon immediately after WoL: Node might not be ready, pods could fail
- Never cordoned in first place: Defeats power savings, pods would fail on suspended nodes

### 5. Why 120-Second Wake Cooldown?

**Decision:** Enforce 120-second cooldown between wake attempts for the same node.

**Rationale:**
- **Prevent WoL spam**: Rapid connection attempts shouldn't spam wake packets
- **Hardware protection**: Some NICs rate-limit WoL packet processing
- **Power efficiency**: Avoid wake/sleep thrashing
- **Realistic expectations**: Real hardware needs 30-90s to wake anyway

**Implementation:**
```bash
declare -A LAST_WAKE_TIME
LAST_WAKE_TIME["storage"]=0
LAST_WAKE_TIME["homelab"]=0

should_wake() {
  local elapsed=$(($(date +%s) - ${LAST_WAKE_TIME[$node_type]}))
  [[ $elapsed -ge $WAKE_COOLDOWN ]]  # 120 seconds
}
```

**Alternatives considered:**
- No cooldown: Would spam WoL packets, no benefit
- Longer cooldown (5+ minutes): Would delay legitimate wake attempts
- Per-service cooldown: More complex, not necessary

### 6. Why State Files in `/var/lib/vmstation/`?

**Decision:** Track node state (suspended/awake) in persistent files.

**Rationale:**
- **Survives crashes**: Systemd service restart doesn't lose state
- **Debugging**: Operators can see last state transition
- **Auditing**: Timestamp of last suspend/wake
- **State recovery**: Can detect if node crashed during suspend

**Format:**
```bash
echo "suspended:$(date +%s)" > /var/lib/vmstation/storagenodet3500.state
echo "awake:$(date +%s)" > /var/lib/vmstation/storagenodet3500.state
```

**Alternatives considered:**
- In-memory only: Lost on service restart
- Database (etcd/Redis): Overkill, adds dependency
- Kubernetes ConfigMap: Requires API access, more complex
- Syslog only: Harder to parse, no structured state

### 7. Why Not Use Kubernetes DaemonSet for Event-Wake?

**Decision:** Run event-wake monitor as systemd service on masternode only.

**Rationale:**
- **Masternode always on**: Can't monitor for wake if the monitor is asleep
- **Requires tcpdump**: Needs host network access, privileged mode
- **Requires WoL tools**: Needs raw socket access
- **Simpler deployment**: No Kubernetes YAML, just systemd unit

**Alternatives considered:**
- DaemonSet with `hostNetwork: true`: Possible but complex
- Pod on masternode: Adds K8s dependency, harder to debug
- External monitoring service: Requires separate infrastructure

### 8. Why Separate Scripts for Sleep and Wake?

**Decision:** Separate `vmstation-sleep.sh` and `vmstation-event-wake.sh`.

**Rationale:**
- **Different triggers**: Sleep is timer-based, wake is event-based
- **Different lifecycles**: Sleep runs once and exits, wake runs continuously
- **Easier testing**: Can test sleep without running wake monitor
- **Better maintainability**: Single responsibility principle

**Alternatives considered:**
- Single monolithic script: Harder to test, more complex control flow
- Built into monitoring stack: Adds dependency, harder to disable

## Security Considerations

### 1. WoL Magic Packet Security

**Risk:** WoL packets are unauthenticated - anyone can wake nodes.

**Mitigation:**
- Wake-on-event monitor only on private LAN (192.168.4.0/24)
- No WoL port forwarding from internet
- Firewall blocks WoL from outside network
- Physical network access required

**Future enhancement:** SecureOn password in WoL packets (ethtool -s eth0 wol s)

### 2. SSH Command Execution

**Risk:** Sleep script executes `ssh user@node "systemctl suspend"` - could be exploited.

**Mitigation:**
- SSH keys with no password (passphrase optional)
- Known hosts validation
- SSH config: `StrictHostKeyChecking=yes`
- User has sudo for systemctl suspend only (sudoers configuration)

**Example sudoers entry:**
```
vmstation-sleep ALL=(ALL) NOPASSWD: /usr/bin/systemctl suspend
```

### 3. Privilege Escalation

**Risk:** Event-wake monitor runs as root (needs tcpdump raw sockets).

**Mitigation:**
- Systemd service runs with `ProtectHome=yes`
- `ProtectSystem=strict`
- `PrivateTmp=yes`
- Minimal capabilities: `CAP_NET_RAW`, `CAP_NET_ADMIN`

**Example systemd hardening:**
```ini
[Service]
User=root
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
ProtectHome=yes
ProtectSystem=strict
PrivateTmp=yes
```

### 4. Log Injection

**Risk:** User-controlled IPs in logs could inject malicious content.

**Mitigation:**
- IP address extraction via regex (validates format)
- No user input directly in logs
- Log rotation configured (logrotate)

## Performance Considerations

### 1. tcpdump CPU Usage

**Impact:** Running multiple tcpdump processes (Samba, Jellyfin, SSH monitoring).

**Measurement:**
- Each tcpdump: ~0.5-1% CPU on idle
- Total: ~2-3% CPU on masternode
- Acceptable on control plane node

**Optimization:**
- BPF filters reduce packet processing
- `tcp[tcpflags]` filter applied in kernel
- Only SYN packets processed, not all traffic

### 2. Wake Latency

**Measurement:**
- WoL packet transmission: <1ms
- Hardware wake from S3: 30-90 seconds
- Service initialization: 10-30 seconds
- Total user-perceived latency: 40-120 seconds

**Optimization:**
- Can't reduce hardware wake time (BIOS-dependent)
- Could pre-wake on schedule (future enhancement)
- Could keep "hot" nodes in lower sleep state

### 3. Disk I/O for State Files

**Impact:** Writing state files on every wake/sleep.

**Measurement:**
- State file writes: 2 per wake/sleep cycle
- File size: ~30 bytes
- Impact: Negligible (<1 write/minute worst case)

## Scalability

### Current Design (3 nodes)

- Masternode: Always on
- 2 worker nodes: Can sleep
- Manual node configuration in scripts

### Future Scaling (10+ nodes)

**Changes needed:**

1. **Dynamic node discovery:**
   ```bash
   NODES=$(kubectl get nodes -l vmstation.io/can-sleep=true -o name)
   ```

2. **Node group configuration:**
   ```yaml
   sleep_groups:
     - name: storage
       nodes: [storagenodet3500, storage2, storage3]
       wake_triggers: [samba, jellyfin]
     - name: compute
       nodes: [homelab, compute2]
       wake_triggers: [ssh, http]
   ```

3. **Distributed wake monitoring:**
   - Multiple event-wake instances
   - Load balancing across control plane
   - HA for wake service

## Testing Strategy

### Unit Tests (`test-sleep-wake-unit.sh`)

**Coverage:**
- Script syntax validation
- Key functions present (uncordon_node, wake_node)
- Configuration variables defined
- State tracking implemented

**Limitations:**
- Doesn't test actual hardware sleep/wake
- Doesn't test network traffic filtering
- Doesn't test WoL packet transmission

### Integration Tests (`test-sleep-wake-cycle.sh`)

**Coverage:**
- End-to-end sleep/wake cycle
- Actual node suspension and wake
- Service restoration validation
- Node uncordon verification

**Limitations:**
- Requires actual hardware
- Disruptive (suspends nodes)
- Can't run in CI/CD

### Manual Testing

**Required tests:**
1. WoL from BIOS (verify hardware support)
2. Wake on each trigger (Samba, Jellyfin, SSH)
3. Internal traffic filtering (NTP, monitoring shouldn't wake)
4. Wake time measurement
5. Power consumption measurement

## Monitoring and Observability

### Current Logging

- **Event-wake log:** `/var/log/vmstation-event-wake.log`
  - Wake triggers
  - WoL packet transmission
  - Node wake time
  - Uncordon success/failure

- **Sleep log:** `/var/log/vmstation-sleep.log`
  - Suspend trigger
  - Cordon/drain actions
  - Suspend execution

- **Syslog collection:** `vmstation-collect-wake-logs.sh`
  - Suspend/resume service logs
  - Kernel power management
  - Authentication logs
  - WoL configuration

### Future Prometheus Metrics

```promql
# Node power state
vmstation_node_suspended{node="storagenodet3500"} 1

# Wake events per hour
rate(vmstation_wake_events_total[1h])

# Average wake time
vmstation_wake_duration_seconds{node="storagenodet3500"}

# Power savings estimate (watts)
vmstation_power_savings_watts 250
```

### Alerting Rules

```yaml
# Node won't wake
- alert: NodeWakeFailed
  expr: vmstation_wake_duration_seconds > 180
  for: 5m
  
# Excessive wake frequency
- alert: ExcessiveWakeEvents
  expr: rate(vmstation_wake_events_total[1h]) > 10
  for: 15m
  
# Node stuck suspended
- alert: NodeStuckSuspended
  expr: vmstation_node_suspended == 1 and vmstation_last_wake_attempt_timestamp < (time() - 300)
  for: 10m
```

## Future Enhancements

### 1. Machine Learning Wake Prediction

Learn usage patterns and pre-wake nodes:
```python
# Predict wake at 9 AM weekdays
if day_of_week <= 5 and hour == 8 and minute == 45:
    wake_node("storagenodet3500")  # Pre-wake 15 min early
```

### 2. Graduated Sleep States

Different sleep depths based on wake probability:
- **S1 (CPU stop)**: 1-2s wake, for low-latency services
- **S3 (RAM only)**: 30-90s wake, for general use
- **S4 (hibernate)**: 2-5min wake, for rarely-used nodes

### 3. Wake API

HTTP endpoint for programmatic wake:
```bash
curl -X POST http://masternode/api/wake/storagenodet3500
```

Integration with:
- Home automation (Home Assistant, etc.)
- Scheduled tasks (cron wake for backups)
- External monitoring (wake if metrics unavailable)

### 4. Power Consumption Tracking

Real-time power monitoring:
- IPMI/iDRAC power readings
- Smart PDU integration
- Calculate actual savings vs. estimates

## Conclusion

This architecture implements **true power management** while maintaining:
- ✅ **Reliability**: Nodes wake on demand
- ✅ **Security**: No external wake capability
- ✅ **Performance**: <2 minute wake latency
- ✅ **Maintainability**: Simple scripts, clear logs
- ✅ **Cost savings**: ~$175/year at $0.12/kWh

The design balances **power efficiency** with **user experience**, ensuring services are available when needed while minimizing energy consumption when idle.

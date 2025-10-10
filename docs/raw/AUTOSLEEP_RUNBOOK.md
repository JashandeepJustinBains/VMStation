# VMStation Auto-Sleep/Wake Operational Runbook

This document provides operational procedures for managing the VMStation auto-sleep and wake functionality.

## Overview

VMStation includes automated power management features:
- **Auto-Sleep**: Automatically cordons, drains, and scales down workloads after inactivity
- **Event-Wake**: Wakes the cluster on demand via events or scheduled tasks

## Auto-Sleep Configuration

### Installation

Deploy auto-sleep monitoring:
```bash
./deploy.sh setup
```

Or manually:
```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/setup-autosleep.yaml
```

### Configuration

Auto-sleep is configured via systemd environment variables.

**Default Configuration**:
- Inactivity threshold: 7200 seconds (2 hours)
- Check interval: 15 minutes
- Target: Non-system pods (excludes kube-system, kube-flannel, monitoring)

**Customizing Inactivity Threshold**:

Edit `/etc/systemd/system/vmstation-autosleep.service`:
```ini
[Service]
# Change from 7200 (2 hours) to 3600 (1 hour)
Environment=VMSTATION_INACTIVITY_THRESHOLD=3600
```

Apply changes:
```bash
sudo systemctl daemon-reload
sudo systemctl restart vmstation-autosleep.timer
```

**Customizing Check Interval**:

Edit `/etc/systemd/system/vmstation-autosleep.timer`:
```ini
[Timer]
# Change from 15 minutes to 10 minutes
OnUnitActiveSec=10min
```

Apply changes:
```bash
sudo systemctl daemon-reload
sudo systemctl restart vmstation-autosleep.timer
```

### Monitoring Auto-Sleep

**Check status**:
```bash
# Timer status
systemctl status vmstation-autosleep.timer

# Service status (last run)
systemctl status vmstation-autosleep.service

# View logs
journalctl -u vmstation-autosleep -f

# View dedicated log file
tail -f /var/log/vmstation-autosleep.log
```

**View last activity timestamp**:
```bash
cat /var/lib/vmstation/last-activity
# Output: Unix timestamp (e.g., 1704067200)

# Convert to human-readable
date -d @$(cat /var/lib/vmstation/last-activity)
```

**Calculate time until sleep**:
```bash
#!/bin/bash
THRESHOLD=7200  # 2 hours
LAST_ACTIVITY=$(cat /var/lib/vmstation/last-activity)
CURRENT_TIME=$(date +%s)
INACTIVE_DURATION=$((CURRENT_TIME - LAST_ACTIVITY))
REMAINING=$((THRESHOLD - INACTIVE_DURATION))

if [[ $REMAINING -gt 0 ]]; then
  echo "Time until sleep: $((REMAINING / 60)) minutes"
else
  echo "Sleep threshold reached"
fi
```

### Disabling Auto-Sleep

**Temporary disable** (until next boot):
```bash
sudo systemctl stop vmstation-autosleep.timer
```

**Permanent disable**:
```bash
sudo systemctl stop vmstation-autosleep.timer
sudo systemctl disable vmstation-autosleep.timer
```

**Re-enable**:
```bash
sudo systemctl enable vmstation-autosleep.timer
sudo systemctl start vmstation-autosleep.timer
```

### Preventing Auto-Sleep

**Method 1: Deploy a dummy pod**
```bash
kubectl run keepalive \
  --image=busybox \
  --restart=Never \
  -- sleep 86400
```

This creates activity that prevents auto-sleep.

**Method 2: Update last activity timestamp**
```bash
sudo date +%s > /var/lib/vmstation/last-activity
```

Resets the inactivity timer.

## Manual Sleep Operations

### Manual Cluster Sleep

Trigger sleep manually:
```bash
sudo /usr/local/bin/vmstation-sleep.sh
```

This will:
1. Cordon all worker nodes
2. Drain all worker nodes
3. Scale deployments to 0 replicas
4. Log all operations

**What is NOT affected**:
- Control plane pods
- System pods (kube-system, kube-flannel)
- Monitoring stack
- DaemonSets

### Waking the Cluster

**Option 1: Deploy workloads**
```bash
# Uncordon nodes
kubectl uncordon <node-name>

# Deploy workload
kubectl apply -f your-app.yaml
```

**Option 2: Scale up existing deployments**
```bash
# List deployments
kubectl get deployments -A

# Scale up
kubectl scale deployment <name> --replicas=<desired> -n <namespace>
```

**Option 3: Reset activity timestamp**
```bash
sudo date +%s > /var/lib/vmstation/last-activity
```

## Event-Based Wake

### Setup Wake-on-Event

Deploy event wake monitoring:
```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/deploy-event-wake.yaml
```

### Wake Events

The system can wake on:
1. **Scheduled events**: Cron-based wake times
2. **External triggers**: API calls, webhooks
3. **Resource requests**: Incoming traffic, job queue

### Configuration Files

**Wake Script**: `/usr/local/bin/vmstation-event-wake.sh`
**Systemd Service**: `/etc/systemd/system/vmstation-event-wake.service`
**Systemd Timer**: `/etc/systemd/system/vmstation-event-wake.timer`

## Troubleshooting

### Auto-Sleep Not Working

**Check 1: Timer is running**
```bash
systemctl status vmstation-autosleep.timer
systemctl list-timers vmstation-autosleep.timer
```

**Check 2: Service can run**
```bash
# Manually trigger
sudo systemctl start vmstation-autosleep.service

# Check logs
journalctl -u vmstation-autosleep -n 50
```

**Check 3: kubectl is accessible**
```bash
# Test kubectl
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get nodes
```

**Check 4: Script has correct permissions**
```bash
ls -la /usr/local/bin/vmstation-autosleep-monitor.sh
# Should be: -rwxr-xr-x (755)

ls -la /usr/local/bin/vmstation-sleep.sh
# Should be: -rwxr-xr-x (755)
```

### Cluster Slept Unexpectedly

**Diagnose**:
```bash
# Check logs for when sleep was triggered
grep "Inactivity threshold reached" /var/log/vmstation-autosleep.log

# Check last activity time
cat /var/lib/vmstation/last-activity
date -d @$(cat /var/lib/vmstation/last-activity)

# Check for running pods at time of sleep
kubectl get pods -A --field-selector=status.phase=Running
```

**Recovery**:
```bash
# Uncordon all nodes
kubectl get nodes -o name | xargs -I {} kubectl uncordon {}

# Scale up deployments
kubectl scale deployment --all --replicas=1 -n default
```

### Sleep Script Hangs

**Symptoms**:
- Sleep process doesn't complete
- Nodes stuck in "SchedulingDisabled" state

**Recovery**:
```bash
# Force uncordon all nodes
for node in $(kubectl get nodes -o name); do
  kubectl uncordon $node --timeout=10s || true
done

# Check for stuck pods
kubectl get pods -A | grep -E "(Terminating|Unknown)"

# Force delete stuck pods
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0
```

### Logs Not Appearing

**Check log directory**:
```bash
ls -la /var/log/vmstation-*.log

# Check permissions
ls -la /var/log/ | grep vmstation
```

**Create log directory if missing**:
```bash
sudo mkdir -p /var/log
sudo touch /var/log/vmstation-autosleep.log
sudo chmod 644 /var/log/vmstation-autosleep.log
```

**Check journald**:
```bash
# All vmstation logs
journalctl -t vmstation-autosleep -f

# Logs with timestamps
journalctl -u vmstation-autosleep.service --since "1 hour ago"
```

## Operational Procedures

### Daily Operations

**Morning**: Check cluster status
```bash
# Verify nodes are ready
kubectl get nodes

# Check recent sleep/wake events
journalctl -u vmstation-autosleep --since "24 hours ago"

# Verify auto-sleep is enabled
systemctl status vmstation-autosleep.timer
```

**Evening**: Review activity
```bash
# Check if cluster will sleep tonight
cat /var/lib/vmstation/last-activity
# Calculate remaining time (see script above)

# Check for running workloads
kubectl get pods -A --field-selector=status.phase=Running
```

### Weekly Maintenance

**Review logs**:
```bash
# Check for errors
journalctl -u vmstation-autosleep --since "7 days ago" | grep ERROR

# Count sleep events
grep "Inactivity threshold reached" /var/log/vmstation-autosleep.log | wc -l
```

**Verify configuration**:
```bash
# Check threshold
systemctl cat vmstation-autosleep.service | grep INACTIVITY_THRESHOLD

# Check interval
systemctl cat vmstation-autosleep.timer | grep OnUnitActiveSec
```

### Changing Behavior

**Disable for maintenance window**:
```bash
# Stop auto-sleep
sudo systemctl stop vmstation-autosleep.timer

# Perform maintenance
# ...

# Re-enable auto-sleep
sudo systemctl start vmstation-autosleep.timer
```

**Temporary threshold change**:
```bash
# Stop timer
sudo systemctl stop vmstation-autosleep.timer

# Edit service file
sudo systemctl edit vmstation-autosleep.service
# Add:
# [Service]
# Environment=VMSTATION_INACTIVITY_THRESHOLD=14400

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl start vmstation-autosleep.timer
```

## Integration with Monitoring

### Prometheus Metrics

Auto-sleep can be monitored via Prometheus by exposing metrics:

**Example metric exporter** (future enhancement):
```bash
#!/bin/bash
# /usr/local/bin/vmstation-metrics-exporter.sh

LAST_ACTIVITY=$(cat /var/lib/vmstation/last-activity 2>/dev/null || echo 0)
CURRENT_TIME=$(date +%s)
INACTIVE_DURATION=$((CURRENT_TIME - LAST_ACTIVITY))

cat <<EOF
# HELP vmstation_last_activity_timestamp Unix timestamp of last cluster activity
# TYPE vmstation_last_activity_timestamp gauge
vmstation_last_activity_timestamp $LAST_ACTIVITY

# HELP vmstation_inactive_duration_seconds Seconds since last activity
# TYPE vmstation_inactive_duration_seconds gauge
vmstation_inactive_duration_seconds $INACTIVE_DURATION
EOF
```

### Alerting

**Example alert rules** (future enhancement):
```yaml
groups:
- name: vmstation-autosleep
  rules:
  - alert: ClusterInactiveLongTime
    expr: vmstation_inactive_duration_seconds > 5400
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Cluster inactive for {{ $value }} seconds"
      description: "Cluster will sleep in {{ sub 7200 $value }} seconds"
```

## Best Practices

1. **Set appropriate thresholds**
   - Consider your workload patterns
   - Allow enough time for scheduled jobs
   - Account for deployment times

2. **Monitor logs regularly**
   - Review auto-sleep events
   - Verify expected behavior
   - Catch issues early

3. **Test sleep/wake cycle**
   - Verify recovery procedures
   - Document any manual steps needed
   - Test during low-usage periods

4. **Document customizations**
   - Track threshold changes
   - Note any special configurations
   - Keep runbook updated

5. **Plan for exceptions**
   - Critical workloads (disable auto-sleep)
   - Maintenance windows (temporary disable)
   - Special events (adjust threshold)

## References

- [setup-autosleep.yaml](../ansible/playbooks/setup-autosleep.yaml) - Installation playbook
- [MONITORING_ACCESS.md](MONITORING_ACCESS.md) - Monitoring endpoints
- [BEST_PRACTICES.md](BEST_PRACTICES.md) - General best practices

# VMStation Auto-Sleep/Wake and Monitoring Validation Guide

This document describes the comprehensive test suite for validating VMStation's auto-sleep/wake functionality and monitoring stack health.

## Overview

The VMStation validation suite tests the complete lifecycle of cluster sleep/wake operations and ensures all monitoring components are functioning correctly.

## Test Suite Components

### 1. Auto-Sleep/Wake Configuration Validation

**Test**: `test-autosleep-wake-validation.sh`

**Purpose**: Validates that auto-sleep and wake-on-LAN are properly configured on both worker nodes.

**Tests Performed**:
- ✓ Systemd timer enabled on storagenodet3500 (Debian/kubeadm)
- ✓ Systemd timer enabled on homelab (RHEL10/RKE2)
- ✓ Auto-sleep monitor script deployed and executable
- ✓ Cluster sleep script deployed and executable
- ✓ Wake-on-LAN script and systemd service configured
- ✓ kubectl access from control plane
- ✓ WoL tool availability (wakeonlan/etherwake/ether-wake)
- ✓ Node reachability (ping test)
- ✓ Monitoring services running
- ✓ Log files and state directories created
- ✓ Systemd timer schedules verified

**Usage**:
```bash
./tests/test-autosleep-wake-validation.sh
```

**Example Output**:
```
=========================================
VMStation Auto-Sleep/Wake Validation
Testing sleep/wake cycle and monitoring
=========================================

[1/10] Testing systemd timer on storagenodet3500...
✅ PASS: Auto-sleep timer is enabled on storagenodet3500
✅ PASS: Auto-sleep timer is active on storagenodet3500

[2/10] Testing systemd timer on homelab (RHEL10)...
✅ PASS: Auto-sleep timer is enabled on homelab
✅ PASS: Auto-sleep timer is active on homelab

...

=========================================
Test Results Summary
=========================================
Passed:   15
Failed:   0
Warnings: 0

✅ All critical tests passed!
```

### 2. Monitoring Exporters Health Validation

**Test**: `test-monitoring-exporters-health.sh`

**Purpose**: Validates all monitoring exporters, Prometheus targets, and dashboard metrics.

**Tests Performed**:
- ✓ Prometheus targets health (identifies DOWN targets)
- ✓ Node exporter health on all nodes
- ✓ IPMI exporter health and credentials
- ✓ Dashboard metric validation (ensures metrics are updating, not stuck at zero)
- ✓ Grafana dashboards availability
- ✓ Loki log aggregation health
- ✓ Promtail log shipper status
- ✓ Service connectivity with concise curl output

**Usage**:
```bash
./tests/test-monitoring-exporters-health.sh
```

**Concise Output Format**:
```
curl http://192.168.4.63:30090/-/healthy ok
curl http://192.168.4.63:30300/api/health ok
curl http://192.168.4.63:9100/metrics ok
```

**Troubleshooting DOWN Targets**:

If targets show as DOWN:
1. Check service status: `systemctl status node_exporter`
2. Verify firewall: `iptables -L -n | grep 9100`
3. Test connectivity: `curl http://node-ip:9100/metrics`
4. Check Prometheus config: `kubectl logs -n monitoring prometheus-xxx`
5. For IPMI exporter: Verify credentials with `kubectl get secret ipmi-credentials -n monitoring`

### 3. Loki Log Aggregation Validation

**Test**: `test-loki-validation.sh`

**Purpose**: Validates Loki connectivity, log ingestion, and query functionality.

**Tests Performed**:
- ✓ Loki pod status
- ✓ Loki service configuration and endpoints
- ✓ Loki API connectivity
- ✓ Promtail log shipper status
- ✓ Loki DNS resolution
- ✓ Loki datasource health in Grafana

**Usage**:
```bash
./tests/test-loki-validation.sh
```

**Common Loki Issues**:

| Issue | Cause | Fix |
|-------|-------|-----|
| DNS lookup failures | CoreDNS not working | `kubectl logs -n kube-system coredns-xxx` |
| 500 status errors | Loki internal error | `kubectl logs -n monitoring loki-xxx` |
| No logs appearing | Promtail not running | `kubectl get pods -n monitoring | grep promtail` |
| Connection refused | Service not exposed | `kubectl get svc -n monitoring loki` |

### 4. Sleep/Wake Cycle Test (Destructive)

**Test**: `test-sleep-wake-cycle.sh`

**Purpose**: Automated end-to-end test of the complete sleep/wake cycle.

⚠️ **WARNING**: This is a destructive test that will temporarily disrupt the cluster.

**Tests Performed**:
1. ✓ Records initial cluster state
2. ✓ Triggers cluster sleep (cordons/drains worker nodes)
3. ✓ Verifies nodes are cordoned
4. ✓ Sends Wake-on-LAN packets to both worker nodes
5. ✓ Measures wake time for each node
6. ✓ Validates service restoration (kubelet, rke2, node-exporter)
7. ✓ Validates monitoring stack availability after wake

**Usage**:
```bash
./tests/test-sleep-wake-cycle.sh
```

**Expected Wake Times**:
- storagenodet3500 (Debian): 30-60 seconds
- homelab (RHEL10): 45-90 seconds

**Post-Test Actions**:
```bash
# Uncordon nodes to allow scheduling
kubectl uncordon storagenodet3500
kubectl uncordon homelab

# Verify pods are rescheduled
kubectl get pods -A

# Check monitoring dashboards
open http://192.168.4.63:30300
```

### 5. Complete Validation Suite

**Test**: `test-complete-validation.sh`

**Purpose**: Master test suite that runs all validation tests in sequence.

**Test Phases**:
1. **Phase 1**: Configuration validation (non-destructive)
   - Auto-sleep/wake configuration
2. **Phase 2**: Monitoring health validation (non-destructive)
   - Monitoring exporters health
   - Loki log aggregation
   - Monitoring access
3. **Phase 3**: Sleep/wake cycle (optional, requires confirmation)

**Usage**:
```bash
./tests/test-complete-validation.sh
```

**Features**:
- Color-coded output for easy reading
- Suite-level pass/fail tracking
- Optional destructive tests with user confirmation
- Comprehensive summary report

## Running Tests

### Quick Start

```bash
# Run configuration validation only (safe)
./tests/test-autosleep-wake-validation.sh
./tests/test-monitoring-exporters-health.sh
./tests/test-loki-validation.sh

# Run complete suite (includes optional destructive test)
./tests/test-complete-validation.sh
```

### CI/CD Integration

For automated CI/CD pipelines, run non-destructive tests only:

```bash
# Safe for CI/CD
./tests/test-autosleep-wake-validation.sh
./tests/test-monitoring-exporters-health.sh
./tests/test-loki-validation.sh
./tests/test-monitoring-access.sh
```

### Manual Sleep/Wake Testing

For manual testing of the sleep/wake cycle:

```bash
# 1. Trigger sleep
ssh root@192.168.4.63 'sudo /usr/local/bin/vmstation-sleep.sh'

# 2. Check node status (should show SchedulingDisabled)
kubectl get nodes

# 3. Send WoL packets
wakeonlan b8:ac:6f:7e:6c:9d  # storagenodet3500
wakeonlan d0:94:66:30:d6:63  # homelab

# 4. Monitor wake progress
watch kubectl get nodes

# 5. Uncordon nodes after wake
kubectl uncordon storagenodet3500
kubectl uncordon homelab

# 6. Validate services
./tests/test-monitoring-exporters-health.sh
```

## Interpreting Results

### Success Criteria

✅ **All tests passed** means:
- Auto-sleep timers are configured on both nodes
- WoL is ready to wake nodes
- All Prometheus targets are UP
- All exporters are healthy
- Dashboard metrics are updating
- Loki is ingesting logs
- Sleep/wake cycle completes successfully

### Common Issues and Fixes

#### Auto-Sleep Not Working

```bash
# Check timer status
systemctl status vmstation-autosleep.timer

# Check logs
journalctl -u vmstation-autosleep -n 50

# Manually trigger to test
sudo systemctl start vmstation-autosleep.service
```

#### Nodes Not Waking

```bash
# Verify WoL is enabled on NIC
ssh root@node "ethtool eth0 | grep Wake-on"

# Should show "Wake-on: g"
# If not, enable it:
ssh root@node "ethtool -s eth0 wol g"
```

#### Exporters DOWN

```bash
# Restart the exporter
systemctl restart node_exporter

# Check if port is open
netstat -tulpn | grep 9100

# Test from Prometheus host
curl http://node-ip:9100/metrics
```

#### Loki Connectivity Errors

```bash
# Check Loki pod logs
kubectl logs -n monitoring -l app=loki

# Verify DNS
kubectl run -it --rm dns-test --image=busybox --restart=Never -- nslookup loki.monitoring

# Check service endpoints
kubectl get endpoints -n monitoring loki
```

## Monitoring Dashboards

After validation, access these dashboards to view metrics:

- **Grafana**: http://192.168.4.63:30300
- **Prometheus**: http://192.168.4.63:30090
- **Node Metrics**: http://192.168.4.63:9100/metrics

### Expected Dashboards

1. **VMStation Dashboard**: Overall cluster health
2. **IPMI Hardware Monitoring**: Enterprise server hardware metrics
3. **Loki Logs & Aggregation**: Log queries and aggregation
4. **Node Metrics**: Per-node resource usage
5. **Cluster Overview**: Kubernetes cluster status
6. **Prometheus Metrics & Health**: Prometheus internal metrics

### Verifying Dashboard Metrics

To ensure dashboards are working:

1. Open Grafana
2. Navigate to each dashboard
3. Verify graphs are showing data (not flat at zero)
4. Check time range is set correctly
5. Verify datasources are healthy (Settings → Data Sources)

## Automation

### Scheduled Validation

Add to crontab for regular validation:

```cron
# Run validation every day at 2 AM
0 2 * * * /home/runner/work/VMStation/VMStation/tests/test-complete-validation.sh 2>&1 | tee /var/log/vmstation-validation.log
```

### Pre-Deployment Validation

Before deploying changes:

```bash
# 1. Run all non-destructive tests
./tests/test-autosleep-wake-validation.sh
./tests/test-monitoring-exporters-health.sh

# 2. Deploy changes
./deploy.sh debian

# 3. Re-run validation
./tests/test-complete-validation.sh
```

## Troubleshooting Guide

### No WoL Tool Available

```bash
# Install wakeonlan
apt-get install wakeonlan  # Debian/Ubuntu
yum install wakeonlan      # RHEL/CentOS
```

### kubectl Access Denied

```bash
# Ensure KUBECONFIG is set
export KUBECONFIG=/etc/kubernetes/admin.conf

# Verify access
kubectl get nodes
```

### Monitoring Pods Not Running

```bash
# Check pod status
kubectl get pods -n monitoring

# Check events
kubectl get events -n monitoring --sort-by='.lastTimestamp'

# Review logs
kubectl logs -n monitoring <pod-name>
```

## References

- [Auto-Sleep Runbook](AUTOSLEEP_RUNBOOK.md)
- [Enterprise Monitoring Enhancement](ENTERPRISE_MONITORING_ENHANCEMENT.md)
- [Monitoring Access Guide](MONITORING_ACCESS.md)
- [Troubleshooting Guide](../troubleshooting.md)

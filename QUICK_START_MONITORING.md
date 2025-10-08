# Quick Start Guide - Monitoring Enhancements

## What Was Added

This PR adds comprehensive monitoring enhancements to VMStation:

1. **Enhanced Diagnostics** - Blackbox exporter and Jellyfin wait tasks now show detailed status
2. **Syslog Server** - Centralized log collection from all network devices
3. **New Dashboards** - 3 professional-grade Grafana dashboards
4. **RKE2 Integration** - Already configured to federate metrics from homelab

## Immediate Actions After Deployment

### 1. Verify Deployment
```bash
cd /srv/monitoring_data/VMStation
./tests/verify-monitoring-enhancements.sh
```

### 2. Access Grafana
```bash
# Get the URL
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide | awk 'NR==2 {print "http://"$6":30300"}'

# Default credentials: admin / admin
# IMPORTANT: Change the password immediately!
```

### 3. New Dashboards to Explore

Navigate to Dashboards in Grafana:

- **Network Monitoring - Blackbox Exporter**
  - Network probe results (HTTP, ICMP, DNS)
  - SSL certificate expiry warnings
  - Probe success rates
  
- **Network Security & Analysis**
  - Network traffic monitoring
  - Packet drops and errors
  - TCP connection tracking
  - DNS query monitoring
  
- **Syslog Analysis & Monitoring**
  - Centralized log viewing
  - Security event detection
  - Authentication tracking
  - Error message analysis

## Troubleshooting

### Blackbox Exporter Not Starting?

The wait task now shows diagnostic output. Check the Ansible output for:
- Pod status and events
- Deployment conditions
- Readiness probe results

Common fixes:
```bash
# Check if node has the label
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --show-labels | grep control-plane

# If missing, add it
kubectl --kubeconfig=/etc/kubernetes/admin.conf label node <masternode> node-role.kubernetes.io/control-plane=""
```

### Syslog Not Receiving Messages?

Test syslog reception:
```bash
# Get masternode IP
MASTER_IP=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o jsonpath='{.items[0].status.addresses[0].address}')

# Send test message
logger -n $MASTER_IP -P 514 "Test syslog message from $(hostname)"

# Check if received
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring logs daemonset/syslog-server --tail=10
```

### Loki 502 Errors?

Check Loki status:
```bash
# Verify Loki is running
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods -l app=loki

# Check logs
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring logs deployment/loki --tail=50

# Test readiness
curl http://<masternode-ip>:31100/ready
```

If Loki is down:
```bash
# Restart Loki
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring rollout restart deployment/loki

# Wait for it to be ready
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring rollout status deployment/loki
```

## Performance Monitoring

The new dashboards provide:

### For Network Engineers
- **Blackbox Exporter Dashboard**: End-to-end connectivity testing
- **Network Security Dashboard**: Traffic patterns, errors, connection states

### For Security Analysts
- **Syslog Dashboard**: Security events, authentication failures, threats
- **Network Security Dashboard**: Firewall activity, suspicious patterns

### For System Administrators
- All existing dashboards (Node, Cluster, IPMI, Prometheus, Loki)
- Enhanced with syslog correlation

## Advanced Configuration

### Configure Network Devices to Send Syslog

Point your routers, switches, firewalls to:
- **Server**: `<masternode-ip>`
- **Port**: `514` (UDP or TCP)
- **Protocol**: Syslog (RFC 3164 or RFC 5424)

Example for Cisco devices:
```
logging host <masternode-ip> transport udp port 514
logging trap informational
```

### RKE2 Federation

Already configured! Metrics from the RKE2 cluster on homelab (192.168.4.62) are automatically scraped.

To verify RKE2 metrics are being collected:
1. Open Prometheus UI: `http://<masternode-ip>:30090`
2. Go to Status → Targets
3. Look for `rke2-federation` job
4. If target is down, ensure RKE2 Prometheus is running on homelab:30090

### Add Custom Probes

Edit `manifests/monitoring/prometheus.yaml` and add targets to the `blackbox` job:

```yaml
- job_name: 'blackbox'
  static_configs:
  - targets:
    - http://prometheus.monitoring.svc.cluster.local:9090
    - http://grafana.monitoring.svc.cluster.local:3000
    - http://your-app.namespace.svc.cluster.local:8080  # Add your app
```

Then reload Prometheus:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring rollout restart deployment/prometheus
```

## Security Recommendations

1. **Change Grafana Password**
   ```bash
   kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring exec -it deployment/grafana -- grafana-cli admin reset-admin-password <new-password>
   ```

2. **Enable Syslog TLS** (Optional)
   - Configure certificates in syslog-ng.conf
   - Update client devices to use port 601
   - Provides encrypted log transmission

3. **Set Up Alerting**
   - Configure AlertManager
   - Add notification channels (email, Slack)
   - Customize alert rules in Prometheus

## Documentation

- **Full Details**: `COMPREHENSIVE_MONITORING_FIX.md`
- **Verification Script**: `tests/verify-monitoring-enhancements.sh`
- **Original Docs**: `MONITORING_FIX_SUMMARY.md`

## Support

If you encounter issues:

1. Run the verification script:
   ```bash
   ./tests/verify-monitoring-enhancements.sh
   ```

2. Check pod status:
   ```bash
   kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods -o wide
   ```

3. Review comprehensive documentation:
   ```bash
   cat COMPREHENSIVE_MONITORING_FIX.md | less
   ```

4. Check Ansible output for diagnostic messages from enhanced wait tasks

## What's Next?

Recommended next steps:

1. **Explore Dashboards** - Familiarize yourself with the new monitoring capabilities
2. **Configure Syslog Sources** - Set up network devices to send logs
3. **Set Up Alerts** - Configure notifications for critical events
4. **Customize Dashboards** - Adjust thresholds and panels to your needs
5. **Review Security Events** - Check the syslog dashboard for any issues

---

**Monitoring Stack Version**: 2.0  
**Date**: 2025  
**Components**: Prometheus, Grafana, Loki, Blackbox Exporter, Syslog-NG, RKE2 Federation

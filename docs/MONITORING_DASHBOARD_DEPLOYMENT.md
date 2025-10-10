# Monitoring Stack Dashboard Enhancements - Deployment Guide

## Quick Start

This guide provides step-by-step instructions to deploy the new enterprise-grade dashboards and configure comprehensive monitoring for the VMStation cluster.

---

## What's New

### ✅ Dashboards Created/Enhanced (Oct 2025)

1. **Syslog Infrastructure Monitoring** - NEW
   - Comprehensive syslog server monitoring
   - Message rate tracking and latency metrics
   - Severity/facility-based filtering
   - Live tail of critical logs

2. **CoreDNS Performance & Health** - NEW
   - DNS query performance monitoring
   - Cache statistics and hit rate
   - Response time percentiles
   - Top queried domains

3. **Loki Logs & Aggregation** - ENHANCED
   - Service health indicators
   - Template variables for filtering
   - Error and warning rate tracking
   - Loki performance metrics

### 📚 Documentation Added

- `docs/GRAFANA_DASHBOARD_USAGE_GUIDE.md` - Complete dashboard usage guide
- `docs/RHEL10_HOMELAB_METRICS_SETUP.md` - Homelab node monitoring setup

---

## Deployment Steps

### Prerequisites

- SSH access to masternode (192.168.4.63)
- Cluster deployed and running
- Git repository up to date

### Step 1: Update Repository

```bash
cd /srv/monitoring_data/VMStation
git pull origin main
```

### Step 2: Deploy Updated Monitoring Stack

```bash
./deploy.sh monitoring
```

This will:
- Update Grafana ConfigMap with new dashboards
- Restart Grafana pod to load dashboards
- Keep existing Prometheus and Loki configurations

**Expected Output:**
```
[INFO] Deploying monitoring stack...
[INFO] ✓ Monitoring stack deployment completed successfully
```

### Step 3: Verify Grafana Dashboards

1. Access Grafana: `http://192.168.4.63:30300`
2. Login: `admin/admin` (change in production)
3. Click "Dashboards" (☰ menu)
4. Verify new dashboards appear:
   - ✅ Syslog Infrastructure Monitoring
   - ✅ CoreDNS Performance & Health
   - ✅ Loki Logs & Aggregation - Enterprise (updated)

### Step 4: Check Dashboard Data

#### Test Syslog Dashboard

1. Open "Syslog Infrastructure Monitoring"
2. Check "Syslog Server Status" panel (should show "Up" or "Down")
3. If "Down", verify syslog-ng pod:
   ```bash
   kubectl get pods -n infrastructure
   kubectl logs -n infrastructure syslog-server-0
   ```

#### Test CoreDNS Dashboard

1. Open "CoreDNS Performance & Health"
2. Check "CoreDNS Status" panel (should show 2)
3. Verify "Total Queries (5m)" shows data
4. If no data, check CoreDNS pods:
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   ```

#### Test Enhanced Loki Dashboard

1. Open "Loki Logs & Aggregation - Enterprise"
2. Check "Loki Service Status" (should be "Healthy")
3. Use namespace dropdown to filter logs
4. Verify log panels show data
5. If "Down", check Loki pod:
   ```bash
   kubectl get pods -n monitoring loki-0
   kubectl logs -n monitoring loki-0
   ```

---

## Troubleshooting

### Dashboard Shows "No Data"

**Check Datasources:**
```bash
# In Grafana: Configuration → Data Sources
# Test both Prometheus and Loki connections

# Or via kubectl
kubectl get svc -n monitoring prometheus loki grafana
kubectl get endpoints -n monitoring prometheus loki
```

**Expected Endpoints:**
```
NAME         ENDPOINTS
prometheus   10.244.x.x:9090
loki         10.244.x.x:3100,10.244.x.x:9096
```

### Prometheus Pod Shows 1/2 Ready

This is a known issue addressed in previous work. Run remediation:

```bash
./scripts/diagnose-monitoring-stack.sh
./scripts/remediate-monitoring-stack.sh
./scripts/validate-monitoring-stack.sh
```

See `AI_AGENT_IMPLEMENTATION_REPORT.md` for details.

### Loki Connection Refused

Check if Loki pod is ready:
```bash
kubectl get pods -n monitoring loki-0
kubectl describe pod loki-0 -n monitoring
kubectl logs -n monitoring loki-0 --tail=100
```

Verify endpoints:
```bash
kubectl get endpoints -n monitoring loki
```

If empty, Loki pod is not Ready. Check readiness probe:
```bash
kubectl exec -n monitoring loki-0 -- wget -O- http://localhost:3100/ready
```

---

## Configure RHEL10 Homelab Node (Optional but Recommended)

The homelab node (192.168.4.62) is not currently sending metrics to the monitoring stack.

### Quick Setup

Follow the comprehensive guide: `docs/RHEL10_HOMELAB_METRICS_SETUP.md`

### Summary Steps

1. **Install Node Exporter** (port 9100)
   ```bash
   ssh root@192.168.4.62
   # Download and install node_exporter
   # Create systemd service
   # Configure firewall
   systemctl start node_exporter
   firewall-cmd --add-port=9100/tcp --permanent
   firewall-cmd --reload
   ```

2. **Install IPMI Exporter** (port 9290) - for hardware monitoring
   ```bash
   dnf install -y ipmitool freeipmi
   # Download and install ipmi_exporter
   # Create systemd service with CAP_SYS_RAWIO
   # Configure firewall
   systemctl start ipmi_exporter
   firewall-cmd --add-port=9290/tcp --permanent
   firewall-cmd --reload
   ```

3. **Configure Syslog Forwarding**
   ```bash
   echo '*.* @@192.168.4.63:30515' > /etc/rsyslog.d/50-forward-to-vmstation.conf
   systemctl restart rsyslog
   ```

4. **Verify from Masternode**
   ```bash
   curl http://192.168.4.62:9100/metrics | head -10
   curl http://192.168.4.62:9290/metrics | head -10
   ```

5. **Check Prometheus Targets**
   - Go to: `http://192.168.4.63:30090/targets`
   - Verify homelab targets are UP:
     - `node-exporter` (192.168.4.62:9100)
     - `ipmi-exporter` (192.168.4.62:9290)

6. **View in Dashboards**
   - **Node Metrics - Detailed System Monitoring**: Should show homelab node
   - **IPMI Hardware Monitoring**: Should show temperature, fans, power
   - **Syslog Infrastructure Monitoring**: Should show homelab logs

---

## Validation Checklist

After deployment, verify:

- [ ] All 8 dashboards appear in Grafana
- [ ] Syslog Infrastructure Monitoring shows data
- [ ] CoreDNS Performance & Health shows metrics
- [ ] Enhanced Loki dashboard has new panels
- [ ] Prometheus shows all targets UP (or documented why down)
- [ ] Grafana datasources test successfully
- [ ] Logs appear in Loki from all namespaces
- [ ] (Optional) Homelab node metrics visible

### Quick Validation Commands

```bash
# Check all monitoring pods
kubectl get pods -n monitoring

# Expected output:
# prometheus-0                          2/2     Running
# loki-0                                1/1     Running
# grafana-xxx                           1/1     Running
# node-exporter-xxx                     1/1     Running (DaemonSet on each node)
# promtail-xxx                          1/1     Running (DaemonSet on each node)

# Check infrastructure pods
kubectl get pods -n infrastructure

# Expected output:
# syslog-server-0                       2/2     Running

# Check Prometheus targets
curl -s http://192.168.4.63:30090/api/v1/targets | jq '.data.activeTargets[] | select(.health != "up") | {job: .labels.job, instance: .labels.instance, health: .health, error: .lastError}'

# Should return empty array if all targets are up
```

---

## Dashboard Usage

Refer to `docs/GRAFANA_DASHBOARD_USAGE_GUIDE.md` for:
- Detailed description of each dashboard
- Key metrics and their meanings
- Troubleshooting tips
- Best practices for time ranges and refresh rates
- Alert integration recommendations

### Quick Tips

1. **Adjust Time Range**: Use time picker (top right) to view different periods
2. **Auto Refresh**: Set to 30s for real-time monitoring
3. **Template Variables**: Use dropdowns to filter by namespace, pod, etc.
4. **Export Panels**: Click "..." on panel → Inspect → Download CSV
5. **Share Dashboard**: Click share icon (🔗) for URL

---

## Support

For issues:

1. **Run Diagnostics**:
   ```bash
   ./scripts/diagnose-monitoring-stack.sh
   # Review output in /tmp/monitoring-diagnostics-*/
   ```

2. **Review Logs**:
   ```bash
   kubectl logs -n monitoring prometheus-0 -c prometheus
   kubectl logs -n monitoring loki-0
   kubectl logs -n monitoring <grafana-pod>
   ```

3. **Check Documentation**:
   - Dashboard usage: `docs/GRAFANA_DASHBOARD_USAGE_GUIDE.md`
   - Homelab setup: `docs/RHEL10_HOMELAB_METRICS_SETUP.md`
   - Troubleshooting: `docs/MONITORING_STACK_DIAGNOSTICS_AND_REMEDIATION.md`

4. **Validate Stack**:
   ```bash
   ./scripts/validate-monitoring-stack.sh
   ```

---

## Rollback (If Needed)

If issues occur with new dashboards:

```bash
# Restore previous Grafana ConfigMap
kubectl rollout undo deployment/grafana -n monitoring

# Or redeploy from previous commit
git checkout <previous-commit>
./deploy.sh monitoring
git checkout main
```

Dashboards are stored in ConfigMap, so pod restart loads changes.

---

## Next Steps

1. ✅ Deploy updated monitoring stack
2. ✅ Verify all dashboards load in Grafana
3. ✅ Check data is flowing to all dashboards
4. ⏭️ Configure RHEL10 homelab node (optional)
5. ⏭️ Set up alerting rules based on dashboard metrics
6. ⏭️ Train team on dashboard usage

---

## Summary of Changes

**Files Modified:**
- `manifests/monitoring/grafana.yaml` - Added 2 new dashboards, updated 1
- `ansible/files/grafana_dashboards/` - Added syslog and coredns dashboards, enhanced loki dashboard

**Files Created:**
- `docs/GRAFANA_DASHBOARD_USAGE_GUIDE.md` - Dashboard documentation
- `docs/RHEL10_HOMELAB_METRICS_SETUP.md` - Homelab monitoring setup guide
- `docs/MONITORING_DASHBOARD_DEPLOYMENT.md` - This deployment guide

**Dashboards Updated:**
- ✅ Syslog Infrastructure Monitoring (NEW)
- ✅ CoreDNS Performance & Health (NEW)
- ✅ Loki Logs & Aggregation - Enterprise (ENHANCED)

---

**Deployment Time**: ~5 minutes  
**Tested On**: VMStation Debian Bookworm + RHEL10 cluster  
**Last Updated**: 2025-10-10

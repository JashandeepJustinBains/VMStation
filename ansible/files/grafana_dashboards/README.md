# VMStation Grafana Dashboards

## Overview

This directory contains enterprise-grade Grafana dashboards for the VMStation monitoring stack. These dashboards provide comprehensive visibility into Kubernetes cluster health, application performance, and infrastructure metrics.

## Dashboards

### 1. VMStation Kubernetes Cluster Overview
**File:** `kubernetes-cluster-dashboard.json`  
**UID:** `vmstation-k8s-overview`

High-level cluster health monitoring with key metrics for nodes, pods, and resource utilization.

**Key Panels:**
- Total Nodes, Running Pods, Failed Pods
- Node CPU and Memory Usage
- Node Status Table

### 2. Node Metrics - Detailed System Monitoring
**File:** `node-dashboard.json`  
**UID:** `node-metrics-detailed`

Detailed system-level metrics for all cluster nodes (master and workers).

**Key Panels:**
- CPU, Memory, Disk Usage by Node
- Network Traffic by Interface
- System Load Average
- OS Distribution Table

### 3. Prometheus Metrics & Health
**File:** `prometheus-dashboard.json`  
**UID:** `prometheus-health`

Monitor Prometheus server health and scrape target status.

**Key Panels:**
- Targets Up/Down Count
- Sample Ingestion Rate
- Query Duration (P95, P99)
- Scrape Target Status Table
- TSDB Series and Storage Size

### 4. Network & DNS Performance
**File:** `network-latency-dashboard.json`  
**UID:** `network-dns-performance`

Monitor network connectivity and DNS resolution performance via Blackbox Exporter and CoreDNS.

**Key Panels:**
- HTTP Probe Success
- HTTP Latency
- DNS Query Time
- DNS Error Rate
- CoreDNS Pod Restarts
- Probe Status Table

### 5. Loki Logs & Aggregation - Enterprise ✨ NEW
**File:** `loki-dashboard.json`  
**UID:** `loki-logs`

Enterprise-grade log aggregation with advanced filtering and performance metrics.

**Key Panels:**
- Loki Service Status
- Log Ingestion Rate
- Error and Warning Rate Tracking
- Log Volume by Namespace and Job
- Top Log-Producing Pods
- Loki Performance Metrics
- Filtered Log Views (Application, System, Monitoring)

**Features:**
- Template variables for namespace filtering
- Live tail with auto-refresh
- Error/warning log highlighting

### 6. Syslog Infrastructure Monitoring ✨ NEW
**File:** `syslog-dashboard.json`  
**UID:** `syslog-infrastructure`

Monitor centralized syslog server receiving logs from network devices and external systems.

**Key Panels:**
- Syslog Server Status
- Message Received/Sent Rates
- Processing Latency (P50, P95, P99)
- Messages by Severity (emergency, alert, critical, error, etc.)
- Messages by Facility (kern, user, daemon, etc.)
- Messages by Host (Top 10)
- Critical and Error Logs
- Recent Syslog Events (Live Tail)

**Use Cases:**
- Network device log aggregation (routers, switches)
- External server syslog forwarding
- Critical event monitoring

### 7. CoreDNS Performance & Health ✨ NEW
**File:** `coredns-dashboard.json`  
**UID:** `coredns-performance`

Comprehensive DNS service monitoring with performance and cache analytics.

**Key Panels:**
- CoreDNS Status and Restart Count
- Total Queries and Error Rate
- Cache Hit Rate (gauge)
- Query Rate by DNS Record Type (A, AAAA, SRV, etc.)
- Response Time Percentiles (P50, P95, P99)
- Response Codes (NOERROR, NXDOMAIN, SERVFAIL)
- Cache Statistics (hits, misses, entries)
- Forward Requests by Upstream
- Forward Response Time
- Top 10 Queried Domains
- Pod Resource Usage (CPU, Memory)
- Plugin Status Table

**Thresholds:**
- Response Time: < 50ms (good), 50-100ms (warning), > 100ms (critical)
- Cache Hit Rate: > 80% (good), 50-80% (warning), < 50% (critical)

### 8. IPMI Hardware Monitoring - RHEL 10 Enterprise Server
**File:** `ipmi-hardware-dashboard.json`  
**UID:** `ipmi-hardware`

Monitor physical server hardware sensors via IPMI/BMC.

**Key Panels:**
- Temperature Sensors (with thresholds)
- Fan Speeds (RPM)
- Power Consumption (Watts)
- Voltage Sensors
- Current Temperature Status
- BMC Status
- Sensor Status Table

**Requirements:**
- IPMI exporter deployed
- IPMI credentials configured
- BMC network access

---

## Dashboard Installation

Dashboards are automatically deployed via Grafana ConfigMap in `manifests/monitoring/grafana.yaml`.

### Deployment

```bash
cd /srv/monitoring_data/VMStation
kubectl apply -f manifests/monitoring/grafana.yaml
kubectl delete pod -n monitoring -l app=grafana  # Restart to load dashboards
```

### Verification

1. Access Grafana: `http://<masternode-ip>:30300`
2. Login: `admin/admin`
3. Navigate to Dashboards → Browse
4. Verify all 8 dashboards are listed

---

## Dashboard Development

### File Format

All dashboards are stored as Grafana JSON models with:
- **schemaVersion**: 27 (Grafana 10.0 compatible)
- **Minified versions**: `-minified.json` files for ConfigMap embedding

### Creating New Dashboards

1. **Design in Grafana UI**:
   - Create dashboard in Grafana
   - Configure panels, queries, and layout
   - Test with live data

2. **Export JSON**:
   - Click share icon (🔗) → Export → Save to file
   - Download as JSON

3. **Add to Repository**:
   ```bash
   # Save to dashboards directory
   cp ~/Downloads/my-dashboard.json ansible/files/grafana_dashboards/
   
   # Minify for ConfigMap
   python3 -c "import json; f=open('my-dashboard.json'); d=json.load(f); f.close(); print(json.dumps(d, separators=(',',':')))" > my-dashboard-minified.json
   ```

4. **Update Grafana ConfigMap**:
   ```yaml
   # manifests/monitoring/grafana.yaml
   data:
     my-dashboard.json: |
       <paste minified JSON here>
   ```

5. **Deploy**:
   ```bash
   kubectl apply -f manifests/monitoring/grafana.yaml
   kubectl delete pod -n monitoring -l app=grafana
   ```

### Best Practices

1. **Use Template Variables**: Enable filtering by namespace, pod, node, etc.
2. **Set Thresholds**: Use color coding for quick status identification
3. **Optimize Queries**: Avoid expensive queries that slow dashboard load
4. **Add Descriptions**: Include panel descriptions for documentation
5. **Test with No Data**: Ensure graceful handling when metrics are missing
6. **Mobile-Friendly**: Test responsive layout on smaller screens

### Panel Guidelines

- **Stat Panels**: Use for single value metrics (counts, percentages)
- **Gauge Panels**: Use for percentage values with thresholds
- **Timeseries**: Use for trends over time
- **Table Panels**: Use for lists and comparisons
- **Logs Panels**: Use for log viewing (Loki only)

---

## Datasources

Dashboards use two primary datasources:

1. **Prometheus** (`prometheus.monitoring.svc.cluster.local:9090`)
   - Metrics collection and time-series data
   - Used by most dashboards

2. **Loki** (`loki.monitoring.svc.cluster.local:3100`)
   - Log aggregation and querying
   - Used by Loki and Syslog dashboards

### Testing Datasources

In Grafana:
1. Configuration → Data Sources
2. Click datasource name
3. Scroll to bottom → "Test" button
4. Should show "Data source is working"

---

## Common Queries

### Prometheus

```promql
# Node CPU usage
100 - (avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Pod count by namespace
sum by (namespace) (kube_pod_info)

# Prometheus scrape targets up
sum(up)

# CoreDNS query rate
sum(rate(coredns_dns_requests_total[5m]))
```

### Loki (LogQL)

```logql
# All logs from monitoring namespace
{namespace="monitoring"}

# Error logs from all pods
{job=~".+"} |~ "(?i)error|exception|fatal"

# Logs from specific pod
{pod="prometheus-0"}

# Log rate by namespace
sum by (namespace) (rate({job=~".+"}[1m]))

# Syslog entries
{job="syslog"}

# Critical syslog messages
{job="syslog"} | json | severity=~"emergency|alert|critical"
```

---

## Troubleshooting

### Dashboard Shows "No Data"

1. Check datasource configuration
2. Verify target pods are running
3. Check if metrics are being scraped
4. Extend time range

### Panel Shows "N/A" or Error

1. Click panel title → Edit
2. Review query syntax
3. Test query in Explore view
4. Check if metric name exists

### Slow Dashboard Performance

1. Reduce time range (use 1h instead of 24h)
2. Increase refresh interval (use 1m instead of 10s)
3. Simplify complex queries
4. Remove unused panels

### Dashboard Not Appearing

1. Verify dashboard JSON is valid
2. Check ConfigMap is updated: `kubectl get cm grafana-dashboards -n monitoring`
3. Restart Grafana pod
4. Check Grafana logs: `kubectl logs -n monitoring <grafana-pod>`

---

## Documentation

- **Dashboard Usage Guide**: `docs/GRAFANA_DASHBOARD_USAGE_GUIDE.md`
- **Deployment Guide**: `docs/MONITORING_DASHBOARD_DEPLOYMENT.md`
- **Homelab Setup**: `docs/RHEL10_HOMELAB_METRICS_SETUP.md`
- **Monitoring Stack Diagnostics**: `docs/MONITORING_STACK_DIAGNOSTICS_AND_REMEDIATION.md`

---

## Contributing

When adding or modifying dashboards:

1. Test thoroughly with live data
2. Document all panels and queries
3. Add to this README
4. Update usage guide if needed
5. Minify JSON for ConfigMap
6. Test deployment in cluster
7. Create PR with clear description

---

## Version History

### v1.3 - October 2025
- ✨ Added Syslog Infrastructure Monitoring dashboard
- ✨ Added CoreDNS Performance & Health dashboard
- 🔧 Enhanced Loki dashboard to enterprise-grade
- 📚 Created comprehensive documentation

### v1.2 - October 2025
- Fixed Loki schema configuration
- Fixed Blackbox exporter configuration
- Added network latency dashboard

### v1.1 - October 2025
- Added IPMI hardware monitoring
- Enhanced Prometheus dashboard

### v1.0 - Initial Release
- Basic Kubernetes cluster monitoring
- Node metrics dashboard
- Prometheus health dashboard

---

**Maintained By**: VMStation Operations Team  
**Last Updated**: 2025-10-10  
**Grafana Version**: 10.0.0

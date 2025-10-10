# Grafana Dashboard Usage Guide

## Overview

This document provides comprehensive guidance on using the enterprise-grade Grafana dashboards deployed in the VMStation monitoring stack.

## Dashboard Access

Access Grafana at: `http://<masternode-ip>:30300`  
Default credentials: `admin/admin` (change in production)

Anonymous access is enabled for viewing dashboards (Viewer role).

---

## Available Dashboards

### 1. VMStation Kubernetes Cluster Overview
**UID:** `vmstation-k8s-overview`  
**Tags:** kubernetes, vmstation, cluster

#### Purpose
High-level overview of Kubernetes cluster health and resource utilization.

#### Key Metrics
- **Total Nodes**: Number of nodes in the cluster
- **Running Pods**: Currently running pod count
- **Failed Pods**: Pods in failed state (requires attention if > 0)
- **Node CPU Usage**: CPU utilization per node over time
- **Node Memory Usage**: Memory utilization per node over time
- **Node Status**: Table showing node health and status

#### Use Cases
- Quick cluster health check
- Identify resource-constrained nodes
- Monitor pod deployment status
- Track node availability

---

### 2. Node Metrics - Detailed System Monitoring
**UID:** `node-metrics-detailed`  
**Tags:** nodes, system, vmstation

#### Purpose
Detailed system-level metrics for all cluster nodes including master and workers.

#### Key Metrics
- **CPU Usage by Node**: Per-node CPU utilization with thresholds (60% yellow, 80% red)
- **Memory Usage by Node**: Memory utilization with thresholds (70% yellow, 85% red)
- **Disk Usage by Node**: Root filesystem usage with thresholds (75% yellow, 90% red)
- **Network Traffic by Node**: Network I/O by interface (RX/TX)
- **System Load Average**: 5-minute load average per node
- **OS Distribution by Node**: Table showing OS version and kernel

#### Use Cases
- Identify resource bottlenecks
- Monitor disk space consumption
- Track network bandwidth usage
- Verify OS/kernel versions across nodes
- Capacity planning

#### Alerts to Watch For
- CPU usage sustained above 80%
- Memory usage above 85%
- Disk usage above 90%
- Unusual network traffic spikes

---

### 3. Prometheus Metrics & Health
**UID:** `prometheus-health`  
**Tags:** prometheus, metrics, vmstation

#### Purpose
Monitor Prometheus server health and scrape target status.

#### Key Metrics
- **Prometheus Targets Up**: Count of healthy scrape targets
- **Total Scrape Targets**: Total configured targets
- **Samples Ingested Rate**: Metrics samples per second
- **Query Duration**: Query latency (P95, P99)
- **Scrape Target Status**: Table of all targets with health status
- **TSDB Head Series**: Active time series count
- **Storage Size**: Prometheus storage utilization

#### Use Cases
- Verify all exporters are being scraped
- Identify failing scrape targets
- Monitor Prometheus performance
- Track storage growth
- Troubleshoot missing metrics

#### Troubleshooting
If targets show "Down" status:
1. Check if the target service is running
2. Verify network connectivity
3. Check firewall rules (port 9100 for node-exporter, etc.)
4. Review Prometheus logs: `kubectl logs prometheus-0 -n monitoring -c prometheus`

---

### 4. Network & DNS Performance
**UID:** `network-dns-performance`  
**Tags:** network, dns, latency, vmstation

#### Purpose
Monitor network connectivity and DNS resolution performance.

#### Key Metrics
- **HTTP Probe Success**: Blackbox exporter probe results
- **HTTP Latency**: HTTP request duration
- **DNS Query Time**: CoreDNS response time (P95)
- **DNS Error Rate**: Failed DNS queries per second
- **CoreDNS Pod Restarts**: Restart count (last hour)
- **Blackbox Probe Failures**: Failed probes (last hour)
- **Probe Status Table**: All probe targets with status

#### Use Cases
- Monitor external connectivity
- Track DNS resolution performance
- Identify network latency issues
- Alert on DNS failures

---

### 5. Loki Logs & Aggregation - Enterprise
**UID:** `loki-logs`  
**Tags:** loki, logs, vmstation, enterprise

#### Purpose
Centralized log aggregation and analysis with enterprise features.

#### Key Metrics
- **Loki Service Status**: Loki server health
- **Total Log Lines (5m)**: Log ingestion volume
- **Log Ingestion Rate**: Real-time log rate (logs/s)
- **Error Rate (5m)**: Count of error-level logs
- **Warning Rate (5m)**: Count of warning-level logs
- **Log Volume by Namespace**: Stacked area chart of logs per namespace
- **Log Volume by Job**: Log sources breakdown
- **Error Log Rate by Namespace**: Error trends
- **Top 10 Log Producing Pods**: Pods with highest log volume
- **Loki Performance Metrics**: Chunks created, memory usage, request duration

#### Features
- **Template Variables**: Filter by namespace using dropdown
- **Log Panels**: 
  - Application logs (non-system namespaces)
  - System logs (kube-system)
  - Monitoring stack logs
- **Live Tail**: Logs update in real-time (30s refresh)

#### Use Cases
- Troubleshoot application issues
- Monitor log volume trends
- Identify chatty applications
- Search logs across all pods
- Track error patterns

#### Query Examples
```
# All logs from a specific pod
{pod="prometheus-0"}

# Error logs from all namespaces
{job=~".+"} |~ "(?i)error|exception|fatal"

# Logs from monitoring namespace in last 5m
{namespace="monitoring"} [5m]
```

---

### 6. Syslog Infrastructure Monitoring
**UID:** `syslog-infrastructure`  
**Tags:** syslog, logs, infrastructure, vmstation, enterprise

#### Purpose
Monitor centralized syslog server receiving logs from network devices and external systems.

#### Key Metrics
- **Syslog Server Status**: Service health (Up/Down)
- **Messages Received (Last 5m)**: Incoming syslog messages
- **Messages Sent to Loki (Last 5m)**: Forwarded messages
- **Connection Count**: Active syslog connections
- **Syslog Message Rate**: Received vs sent message rates
- **Message Processing Latency**: Processing time (P50, P95, P99)
- **Syslog Messages by Severity**: Breakdown by log level (emergency, alert, critical, error, warning, etc.)
- **Syslog Messages by Facility**: Distribution across syslog facilities (kern, user, mail, daemon, etc.)
- **Syslog Messages by Host**: Top 10 hosts sending logs
- **Critical and Error Logs**: Filtered view of high-priority logs
- **Recent Syslog Events**: Live tail of all syslog messages

#### Configuration
To send syslog from devices to the cluster:
```bash
# Configure device to send syslog to:
# UDP: <masternode-ip>:30514
# TCP: <masternode-ip>:30515 (recommended)
# TLS: <masternode-ip>:30601 (RFC5424)

# Test from Linux:
logger -n <masternode-ip> -P 30514 "Test syslog message"
```

#### Use Cases
- Monitor network device logs (routers, switches, firewalls)
- Aggregate system logs from external servers
- Track syslog message volume
- Identify devices generating excessive logs
- Monitor critical system events

#### Troubleshooting
- **No data in dashboard**: Verify syslog-ng pod is running in infrastructure namespace
- **Missing logs from device**: Check device syslog configuration and firewall rules
- **High latency**: Review connection count and consider scaling

---

### 7. CoreDNS Performance & Health
**UID:** `coredns-performance`  
**Tags:** coredns, dns, kubernetes, vmstation, enterprise

#### Purpose
Monitor Kubernetes DNS service performance and health.

#### Key Metrics
- **CoreDNS Status**: Pod health and count
- **Total Queries (5m)**: DNS query volume
- **Cache Hit Rate**: Percentage of queries served from cache
- **Query Errors (5m)**: Failed DNS resolutions
- **Pod Restart Count**: CoreDNS pod restarts (last hour)
- **DNS Query Rate by Type**: Breakdown by record type (A, AAAA, SRV, PTR, etc.)
- **DNS Response Time (Percentiles)**: P50, P95, P99 latency
- **DNS Response Codes**: NOERROR, NXDOMAIN, SERVFAIL distribution
- **Cache Statistics**: Cache hits, misses, and entries
- **Forward Requests by Upstream**: External DNS forwarding
- **Forward Response Time by Upstream**: Upstream DNS server latency
- **Top 10 Queried Domains**: Most frequently resolved domains
- **CoreDNS Pod Resource Usage**: CPU and memory consumption
- **Plugin Status & Health**: Enabled CoreDNS plugins

#### Thresholds
- **Response Time**: < 50ms (good), 50-100ms (warning), > 100ms (critical)
- **Cache Hit Rate**: > 80% (good), 50-80% (warning), < 50% (critical)
- **Pod Restarts**: 0 (good), 1-2 (warning), > 3 (critical)

#### Use Cases
- Troubleshoot DNS resolution failures
- Monitor DNS query performance
- Identify pods with excessive DNS queries
- Track cache efficiency
- Optimize CoreDNS configuration
- Monitor upstream DNS health

#### Common Issues
1. **Low Cache Hit Rate**
   - Increase cache TTL in CoreDNS config
   - Check for apps making unique queries
   
2. **High Response Time**
   - Check upstream DNS server latency
   - Consider adding more CoreDNS replicas
   - Review network connectivity

3. **NXDOMAIN Errors**
   - Check service names in application configs
   - Verify search domain configuration
   - Review DNS query logs

4. **Pod Restarts**
   - Check CoreDNS logs: `kubectl logs -n kube-system -l k8s-app=kube-dns`
   - Review resource limits
   - Check for OOMKilled events

---

### 8. IPMI Hardware Monitoring - RHEL 10 Enterprise Server
**UID:** `ipmi-hardware`  
**Tags:** ipmi, hardware, rhel10, enterprise, vmstation

#### Purpose
Monitor physical server hardware sensors via IPMI/BMC on the RHEL10 homelab node.

#### Key Metrics
- **Server Temperature Sensors**: All temperature sensors with thresholds (65°C yellow, 75°C orange, 85°C red)
- **Fan Speeds**: RPM for all cooling fans (< 1000 rpm warning)
- **Power Consumption**: Current power draw in watts
- **Voltage Sensors**: All voltage rails
- **Current Temperature Status**: Highest sensor reading
- **BMC Status**: BMC connectivity health
- **Current Power Draw**: Real-time power consumption
- **Sensor Status Table**: All IPMI sensors with status

#### Requirements
- IPMI exporter deployed on homelab node
- IPMI credentials configured
- Network access to BMC (port 623 UDP)

#### Use Cases
- Monitor server temperature
- Track power consumption
- Alert on fan failures
- Verify voltage stability
- Predict hardware failures

#### Troubleshooting
- **No data**: Verify ipmi-exporter pod is running and IPMI credentials are configured
- **BMC Offline**: Check network connectivity to BMC interface
- **Missing sensors**: Review IPMI exporter configuration

---

## Dashboard Best Practices

### Refresh Rates
- **Production Monitoring**: 30s - 1m refresh
- **Troubleshooting**: 10s - 30s refresh
- **Historical Analysis**: Disable auto-refresh

### Time Ranges
- **Real-time**: Last 5m - 15m
- **Recent Issues**: Last 1h - 6h
- **Trend Analysis**: Last 24h - 7d
- **Capacity Planning**: Last 30d - 90d

### Using Template Variables
Many dashboards include dropdown filters for namespace, pod, node, etc:
1. Click dropdown at top of dashboard
2. Select one or more values
3. Click "Apply" or press Enter
4. Use "All" to see aggregated view

### Sharing Dashboards
1. Click share icon (🔗) at top
2. Choose "Link" tab for URL
3. Enable "Short URL" for clean links
4. Toggle "Lock time range" to share specific time window

### Exporting Data
1. Hover over panel title
2. Click "..." menu
3. Select "Inspect" → "Data"
4. Choose "Download CSV" or "Download Excel"

---

## Alerting Integration

Dashboards display current state but alerts provide proactive notifications.

### Recommended Alerts
- **Node CPU > 80%** for 5 minutes
- **Node Memory > 85%** for 5 minutes
- **Node Disk > 90%**
- **Pod CrashLoopBackOff**
- **Prometheus Target Down**
- **CoreDNS High Latency** > 100ms P95
- **Loki Ingestion Errors**

Configure alerts in Prometheus alert rules: `manifests/monitoring/prometheus.yaml`

---

## Troubleshooting Common Issues

### Dashboard Shows "No Data"

1. **Check Datasource**:
   - Go to Configuration → Data Sources
   - Test Prometheus and Loki connections
   - Verify URLs: `http://prometheus.monitoring.svc.cluster.local:9090` and `http://loki.monitoring.svc.cluster.local:3100`

2. **Verify Pods**:
   ```bash
   kubectl get pods -n monitoring
   kubectl get pods -n infrastructure
   ```

3. **Check Endpoints**:
   ```bash
   kubectl get endpoints -n monitoring prometheus loki
   ```

4. **Review Logs**:
   ```bash
   kubectl logs -n monitoring prometheus-0 -c prometheus
   kubectl logs -n monitoring loki-0
   kubectl logs -n monitoring grafana-xxx
   ```

### Panel Shows "Error" or "N/A"

1. **Invalid Query**: Edit panel and check query syntax
2. **Missing Metrics**: Verify exporter is running and being scraped
3. **Time Range**: Extend time range to ensure data exists

### Slow Dashboard Performance

1. **Reduce Time Range**: Use shorter time windows (1h instead of 24h)
2. **Limit Queries**: Remove or simplify complex queries
3. **Decrease Refresh Rate**: Use 1m instead of 10s
4. **Optimize Prometheus**: Review retention and TSDB settings

---

## Advanced Features

### Variables and Templating
Create dynamic dashboards using variables:
- `$namespace` - Filter by Kubernetes namespace
- `$node` - Select specific node
- `$pod` - Choose pod name
- `$interval` - Dynamic query interval

### Annotations
Add event annotations to correlate metrics with deployments:
1. Create annotation query in dashboard settings
2. Use Prometheus or Loki as source
3. Example: Show pod restarts as vertical lines

### Panel Links
Dashboards can link to related views:
- Click panel title → "View" to see full query
- Use drilldown links to navigate between dashboards

---

## Support and Feedback

For issues or questions:
1. Review this guide for troubleshooting steps
2. Check monitoring stack logs
3. Run diagnostic script: `./scripts/diagnose-monitoring-stack.sh`
4. Consult main documentation: `docs/MONITORING_STACK_DIAGNOSTICS_AND_REMEDIATION.md`

---

**Last Updated**: 2025-10-10  
**Version**: 1.0  
**Maintainer**: VMStation Operations

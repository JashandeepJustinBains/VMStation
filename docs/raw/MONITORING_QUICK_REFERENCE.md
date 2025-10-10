# Monitoring Stack Quick Reference

## Access URLs

| Service | URL | Authentication | Purpose |
|---------|-----|----------------|---------|
| Grafana | http://192.168.4.63:30300 | None (Anonymous Admin) | Dashboards & Visualization |
| Prometheus | http://192.168.4.63:30090 | None | Metrics Query & Federation |
| Loki | http://192.168.4.63:31100 | None | Log Aggregation |
| Node Exporter (master) | http://192.168.4.63:9100 | None | System Metrics |
| Node Exporter (storage) | http://192.168.4.61:9100 | None | System Metrics |
| Node Exporter (homelab) | http://192.168.4.62:9100 | None | System Metrics |
| IPMI Exporter (homelab) | http://192.168.4.62:9290 | None | Hardware Metrics |

## Pre-Configured Dashboards

1. **VMStation Kubernetes Cluster Overview** (`vmstation-k8s-overview`)
   - Total nodes, running pods, failed pods
   - CPU and memory usage by node
   - Node status table

2. **Node Metrics - Detailed System Monitoring** (`node-metrics-detailed`)
   - CPU, memory, disk usage
   - Network traffic by interface
   - System load average
   - OS distribution table

3. **IPMI Hardware Monitoring** (`ipmi-hardware`)
   - Temperature sensors
   - Fan speeds
   - Power consumption
   - Voltage rails
   - BMC status

4. **Prometheus Metrics & Health** (`prometheus-health`)
   - Target status
   - Scrape statistics
   - Query performance
   - TSDB metrics

5. **Loki Logs & Aggregation** (`loki-logs`)
   - Log volume by namespace
   - Real-time log viewing
   - Error log rates

## Quick Commands

### Check Monitoring Stack Status

```bash
# All monitoring pods
kubectl get pods -n monitoring

# Specific component
kubectl get pods -n monitoring -l app=prometheus
kubectl get pods -n monitoring -l app=grafana
kubectl get pods -n monitoring -l app=loki
kubectl get pods -n monitoring -l app=promtail
kubectl get pods -n monitoring -l app=ipmi-exporter

# All services
kubectl get svc -n monitoring
```

### View Logs

```bash
# Prometheus logs
kubectl logs -n monitoring -l app=prometheus -f

# Grafana logs
kubectl logs -n monitoring -l app=grafana -f

# Loki logs
kubectl logs -n monitoring -l app=loki -f

# Promtail logs (specific node)
kubectl logs -n monitoring promtail-xxxx -f
```

### Restart Components

```bash
# Restart Prometheus
kubectl rollout restart deployment -n monitoring prometheus

# Restart Grafana
kubectl rollout restart deployment -n monitoring grafana

# Restart Loki
kubectl rollout restart deployment -n monitoring loki

# Restart Promtail (will restart all DaemonSet pods)
kubectl rollout restart daemonset -n monitoring promtail
```

### Check Prometheus Targets

```bash
# Via API
curl -s http://192.168.4.63:30090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, instance: .labels.instance}'

# Count healthy targets
curl -s http://192.168.4.63:30090/api/v1/targets | jq '[.data.activeTargets[] | select(.health == "up")] | length'
```

### Query Metrics

```bash
# CPU usage
curl -G http://192.168.4.63:30090/api/v1/query \
  --data-urlencode 'query=100 - (avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'

# Memory usage
curl -G http://192.168.4.63:30090/api/v1/query \
  --data-urlencode 'query=(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100'

# Temperature (IPMI)
curl -G http://192.168.4.63:30090/api/v1/query \
  --data-urlencode 'query=ipmi_temperature_celsius{node="homelab"}'
```

### Query Logs

```bash
# Recent logs from namespace
curl -G -s "http://192.168.4.63:31100/loki/api/v1/query" \
  --data-urlencode 'query={namespace="default"}' | jq

# Error logs
curl -G -s "http://192.168.4.63:31100/loki/api/v1/query" \
  --data-urlencode 'query={namespace=~".+"} |= "error"' | jq

# Logs from specific pod
curl -G -s "http://192.168.4.63:31100/loki/api/v1/query" \
  --data-urlencode 'query={pod="my-pod-name"}' | jq
```

## Common Issues and Fixes

### Grafana Dashboard Not Loading

```bash
# Check if ConfigMap exists
kubectl get configmap -n monitoring grafana-dashboard-kubernetes

# Recreate if missing
kubectl apply -f manifests/monitoring/grafana.yaml

# Restart Grafana
kubectl rollout restart deployment -n monitoring grafana
```

### Prometheus Target Down

```bash
# Identify down target
curl -s http://192.168.4.63:30090/api/v1/targets | \
  jq '.data.activeTargets[] | select(.health != "up") | {job: .labels.job, instance: .labels.instance, error: .lastError}'

# Check network connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  curl http://target-ip:port/metrics

# Verify service exists
kubectl get svc -n monitoring <service-name>
```

### No Logs in Loki

```bash
# Check Promtail is running on all nodes
kubectl get pods -n monitoring -l app=promtail -o wide

# Check Promtail logs
kubectl logs -n monitoring -l app=promtail --tail=50

# Verify Loki is receiving logs
curl http://192.168.4.63:31100/metrics | grep loki_ingester_streams_created_total

# Test log ingestion
kubectl logs -n monitoring -l app=promtail | grep "POST /loki/api/v1/push"
```

### IPMI Metrics Not Available

```bash
# Check IPMI exporter pod
kubectl get pods -n monitoring -l app=ipmi-exporter

# Verify node label
kubectl get node homelab --show-labels | grep vmstation.io/role

# Check IPMI exporter logs
kubectl logs -n monitoring -l app=ipmi-exporter

# Test IPMI locally
ssh homelab "sudo ipmitool sensor list"
```

### High Memory Usage

```bash
# Check resource usage
kubectl top pods -n monitoring

# Prometheus: Reduce retention
kubectl edit deployment -n monitoring prometheus
# Change: --storage.tsdb.retention.time=30d to 15d

# Loki: Reduce retention
kubectl edit configmap -n monitoring loki-config
# Change: retention_period: 168h to 72h

# Restart affected components
kubectl rollout restart deployment -n monitoring prometheus
kubectl rollout restart deployment -n monitoring loki
```

## Alert Thresholds

| Alert | Threshold | Duration | Severity |
|-------|-----------|----------|----------|
| NodeDown | up == 0 | 2m | critical |
| HighCPUUsage | CPU > 80% | 5m | warning |
| HighMemoryUsage | Memory > 85% | 5m | warning |
| DiskSpaceLow | Disk > 85% | 5m | warning |
| PodCrashLooping | Restarts > 0 | 5m | critical |
| PodNotReady | Not Running/Succeeded | 10m | warning |
| IPMIHighTemperature | Temp > 75°C | 5m | warning |
| IPMIFanSpeed | RPM < 1000 | 5m | warning |

## Useful Prometheus Queries

```promql
# Node CPU usage
100 - (avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Node memory usage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Disk usage
(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100

# Network traffic
rate(node_network_receive_bytes_total{device!~"lo|veth.*"}[5m])
rate(node_network_transmit_bytes_total{device!~"lo|veth.*"}[5m])

# Pod count by namespace
count by (namespace) (kube_pod_info)

# Failed pods
sum by (namespace, pod) (kube_pod_status_phase{phase="Failed"})

# Temperature (IPMI)
ipmi_temperature_celsius{node="homelab"}

# Fan speed (IPMI)
ipmi_fan_speed_rpm{node="homelab"}

# Power consumption (IPMI)
ipmi_dcmi_power_consumption_watts{node="homelab"}
```

## Useful LogQL Queries

```logql
# All logs from namespace
{namespace="default"}

# Error logs
{namespace=~".+"} |= "error"

# Warning logs
{namespace=~".+"} |~ "warn|warning"

# Logs from specific pod
{pod="my-pod-name"}

# Logs from specific container
{container="my-container-name"}

# Rate of error logs
sum by (namespace) (rate({namespace=~".+"} |= "error" [5m]))

# Logs excluding system namespaces
{namespace!~"kube-system|kube-flannel|monitoring"}
```

## Backup and Restore

### Export Grafana Dashboards

```bash
# List all dashboards
curl -s http://192.168.4.63:30300/api/search?type=dash-db | jq

# Export specific dashboard
curl -s http://192.168.4.63:30300/api/dashboards/uid/vmstation-k8s-overview | \
  jq '.dashboard' > kubernetes-dashboard-backup.json

# Export all dashboards
for uid in $(curl -s http://192.168.4.63:30300/api/search?type=dash-db | jq -r '.[].uid'); do
  curl -s http://192.168.4.63:30300/api/dashboards/uid/$uid | \
    jq '.dashboard' > "dashboard-${uid}.json"
done
```

### Import Grafana Dashboard

```bash
# Import from file
curl -X POST http://192.168.4.63:30300/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d @dashboard-backup.json
```

## Performance Tuning

### Prometheus

```yaml
# Adjust scrape interval (default: 15s)
global:
  scrape_interval: 30s  # Less frequent, lower load

# Reduce retention (default: 30d)
--storage.tsdb.retention.time=15d

# Limit memory (in deployment)
resources:
  limits:
    memory: 2Gi  # Increase if needed
```

### Loki

```yaml
# Reduce retention (default: 168h = 7d)
table_manager:
  retention_period: 72h  # 3 days

# Increase ingestion limits
limits_config:
  ingestion_rate_mb: 20  # From 10
  ingestion_burst_size_mb: 40  # From 20
```

### Grafana

```yaml
# Reduce dashboard refresh interval
# In each dashboard, change refresh from 30s to 1m

# Limit query result rows
# In panel query options:
max_data_points: 1000
```

## Node Exporter Metrics Reference

| Metric | Description | Unit |
|--------|-------------|------|
| node_cpu_seconds_total | CPU time spent in each mode | seconds |
| node_memory_MemTotal_bytes | Total memory | bytes |
| node_memory_MemAvailable_bytes | Available memory | bytes |
| node_filesystem_size_bytes | Filesystem size | bytes |
| node_filesystem_avail_bytes | Filesystem available space | bytes |
| node_network_receive_bytes_total | Network bytes received | bytes |
| node_network_transmit_bytes_total | Network bytes transmitted | bytes |
| node_load1 | 1-minute load average | - |
| node_load5 | 5-minute load average | - |
| node_load15 | 15-minute load average | - |

## Support and Documentation

- **Full Enhancement Guide**: [ENTERPRISE_MONITORING_ENHANCEMENT.md](ENTERPRISE_MONITORING_ENHANCEMENT.md)
- **IPMI Setup Guide**: [IPMI_MONITORING_GUIDE.md](IPMI_MONITORING_GUIDE.md)
- **Autosleep Runbook**: [AUTOSLEEP_RUNBOOK.md](AUTOSLEEP_RUNBOOK.md)
- **Monitoring Access**: [MONITORING_ACCESS.md](MONITORING_ACCESS.md)

## Quick Health Check

```bash
# One-liner to check all monitoring components
kubectl get pods -n monitoring && \
echo "---" && \
curl -s http://192.168.4.63:30090/api/v1/targets | \
jq -r '.data.activeTargets[] | "\(.labels.job): \(.health)"' | \
sort | uniq -c && \
echo "---" && \
curl -s http://192.168.4.63:30300/api/health | jq
```

Expected output:
```
NAME                              READY   STATUS    RESTARTS   AGE
grafana-xxx                       1/1     Running   0          1h
ipmi-exporter-xxx                 1/1     Running   0          1h
kube-state-metrics-xxx            1/1     Running   0          1h
loki-xxx                          1/1     Running   0          1h
prometheus-xxx                    1/1     Running   0          1h
promtail-xxx                      1/1     Running   0          1h
promtail-yyy                      1/1     Running   0          1h
promtail-zzz                      1/1     Running   0          1h
---
   3 node-exporter: up
   1 ipmi-exporter: up
   1 prometheus: up
   1 kube-state-metrics: up
---
{
  "database": "ok",
  "version": "10.0.0"
}
```

# VMStation Monitoring Stack

This repository contains a comprehensive monitoring solution for the VMStation homelab server cluster using Podman, Prometheus, Grafana, and Loki.

## Architecture

- **Monitoring Node** (192.168.4.63): Runs the monitoring stack (Debian)
- **Storage Node** (192.168.4.61): Monitored server (Debian)  
- **Compute Node** (192.168.4.62): Monitored server (RHEL)

## Components

### Core Monitoring Stack
- **Prometheus** (port 9090): Metrics collection and storage
- **Grafana** (port 3000): Visualization and dashboards
- **Loki** (port 3100): Log aggregation and storage
- **Promtail**: Log collection agent
- **Local Registry** (port 5000): Container image storage

### Exporters
- **Node Exporter** (port 9100): System metrics (CPU, memory, disk, network)
- **Podman System Metrics** (port 9882): Podman system-level metrics
- **Podman System Metrics** (host port configurable via `podman_system_metrics_host_port`, default 19882): Podman system-level metrics
- **Podman Exporter** (port 9300): Container-level metrics

## Pre-built Dashboards

### 1. Node Metrics Dashboard
- System uptime and health indicators
- CPU usage by core with real-time charts
- Memory usage (used vs available) 
- Disk usage and I/O operations
- Network interface statistics

### 2. Podman Container Dashboard  
- Running container count and status
- Container CPU and memory usage
- Container network I/O statistics
- Live container logs from Loki
- Container status table with health indicators

### 3. Prometheus Overview Dashboard
- Target monitoring status (up/down)
- Scrape duration and performance metrics
- Prometheus memory usage and TSDB statistics
- Query rate and performance monitoring

### 4. Loki Logs Dashboard
- Centralized system and container logs
- Log rate analysis by source
- Error detection and alerting
- Searchable log viewer with filtering

## Data Storage

All monitoring data is persisted in `/srv/monitoring_data` on the monitoring node:

```
/srv/monitoring_data/
├── prometheus/          # Metrics data
├── grafana/            # Dashboard configs and data
├── loki/               # Log data
├── promtail/           # Log collection state
└── registry/           # Container images
```

## Deployment

### Prerequisites
- Ansible installed on control node
- SSH access to all nodes configured
- Podman installed on all nodes (handled by playbooks)

### Deploy the monitoring stack:

```bash
# Deploy the complete monitoring stack
ansible-playbook -i ansible/inventory.txt ansible/plays/site.yaml

# Deploy only monitoring components
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml
```

### Verify deployment:

```bash
# Check syntax and configuration
./syntax_validator.sh

# Run monitoring validation (if available)
/tmp/validate_monitoring.sh
```

## Access

After deployment, access the monitoring services:

- **Grafana**: http://192.168.4.63:3000
- **Prometheus**: http://192.168.4.63:9090
- **Loki**: http://192.168.4.63:3100

## Configuration

The monitoring setup uses these key configuration files:

- `ansible/inventory.txt`: Node definitions and groups
- `ansible/templates/prometheus.yml.j2`: Prometheus scrape configuration
- `ansible/plays/monitoring/templates/`: Service configuration templates
- `ansible/files/grafana_*_dashboard.json`: Pre-built Grafana dashboards

## Features

✅ **Podman-native**: Uses Podman containers for all services  
✅ **Comprehensive metrics**: System and container monitoring  
✅ **Centralized logging**: All logs aggregated in Loki  
✅ **Pre-built dashboards**: Ready-to-use visualization  
✅ **Persistent storage**: Data survives container restarts  
✅ **Multi-node support**: Monitors entire cluster  
✅ **Local registry**: Custom container image support

## Troubleshooting

### Debug information collection:
```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/debug_collect.yaml
```

### Common issues:
- Ensure `/srv/monitoring_data` mount exists on monitoring node
- Check firewall rules for monitoring ports
- Verify Podman service is running on all nodes
- Check container logs: `podman logs <container_name>`

## Maintenance

### Update dashboards:
Edit JSON files in `ansible/files/grafana_*_dashboard.json` and redeploy.

### Add new metrics:
Update `ansible/templates/prometheus.yml.j2` and restart Prometheus.

### Backup monitoring data:
```bash
tar -czf monitoring-backup-$(date +%Y%m%d).tar.gz /srv/monitoring_data/
```
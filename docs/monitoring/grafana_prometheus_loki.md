# Monitoring Stack: Grafana, Prometheus, Loki

## Overview
- **Grafana** (port 3000): Dashboards and visualization with 4 pre-built dashboards
- **Prometheus** (port 9090): Metrics collection from all nodes  
- **Loki** (port 3100): Log aggregation with Promtail agents

## Pre-built Dashboards
1. **Node Metrics**: System monitoring (CPU, memory, disk, network)
2. **Podman Containers**: Container metrics and logs
3. **Prometheus Overview**: Monitoring system health
4. **Loki Logs**: Centralized log viewing and error detection

## Setup
- Use `ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml`
- All data stored in `/srv/monitoring_data` on monitoring_nodes
- Podman exporters enabled for container metrics

## Access
- Grafana: http://192.168.4.63:3000  
- Prometheus: http://192.168.4.63:9090
- Loki: http://192.168.4.63:3100

## Features
- ✅ Multi-node monitoring (monitoring, storage, compute nodes)
- ✅ Podman container metrics export
- ✅ Centralized logging with error detection
- ✅ Local container registry (port 5000)
- ✅ Persistent data storage

See `docs/monitoring/README.md` for complete documentation.

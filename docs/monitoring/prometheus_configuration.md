# Prometheus Dynamic Scrape Targets Configuration

This document describes how to configure Prometheus to dynamically scrape targets from all node groups with Podman exporters.

## Configuration Files

### ansible/group_vars/all.yml

Create this file to control Podman exporter behavior:

```yaml
---
# Global variables for all hosts
# Enable Podman exporters for container monitoring
enable_podman_exporters: true

# Port configuration for Podman system metrics
# Map the host port (configured via `podman_system_metrics_host_port`) to container port 9882.
# The repository default used in `ansible/group_vars/all.yml` is 19882.
podman_system_metrics_host_port: 19882
```

**Note**: This file is gitignored for security reasons. Create it locally as needed.

## Validation Steps

1. Create `ansible/group_vars/all.yml` with `enable_podman_exporters: true`
2. Run: `ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/install_node.yaml --check`
3. Verify rendered file contains targets for ports 19882 and 9300 for all node groups

## Expected Output

When `enable_podman_exporters: true`, the rendered `/srv/monitoring_data/prometheus/prometheus.yml` contains:

```yaml
scrape_configs:
  - job_name: 'node_exporters'
    static_configs:
      - targets:
        - '192.168.4.63:9100'  # monitoring_nodes
        - '192.168.4.61:9100'  # storage_nodes  
        - '192.168.4.62:9100'  # compute_nodes

  - job_name: 'podman_system_metrics'
    static_configs:
      - targets:
  - '192.168.4.63:19882'  # monitoring_nodes
  - '192.168.4.61:19882'  # storage_nodes
  - '192.168.4.62:19882'  # compute_nodes

  - job_name: 'podman_exporter'
    static_configs:
      - targets:
        - '192.168.4.63:9300'  # monitoring_nodes
        - '192.168.4.61:9300'  # storage_nodes
        - '192.168.4.62:9300'  # compute_nodes
```
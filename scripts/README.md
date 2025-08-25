# VMStation Monitoring Scripts

This directory contains utility scripts for diagnosing and fixing monitoring issues.

## Scripts

### `fix_podman_metrics.sh`
**Purpose**: Complete automated fix for podman_system_metrics container issues.

**Usage**:
```bash
./scripts/fix_podman_metrics.sh
```

**What it does**:
- Ensures local registry is running
- Pulls and publishes required container images
- Configures insecure registry access
- Stops conflicting processes
- Starts podman_system_metrics container
- Verifies the fix worked

### `podman_metrics_diagnostic.sh`
**Purpose**: Comprehensive diagnostic analysis for monitoring issues.

**Usage**:
```bash
./scripts/podman_metrics_diagnostic.sh
```

**What it reports**:
- System information and Podman version
- Network and port status
- Container status and logs
- Image availability
- Podman system state
- Manual container testing
- Firewall status
- Recommended actions

### `validate_monitoring.sh`
**Purpose**: Quick validation of entire monitoring stack health.

**Usage**:
```bash
./scripts/validate_monitoring.sh
```

**What it checks**:
- Core monitoring services (Prometheus, Grafana, Loki)
- Node exporters on all nodes
- Podman system metrics on all nodes
- Podman exporters on all nodes
- Prometheus target status
- Sample metrics collection
- Container status
- Provides access URLs and troubleshooting tips

## Common Issues

### Missing Configuration
If `ansible/group_vars/all.yml` doesn't exist:
```bash
# Copy template and customize
cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml
```

### podman_system_metrics exits immediately
1. Run `./scripts/fix_podman_metrics.sh`
2. If that fails, run `./scripts/podman_metrics_diagnostic.sh` for detailed analysis
3. Check logs: `podman logs podman_system_metrics`

### Port 19882 refuses connections
1. Check if service is running: `podman ps | grep podman_system_metrics`
2. Check port usage: `lsof -i :19882`
3. Run fix script: `./scripts/fix_podman_metrics.sh`

### Local registry issues
1. Check registry: `curl http://192.168.4.63:5000/v2/_catalog`
2. Restart registry: `podman restart local_registry`
3. Run full fix: `./scripts/fix_podman_metrics.sh`

## Quick Reference

```bash
# Full monitoring health check
./scripts/validate_monitoring.sh

# Fix podman metrics issues
./scripts/fix_podman_metrics.sh

# Detailed diagnostic
./scripts/podman_metrics_diagnostic.sh

# Deploy monitoring stack
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml

# Deploy only exporters
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/install_exporters.yaml
```
# Grafana Container Fix - Quick Reference

## Problem
Grafana container was not launching when running `./update_and_deploy` due to missing Ansible configuration variables.

## Root Cause
The `ansible/group_vars/all.yml` file was missing, causing undefined variable errors during deployment:
- `AnsibleUndefinedVariable: 'podman_system_metrics_host_port' is undefined`

## Solution Applied
Created `ansible/group_vars/all.yml` with required variables:

```yaml
enable_podman_exporters: true
podman_system_metrics_host_port: 19882
enable_quay_metrics: false
prometheus_port: 9090
grafana_port: 3000
loki_port: 3100
# ... (full config in the file)
```

## Verification Steps

1. **Run validation script:**
   ```bash
   ./scripts/validate_grafana_fix.sh
   ```

2. **Deploy the monitoring stack:**
   ```bash
   ./update_and_deploy
   ```

3. **Verify containers are running:**
   ```bash
   podman ps
   ```
   Expected to see: grafana, prometheus, loki, promtail_local, local_registry, node-exporter

4. **Access Grafana:**
   - URL: http://192.168.4.63:3000
   - Default credentials: admin/admin (first login)

## Expected Result
After deployment, `podman ps` should show the Grafana container running in the monitoring pod alongside other monitoring services.

## Additional Notes
- All Grafana dashboard files are included and will be automatically provisioned
- Datasources (Prometheus, Loki) are automatically configured
- The monitoring pod exposes Grafana on port 3000
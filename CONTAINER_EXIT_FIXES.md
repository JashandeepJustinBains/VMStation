# Container Exit Fix Documentation

## Problem Summary

The monitoring containers were exiting immediately after being started by the Ansible playbooks:
- `promtail_local` - Exited (1) 
- `promtail` - Exited (1)
- `podman_system_metrics` - Exited (0)
- `podman_exporter` - Exited (0)

## Root Causes Identified

1. **Missing Configuration Variables**: `ansible/group_vars/all.yml` was missing, causing undefined variables like `podman_system_metrics_host_port`.

2. **Promtail Configuration Mismatch**: The promtail configuration template was inconsistent between different playbooks:
   - `install_node.yaml` used `http://loki:3100` (missing push path)
   - `deploy_promtail.yaml` used the full push URL with `/loki/api/v1/push`

3. **Missing Podman Socket Access**: The `podman_system_metrics` container lacked access to the Podman socket (`/run/podman/podman.sock`) needed for metrics collection.

## Fixes Implemented

### 1. Created Configuration Template

**File**: `ansible/group_vars/all.yml.template`
- Provides template for all required variables
- Includes `podman_system_metrics_host_port: 19882`
- Includes `enable_podman_exporters: true`
- Documents security variables that should go in `secrets.yml`

### 2. Fixed Promtail Configuration Consistency

**File**: `ansible/plays/monitoring/install_node.yaml`
- Changed: `loki_url: "http://loki:{{ loki_port }}"` 
- To: `loki_url: "http://loki:{{ loki_port }}/loki/api/v1/push"`
- Now consistent with `deploy_promtail.yaml`

### 3. Added Podman Socket Mount

**File**: `ansible/plays/monitoring/install_exporters.yaml`
- Added volume mount: `/run/podman/podman.sock:/run/podman/podman.sock:Z`
- Enables `podman_system_metrics` to collect metrics from Podman API

### 4. Updated .gitignore

**File**: `.gitignore`
- Excludes `all.yml` but includes `all.yml.template`
- Maintains security while providing configuration guidance

### 5. Created Validation Script

**File**: `scripts/validate_container_fixes.sh`
- Validates all fixes are properly implemented
- Checks configuration templates and variable usage
- Runs Ansible syntax validation

## Usage Instructions

### Deploy the Fixed Monitoring Stack

1. **Copy Configuration Template**:
   ```bash
   cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml
   # Edit all.yml as needed for your environment
   ```

2. **Deploy Monitoring Stack**:
   ```bash
   ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml
   ```

3. **Verify Container Status**:
   ```bash
   podman ps
   ```

### Validate Fixes Before Deployment

```bash
./scripts/validate_container_fixes.sh
```

## Expected Results

After applying these fixes:

- **promtail containers** will successfully connect to Loki using the correct push URL
- **podman_system_metrics** will have socket access and provide metrics on port 19882
- **All containers** will have proper restart policies and stay running
- **Configuration errors** will be eliminated through proper variable definitions

## Troubleshooting

If containers still exit after applying fixes:

1. Check container logs: `podman logs <container_name>`
2. Verify configuration: `./scripts/validate_container_fixes.sh`
3. Run diagnostic: `./scripts/podman_metrics_diagnostic.sh`
4. Check network connectivity between containers

## Security Notes

- Never commit `ansible/group_vars/all.yml` with real credentials
- Use `ansible-vault` for sensitive variables in `secrets.yml`
- The template includes comments showing which variables should be vaulted
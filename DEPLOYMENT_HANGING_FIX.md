# Deployment Hanging Fix - Solution Summary

## Problem
The deployment script `./update_and_deploy.sh` was hanging at the task:
```
TASK [Install kube-prometheus-stack (Prometheus + Grafana)]
```

## Root Cause
The hanging was caused by three missing prerequisites:

1. **Missing Configuration File**: `ansible/group_vars/all.yml` didn't exist (only the template existed)
2. **Missing Monitoring Directories**: Required directories like `/srv/monitoring_data` with proper permissions weren't created
3. **No Prerequisite Setup**: The deployment attempted to install kube-prometheus-stack without ensuring the necessary directory structure and permissions were in place

## Solution Implemented

### 1. Automatic Configuration Creation
- Modified `update_and_deploy.sh` and `ansible/deploy.sh` to auto-create `ansible/group_vars/all.yml` from the template if missing
- Scripts now continue deployment instead of exiting after config creation
- Users get helpful messages about the configuration file creation

### 2. Monitoring Prerequisites Setup
- Created new playbook `ansible/plays/setup_monitoring_prerequisites.yaml` that:
  - Creates all required monitoring directories (`/srv/monitoring_data` and subdirectories)
  - Sets proper permissions (755) and ownership (root:root)
  - Handles SELinux contexts if SELinux is enabled
  - Provides detailed feedback about the setup process

### 3. Enhanced Permission Setup in Scripts
- Both deployment scripts now call `scripts/fix_monitoring_permissions.sh` before deployment
- Added sudo detection with graceful fallback if sudo isn't available
- Clear warnings and remediation steps if manual intervention is needed

### 4. Integrated into Deployment Flow
- Added the monitoring prerequisites setup to `ansible/site.yaml` to run before core infrastructure deployment
- Ensures prerequisites are established at the right time in the deployment sequence

## Files Modified

1. `update_and_deploy.sh` - Added config creation and permission setup
2. `ansible/deploy.sh` - Added config creation and permission setup
3. `ansible/site.yaml` - Added monitoring prerequisites playbook import
4. `ansible/subsites/03-monitoring.yaml` - Fixed ansible syntax issues
5. `ansible/plays/setup_monitoring_prerequisites.yaml` - New playbook for monitoring setup

## Testing

Run the test script to validate the fixes:
```bash
./test_deployment_fixes.sh
```

## Usage

The deployment should now work without hanging:
```bash
./update_and_deploy.sh
```

If you want to run just the monitoring prerequisites setup:
```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/setup_monitoring_prerequisites.yaml
```

## Verification

After deployment, you should see:
- Configuration file exists: `ansible/group_vars/all.yml`
- Monitoring directories exist with proper permissions: `/srv/monitoring_data/*`
- No hanging during kube-prometheus-stack installation
- Successful monitoring stack deployment
- Monitoring pods are automatically scheduled and running (no Pending state)

The deployment hanging issue should now be resolved.

## Additional Fixes

### Automatic Monitoring Pod Scheduling Fix

As of this update, the deployment process includes automatic fixes for common monitoring pod scheduling issues:

- **Node Taints**: Automatically removes control-plane taints on single-node clusters
- **Node Labels**: Automatically labels available nodes for monitoring workloads
- **Scheduling Constraints**: Falls back to unrestricted scheduling if pods remain pending

This is handled by the new `scripts/fix_monitoring_scheduling.sh` script that runs automatically during deployment.

If you encounter scheduling issues after deployment, you can manually run:
```bash
./scripts/fix_monitoring_scheduling.sh
```
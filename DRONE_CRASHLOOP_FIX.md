# Drone Pod Crash Loop Fix - Setup Guide

## Problem Summary
Multiple drone pods are running with CrashLoopBackOff status due to "source code management system not configured" error.

## Root Cause
- Duplicate drone deployments exist in the cluster
- GitHub OAuth secrets may not be properly deployed to Kubernetes
- update_and_deploy.sh was not configured to run the drone deployment playbook

## Solution Steps

### 1. Clean Up Existing Drone Deployments
First, remove any existing problematic drone deployments:

```bash
# Run the automated cleanup script
./scripts/cleanup_drone_deployments.sh
```

**Manual cleanup alternative:**
```bash
# Delete all drone deployments
kubectl delete deployment --all -n drone

# Delete drone services  
kubectl delete service --all -n drone

# Delete drone secrets
kubectl delete secret --all -n drone

# Wait for pods to terminate
kubectl wait --for=delete pods -l app=drone -n drone --timeout=60s
```

### 2. Verify Your Secrets Configuration
Ensure your `ansible/group_vars/secrets.yml` file contains the required drone variables:

```yaml
# Required drone secrets (replace with your actual values)
drone_github_client_id: "your_actual_github_oauth_client_id"
drone_github_client_secret: "your_actual_github_oauth_client_secret"  
drone_rpc_secret: "your_generated_rpc_secret"  # Generate with: openssl rand -hex 16
drone_server_host: "your_server_ip:32001"      # e.g., "192.168.4.62:32001"
```

**To create/edit secrets file:**
```bash
# If using ansible-vault (recommended)
ansible-vault edit ansible/group_vars/secrets.yml

# Or edit directly (less secure)
nano ansible/group_vars/secrets.yml
```

**GitHub OAuth App Setup:**
1. Go to https://github.com/settings/applications/new
2. Set these values:
   - Application name: `VMStation Drone CI`
   - Homepage URL: `http://192.168.4.62:32001` (replace with your node IP)
   - Authorization callback URL: `http://192.168.4.62:32001/login`
3. Copy the Client ID and Client Secret to your secrets.yml

### 3. Run the Drone Deployment
The update_and_deploy.sh script has been configured to deploy the 05-extra_apps.yaml playbook which handles drone deployment:

```bash
# Run the deployment script
./update_and_deploy.sh
```

This will:
- Fetch latest changes from git
- Run syntax check on the playbook
- Deploy drone with proper configuration
- Create exactly 1 drone pod (not multiple)

### 4. Verify the Fix
After deployment, verify that the drone pod is working:

```bash
# Check drone pod status (should be Running, not CrashLoopBackOff)
kubectl get pods -n drone

# Check drone logs (should not show SCM configuration errors)
kubectl logs -n drone -l app=drone

# Verify drone service is accessible
curl -I http://NODE_IP:32001
```

**Expected Results:**
- Single drone pod in "Running" status
- No "source code management system not configured" errors in logs
- Drone web interface accessible on port 32001

### 5. Troubleshooting

**If secrets are missing:**
```bash
# Validate drone configuration
./scripts/validate_drone_config.sh
```

**If playbook fails:**
```bash
# Run in check mode to see what would happen
ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml --check

# Run with increased verbosity for debugging
ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml -vv
```

**Manual playbook execution (alternative to update_and_deploy.sh):**
```bash
ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml
```

## Files Modified
- `update_and_deploy.sh` - Enabled 05-extra_apps.yaml playbook
- `ansible/group_vars/all.yml` - Created basic configuration variables
- `scripts/cleanup_drone_deployments.sh` - New cleanup script

## Technical Details
The 05-extra_apps.yaml playbook:
- Creates exactly 1 drone replica (not multiple)
- Validates that all required secrets exist before deployment
- Uses proper GitHub OAuth integration for source code management
- Schedules drone pod on homelab node
- Creates hostPath storage at /mnt/storage/drone

This ensures a single, properly configured drone pod instead of multiple crashing pods.
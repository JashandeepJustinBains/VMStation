# Drone Secrets Configuration Fix

## Problem
When running `update_and_deploy.sh`, the deployment hangs or fails when trying to configure drone secrets because:
1. No `ansible/group_vars/secrets.yml` file exists with proper drone configuration
2. The deployment requires drone secrets to be configured before proceeding
3. Users may encounter Kubernetes API rate limiting when checking for existing secrets

## Solution

### Option 1: Skip Drone Deployment (Recommended for Initial Setup)
If you want to deploy other VMStation components without configuring drone:

```bash
# Skip drone and deploy other components
SKIP_DRONE=true ./update_and_deploy.sh
```

Or for individual playbook runs:
```bash
SKIP_DRONE=true ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml
```

This will:
- Deploy Kubernetes Dashboard and MongoDB successfully
- Skip all drone-related tasks
- Show a clear message that drone was skipped
- Allow you to configure drone later

### Option 2: Configure Drone Secrets Properly
To properly configure drone secrets:

1. **Use the setup helper script:**
   ```bash
   ./scripts/setup_drone_secrets.sh
   ```

2. **Or manually create the secrets file:**
   ```bash
   # Create the secrets file from template
   cp ansible/group_vars/secrets.yml.example ansible/group_vars/secrets.yml
   
   # Edit with real values
   nano ansible/group_vars/secrets.yml
   ```

3. **Configure GitHub OAuth:**
   - Go to https://github.com/settings/applications/new
   - Create a new OAuth app with your server details
   - Add the client ID and secret to `secrets.yml`

4. **Deploy normally:**
   ```bash
   ./update_and_deploy.sh
   ```

## Key Benefits of This Fix
- **Non-blocking**: Other components can deploy even without drone configuration
- **Clear guidance**: Helpful error messages and troubleshooting steps
- **Flexible**: Choose when to configure drone based on your needs
- **Backward compatible**: Existing configurations continue to work

## Files Modified
- `ansible/subsites/05-extra_apps.yaml` - Added SKIP_DRONE conditions to all drone tasks
- `update_and_deploy.sh` - Added troubleshooting guidance for drone issues
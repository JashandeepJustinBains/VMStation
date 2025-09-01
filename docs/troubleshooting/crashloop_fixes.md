# Fixing CrashLoopBackOff Issues: Drone and Kubernetes Dashboard

This document provides step-by-step solutions for common CrashLoopBackOff issues in the VMStation Kubernetes cluster.

## Validation Fix (Updated)

**Issue**: The VMStation deployment validation was incorrectly checking for kubernetes-dashboard, drone, and mongodb on ALL hosts, causing validation failures and python library errors.

**Solution**: As of the latest update, the validation now runs only from the masternode and properly validates that services are deployed on their intended nodes:
- kubernetes-dashboard → masternode (192.168.4.63)
- drone → homelab (192.168.4.62) 
- mongodb → homelab (192.168.4.62)

**How to Validate**: Use the new validation script:
```bash
./scripts/validate_app_deployment.sh
```

Or run just the validation from the main playbook:
```bash
ansible-playbook -i ansible/inventory.txt ansible/site.yaml --tags validate
```

## Problem Summary

From the pod status output:
```
drone-f85cdf76f-x8949                                       0/1     CrashLoopBackOff   198 (3m12s ago)   14h
kubernetes-dashboard-fd69857ff-9hd75                        0/1     CrashLoopBackOff   12 (4m34s ago)    28m
```

## 1. Drone CI CrashLoopBackOff Fix

### Root Cause
The drone pod crashes because it lacks proper GitHub integration configuration and secrets.

**Common Error Messages:**
- `"main: source code management system not configured"` - This is the most common error, indicating missing GitHub OAuth credentials
- Pod status: `CrashLoopBackOff` or `Error`
- Deployment fails validation due to missing required secrets

**Why This Happens:**
- GitHub OAuth credentials are required for Drone CI to function as a source code management system
- Without these credentials, Drone cannot start properly and will fail with the SCM error
- The deployment now validates that all required secrets exist before starting the pod

### Solution Steps

#### Step 1: Create GitHub OAuth Application
1. Visit [GitHub OAuth Apps](https://github.com/settings/applications/new)
2. Fill in details:
   - **Application name**: `VMStation Drone CI`
   - **Homepage URL**: `http://192.168.4.62:32001` (replace with your node IP)
   - **Authorization callback URL**: `http://192.168.4.62:32001/login`
3. Note down the **Client ID** and **Client Secret**

#### Step 2: Configure Secrets

**Quick Setup (Recommended):**
Use the interactive setup script:
```bash
./scripts/setup_drone_secrets.sh
```

**Manual Setup:**
```bash
# Create or edit the vault secrets file
# Option 1: If you want to use ansible-vault encryption (recommended for production)
ansible-vault edit ansible/group_vars/secrets.yml

# Option 2: If you want to edit as plain text (for testing/development)
nano ansible/group_vars/secrets.yml

# Add these REQUIRED variables (all must be set for Drone to work):
drone_github_client_id: "your_actual_github_oauth_client_id"
drone_github_client_secret: "your_actual_github_oauth_client_secret"
drone_rpc_secret: "$(openssl rand -hex 16)"  # Generate a random secret
drone_server_host: "192.168.4.62:32001"     # Your actual node IP and port

# IMPORTANT: All four values above are required. The deployment will fail 
# with validation errors if any are missing or set to default/placeholder values.
# Do NOT use values starting with "REPLACE_WITH_" or "changeme" or "your_"
```

**Generate RPC Secret:**
```bash
openssl rand -hex 16
```

**GitHub OAuth Application Setup:**
1. Go to https://github.com/settings/applications/new
2. Set these values:
   - Application name: `VMStation Drone CI`
   - Homepage URL: `http://192.168.4.62:32001` (replace with your actual node IP)
   - Authorization callback URL: `http://192.168.4.62:32001/login`
3. Copy the **Client ID** and **Client Secret** to your secrets.yml file
   - Homepage URL: `http://your_node_ip:32001`
   - Authorization callback URL: `http://your_node_ip:32001/login`
3. Copy the Client ID and Client Secret to your secrets.yml file

#### Step 3: Deploy Updated Configuration
```bash
# Deploy with vault password
ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml --ask-vault-pass

# Or if you have a vault password file
ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml --vault-password-file ~/.vault_pass.txt
```

#### Step 4: Verify Fix
```bash
# Run the enhanced drone validation script (now detects SCM configuration errors)
./scripts/validate_drone_config.sh

# Check pod status - should be Running, not CrashLoopBackOff
kubectl get pods -n drone

# Check logs for successful startup
kubectl logs -n drone -l app=drone

# Test web interface accessibility  
curl -I http://your_node_ip:32001
```

**Expected Results:**
- Pod status: `Running` (not `CrashLoopBackOff`)
- Validation script shows: `✓ Drone configuration validation passed`
- No "source code management system not configured" errors in logs
- Web interface responds on port 32001

## 2. Kubernetes Dashboard CrashLoopBackOff Fix

### Root Cause
The dashboard crashes due to directory permission issues preventing certificate generation.

### Solution Steps

#### Step 1: Run Diagnostic
```bash
# Diagnose permission issues
./scripts/diagnose_monitoring_permissions.sh

# Run dashboard-specific diagnostic
./scripts/fix_k8s_dashboard_permissions.sh
```

#### Step 2: Apply Permission Fixes
```bash
# Option A: Automatic fix with the script
./scripts/fix_k8s_dashboard_permissions.sh --auto-approve

# Option B: Manual permission fix
# Find the node running the dashboard
kubectl get pods -n kubernetes-dashboard -o wide

# SSH to that node and run:
sudo mkdir -p /tmp/k8s-dashboard-certs
sudo chown -R 65534:65534 /tmp/k8s-dashboard-certs
sudo chmod -R 755 /tmp/k8s-dashboard-certs

# If SELinux is enabled:
sudo semanage fcontext -a -t container_file_t '/tmp/k8s-dashboard-certs(/.*)?'
sudo restorecon -R /tmp/k8s-dashboard-certs
```

#### Step 3: Restart Dashboard Pod
```bash
# Delete the failed pod (it will be recreated)
kubectl delete pod -n kubernetes-dashboard -l app=kubernetes-dashboard

# Or restart the deployment
kubectl rollout restart deployment kubernetes-dashboard -n kubernetes-dashboard
```

#### Step 4: Verify Fix
```bash
# Check pod status
kubectl get pods -n kubernetes-dashboard

# Check logs
kubectl logs -n kubernetes-dashboard -l app=kubernetes-dashboard

# Test access (replace with your node IP)
curl -k https://192.168.4.63:32000
```

## 3. Alternative Dashboard Configuration

If permission fixes don't work, you can disable auto-certificate generation:

```bash
# Patch deployment to use insecure mode
kubectl patch deployment kubernetes-dashboard -n kubernetes-dashboard --type='json' \
  -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/args"}]'

kubectl patch deployment kubernetes-dashboard -n kubernetes-dashboard --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args", "value": ["--namespace=kubernetes-dashboard", "--enable-insecure-login"]}]'
```

## 4. Validation Commands

### Check Overall Cluster Health
```bash
# Get all pods status
kubectl get pods -o wide --all-namespaces

# Check for CrashLoopBackOff pods
kubectl get pods -A --no-headers | grep CrashLoopBackOff

# Check events for errors
kubectl get events --sort-by='.lastTimestamp' -A
```

### Drone-Specific Validation
```bash
# Run comprehensive drone validation
./scripts/validate_drone_config.sh

# Check drone secrets
kubectl get secret drone-secrets -n drone -o yaml

# Test drone web interface
curl -I http://NODE_IP:32001
```

### Dashboard-Specific Validation
```bash
# Check dashboard pods
kubectl get pods -n kubernetes-dashboard

# Check service
kubectl get service -n kubernetes-dashboard

# Test dashboard access
curl -k https://NODE_IP:32000
```

## 5. Prevention for Future Deployments

### For Drone
1. Always configure GitHub OAuth before deployment
2. Use proper secret management with ansible-vault
3. Validate configuration with `./scripts/validate_drone_config.sh`

### For Dashboard
1. Ensure proper storage provisioner configuration
2. Use the fixed deployment manifest with proper security contexts
3. Run permission diagnostics before deployment

## 6. Troubleshooting

If issues persist:

1. **Check resource constraints**:
   ```bash
   kubectl top nodes
   kubectl describe node NODE_NAME
   ```

2. **Check storage issues**:
   ```bash
   kubectl get pv,pvc -A
   kubectl describe pvc PVC_NAME -n NAMESPACE
   ```

3. **Check detailed logs**:
   ```bash
   kubectl logs POD_NAME -n NAMESPACE --previous
   kubectl describe pod POD_NAME -n NAMESPACE
   ```

4. **Run comprehensive diagnostics**:
   ```bash
   ./scripts/diagnose_monitoring_permissions.sh
   ./scripts/validate_infrastructure.sh
   ```

## 7. Files Modified

- `ansible/group_vars/secrets.yml.example` - Added drone secret template
- `ansible/subsites/05-extra_apps.yaml` - Updated drone deployment with GitHub integration
- `scripts/fix_k8s_dashboard_permissions.sh` - New dashboard permission fix script
- `scripts/validate_drone_config.sh` - New drone validation script
- `scripts/diagnose_monitoring_permissions.sh` - Enhanced with dashboard checks

All scripts are executable and include comprehensive error checking and user guidance.
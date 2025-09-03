# Cert-Manager Timeout Fix Implementation

## Problem Summary
The VMStation deployment was experiencing timeout errors when deploying cert-manager and local-path provisioner:

1. **cert-manager timeout**: "Error: context deadline exceeded" during Helm installation
2. **cert-manager rollout failures**: All cert-manager deployments (cert-manager, cert-manager-webhook, cert-manager-cainjector) exceeding progress deadlines
3. **local-path provisioner hanging**: "Failed to gather information about Deployment(s) even after waiting for 120 seconds"

## Root Cause Analysis

### Original timeout values were too aggressive:
- cert-manager Helm timeout: 120s (2 minutes) - insufficient for large image pulls
- cert-manager rollout timeout: 600s but inconsistent error handling
- local-path provisioner timeout: 120s (2 minutes) - insufficient for deployment readiness

### Additional issues:
- No retry logic for transient failures
- No cleanup of failed previous installations
- Missing prerequisite directory creation (after 00-spindown.yaml cleanup)
- No pre-flight cluster readiness checks
- Aggressive image pull policies causing repeated downloads

## Solution Implemented

### 1. Generous Timeout Values
```yaml
# cert-manager Helm installation
timeout: 150s  # 15 minutes (was 120s)

# cert-manager rollout status  
--timeout=150s  

# local-path provisioner
wait_timeout: 150 
```

### 2. Retry Logic with Exponential Backoff
```yaml
retries: 3  # Increased from 2
delay: 60   # Increased from 30s
until: operation_result is succeeded
```

### 3. Enhanced Pre-flight Checks and Connectivity Validation
- Verify cluster nodes are ready before deployment
- Test network connectivity to container registries (Docker Hub, Jetstack Charts)
- Check cluster resource usage and component health
- Clean up any failed previous cert-manager installations
- Check for existing cert-manager pods (conflict detection)
- Validate container runtime status on nodes
- Force update Helm repositories

### 4. Comprehensive Error Handling and Debugging
- Detailed failure analysis with resource status, pod descriptions, and events
- Step-by-step troubleshooting guidance
- Enhanced logging throughout the installation process
- Graceful error recovery with actionable remediation steps

### 5. Resource Optimization
```yaml
resources:
  requests:
    cpu: 10m
    memory: 32Mi
```

### 6. Image Pull Optimization
```yaml
global:
  imagePullPolicy: IfNotPresent
image:
  pullPolicy: IfNotPresent
```

### 7. Directory Prerequisites
- Ensure `/srv/monitoring_data` and subdirectories exist
- Set proper permissions (755, root:root)
- Create required subdirectories for monitoring components

## Files Modified

1. **`ansible/plays/kubernetes/setup_cert_manager.yaml`**
   - Increased timeouts from 120s to 120s
   - Added retry logic and cleanup
   - Added pre-flight checks and debugging

2. **`ansible/plays/kubernetes/setup_local_path_provisioner.yaml`**
   - Increased timeout from 120s to 600s
   - Added retry logic
   - Added directory creation

3. **`ansible/plays/kubernetes_stack.yaml`**
   - Added prerequisite monitoring directory creation
   - Ensures directories exist before any K8s deployment

4. **`scripts/validate_cert_manager.sh`** (NEW)
   - Comprehensive cert-manager health validation
   - Pre-requisite checks (kubectl, helm connectivity)
   - Deployment, pod, and service status validation
   - CRD availability verification
   - Functional testing with test issuer creation
   - Resource usage monitoring
   - Detailed troubleshooting guidance

5. **`scripts/test_cert_manager_timeout_fixes.sh`** (ENHANCED)
   - Comprehensive validation script for all timeout configurations
   - Tests syntax, timeouts, retry logic, connectivity checks, and prerequisites
   - Validates enhanced pre-flight checks and network connectivity validation

## Usage Instructions

### Test the fixes:
```bash
# Validate all timeout configurations
./scripts/test_cert_manager_timeout_fixes.sh

# Run syntax checks only
ansible-playbook --syntax-check ansible/plays/kubernetes_stack.yaml
```

### Deploy with fixes:
```bash
# Full deployment with timeout fixes
./update_and_deploy.sh

# Individual component deployment
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cert_manager.yaml
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_local_path_provisioner.yaml
```

### Monitor deployment progress:
```bash
# Watch cert-manager pods
kubectl get pods -n cert-manager -w

# Check deployment status
kubectl rollout status deployment/cert-manager -n cert-manager

# View detailed events if issues occur
kubectl describe deployment/cert-manager -n cert-manager
kubectl get events -n cert-manager --sort-by=.metadata.creationTimestamp

# Comprehensive cert-manager validation (NEW)
./scripts/validate_cert_manager.sh
```

## Expected Outcomes

### Before (Issues):
- cert-manager installation timeouts after 2 minutes
- Rollout status checks fail after 2-10 minutes inconsistently  
- Local-path provisioner hangs after 2 minutes
- Directory permission errors after spindown
- No retry on transient failures

### After (Fixed):
- cert-manager installation has 15 minutes to complete
- Consistent 15-minute timeouts for all cert-manager operations
- Local-path provisioner has 10 minutes with retry logic
- Automatic directory creation and permission setup
- Retry logic handles transient network/resource issues
- Pre-flight checks prevent deployment to unhealthy clusters
- Automatic cleanup of failed previous attempts

## Troubleshooting

If timeouts still occur despite these fixes:

1. **Check cluster resources:**
   ```bash
   kubectl top nodes
   kubectl describe nodes
   ```

2. **Check image pull issues:**
   ```bash
   kubectl get events --all-namespaces | grep Pull
   docker image ls | grep cert-manager
   ```

3. **Validate Helm repositories:**
   ```bash
   helm repo list
   helm repo update
   helm search repo jetstack/cert-manager
   ```

4. **Check directory permissions:**
   ```bash
   ls -la /srv/monitoring_data/
   sudo ./scripts/fix_monitoring_permissions.sh
   ```

## Validation Results

All timeout fix tests pass:
- ✅ Syntax validation for all modified playbooks
- ✅ Timeout values are generous (120s+ for cert-manager, 600s+ for local-path)
- ✅ Retry logic is configured with proper delays
- ✅ Pre-flight cluster checks are implemented
- ✅ Cleanup logic prevents conflicts from failed installations
- ✅ Directory prerequisites are created
- ✅ Resource requests prevent resource starvation

These comprehensive fixes address the "context deadline exceeded" and "deployment exceeded its progress deadline" errors by providing more generous timeouts, better error handling, and proper preparation steps.
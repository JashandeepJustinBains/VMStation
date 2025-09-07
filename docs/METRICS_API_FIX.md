# Kubernetes Metrics API Fix

## Problem
The VMStation deployment was failing with the error:
```
TASK [Get node resource usage] *************************************************************************
fatal: [192.168.4.63]: FAILED! => {"changed": true, "cmd": ["kubectl", "top", "nodes", "--kubeconfig", "/root/.kube/config", "--no-headers"], "delta": "0:00:00.060483", "end": "2025-09-06 20:23:31.847252", "msg": "non-zero return code", "rc": 1, "start": "2025-09-06 20:23:31.786769", "stderr": "error: Metrics API not available", "stderr_lines": ["error: Metrics API not available"], "stdout": "", "stdout_lines": []}
...ignoring
```

## Root Cause
The Kubernetes cluster did not have a metrics-server deployed, which is required for:
- `kubectl top nodes` commands
- `kubectl top pods` commands
- Resource monitoring and metrics collection
- Proper cluster resource visibility

## Solution Implemented

### 1. Added metrics-server Helm repository
**File**: `ansible/plays/kubernetes/setup_helm.yaml`
- Added metrics-server repository: `https://kubernetes-sigs.github.io/metrics-server/`
- Repository is added during Helm setup before any deployments

### 2. Deploy metrics-server before cert-manager
**File**: `ansible/plays/kubernetes/setup_helm.yaml`
- Added metrics-server deployment task
- Configured with appropriate flags for development environments:
  - `--kubelet-insecure-tls` for test environments
  - `--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname`
  - `--metric-resolution=15s`
- Added proper resource limits and requests
- Added readiness verification before proceeding

### 3. Improved error handling
**File**: `ansible/plays/kubernetes/setup_cert_manager.yaml`
- Enhanced error messages when Metrics API is not available
- Added context about metrics-server startup delays
- Made failure messages more informative for troubleshooting

## Deployment Order
The fix ensures this sequence:
1. **setup_cluster.yaml** - Sets up Kubernetes cluster
2. **setup_helm.yaml** - Deploys Helm + metrics-server ✅
3. **setup_cert_manager.yaml** - Now has Metrics API available ✅
4. **setup_local_path_provisioner.yaml**
5. **deploy_monitoring.yaml** - Monitoring stack

## Testing
All changes have been validated with:
- Ansible syntax checks
- Deployment order verification
- No duplicate deployments
- Comprehensive test suite

## Expected Results
After this fix:
- ✅ `kubectl top nodes` commands will work
- ✅ `kubectl top pods` commands will work  
- ✅ Resource monitoring will be functional
- ✅ No more "Metrics API not available" errors
- ✅ Cert-manager setup will complete successfully

## Files Modified
- `ansible/plays/kubernetes/setup_helm.yaml` - Added metrics-server repo and deployment
- `ansible/plays/kubernetes/setup_cert_manager.yaml` - Improved error messaging

## Configuration Details
```yaml
# metrics-server deployment configuration
args:
  - --cert-dir=/tmp
  - --secure-port=4443
  - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
  - --kubelet-use-node-status-port
  - --metric-resolution=15s
  - --kubelet-insecure-tls  # For development environments

resources:
  requests:
    cpu: 100m
    memory: 200Mi
  limits:
    cpu: 1000m
    memory: 1000Mi
```

This fix resolves the "Metrics API not available" error and enables full resource monitoring capabilities in the VMStation Kubernetes deployment.
# VMStation API Server Authorization Mode Fix

## Problem Description

The VMStation Kubernetes cluster was experiencing critical issues with the API server:

1. **API Server Health Check Failures**: The `kube-apiserver-masternode` pod was running but not Ready, with startup and readiness probes failing with HTTP 401 Unauthorized errors
2. **Insecure Authorization Mode**: The API server was configured with `--authorization-mode=AlwaysAllow`, which is insecure and paradoxically causing health endpoint failures
3. **RBAC Permission Issues**: kubernetes-admin user lacked proper cluster-admin permissions
4. **Worker Join Failures**: Worker nodes could not join the cluster due to API server instability

## Root Cause Analysis

From the pod description, the API server was running with these problematic settings:
```yaml
Command:
  - --authorization-mode=AlwaysAllow  # ← This is the core issue
```

The AlwaysAllow mode was causing:
- Health endpoints (`/livez`, `/readyz`) to return 401 Unauthorized
- Inconsistent authentication behavior
- RBAC system confusion
- Startup probe failures (24 attempts failing)

## Solution Implemented

### 1. Automatic Authorization Mode Detection and Fix

```yaml
- name: "Check current authorization mode"
  shell: >
    kubectl get pods -n kube-system kube-apiserver-* -o jsonpath='{.items[0].spec.containers[0].command}' | 
    grep -o '\--authorization-mode=[^[:space:]]*' | 
    cut -d= -f2
  register: current_auth_mode

- name: "Fix API server authorization mode if using AlwaysAllow"
  block:
    - name: "Backup API server manifest"
      copy:
        src: /etc/kubernetes/manifests/kube-apiserver.yaml
        dest: /etc/kubernetes/manifests/kube-apiserver.yaml.backup
        remote_src: yes

    - name: "Update authorization mode from AlwaysAllow to Node,RBAC"
      replace:
        path: /etc/kubernetes/manifests/kube-apiserver.yaml
        regexp: '--authorization-mode=AlwaysAllow'
        replace: '--authorization-mode=Node,RBAC'
```

### 2. API Server Health Verification

```yaml
- name: "Wait for API server pod to be Ready"
  shell: |
    kubectl get pods -n kube-system -l component=kube-apiserver \
      -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' | grep -q "True"
  register: api_pod_ready
  retries: 20
  delay: 15
  until: api_pod_ready.rc == 0
```

### 3. Proper RBAC Configuration

```yaml
- name: "Apply RBAC fix after authorization mode change"
  shell: |
    kubectl create clusterrolebinding kubernetes-admin \
      --clusterrole=cluster-admin \
      --user=kubernetes-admin \
      --dry-run=client -o yaml | kubectl apply -f -
```

### 4. Enhanced Join Command Generation

```yaml
- name: "Generate join command"
  shell: kubeadm token create --print-join-command
  register: join_command
  retries: 3
  delay: 10
  until: join_command.rc == 0
```

## Standalone Fix Script

A comprehensive standalone fix script is also provided: `fix_api_server_authorization.sh`

This script can be run directly on the control plane node to:
1. Detect the current authorization mode
2. Fix AlwaysAllow mode to secure Node,RBAC
3. Verify API server health and readiness
4. Restore proper RBAC permissions
5. Test join command generation

## Testing

Run the comprehensive test suite:

```bash
# Test the basic RBAC fix
./test_rbac_fix.sh

# Test the complete API server authorization fix
./test_api_server_authorization_fix.sh

# Test the deployment failure fix
./test_deployment_failure_fix.sh
```

## Expected Results

After applying this fix:

- ✅ API server runs with secure `Node,RBAC` authorization mode
- ✅ API server pod shows `Ready: True` status
- ✅ Health endpoints (`/livez`, `/readyz`) return 200 OK
- ✅ kubernetes-admin has proper cluster-admin permissions
- ✅ `kubeadm token create --print-join-command` works reliably
- ✅ Worker nodes can successfully join the cluster
- ✅ No more startup probe failures or 401 Unauthorized errors

## Files Modified

- `ansible/plays/setup-cluster.yaml` - Added comprehensive authorization mode fix logic
- `fix_api_server_authorization.sh` - Standalone fix script for immediate resolution
- `test_api_server_authorization_fix.sh` - Comprehensive test suite
- `test_rbac_fix.sh` - Updated with correct grep patterns

## Security Impact

This fix **improves** security by:
- Removing the insecure `AlwaysAllow` authorization mode
- Implementing proper `Node,RBAC` authorization
- Ensuring kubernetes-admin has appropriate permissions through proper ClusterRoleBinding
- Maintaining audit trails and access controls

The cluster moves from an insecure state to a properly secured Kubernetes cluster with standard RBAC controls.
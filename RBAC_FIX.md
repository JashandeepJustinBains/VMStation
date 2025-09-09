# VMStation RBAC Permission Fix

## Problem Description

The VMStation deployment was failing during the "Generate join command" task with the following error:

```
kubeadm token create --print-join-command
"timed out waiting for the condition"

secrets "bootstrap-token-xxx" is forbidden: User "kubernetes-admin" cannot get resource "secrets" in API group "" in the namespace "kube-system"
secrets is forbidden: User "kubernetes-admin" cannot create resource "secrets" in API group "" in the namespace "kube-system"
```

## Root Cause

After `kubeadm init`, the kubernetes-admin user was not properly bound to the cluster-admin role, preventing it from creating the bootstrap tokens needed for worker node joins.

## Solution

Added RBAC validation and fix logic to `ansible/plays/setup-cluster.yaml`:

### 1. RBAC Permission Validation

```yaml
- name: "Validate kubernetes-admin RBAC permissions"
  shell: >
    kubectl auth can-i create secrets --namespace=kube-system
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  register: rbac_check
  failed_when: false
```

### 2. Automatic RBAC Fix

```yaml
- name: "Fix kubernetes-admin RBAC if needed"
  shell: |
    kubectl create clusterrolebinding kubernetes-admin \
      --clusterrole=cluster-admin \
      --user=kubernetes-admin \
      --dry-run=client -o yaml | kubectl apply -f -
  environment:
    KUBECONFIG: /etc/kubernetes/admin.conf
  when: rbac_check.stdout != "yes"
```

### 3. Enhanced Join Command Generation

```yaml
- name: "Generate join command"
  shell: kubeadm token create --print-join-command
  register: join_command
  retries: 3
  delay: 10
  until: join_command.rc == 0
```

## Changes Made

1. **Pre-validation**: Check if kubernetes-admin can create secrets in kube-system
2. **Auto-fix**: Create/update the cluster-admin ClusterRoleBinding if needed
3. **Retry logic**: Add 3 retries with 10-second delays for join command generation
4. **Error handling**: Graceful handling of permission issues

## Testing

Run the validation test:

```bash
./test_rbac_fix.sh
```

## Expected Results

- ✅ Deployment no longer fails on "Generate join command"
- ✅ kubernetes-admin has proper cluster-admin permissions
- ✅ Bootstrap token creation works reliably
- ✅ Worker nodes can successfully join the cluster

## Files Modified

- `ansible/plays/setup-cluster.yaml` - Added RBAC validation and fix logic
- `test_rbac_fix.sh` - Created comprehensive test suite

This minimal fix resolves the deployment issue without requiring extensive changes to the codebase.
# VMStation API Server Fix - Usage Instructions

## Quick Fix for Immediate Resolution

If you have an API server that's failing health checks with HTTP 401 errors:

### Option 1: Standalone Fix Script (Immediate)

```bash
# On the control plane node, run as root:
sudo ./fix_api_server_authorization.sh
```

This script will:
1. ✅ Detect if API server is using insecure AlwaysAllow mode
2. ✅ Safely backup and update the API server manifest  
3. ✅ Wait for API server to restart with secure authorization
4. ✅ Verify API server pod becomes Ready
5. ✅ Restore proper RBAC permissions
6. ✅ Test join command generation

### Option 2: Ansible Deployment (Integrated)

```bash
# Deploy the full cluster with the integrated fix:
ansible-playbook -i inventory.txt ansible/plays/setup-cluster.yaml
```

The Ansible playbook now includes:
- Automatic authorization mode detection
- Conditional fixing of AlwaysAllow mode
- API server health verification
- Enhanced retry logic for all operations

## Symptoms This Fix Addresses

```
❌ kube-apiserver pod shows "Running" but "Ready: False"
❌ Startup probe failures: "HTTP probe failed with statuscode: 401"
❌ Health endpoints returning 401 Unauthorized  
❌ kubeadm token create commands timing out
❌ Worker nodes failing to join with "Unauthorized" errors
❌ API server configured with --authorization-mode=AlwaysAllow
```

## After the Fix

```
✅ kube-apiserver pod shows "Ready: True"
✅ Health endpoints return 200 OK
✅ Authorization mode is secure "Node,RBAC"
✅ kubeadm token create works reliably
✅ Worker nodes can join successfully
✅ kubernetes-admin has proper cluster-admin permissions
```

## Testing

Verify the fix worked:

```bash
# Test the implementation
./test_api_server_authorization_fix.sh

# Test RBAC functionality  
./test_rbac_fix.sh

# Check API server health manually
kubectl get pods -n kube-system -l component=kube-apiserver
kubectl get nodes
kubeadm token create --print-join-command
```

## Troubleshooting

If issues persist:

1. **Check API server logs**:
   ```bash
   kubectl logs -n kube-system -l component=kube-apiserver
   ```

2. **Verify authorization mode**:
   ```bash
   kubectl get pods -n kube-system kube-apiserver-* -o yaml | grep authorization-mode
   ```

3. **Check RBAC permissions**:
   ```bash
   kubectl auth can-i create secrets --namespace=kube-system
   ```

4. **Manual recovery** (if needed):
   ```bash
   # Restore from backup
   sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml.backup /etc/kubernetes/manifests/kube-apiserver.yaml
   
   # Re-run the fix
   sudo ./fix_api_server_authorization.sh
   ```

## Safety Features

- ✅ **Automatic backup**: Original manifest saved before changes
- ✅ **Health verification**: Waits for API server to be ready before proceeding  
- ✅ **Retry logic**: Multiple attempts with exponential backoff
- ✅ **Rollback capability**: Can restore from backup if needed
- ✅ **Non-destructive**: Only fixes the specific authorization issue
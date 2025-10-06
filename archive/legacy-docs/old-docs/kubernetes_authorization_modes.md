# Kubernetes Authorization Mode Configuration

VMStation now supports configurable authorization modes for the Kubernetes API server to address RBAC issues that may prevent worker nodes from joining the cluster.

## Configuration Options

### Authorization Mode Settings

Add these variables to your `ansible/group_vars/all.yml`:

```yaml
# Controls the authorization mode for the Kubernetes API server
# Options:
#   'Node,RBAC' - Default secure mode with Node and RBAC authorization (recommended)
#   'AlwaysAllow' - Allows all API requests (less secure, use only for troubleshooting)
#   'RBAC' - Only RBAC authorization
kubernetes_authorization_mode: "Node,RBAC"

# Enable automatic fallback to AlwaysAllow mode if Node,RBAC fails during init
# This can help with initial cluster setup issues but should be disabled for production
kubernetes_authorization_fallback: false
```

### Default Behavior

If these variables are not set:
- **Authorization Mode**: Defaults to `Node,RBAC` (secure, recommended)
- **Fallback**: Disabled (no automatic fallback)

## Usage Scenarios

### 1. Default Secure Setup (Recommended)

```yaml
kubernetes_authorization_mode: "Node,RBAC"
kubernetes_authorization_fallback: false
```

This provides the most secure configuration with proper RBAC enforcement.

### 2. Troubleshooting Setup Issues

```yaml
kubernetes_authorization_mode: "Node,RBAC" 
kubernetes_authorization_fallback: true
```

If cluster initialization fails with `Node,RBAC`, the system will automatically retry with `AlwaysAllow` mode and display a warning.

### 3. Temporary AlwaysAllow Mode

```yaml
kubernetes_authorization_mode: "AlwaysAllow"
kubernetes_authorization_fallback: false
```

**WARNING**: This disables authorization checks entirely. Use only for troubleshooting and switch back to `Node,RBAC` once issues are resolved.

## Enhanced RBAC Handling

The system now includes intelligent RBAC handling:

1. **Authorization Mode Detection**: Automatically detects the current authorization mode
2. **Conditional RBAC Fixes**: Only applies RBAC fixes when running in RBAC-enabled modes
3. **AlwaysAllow Skip**: Skips RBAC operations when running in `AlwaysAllow` mode
4. **Clear Warnings**: Displays warnings when less secure modes are active

## Troubleshooting

### Worker Nodes Cannot Join

If you're experiencing issues with worker nodes joining the control plane:

1. **Start with secure mode**:
   ```yaml
   kubernetes_authorization_mode: "Node,RBAC"
   kubernetes_authorization_fallback: false
   ```

2. **If issues persist, enable fallback**:
   ```yaml
   kubernetes_authorization_mode: "Node,RBAC"
   kubernetes_authorization_fallback: true
   ```

3. **Check cluster status after deployment**:
   ```bash
   kubectl get nodes
   kubectl get pods -n kube-system
   ```

4. **Verify authorization mode**:
   ```bash
   kubectl get pods -n kube-system kube-apiserver-* -o jsonpath='{.items[0].spec.containers[0].command}' | grep authorization-mode
   ```

### RBAC Permission Issues

The system automatically:
- Validates `kubernetes-admin` user permissions
- Creates necessary ClusterRoleBindings if missing
- Provides clear feedback about permission issues

### Migration from AlwaysAllow to Node,RBAC

If you need to transition from `AlwaysAllow` back to secure mode:

1. Update configuration:
   ```yaml
   kubernetes_authorization_mode: "Node,RBAC"
   ```

2. **Note**: This requires cluster reinitialization as authorization mode cannot be changed on a running cluster.

## Security Considerations

- **Production environments**: Always use `Node,RBAC` mode
- **Fallback mode**: Disable in production (`kubernetes_authorization_fallback: false`)
- **AlwaysAllow mode**: Only for troubleshooting, never for production
- **Regular audits**: Periodically verify your cluster is running in secure mode

## Testing

Run the authorization mode tests to verify your configuration:

```bash
./test_authorization_mode_fix.sh
```

This validates:
- Configuration variables are properly set
- kubeadm init uses the correct authorization mode
- RBAC fixes are applied appropriately
- Fallback mechanisms work as expected
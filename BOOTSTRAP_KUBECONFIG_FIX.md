# Bootstrap Kubeconfig Configuration Fix

## Problem

Nodes that have already joined the Kubernetes cluster were configured with kubelet systemd service that references `--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf`, causing kubelet startup failures because:

1. The bootstrap kubeconfig file is only needed during the initial join process
2. After successful join, nodes should only use `--kubeconfig=/etc/kubernetes/kubelet.conf`
3. The bootstrap file may not exist or be accessible after the join process completes

## Root Cause

The kubelet systemd configuration in `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf` was hardcoded to always include:

```bash
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
```

This caused issues when:
- Nodes had already joined but kubelet service was restarted
- The bootstrap-kubelet.conf file was missing or inaccessible
- Playbook was re-run on already-joined nodes

## Solution

### Conditional Bootstrap Configuration

The fix implements conditional logic that:

1. **Detects join status** by checking for `/etc/kubernetes/kubelet.conf`
2. **Uses bootstrap config** only for nodes that haven't joined yet
3. **Uses regular config** only for nodes that have already joined

### Implementation Details

#### For New/Not-Yet-Joined Nodes:
```yaml
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
```

#### For Already-Joined Nodes:
```yaml
Environment="KUBELET_KUBECONFIG_ARGS=--kubeconfig=/etc/kubernetes/kubelet.conf"
```

### Recovery Mechanism

Added automatic detection and fix for nodes stuck with incorrect bootstrap configuration:

1. **Detects bootstrap errors** in kubelet logs
2. **Checks join status** vs current systemd configuration
3. **Automatically fixes** mismatched configurations
4. **Restarts services** with correct configuration

## Testing

The fix includes comprehensive test validation:

```bash
./test_bootstrap_kubeconfig_fix.sh
```

Tests verify:
- Conditional configuration logic
- Proper bootstrap config inclusion/exclusion
- Recovery mechanisms
- Syntax correctness

## Benefits

- **Eliminates bootstrap config errors** on already-joined nodes
- **Maintains compatibility** with initial join process
- **Provides automatic recovery** for misconfigured nodes
- **Reduces manual intervention** required for stuck nodes

## Usage

### Automatic Application
The fix is automatically applied when running:
```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml
```

### Manual Recovery
For nodes already experiencing issues:
```bash
# Check if node has bootstrap config issues
ssh <node> "journalctl -u kubelet -n 50 | grep bootstrap-kubelet.conf"

# Re-run the setup playbook to apply the fix
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml
```

### Verification
After applying the fix:
```bash
# Check kubelet status
ssh <node> "systemctl status kubelet"

# Verify correct configuration
ssh <node> "cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

# Check for bootstrap references (should be none for joined nodes)
ssh <node> "grep -i bootstrap /etc/systemd/system/kubelet.service.d/10-kubeadm.conf || echo 'No bootstrap config found'"
```

## Related Issues

This fix addresses the specific issue where:
- Node 192.168.4.62 fails to start kubelet with bootstrap config errors
- Other nodes in the same cluster work fine
- All nodes were provisioned with the same playbook
- The failing node requires `--bootstrap-kubeconfig` while others don't

## Files Modified

- `ansible/plays/kubernetes/setup_cluster.yaml` - Main configuration logic
- `test_bootstrap_kubeconfig_fix.sh` - Validation tests
- Documentation updates

## Backwards Compatibility

The fix maintains full backwards compatibility:
- Initial join process works unchanged
- Already-joined nodes get corrected configuration
- No impact on working nodes
- No manual intervention required
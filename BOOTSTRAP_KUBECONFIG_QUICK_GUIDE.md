# Bootstrap Kubeconfig Fix - Quick Usage Guide

## Problem

Node 192.168.4.62 fails to start kubelet with errors like:
- "failed to load bootstrap kubeconfig"
- "bootstrap-kubelet.conf: no such file or directory"

While other nodes in the cluster work fine.

## Quick Fix

### Automatic Fix (Recommended)
```bash
# Run the enhanced setup playbook - it will automatically detect and fix the issue
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml
```

### Manual Verification
```bash
# Use the verification script to check and fix the specific node
./verify_bootstrap_fix.sh 192.168.4.62 192.168.4.63
```

### Test the Fix
```bash
# Validate the fix implementation
./test_bootstrap_kubeconfig_fix.sh
```

## What the Fix Does

1. **Detects** if a node has already joined the cluster
2. **Configures** kubelet appropriately:
   - **Not joined yet**: Uses bootstrap config for initial join
   - **Already joined**: Uses only regular kubelet.conf (no bootstrap)
3. **Recovers** nodes stuck with wrong configuration
4. **Restarts** services with correct settings

## Verification Commands

```bash
# Check if node has joined
ssh 192.168.4.62 "ls -la /etc/kubernetes/kubelet.conf"

# Check current kubelet config
ssh 192.168.4.62 "cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"

# Check kubelet status
ssh 192.168.4.62 "systemctl status kubelet"

# For joined nodes, this should return nothing (no bootstrap config):
ssh 192.168.4.62 "grep bootstrap /etc/systemd/system/kubelet.service.d/10-kubeadm.conf || echo 'No bootstrap config (correct)'"
```

## Expected Results

After the fix:
- ✅ Kubelet starts successfully on all nodes
- ✅ Joined nodes don't reference bootstrap config
- ✅ New nodes can still join normally
- ✅ No manual intervention required

## Files Added/Modified

- `ansible/plays/kubernetes/setup_cluster.yaml` - Main fix logic
- `test_bootstrap_kubeconfig_fix.sh` - Automated testing
- `verify_bootstrap_fix.sh` - Manual verification
- `BOOTSTRAP_KUBECONFIG_FIX.md` - Detailed documentation
- `docs/RHEL10_TROUBLESHOOTING.md` - Updated troubleshooting guide

## Support

If the automatic fix doesn't work:
1. Run the verification script: `./verify_bootstrap_fix.sh 192.168.4.62`
2. Check the detailed documentation: `BOOTSTRAP_KUBECONFIG_FIX.md`
3. Review troubleshooting guide: `docs/RHEL10_TROUBLESHOOTING.md`
# Kubernetes Service Enablement Fix

## Problem Statement

After running tests or troubleshooting activities, critical Kubernetes services may become disabled:

```bash
[jashandeepjustinbains@homelab ~]$ systemctl list-unit-files --no-pager 'kube*' 'containerd' 'flanneld*' --all
UNIT FILE       STATE    PRESET
kubelet.service disabled disabled

1 unit files listed.
```

This causes Kubernetes cluster functionality to break, with symptoms including:
- kubelet service won't start automatically on boot
- containerd runtime may be stopped
- Worker nodes fail to join or maintain cluster membership
- Flannel network pods may not be running

## Root Cause

The services were manually disabled during testing or troubleshooting but were not re-enabled, causing:

1. **kubelet.service disabled**: Prevents Kubernetes node from functioning
2. **containerd.service stopped/disabled**: Prevents container runtime from working  
3. **Flannel issues**: Network pods may be down (flannel runs as pods, not systemd services)
4. **CNI configuration problems**: Missing or misconfigured CNI plugins

## Solution Implemented

### New Fix Script: `scripts/fix_kubernetes_service_enablement.sh`

This script provides comprehensive service recovery:

#### Phase 1: Service Status Check and Fix
- **Detects disabled services**: Checks `systemctl is-enabled` status
- **Enables services**: Runs `systemctl enable` for disabled services  
- **Starts services**: Runs `systemctl start` for inactive services
- **Verifies results**: Confirms services are active and enabled

#### Phase 2: Flannel Network Check
- **Pod status check**: Examines Flannel DaemonSet and pod status
- **Cluster connectivity**: Tests kubectl access to cluster
- **Guidance**: Provides commands to restart Flannel pods if needed

#### Phase 3: CNI Configuration Check  
- **Directory validation**: Checks `/etc/cni/net.d` and `/opt/cni/bin`
- **File presence**: Verifies CNI configuration files exist
- **Troubleshooting guidance**: Suggests fixes for missing CNI components

## Usage

### Automatic Fix (Recommended)
```bash
./scripts/fix_kubernetes_service_enablement.sh
```

### Manual Steps (if automatic fix fails)
```bash
# Enable and start services manually
sudo systemctl enable kubelet containerd
sudo systemctl start kubelet containerd

# Verify status
systemctl status kubelet containerd

# Check Flannel pods  
kubectl get pods -n kube-flannel

# Restart Flannel if needed
kubectl delete pods -n kube-flannel -l app=flannel
```

### Integration with Existing Workflow
The fix can be run before or after the main deployment:
```bash
# Fix services first, then run deployment
./scripts/fix_kubernetes_service_enablement.sh
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes_stack.yaml
```

## Testing and Validation

### Automated Test
```bash
./test_kubernetes_service_enablement_fix.sh
```

### Manual Verification
```bash
# Verify services are enabled and active
systemctl status kubelet containerd

# Check cluster functionality
kubectl cluster-info
kubectl get nodes

# Verify network functionality
kubectl get pods -n kube-flannel
kubectl get pods -n kube-system
```

## Expected Results

After applying this fix:

- ✅ **kubelet.service enabled and active**
- ✅ **containerd.service enabled and active**  
- ✅ **Flannel pods running** (if cluster is accessible)
- ✅ **Clear guidance** for any remaining issues
- ✅ **Comprehensive logging** of what was fixed

## Error Handling

The script provides detailed error handling:

1. **Service not found**: Gracefully handles missing services
2. **Permission issues**: Provides sudo guidance  
3. **Failed starts**: Shows recent logs for troubleshooting
4. **Network issues**: Explains kubectl connectivity problems
5. **CNI problems**: Guides through CNI configuration issues

## Integration with Existing Fixes

This fix complements existing VMStation recovery mechanisms:

- **Works with**: `setup_cluster.yaml` service management
- **Enhances**: Existing kubelet recovery logic in setup playbooks
- **Supports**: Post-spindown service restoration
- **Compatible**: All existing deployment workflows

## Files Modified

- `scripts/fix_kubernetes_service_enablement.sh` - New fix script
- `test_kubernetes_service_enablement_fix.sh` - Comprehensive test validation (new)
- `KUBERNETES_SERVICE_ENABLEMENT_FIX.md` - Documentation (this file)

## Compatibility

- Works with RHEL/CentOS 8, 9, 10+ systems
- Compatible with Debian/Ubuntu systems  
- Handles both systemd service management
- Provides appropriate Flannel pod guidance
- Integrates with existing VMStation infrastructure

## Troubleshooting

If services still fail to start after running the fix:

### 1. Check Installation
```bash
# RHEL/CentOS
rpm -qa | grep -E 'kubelet|containerd'

# Debian/Ubuntu  
dpkg -l | grep -E 'kubelet|containerd'
```

### 2. Check Configuration
```bash
# Kubelet configuration
ls -la /etc/systemd/system/kubelet.service.d/
cat /var/lib/kubelet/config.yaml

# Containerd configuration
cat /etc/containerd/config.toml
```

### 3. Check Logs
```bash
# Recent service logs
journalctl -u kubelet -f
journalctl -u containerd -f

# Boot-time issues
journalctl -b | grep -E 'kubelet|containerd'
```

### 4. Full Re-deployment
If issues persist, re-run the full setup:
```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes_stack.yaml
```
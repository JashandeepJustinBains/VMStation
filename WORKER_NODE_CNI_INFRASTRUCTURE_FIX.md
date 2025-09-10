# Worker Node CNI Infrastructure Fix

## Problem Statement

After running `./deploy cluster`, worker nodes experience CNI plugin initialization failures with containerd logs showing:

```
failed to load cni during init, please check CRI plugin status before setting up network for pods" 
error="cni config load failed: no network config found in /etc/cni/net.d: cni plugin not initialized: failed to load cni config"
```

## Root Cause

Worker nodes lack the necessary CNI infrastructure required by containerd:
- Missing CNI plugin binaries in `/opt/cni/bin/`
- Missing CNI configuration files in `/etc/cni/net.d/`
- kubelet expects CNI to be initialized but cannot find the required components

## Solution Implemented

### Enhanced Worker Node Setup in `ansible/plays/setup-cluster.yaml`

Added comprehensive CNI infrastructure installation for worker nodes before the kubeadm join process:

```yaml
- name: "Install CNI plugins and configuration on worker nodes (required for kubelet)"
  block:
    - name: "Create CNI directories on worker nodes"
      file:
        path: "{{ item }}"
        state: directory
        owner: root
        group: root
        mode: '0755'
      loop:
        - /opt/cni/bin
        - /etc/cni/net.d
        - /var/lib/cni/networks
        - /var/lib/cni/results

    - name: "Download and install Flannel CNI plugin binary on worker nodes"
      get_url:
        url: "https://github.com/flannel-io/cni-plugin/releases/download/v1.7.1/flannel-amd64"
        dest: /opt/cni/bin/flannel
        mode: '0755'
        timeout: 60
      retries: 3

    - name: "Download and install additional CNI plugins on worker nodes"
      unarchive:
        src: "https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz"
        dest: /opt/cni/bin
        remote_src: yes
        creates: /opt/cni/bin/bridge
      retries: 3

    - name: "Create basic CNI configuration for worker nodes"
      copy:
        content: |
          {
            "name": "cni0",
            "cniVersion": "0.3.1",
            "plugins": [
              {
                "type": "flannel",
                "delegate": {
                  "hairpinMode": true,
                  "isDefaultGateway": true
                }
              },
              {
                "type": "portmap",
                "capabilities": {
                  "portMappings": true
                }
              }
            ]
          }
        dest: /etc/cni/net.d/10-flannel.conflist
        owner: root
        group: root
        mode: '0644'

    - name: "Create Flannel subnet environment directory"
      file:
        path: /run/flannel
        state: directory
        mode: '0755'

  when: not kubelet_conf.stat.exists
```

## Files Modified

1. **`ansible/plays/setup-cluster.yaml`** - Added worker node CNI infrastructure installation
2. **`test_worker_node_cni_fix.sh`** - New comprehensive test suite (created)
3. **`validate_cni_config.sh`** - CNI configuration validation script (created)
4. **`WORKER_NODE_CNI_INFRASTRUCTURE_FIX.md`** - Documentation (this file)

## Testing and Validation

### Automated Tests

```bash
# Test CNI infrastructure installation
./test_worker_node_cni_fix.sh

# Validate CNI configuration compatibility
./validate_cni_config.sh
```

### Manual Verification

```bash
# 1. Check worker nodes have CNI plugins (after deployment)
ssh root@192.168.4.61 "ls -la /opt/cni/bin/" # Should show flannel, bridge, portmap
ssh root@192.168.4.62 "ls -la /opt/cni/bin/"

# 2. Check worker nodes have CNI configuration
ssh root@192.168.4.61 "cat /etc/cni/net.d/10-flannel.conflist"
ssh root@192.168.4.62 "cat /etc/cni/net.d/10-flannel.conflist"

# 3. Check containerd logs for successful CNI initialization
ssh root@192.168.4.61 "journalctl -u containerd | grep -i cni | tail -5"
ssh root@192.168.4.62 "journalctl -u containerd | grep -i cni | tail -5"

# 4. Verify kubelet doesn't show NetworkPluginNotReady
ssh root@192.168.4.61 "journalctl -u kubelet | grep -i 'NetworkReady' | tail -5"
ssh root@192.168.4.62 "journalctl -u kubelet | grep -i 'NetworkReady' | tail -5"
```

## Expected Results

After applying this fix:

- ✅ **Worker nodes have proper CNI infrastructure** before kubelet starts
- ✅ **containerd can successfully load CNI configuration** from `/etc/cni/net.d/`
- ✅ **"cni plugin not initialized" errors are eliminated**
- ✅ **kubelet shows NetworkReady=true** status
- ✅ **Pod networking works correctly** across all nodes
- ✅ **No more CNI-related containerd startup failures**

## Architecture

The fix ensures all worker nodes have the minimal CNI infrastructure required:

```
┌─────────────────────────────────────────────┐
│ Control Plane (192.168.4.63)               │
│ ✅ Flannel DaemonSet (network management)   │
│ ✅ CNI Plugins & Configuration              │
└─────────────────────────────────────────────┘
               │
               │ Network Management
               ▼
┌─────────────────────┐    ┌─────────────────────┐
│ Storage Node        │    │ Compute Node        │
│ (192.168.4.61)      │    │ (192.168.4.62)      │
│                     │    │                     │
│ ✅ CNI Plugins      │    │ ✅ CNI Plugins      │
│ ✅ CNI Configuration│    │ ✅ CNI Configuration│
│ ✅ kubelet Ready    │    │ ✅ kubelet Ready    │
│ ✅ Pod Networking   │    │ ✅ Pod Networking   │
└─────────────────────┘    └─────────────────────┘
```

## Impact

This fix resolves:
- CNI plugin initialization failures on worker nodes
- containerd errors about missing network configuration
- kubelet NetworkPluginNotReady status
- Worker node join issues related to CNI

## Backward Compatibility

- ✅ No breaking changes to existing functionality
- ✅ Compatible with existing Flannel DaemonSet deployment
- ✅ Works with both RHEL and Debian-based systems
- ✅ Maintains all existing timeout and retry logic
# Worker Node CNI Infrastructure Fix

## Problem Statement

During the cert-manager install stall, both machines have their `/etc/kubernetes/manifests/` directories created, but worker nodes encounter the following error:

```
"Container runtime network not ready" networkReady="NetworkReady=false reason:NetworkPluginNotReady message:Network plugin returns error: cni plugin not initialized"
```

## Root Cause Analysis

The issue occurs because:

1. **Flannel DaemonSet correctly runs only on control plane nodes** (as intended by the existing fix)
2. **Worker nodes lack CNI plugin infrastructure** - they don't have the necessary CNI plugin binaries and configuration files
3. **kubelet on worker nodes expects CNI to be initialized** but can't find the required components

Even though the Flannel daemon only runs on control plane nodes, **worker nodes still need**:
- CNI plugin binaries (`/opt/cni/bin/flannel`, `bridge`, `portmap`, etc.)
- CNI configuration files (`/etc/cni/net.d/10-flannel.conflist`)
- Basic network configuration for kubelet to initialize CNI

## Solution Implemented

### Enhanced Worker Node Setup in `setup_cluster.yaml`

Added comprehensive CNI infrastructure installation for worker nodes after the cleanup phase:

```yaml
- name: Install CNI plugins and configuration on worker nodes (required for kubelet)
  block:
    - name: Create CNI directories on worker nodes
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

    - name: Download and install Flannel CNI plugin binary on worker nodes
      get_url:
        url: "https://github.com/flannel-io/cni-plugin/releases/download/v1.7.1/flannel-amd64"
        dest: /opt/cni/bin/flannel
        mode: '0755'
        timeout: 60
      retries: 3

    - name: Download and install additional CNI plugins on worker nodes
      unarchive:
        src: "https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz"
        dest: /opt/cni/bin
        remote_src: yes
        creates: /opt/cni/bin/bridge
      retries: 3

    - name: Create basic CNI configuration for worker nodes
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

    - name: Create Flannel subnet configuration for worker nodes
      copy:
        content: |
          {
            "Network": "10.244.0.0/16",
            "EnableNFTables": false,
            "Backend": {
              "Type": "vxlan"
            }
          }
        dest: /run/flannel/subnet.env
```

## Network Architecture

The fix maintains the intended architecture while providing necessary CNI infrastructure:

```
┌─────────────────────────────────────────────┐
│ Control Plane (192.168.4.63)               │
│ ┌─────────────────────────────────────────┐ │
│ │ Flannel Controller (flanneld) ✅       │ │
│ │ CNI0 Interface ✅                      │ │
│ │ CNI Plugins ✅                         │ │
│ │ Network Management ✅                  │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
               │
               │ Network Management
               ▼
┌─────────────────────┐    ┌─────────────────────┐
│ Storage Node        │    │ Compute Node        │
│ (192.168.4.61)      │    │ (192.168.4.62)      │
│                     │    │                     │
│ ❌ No Flannel Daemon│    │ ❌ No Flannel Daemon│
│ ❌ No CNI0 Interface│    │ ❌ No CNI0 Interface│
│ ✅ CNI Plugins      │    │ ✅ CNI Plugins      │
│ ✅ CNI Configuration│    │ ✅ CNI Configuration│
│ ✅ Pod Networking   │    │ ✅ Pod Networking   │
└─────────────────────┘    └─────────────────────┘
```

## Testing and Validation

### Automated Tests

1. **Pre-deployment validation:**
   ```bash
   ./test_flannel_fix.sh          # Validates Flannel control-plane restriction
   ./test_worker_cni_fix.sh       # Validates worker CNI infrastructure
   ```

2. **Post-deployment validation:**
   ```bash
   ./validate_flannel_placement.sh  # Confirms proper deployment
   ```

### Manual Verification

```bash
# 1. Verify Flannel only runs on control plane
kubectl get pods -n kube-flannel -o wide

# 2. Check worker nodes have CNI plugins
ssh root@192.168.4.61 "ls -la /opt/cni/bin/" # Should show flannel, bridge, portmap
ssh root@192.168.4.62 "ls -la /opt/cni/bin/"

# 3. Check worker nodes have CNI configuration
ssh root@192.168.4.61 "cat /etc/cni/net.d/10-flannel.conflist"
ssh root@192.168.4.62 "cat /etc/cni/net.d/10-flannel.conflist"

# 4. Verify no CNI interfaces on workers (should be clean)
ssh root@192.168.4.61 "ip link show | grep -E '(cni0|cbr0|flannel)'" || echo "Clean ✅"
ssh root@192.168.4.62 "ip link show | grep -E '(cni0|cbr0|flannel)'" || echo "Clean ✅"

# 5. Check kubelet logs for CNI initialization success
ssh root@192.168.4.61 "journalctl -u kubelet | grep -i cni | tail -5"
ssh root@192.168.4.62 "journalctl -u kubelet | grep -i cni | tail -5"

# 6. Verify cert-manager pods can start successfully
kubectl get pods -n cert-manager
```

## Files Modified

1. **`ansible/plays/kubernetes/setup_cluster.yaml`** - Added worker node CNI infrastructure installation
2. **`test_worker_cni_fix.sh`** - New test script to validate worker CNI infrastructure (created)
3. **`cni_cleanup_diagnostic.sh`** - Enhanced to show more CNI plugin details
4. **`CERT_MANAGER_CNI_FIX.md`** - Updated with worker CNI infrastructure details
5. **`FLANNEL_FIX_QUICKSTART.md`** - Updated to include new test and architecture

## Expected Results

After applying this fix:

- ✅ **Worker nodes have proper CNI infrastructure** without running Flannel daemon
- ✅ **kubelet on worker nodes can initialize CNI** successfully
- ✅ **"cni plugin not initialized" errors are eliminated**
- ✅ **cert-manager installation completes without hanging**
- ✅ **Pod networking works correctly** across all nodes
- ✅ **Flannel daemon remains centralized** on control plane only

## Troubleshooting

If issues persist:

1. **Check CNI plugin installation:**
   ```bash
   ./cni_cleanup_diagnostic.sh show
   ```

2. **Verify network configuration consistency:**
   ```bash
   kubectl get configmap -n kube-flannel kube-flannel-cfg -o yaml
   ```

3. **Check kubelet CNI logs:**
   ```bash
   journalctl -u kubelet | grep -i cni
   ```

This fix addresses the root cause of worker node CNI initialization failures while maintaining the correct network architecture where only the control plane manages the Flannel daemon.
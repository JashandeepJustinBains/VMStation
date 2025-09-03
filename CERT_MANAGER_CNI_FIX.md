# Cert-Manager Hanging Issue Fix

## Problem Summary

The VMStation site.yaml playbook was stalling on cert-manager related tasks due to CNI (Container Network Interface) conflicts on worker nodes. This manifested as:

1. **cert-manager pods failing to start** on worker nodes (particularly storagenodet3500 - 192.168.4.61)
2. **CNI plugin errors** like: `"plugin type="flannel" failed (add): failed to set bridge addr: "cni0" already has an IP address different from 10.244.x.x/24"`
3. **Playbook hanging** during cert-manager installation phases

## Root Cause Analysis

### Network Architecture Issue
While the existing Flannel CNI controller fix correctly restricts Flannel to control plane nodes only, worker nodes retained **stale CNI state** from previous installations or configurations:

- **Leftover cni0/cbr0 interfaces** with incorrect IP addresses
- **Conflicting CNI configuration files** in `/etc/cni/net.d/`
- **Stale CNI plugin state** in `/var/lib/cni/`

### CNI Plugin Infrastructure Gap (CRITICAL)
**The primary issue**: Worker nodes were missing the necessary CNI plugin binaries and configuration files. Even though the Flannel daemon correctly runs only on control plane nodes, **worker nodes still need**:

- **CNI plugin binaries** in `/opt/cni/bin/` (flannel, bridge, portmap, etc.)
- **CNI configuration files** in `/etc/cni/net.d/` 
- **Basic network configuration** for kubelet to initialize CNI

Without these components, kubelet on worker nodes fails with:
```
"Container runtime network not ready" networkReady="NetworkReady=false reason:NetworkPluginNotReady message:Network plugin returns error: cni plugin not initialized"
```

### CNI Name Inconsistency
The Flannel ConfigMap was using `"name": "cbr0"` but runtime errors referenced `cni0`, creating a mismatch that prevented proper bridge configuration.

### Pod Scheduling Conflict
cert-manager pods were being scheduled to worker nodes with conflicting network state, causing sandbox creation failures that hung the deployment.

## Solution Implementation

### 1. Enhanced Worker Node CNI Cleanup

Added comprehensive CNI cleanup tasks to `ansible/plays/kubernetes/setup_cluster.yaml`:

```yaml
- name: Clean up stale CNI state on worker nodes (prevent cert-manager conflicts)
  block:
    - name: Stop and disable kubelet if running (to prevent CNI conflicts)
      systemd:
        name: kubelet
        state: stopped
        enabled: no
      ignore_errors: yes

    - name: Remove any existing CNI network interfaces (cni0, cbr0, flannel.1)
      shell: |
        # Remove existing interfaces that could conflict
        for interface in cni0 cbr0 flannel.1; do
          if ip link show "$interface" 2>/dev/null; then
            echo "Removing existing $interface interface"
            ip link set "$interface" down || true
            ip link delete "$interface" || true
          fi
        done
      ignore_errors: yes

    - name: Clear existing CNI configuration files
      shell: |
        # Remove any existing CNI configuration and state
        rm -rf /etc/cni/net.d/* || true
        rm -rf /opt/cni/bin/flannel || true
        rm -rf /var/lib/cni/networks/* || true
        rm -rf /var/lib/cni/results/* || true
        rm -rf /var/lib/kubelet/pods/* || true
        rm -rf /var/lib/kubelet/plugins_registry/* || true
      ignore_errors: yes
```

### 1.5. Worker Node CNI Infrastructure Installation (NEW)

**Critical Addition**: Worker nodes need CNI plugin binaries and configuration even though they don't run the Flannel daemon. Added CNI infrastructure installation:

```yaml
- name: Install CNI plugins and configuration on worker nodes (required for kubelet)
  block:
    - name: Create CNI directories on worker nodes
      file:
        path: "{{ item }}"
        state: directory
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

    - name: Download and install additional CNI plugins on worker nodes
      unarchive:
        src: "https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz"
        dest: /opt/cni/bin
        remote_src: yes

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

This ensures worker nodes have the CNI infrastructure needed to prevent "cni plugin not initialized" errors.

### 2. Fixed CNI Name Consistency

Updated `ansible/plays/kubernetes/templates/kube-flannel-masteronly.yml`:

```yaml
# Changed from:
"name": "cbr0"
# To:
"name": "cni0"
```

This ensures consistent bridge naming throughout the stack.

### 3. Diagnostic Tool

Created `cni_cleanup_diagnostic.sh` for troubleshooting and manual cleanup:

```bash
# Show current CNI state
./cni_cleanup_diagnostic.sh show

# Clean up CNI state on worker nodes only
./cni_cleanup_diagnostic.sh worker-cleanup

# Validate clean state
./cni_cleanup_diagnostic.sh validate
```

## Expected Results

### Before Fix:
- ❌ cert-manager pods fail with CNI bridge conflicts
- ❌ site.yaml playbook hangs during cert-manager installation
- ❌ Worker nodes have conflicting cni0/cbr0 interfaces
- ❌ CNI name mismatch between config and runtime

### After Fix:
- ✅ cert-manager pods start successfully on any node
- ✅ site.yaml playbook completes without hanging
- ✅ Worker nodes have clean CNI state before cluster join
- ✅ Consistent CNI bridge naming (cni0)
- ✅ Flannel controller remains properly restricted to control plane

## Usage

### Automatic Fix (Recommended)
The fix is integrated into the normal deployment process:

```bash
# Full deployment with fix
./update_and_deploy.sh

# Or individual steps
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml
ansible-playbook -i ansible/inventory.txt ansible/site.yaml
```

### Manual Troubleshooting
If cert-manager issues persist:

```bash
# 1. Diagnose CNI state on all nodes
./cni_cleanup_diagnostic.sh show

# 2. Clean up worker nodes (run on each worker)
ssh root@192.168.4.61 '/path/to/cni_cleanup_diagnostic.sh worker-cleanup'
ssh root@192.168.4.62 '/path/to/cni_cleanup_diagnostic.sh worker-cleanup'

# 3. Restart cluster setup
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml

# 4. Verify cert-manager
kubectl get pods -n cert-manager -o wide
```

## Testing and Validation

### Updated Test Scripts

Enhanced `test_flannel_fix.sh` to validate CNI name consistency:
```bash
./test_flannel_fix.sh  # Validates all aspects including CNI naming
```

**NEW:** `test_worker_cni_fix.sh` to validate worker node CNI infrastructure:
```bash
./test_worker_cni_fix.sh  # Validates worker node CNI plugin installation
```

Enhanced `validate_flannel_placement.sh` for post-deployment verification:
```bash
./validate_flannel_placement.sh  # Confirms proper Flannel placement
```

### Manual Verification

```bash
# 1. Confirm Flannel only on control plane
kubectl get pods -n kube-flannel -o wide

# 2. Verify worker nodes have CNI plugins but no CNI interfaces
ssh root@192.168.4.61 "ls -la /opt/cni/bin/" # Should show flannel, bridge, portmap
ssh root@192.168.4.61 "ip link show | grep -E '(cni0|cbr0|flannel)'" || echo "Clean (good)"

# 3. Verify worker nodes have CNI configuration
ssh root@192.168.4.61 "ls -la /etc/cni/net.d/" # Should show 10-flannel.conflist
ssh root@192.168.4.62 "ls -la /etc/cni/net.d/" # Should show 10-flannel.conflist

# 4. Check cert-manager pods are running
kubectl get pods -n cert-manager

# 5. Verify no CNI-related events/errors
kubectl get events -A | grep -i cni

# 6. Check kubelet logs for CNI initialization
ssh root@192.168.4.61 "journalctl -u kubelet | grep -i cni | tail -10"
ssh root@192.168.4.62 "journalctl -u kubelet | grep -i cni | tail -10"
```

## Files Modified

1. **`ansible/plays/kubernetes/setup_cluster.yaml`** - Added worker node CNI cleanup tasks
2. **`ansible/plays/kubernetes/templates/kube-flannel-masteronly.yml`** - Fixed CNI name consistency
3. **`test_flannel_fix.sh`** - Added CNI name validation
4. **`FLANNEL_CNI_CONTROLLER_FIX.md`** - Enhanced troubleshooting section
5. **`cni_cleanup_diagnostic.sh`** (NEW) - Comprehensive CNI diagnostic tool
6. **`CERT_MANAGER_CNI_FIX.md`** (NEW) - This detailed guide

## Integration with Existing Architecture

This fix **enhances** the existing Flannel CNI controller placement fix without changing its core principle:

- **Flannel daemon still runs only on control plane** (masternode - 192.168.4.63)
- **Worker nodes remain CNI-agent-free** (storage - 192.168.4.61, compute - 192.168.4.62)
- **Centralized network control** is maintained
- **Added**: Proactive cleanup prevents conflicts
- **Added**: Consistent naming prevents runtime errors

This ensures cert-manager and other Kubernetes services can deploy successfully without CNI-related conflicts while maintaining VMStation's intended network architecture.
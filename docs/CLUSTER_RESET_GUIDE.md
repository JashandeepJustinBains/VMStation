# Kubernetes Cluster Reset Guide

## Overview
This guide covers the comprehensive cluster reset capability that safely removes all Kubernetes configuration and network state while preserving SSH access and physical network interfaces.

## When to Use Reset

Use the cluster reset when you need to:
- Start fresh after a failed deployment
- Clean up after network configuration issues
- Remove all Kubernetes state before reconfiguration
- Test deployment from a clean slate
- Troubleshoot persistent cluster issues

## What Reset Does

### ✅ Removes:
- All Kubernetes configuration files (`/etc/kubernetes`, `/var/lib/kubelet`, `/var/lib/etcd`)
- CNI configuration and state (`/etc/cni/net.d`, `/var/lib/cni`)
- Flannel/Calico network state
- Kubernetes network interfaces (flannel*, cni*, calico*, vxlan*, docker0, kube-*)
- Container runtime state (pods, containers)
- iptables rules created by Kubernetes
- IPVS rules (if used)

### ✅ Preserves:
- SSH keys and authorized_keys
- Physical ethernet interfaces (eth*, ens*, eno*, enp*)
- Container runtime binaries (containerd, etc.)
- System configuration
- User data and home directories

## Usage

### Quick Reset
```bash
# Run from masternode/bastion (192.168.4.63)
./deploy.sh reset
```

### Manual Reset
```bash
# Run playbook directly
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/reset-cluster.yaml
```

### Reset + Deploy (Clean Slate)
```bash
# Reset the cluster
./deploy.sh reset

# Deploy fresh cluster
./deploy.sh
```

## Reset Workflow

The reset operation follows these steps:

1. **Pre-reset Validation**
   - User confirmation prompt
   - Detect running cluster nodes
   - Display nodes to be reset

2. **Graceful Drain**
   - Cordon all nodes (prevent new pods)
   - Drain nodes with timeout
   - Wait for pod termination

3. **Worker Node Reset** (serial execution)
   - Stop kubelet service
   - Run `kubeadm reset --force`
   - Remove Kubernetes config directories
   - Identify and remove K8s network interfaces
   - Flush iptables rules
   - Clean container runtime state
   - Restart containerd
   - Verify SSH and ethernet preservation

4. **Control Plane Reset**
   - Same steps as worker nodes
   - Removes etcd data

5. **Post-reset Validation**
   - Verify kubelet is stopped
   - Confirm no K8s config remains
   - Test SSH connectivity
   - Verify physical interfaces intact

## Safety Features

### SSH Key Protection
The reset role includes explicit checks to ensure SSH keys are not removed:
```yaml
- name: Verify SSH keys are preserved
  ansible.builtin.stat:
    path: "{{ ansible_env.HOME }}/.ssh/authorized_keys"
  register: ssh_keys_check

- name: Assert SSH keys still exist
  ansible.builtin.assert:
    that:
      - ssh_keys_check.stat.exists
    fail_msg: "CRITICAL: SSH keys were removed during reset!"
```

### Physical Interface Protection
Only Kubernetes-specific interfaces are targeted:
```yaml
- name: Identify Kubernetes-related network interfaces
  ansible.builtin.shell: |
    ip -o link show | awk -F': ' '{print $2}' | egrep 'flannel|^cni|^cali|^weave|^vxlan\.calico|^tunl0|docker0|kube-' || true
```

Physical interfaces (eth*, ens*, eno*, enp*) are explicitly verified after reset.

## Troubleshooting

### Reset Fails on Worker Node
```bash
# Check kubelet status
systemctl status kubelet

# Manually run kubeadm reset
kubeadm reset --force

# Check for remaining processes
ps aux | grep kube
```

### Network Interfaces Not Cleaned
```bash
# List all interfaces
ip -o link show

# Manually remove K8s interfaces
ip link delete flannel.1
ip link delete cni0
```

### SSH Access Lost (Should NOT happen)
If SSH access is lost after reset (this indicates a bug):
1. Access the node via console (IPMI/BMC or physical)
2. Check `/root/.ssh/authorized_keys` exists
3. Restore from backup if needed
4. Report the issue

### Container Runtime Issues
```bash
# Restart containerd
systemctl restart containerd

# Check containerd status
systemctl status containerd

# Clean containerd namespaces
ctr -n k8s.io containers list
ctr -n k8s.io tasks list
```

## Best Practices

1. **Always run from bastion/masternode** (192.168.4.63)
2. **Confirm the operation** when prompted
3. **Wait for completion** before deploying
4. **Check the summary** after reset
5. **Deploy immediately** or wait to avoid partial state

## Integration with Existing Workflows

### Spin-down → Reset → Deploy
```bash
# Graceful spin-down (optional, reset does this automatically)
./deploy.sh spindown

# Complete reset
./deploy.sh reset

# Fresh deployment
./deploy.sh
```

### Reset Only Specific Nodes
```bash
# Edit reset-cluster.yaml to target specific hosts
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/reset-cluster.yaml --limit compute_nodes
```

## Verification Commands

After reset, verify clean state:
```bash
# No K8s config
ls /etc/kubernetes  # Should not exist or be empty

# No K8s network interfaces
ip -o link show | grep -E 'flannel|cni|calico'  # Should return nothing

# Kubelet stopped
systemctl status kubelet  # Should show inactive

# SSH works
ssh root@192.168.4.61 uptime  # Should connect successfully

# Physical interfaces intact
ip -o link show | grep -E 'eth|ens|eno|enp'  # Should show your interfaces
```

## Files Modified/Created

### New Files
- `ansible/roles/cluster-reset/tasks/main.yml` - Reset role implementation
- `ansible/playbooks/reset-cluster.yaml` - Reset playbook orchestration
- `docs/CLUSTER_RESET_GUIDE.md` - This documentation

### Modified Files
- `deploy.sh` - Added `reset` command
- `ansible/roles/cluster-spindown/tasks/main.yml` - Enhanced drain with timeout
- `.github/instructions/memory.instruction.md` - Updated project notes

## See Also
- [Deployment Guide](../README.md)
- [Spin-down Documentation](SPINDOWN.md)
- [Network Troubleshooting](NETWORK-DIAGNOSIS-QUICKSTART.md)

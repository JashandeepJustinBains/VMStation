# Cluster Reset Role

## Purpose
Safely and comprehensively resets a Kubernetes cluster node to a clean state, removing all Kubernetes configuration and network resources while explicitly preserving SSH access and physical network interfaces.

## Features

### Safe Cleanup
- Stops kubelet service cleanly
- Runs `kubeadm reset --force`
- Removes all Kubernetes config directories
- Cleans CNI/Flannel state
- Removes only Kubernetes-specific network interfaces
- Flushes iptables rules safely
- Cleans container runtime state

### Preservation Guarantees
- **SSH Keys**: Explicitly verified before and after
- **Physical Interfaces**: Only K8s interfaces removed
- **Container Runtime**: Binary preserved, only state cleaned
- **System Config**: Untouched

### Validation
- Pre-cleanup interface identification
- Post-cleanup SSH verification
- Post-cleanup ethernet verification
- Detailed logging and summaries

## Usage

### Via Playbook
```yaml
- hosts: all
  become: true
  roles:
    - cluster-reset
```

### Via deploy.sh
```bash
./deploy.sh reset
```

## Tasks Overview

1. **Stop kubelet** - Clean service shutdown
2. **Run kubeadm reset** - Official Kubernetes cleanup
3. **Remove config directories** - Delete /etc/kubernetes, /var/lib/kubelet, etc.
4. **Identify K8s interfaces** - Regex match for flannel*, cni*, calico*, etc.
5. **Bring down interfaces** - ip link set down
6. **Delete interfaces** - ip link delete
7. **Flush iptables** - Remove K8s rules
8. **Clean ipvs** - If enabled
9. **Clean container runtime** - Remove containers/tasks
10. **Restart containerd** - Fresh state
11. **Kill remaining processes** - Safety cleanup
12. **Verify SSH keys** - Assert they exist
13. **Verify physical interfaces** - Assert they exist
14. **Display summary** - Show results

## Variables

### Optional
- `container_runtime` - Default: `containerd`

### Automatic
All cleanup is automatic with sane defaults. No configuration required.

## Dependencies

### System Requirements
- kubeadm (if installed)
- iptables
- ip command
- systemd

### Ansible Requirements
- ansible.builtin modules
- become: true (root access)

## Safety Mechanisms

### Interface Identification
Only interfaces matching these patterns are removed:
- `flannel*`
- `cni*`
- `cali*`
- `weave*`
- `vxlan.calico*`
- `tunl0`
- `docker0`
- `kube-*`

Physical interfaces (eth*, ens*, eno*, enp*) are **never** targeted.

### SSH Verification
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

### Ethernet Verification
```yaml
- name: Verify physical ethernet interfaces are preserved
  ansible.builtin.shell: |
    ip -o link show | egrep 'eth|ens|eno|enp' | wc -l
  register: ethernet_check

- name: Assert physical interfaces still exist
  ansible.builtin.assert:
    that:
      - ethernet_check.stdout | int > 0
    fail_msg: "CRITICAL: Physical ethernet interfaces may have been affected!"
```

## Error Handling

All potentially failing tasks use `ignore_errors: true`:
- kubeadm reset (may not be installed)
- Interface operations (may not exist)
- iptables flush (may not have rules)
- Container runtime operations (may not be running)

This ensures the role completes even on partially-configured nodes.

## Testing

### Dry Run
```bash
ansible-playbook --check ansible/playbooks/reset-cluster.yaml
```

### Verify Cleanup
```bash
# After running reset
ls /etc/kubernetes  # Should not exist
ip -o link show | grep cni  # Should return nothing
systemctl status kubelet  # Should be inactive
ssh root@node uptime  # Should work
```

## Integration

### With Spin-down
```yaml
- import_playbook: playbooks/spin-down-cluster.yaml
- hosts: all
  roles:
    - cluster-reset
```

### Before Deploy
```yaml
- hosts: all
  roles:
    - cluster-reset
    
- hosts: all
  roles:
    - system-prep
    - network-fix
    - cluster-spinup
```

## Idempotency

This role is idempotent and can be run multiple times safely:
- Already-removed interfaces are skipped
- Missing directories are ignored
- Stopped services are skipped
- Verification always runs

## Output Example

```
TASK [cluster-reset : Display identified Kubernetes interfaces]
ok: [masternode] => 
  msg: "Kubernetes interfaces to remove: ['flannel.1', 'cni0']"

TASK [cluster-reset : Display reset completion summary]
ok: [masternode] =>
  msg: |-
    Kubernetes cluster reset completed successfully:
    - kubeadm reset: OK
    - Kubernetes interfaces removed: 2
    - SSH keys: preserved
    - Physical interfaces: preserved
    - Node is ready for fresh cluster deployment
```

## Troubleshooting

### kubeadm reset fails
Normal if kubeadm isn't installed. Role continues.

### Interface deletion fails
May already be gone. Check with `ip -o link show`.

### SSH lost (should NOT happen)
If this occurs, it's a bug. Access via console and check `/root/.ssh/authorized_keys`.

### Containerd issues
Restart manually: `systemctl restart containerd`

## See Also
- [Cluster Reset Guide](../../docs/CLUSTER_RESET_GUIDE.md)
- [Reset Playbook](../../ansible/playbooks/reset-cluster.yaml)
- [Deploy Script](../../deploy.sh)

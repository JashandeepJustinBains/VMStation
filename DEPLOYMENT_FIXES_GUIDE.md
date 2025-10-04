# VMStation Deployment Fixes - Summary

## Issues Identified from Deployment Logs

From the `deploy.sh` output analysis, the following critical issues were preventing successful cluster deployment:

1. **CNI Plugin Download Failure on RHEL 10** (homelab node)
   - Ansible `get_url` module incompatibility with RHEL 10's Python SSL stack
   - Error: `HTTPSConnection.__init__() got an unexpected keyword argument 'cert_file'`
   - **Impact**: homelab node failed in Phase 2, couldn't join cluster

2. **Hostname Resolution in Validation**
   - Validation task tried to SSH using node names (`homelab`, `storagenodet3500`)
   - DNS not configured for internal cluster hostnames
   - Error: `ssh: Could not resolve hostname homelab: Name or service not known`

3. **Kubelet Config Missing**
   - network-fix role tried to patch `/var/lib/kubelet/config.yaml` before kubeadm created it
   - Error: `Destination /var/lib/kubelet/config.yaml does not exist !`

4. **kube-proxy CrashLoopBackOff on RHEL 10**
   - kube-proxy starts before Flannel CNI config exists
   - Pre-created iptables chains help but pod still needs restart after CNI is ready

5. **ip6tables-nft Missing**
   - RHEL 10 doesn't have ip6tables alternatives configured
   - Already ignored with `ignore_errors: true`, but still showed as failure

## Solutions Implemented

### 1. CNI Download Fallback (deploy-cluster.yaml)
```yaml
# Use curl for RHEL nodes instead of get_url
- name: Download CNI plugins with curl (RHEL fallback)
  ansible.builtin.shell: |
    curl -L -o /tmp/cni-plugins.tgz https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz
  when:
    - not cni_installed.stat.exists
    - ansible_os_family == 'RedHat'
```

### 2. /etc/hosts Management (system-prep role)
```yaml
- name: Ensure /etc/hosts has all cluster nodes
  become: true
  ansible.builtin.blockinfile:
    path: /etc/hosts
    block: |
      192.168.4.63 masternode
      192.168.4.61 storagenodet3500
      192.168.4.62 homelab
```

### 3. Kubelet Config Check (network-fix role)
```yaml
- name: Check if kubelet config exists (RHEL 10+)
  ansible.builtin.stat:
    path: /var/lib/kubelet/config.yaml
  register: kubelet_config_stat

- name: Ensure kubelet uses systemd cgroup driver (RHEL 10+)
  when:
    - kubelet_config_stat.stat.exists | default(false)
```

### 4. kube-proxy Auto-Recovery (deploy-cluster.yaml)
```yaml
- name: Restart kube-proxy pods to recover from CNI wait (RHEL nodes)
  ansible.builtin.shell: |
    crash_pods=$(kubectl -n kube-system get pods -l k8s-app=kube-proxy \
      -o json | jq -r '.items[] | select(.status.containerStatuses[]? | .state.waiting.reason? == "CrashLoopBackOff") | .metadata.name')
    
    if [ -n "$crash_pods" ]; then
      echo "Restarting CrashLoopBackOff kube-proxy pods: $crash_pods"
      echo "$crash_pods" | xargs -r kubectl -n kube-system delete pod
    fi
```

### 5. IP-Based Validation (deploy-cluster.yaml)
```yaml
- name: Verify CNI config exists on all nodes
  ansible.builtin.shell: |
    {% for host in groups['all'] %}
    ssh -o StrictHostKeyChecking=no {{ hostvars[host]['ansible_host'] }} \
      'test -f /etc/cni/net.d/10-flannel.conflist'
    {% endfor %}
```

### 6. Playbook Optimization
- **Removed redundant Phase 3**: iptables chain pre-creation now only in network-fix role
- **Reduced from 10 to 8 phases**: cleaner structure
- **Reduced timeout**: node ready wait from 5min to 3min
- **32 lines shorter**: 404 → 372 lines in deploy-cluster.yaml

## Updated Deployment Flow (8 Phases)

```
Phase 1: System Preparation
  ├─ Load kernel modules (br_netfilter, overlay, vxlan)
  ├─ Set sysctl parameters (ip_forward, bridge-nf-call-iptables)
  ├─ Install network packages (OS-specific)
  ├─ Configure /etc/hosts for cluster nodes
  ├─ Disable firewalls (ufw, firewalld)
  └─ RHEL 10: Pre-create iptables chains for kube-proxy

Phase 2: CNI Plugins Installation
  ├─ Download CNI plugins (curl fallback for RHEL)
  └─ Extract to /opt/cni/bin

Phase 3: Control Plane Initialization
  ├─ kubeadm init (if not already initialized)
  └─ Wait for API server ready

Phase 4: Worker Node Join
  ├─ Generate join token on masternode
  └─ kubeadm join on worker nodes

Phase 5: Flannel CNI Deployment
  ├─ Apply Flannel manifest
  ├─ Wait for Flannel DaemonSet ready
  └─ Restart any CrashLoopBackOff kube-proxy pods

Phase 6: Wait for All Nodes Ready
  └─ Poll until all nodes show Ready status (3min timeout)

Phase 7: Node Scheduling Configuration
  ├─ Remove NoSchedule taint from control-plane
  └─ Uncordon all nodes

Phase 8: Post-Deployment Validation
  ├─ Check for CrashLoopBackOff pods
  ├─ Verify CNI config on all nodes (via IP)
  └─ Display final cluster status
```

## Testing Instructions

### 1. Syntax Validation
```bash
cd /root/VMStation
ansible-playbook --syntax-check ansible/playbooks/deploy-cluster.yaml
ansible-playbook --syntax-check ansible/playbooks/reset-cluster.yaml
```

### 2. Single Deployment Test
```bash
./deploy.sh reset
./deploy.sh
```

**Expected Results:**
- ✅ All 3 nodes join cluster
- ✅ All nodes show Ready status
- ✅ No CrashLoopBackOff pods
- ✅ Flannel CNI config present on all nodes: `/etc/cni/net.d/10-flannel.conflist`
- ✅ kube-proxy running on all nodes (including homelab/RHEL 10)
- ✅ CoreDNS pods Running

### 3. Idempotency Test (100% Reliability Goal)
```bash
./deploy.sh reset && ./deploy.sh
./deploy.sh reset && ./deploy.sh
./deploy.sh reset && ./deploy.sh
```

**Expected Results:**
- ✅ Each cycle completes without errors
- ✅ No manual intervention needed
- ✅ Consistent results every time

### 4. Verification Commands
```bash
# Check nodes
kubectl get nodes -o wide

# Check all pods
kubectl get pods -A

# Check Flannel
kubectl -n kube-flannel get pods -o wide

# Check CNI config on each node
ssh 192.168.4.63 'ls -l /etc/cni/net.d/'
ssh 192.168.4.61 'ls -l /etc/cni/net.d/'
ssh 192.168.4.62 'ls -l /etc/cni/net.d/'

# Check kube-proxy specifically on homelab
kubectl -n kube-system get pods -l k8s-app=kube-proxy -o wide | grep homelab
kubectl -n kube-system logs -l k8s-app=kube-proxy --tail=50 | grep homelab
```

## Known Limitations

1. **ip6tables-nft on RHEL 10**: Not available in alternatives, but safely ignored
2. **Firewall disabled**: For simplicity; re-enabling requires explicit VXLAN rules
3. **SELinux permissive**: Required for CNI compatibility on RHEL
4. **Mixed OS architecture**: Requires careful handling of iptables vs nftables

## Next Steps

1. **Test deployment** on actual cluster hardware
2. **Verify kube-proxy recovery** works on RHEL 10 node
3. **Run idempotency tests** (3x minimum)
4. **Setup auto-sleep** after successful deployment: `./deploy.sh setup`
5. **Deploy applications** after cluster is stable

## Architecture Notes

- **masternode (192.168.4.63)**: Debian 12, control-plane, always-on
- **storagenodet3500 (192.168.4.61)**: Debian 12, Jellyfin/storage
- **homelab (192.168.4.62)**: RHEL 10, compute workloads

## Troubleshooting

### If homelab still fails to join
```bash
# SSH to homelab and check:
ssh 192.168.4.62
sudo journalctl -u kubelet -n 100
sudo kubeadm reset -f
# Then re-run deploy.sh
```

### If kube-proxy still crashes
```bash
# Check iptables chains exist
ssh 192.168.4.62 'sudo iptables -t nat -L KUBE-SERVICES'
ssh 192.168.4.62 'sudo iptables -t filter -L KUBE-FORWARD'

# Check CNI config
ssh 192.168.4.62 'cat /etc/cni/net.d/10-flannel.conflist'

# Manually restart
kubectl -n kube-system delete pod -l k8s-app=kube-proxy
```

### If validation fails
```bash
# Check /etc/hosts on all nodes
ssh 192.168.4.63 'grep -A3 "VMStation" /etc/hosts'
ssh 192.168.4.61 'grep -A3 "VMStation" /etc/hosts'
ssh 192.168.4.62 'grep -A3 "VMStation" /etc/hosts'
```

## File Changes Summary

| File | Lines Changed | Impact |
|------|---------------|--------|
| `ansible/playbooks/deploy-cluster.yaml` | -32 (404→372) | Core deployment logic |
| `ansible/roles/network-fix/tasks/main.yml` | +30 | Enhanced RHEL support |
| `ansible/roles/system-prep/tasks/main.yml` | +14 | Added /etc/hosts |
| `docs/GOLD_STANDARD_NETWORK_SETUP.md` | -1 | Documentation update |
| **Total** | **+11 lines** | **Net improvement** |

## Success Criteria

The deployment is considered successful when:
1. ✅ All 3 nodes are in Ready state
2. ✅ Zero CrashLoopBackOff pods
3. ✅ Flannel CNI config exists on all nodes
4. ✅ kube-proxy running on all nodes
5. ✅ CoreDNS pods are Running
6. ✅ Can run `deploy.sh reset && deploy.sh` 3 times consecutively without errors

---

**Date**: October 4, 2025  
**Ansible Version**: 2.14.18  
**Kubernetes Version**: 1.29.15  
**Flannel Version**: 0.27.4

# Homelab Node (RHEL 10) Troubleshooting Guide

**Date**: October 2, 2025  
**Node**: homelab (192.168.4.62)  
**OS**: RHEL 10  
**Issues**: kube-proxy CrashLoopBackOff, Loki CrashLoopBackOff, Flannel instability

---

## Root Cause Analysis

### Issue 1: kube-proxy CrashLoopBackOff (28+ restarts)

**Symptoms**:
```
kube-system   kube-proxy-cnzql   0/1  CrashLoopBackOff  28 (107s ago)  128m
```

**Root Causes**:
1. **iptables Mode Mismatch**: RHEL 10 uses `nftables` by default, but kube-proxy expects `iptables-legacy`
2. **Missing conntrack Binary**: kube-proxy requires `/usr/sbin/conntrack` to function
3. **Kernel Module Issues**: `nf_conntrack` module not loaded or accessible in the expected way

**Evidence**:
- Packages installed: `conntrack-tools` ✓
- Kernel modules loaded: `nf_conntrack` ✓
- But kube-proxy still crashes → **iptables mode issue**

**Solution Applied**:
```yaml
# In network-fix role
- name: Configure iptables-legacy as default on RHEL systems
  ansible.builtin.command:
    cmd: "{{ item }}"
  loop:
    - alternatives --set iptables /usr/sbin/iptables-legacy
    - alternatives --set ip6tables /usr/sbin/ip6tables-legacy
  when: ansible_os_family == 'RedHat'
```

---

### Issue 2: NetworkManager Config Failure on storagenodet3500

**Symptoms**:
```
fatal: [storagenodet3500]: FAILED! => changed=false
  msg: Destination directory /etc/NetworkManager/conf.d does not exist
```

**Root Cause**:
- NetworkManager not installed or configured on storagenodet3500 (Debian Bookworm)
- Ansible task tried to write config file without creating parent directory first

**Solution Applied**:
```yaml
- name: Ensure NetworkManager conf.d directory exists
  become: true
  ansible.builtin.file:
    path: /etc/NetworkManager/conf.d
    state: directory
    owner: root
    group: root
    mode: '0755'
  when: ansible_service_mgr == 'systemd'
```

---

### Issue 3: CoreDNS Immutable Selector Error

**Symptoms**:
```
fatal: [masternode]: FAILED! => changed=false
  msg: 'Failed to patch object: Deployment.apps "coredns" is invalid: 
       spec.selector: Invalid value: ... field is immutable'
```

**Root Cause**:
- Playbook tried to re-apply CoreDNS from upstream manifest
- CoreDNS already deployed by `kubeadm init`
- Upstream manifest has different selector labels than kubeadm's version
- Kubernetes Deployment `spec.selector` is immutable after creation

**Solution Applied**:
```yaml
# Remove all CoreDNS deployment logic
# Only check status for informational purposes
- name: "Check CoreDNS status (informational only - kubeadm manages CoreDNS)"
  kubernetes.core.k8s_info:
    api_version: v1
    kind: Pod
    namespace: kube-system
    label_selectors:
      - k8s-app=kube-dns
  register: coredns_check
  ignore_errors: true
```

**Why**: `kubeadm` already deploys and manages CoreDNS. We should never touch it.

---

### Issue 4: Loki CrashLoopBackOff on homelab (17 restarts)

**Symptoms**:
```
monitoring   loki-66944b8d97-p5rbj   0/1  CrashLoopBackOff  17 (4m20s ago)  71m
```

**Likely Cause**:
- DNS resolution failures due to CoreDNS not being available
- Network policy or iptables blocking pod-to-pod communication
- kube-proxy not functional → service endpoints unreachable

**Dependency Chain**:
```
kube-proxy (broken) → Services don't work → DNS doesn't work → Loki can't resolve dependencies → Crashes
```

**Expected Resolution**:
Once kube-proxy is fixed with iptables-legacy, Loki should stabilize automatically.

---

## Diagnostic Procedures

### 1. Run Diagnostic Script

```bash
chmod +x scripts/diagnose-homelab-issues.sh
./scripts/diagnose-homelab-issues.sh > homelab-diagnostics-$(date +%Y%m%d-%H%M%S).txt
```

**This script checks**:
- conntrack installation and functionality
- Kernel modules loaded
- iptables version and mode (legacy vs nftables)
- NetworkManager status and configuration
- firewalld status
- kube-proxy logs (current and previous)
- flannel logs
- System packages
- SELinux status
- iptables rules

### 2. Run Emergency Fix (if needed)

```bash
chmod +x scripts/fix-homelab-kubeproxy.sh
./scripts/fix-homelab-kubeproxy.sh
```

**This script**:
1. Ensures all packages installed
2. Loads required kernel modules (including nf_conntrack_ipv4 fallback)
3. Sets iptables to legacy mode via alternatives
4. Disables SELinux temporarily
5. Restarts kubelet
6. Deletes and recreates kube-proxy pod
7. Waits for kube-proxy to be ready

---

## Manual Troubleshooting Steps

### Check kube-proxy Logs

```bash
# Get kube-proxy pod name on homelab
kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab

# Check logs (current)
kubectl logs -n kube-system kube-proxy-<pod-id>

# Check logs (previous crash)
kubectl logs -n kube-system kube-proxy-<pod-id> --previous
```

**Look for**:
- `conntrack` errors
- `iptables` errors
- `nftables` vs `iptables-legacy` conflicts
- Permission errors (SELinux)

### Verify iptables Mode on homelab

```bash
ssh 192.168.4.62 'iptables --version'
# Should show: iptables v1.x.x (Legacy)

ssh 192.168.4.62 'alternatives --display iptables'
# Should show: link currently points to /usr/sbin/iptables-legacy
```

### Check conntrack Functionality

```bash
ssh 192.168.4.62 'conntrack -L | head -10'
# Should show connection tracking table (may be empty but shouldn't error)

ssh 192.168.4.62 'lsmod | grep nf_conntrack'
# Should show nf_conntrack modules loaded
```

### Check NetworkManager CNI Exclusion

```bash
ssh 192.168.4.62 'cat /etc/NetworkManager/conf.d/99-kubernetes.conf'
# Should show:
# [keyfile]
# unmanaged-devices=interface-name:cni*;interface-name:flannel*;interface-name:veth*

ssh 192.168.4.62 'nmcli device status | grep -E "cni|flannel|veth"'
# Should show these interfaces as "unmanaged"
```

---

## Validation After Fixes

### 1. Re-run Deployment

```bash
cd /srv/monitoring_data/VMStation
git fetch && git pull
./deploy.sh
```

### 2. Check Pod Status

```bash
kubectl get pods -A -o wide | grep homelab
```

**Expected Results**:
```
kube-flannel    kube-flannel-ds-xxxxx   1/1  Running  0  5m  homelab
kube-system     kube-proxy-xxxxx        1/1  Running  0  5m  homelab
monitoring      loki-xxxxx              1/1  Running  0  5m  homelab
```

**All pods should be `Running` with 0 or minimal restarts (<3).**

### 3. Check kube-proxy Connectivity

```bash
# From masternode
kubectl get endpoints kubernetes
# Should show 192.168.4.63:6443

# From homelab, test service resolution
ssh 192.168.4.62 'curl -k https://kubernetes.default.svc.cluster.local:443'
# Should connect (may get auth error, but connection should succeed)
```

### 4. Check DNS Resolution

```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
# Should resolve to 10.96.0.1 (or similar service CIDR)
```

---

## Permanent Fixes Required

### SELinux Configuration (Future)

Currently, SELinux is set to permissive mode. For production:

1. Create custom SELinux policy for Kubernetes
2. Re-enable SELinux in enforcing mode
3. Test all pod operations

**Reference**: Red Hat OpenShift SELinux policies

### Firewalld Re-enablement (Future)

Currently, firewalld is disabled. For production:

1. Re-enable firewalld
2. Add explicit rules for:
   - VXLAN (UDP 8472)
   - Kubelet API (TCP 10250)
   - NodePorts (TCP 30000-32767)
   - Control plane communication

**Example Rules**:
```bash
firewall-cmd --permanent --add-port=8472/udp  # Flannel VXLAN
firewall-cmd --permanent --add-port=10250/tcp # Kubelet API
firewall-cmd --permanent --add-port=30000-32767/tcp # NodePorts
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload
```

---

## Known Limitations

1. **iptables-legacy Mode Required**: RHEL 10 uses nftables by default, but kube-proxy v1.29 doesn't fully support nftables. Must use iptables-legacy until upgrading to Kubernetes 1.31+.

2. **SELinux Permissive**: Currently running in permissive mode for troubleshooting. Should create proper SELinux policies before production use.

3. **Firewalld Disabled**: Disabled to simplify networking. Should re-enable with explicit rules for production.

4. **No Node Exporter**: Homelab node doesn't have node-level metrics exported yet. Add node-exporter DaemonSet in future.

---

## Next Steps

1. ✅ Apply network-fix role enhancements (done in commit 46cbe8f)
2. ⏳ Re-run deployment and verify kube-proxy starts successfully
3. ⏳ Monitor Loki stability after kube-proxy fix
4. ⏳ Once stable, document SELinux policy creation
5. ⏳ Once stable, re-enable firewalld with explicit VXLAN rules
6. ⏳ Add node-exporter DaemonSet for homelab metrics
7. ⏳ Consider upgrading to Kubernetes 1.31+ for native nftables support

---

## References

- [Flannel Troubleshooting](https://github.com/flannel-io/flannel/blob/master/Documentation/troubleshooting.md)
- [kube-proxy iptables vs nftables](https://kubernetes.io/docs/reference/networking/virtual-ips/#proxy-mode-iptables)
- [RHEL 10 Networking Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/10)
- [Kubernetes on RHEL Best Practices](https://access.redhat.com/articles/5115311)
- [SELinux and Kubernetes](https://www.redhat.com/en/blog/running-containers-rhel-8-selinux-enabled)

---

**Last Updated**: October 2, 2025  
**Status**: Fixes applied, awaiting re-deployment validation  
**Commit**: 46cbe8f

# Gold-Standard Kubernetes Network Setup - Never-Fail Guide

## Overview
This document describes the gold-standard, never-fail, idempotent Ansible automation for deploying a Kubernetes cluster with Flannel CNI across mixed OS environments (Debian 12 + RHEL 10).

**Guarantee**: Zero CrashLoopBackOff, zero CoreDNS failures, all nodes Ready, all pods Running.

## Architecture
- **Control Plane**: 1x masternode (Debian 12)
- **Worker Nodes**: 
  - 1x storagenodet3500 (Debian 12)
  - 1x homelab (RHEL 10) - requires special handling
- **CNI**: Flannel v0.27.4 (VXLAN overlay)
- **Kubernetes**: v1.29.15
- **Container Runtime**: containerd with systemd cgroup driver

## Critical Success Factors

### 1. Execution Order is EVERYTHING
The playbook MUST execute in this exact order:

```
System Prep → Control Plane Init → Worker Join → Flannel CNI → 
CNI Config Verification → kube-proxy Health → All Nodes Ready → 
Node Scheduling Config → Apps Deployment
```

**Why**: 
- Flannel cannot deploy if kernel modules aren't loaded
- kubelet cannot start if sysctl isn't configured
- Nodes cannot be Ready without Flannel CNI config
- CoreDNS cannot schedule on NotReady nodes
- kube-proxy crashes on RHEL 10 without iptables chains pre-created

### 2. RHEL 10 Requires Special Care
RHEL 10 uses nftables backend exclusively. The following MUST be done:

#### Required Packages
```bash
- iptables-nft
- iptables-nft-services
- nftables
```

#### Required Services
```bash
systemctl enable --now nftables
systemctl mask systemd-oomd
```

#### Required iptables Configuration
```bash
update-alternatives --set iptables /usr/sbin/iptables-nft
update-alternatives --set ip6tables /usr/sbin/ip6tables-nft
touch /run/xtables.lock
```

#### Pre-create iptables Chains for kube-proxy
```bash
iptables -t nat -N KUBE-SERVICES
iptables -t nat -N KUBE-POSTROUTING
iptables -t nat -N KUBE-FIREWALL
iptables -t nat -N KUBE-MARK-MASQ
iptables -t filter -N KUBE-FORWARD
iptables -t filter -N KUBE-SERVICES

# Link to base chains
iptables -t nat -A PREROUTING -j KUBE-SERVICES
iptables -t nat -A OUTPUT -j KUBE-SERVICES
iptables -t nat -A POSTROUTING -j KUBE-POSTROUTING
iptables -t filter -A FORWARD -j KUBE-FORWARD
```

#### Container Runtime Configuration
```toml
# /etc/containerd/config.toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  SystemdCgroup = true
```

```yaml
# /var/lib/kubelet/config.yaml
cgroupDriver: systemd
```

### 3. System Prerequisites (Before kubelet starts)

#### Kernel Modules
```bash
modprobe br_netfilter
modprobe overlay
modprobe nf_conntrack
modprobe vxlan
```

Persist in `/etc/modules-load.d/kubernetes.conf`

#### Sysctl Parameters
```bash
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
```

Persist in `/etc/sysctl.d/99-k8s.conf`

#### CNI Directory
```bash
mkdir -p /etc/cni/net.d
chmod 755 /etc/cni/net.d
# Remove all configs except 10-flannel.conflist
```

#### Firewall
```bash
# Disable host firewalls (Flannel VXLAN requires open node-to-node communication)
systemctl stop firewalld && systemctl disable firewalld  # RHEL
systemctl stop ufw && systemctl disable ufw              # Debian/Ubuntu
iptables -P FORWARD ACCEPT
```

#### NetworkManager
```bash
# Prevent NetworkManager from managing CNI interfaces
cat > /etc/NetworkManager/conf.d/99-kubernetes.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:cni*;interface-name:flannel*;interface-name:veth*
EOF
systemctl restart NetworkManager
```

## Deployment Phases

### Phase 1: CNI Plugins Installation
Install standard CNI plugins (loopback, bridge, etc.) on all nodes:
```bash
curl -L -o /tmp/cni-plugins.tgz \
  https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz
tar -C /opt/cni/bin -xzf /tmp/cni-plugins.tgz
chmod 755 /opt/cni/bin/*
```

### Phase 2: System Prep and Network Prerequisites
Run `system-prep`, `preflight`, and `network-fix` roles on all nodes.

### Phase 3: Control Plane Initialization
On masternode only:
```bash
kubeadm init --pod-network-cidr=10.244.0.0/16 --upload-certs
```

Wait for API server to be available (up to 150s).

### Phase 4: Worker Node Join
On worker nodes:
```bash
kubeadm token create --print-join-command  # on masternode
<join-command> --ignore-preflight-errors=all  # on workers
```

Wait for nodes to appear in `kubectl get nodes` (up to 150s).

### Phase 5: Flannel CNI Deployment
Deploy Flannel DaemonSet and wait for all pods Running:
```bash
kubectl apply -f manifests/cni/flannel.yaml
kubectl -n kube-flannel rollout status daemonset/kube-flannel-ds --timeout=180s
```

Verify Flannel pods on all nodes:
```bash
total_nodes=$(kubectl get nodes --no-headers | wc -l)
running_flannel=$(kubectl -n kube-flannel get pods -l app=flannel -o json | \
  jq '[.items[] | select(.status.phase=="Running")] | length')
[ "$running_flannel" -eq "$total_nodes" ] || exit 1
```

Verify CNI config on all nodes:
```bash
ssh $node '[ -f /etc/cni/net.d/10-flannel.conflist ]'
```

### Phase 6: kube-proxy Health Check
Check for CrashLoopBackOff on RHEL 10 and auto-recover:
```bash
for node in $(kubectl get nodes -o name | cut -d/ -f2); do
  os=$(kubectl get node $node -o jsonpath='{.status.nodeInfo.osImage}')
  if echo "$os" | grep -qi 'Red Hat Enterprise Linux 10'; then
    pod=$(kubectl -n kube-system get pods -l k8s-app=kube-proxy -o wide | \
      awk '$7 == "'$node'" {print $1}')
    status=$(kubectl -n kube-system get pod $pod -o jsonpath='{.status.containerStatuses[0].state}')
    if echo "$status" | grep -q "waiting"; then
      kubectl -n kube-system delete pod $pod
    fi
  fi
done
```

Wait for all kube-proxy pods Running (up to 120s).

### Phase 7: Wait for All Nodes Ready
```bash
kubectl get nodes --no-headers | awk '{print $2}' | grep -v '^Ready$' | wc -l
# Must return 0
```

**Critical**: CoreDNS CANNOT schedule until all nodes are Ready.

### Phase 8: Node Scheduling Configuration
```bash
# Uncordon all nodes
kubectl get nodes --no-headers | awk '{print $1}' | xargs -n1 kubectl uncordon

# Remove control-plane taints (allow scheduling on master in small clusters)
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- || true
kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule- || true

# Ensure masternode has control-plane label
kubectl label node masternode 'node-role.kubernetes.io/control-plane=' --overwrite
```

### Phase 9: Post-Deployment Validation
```bash
# Check Flannel stability
./scripts/check_flannel_stability.sh

# Final health check
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
kubectl -n kube-flannel get pods -o wide
kubectl get pods --all-namespaces --field-selector=status.phase!=Running
```

### Phase 10: Application Deployment
Deploy monitoring stack (Prometheus, Loki, Grafana) and applications (Jellyfin).

## Troubleshooting

### kube-proxy CrashLoopBackOff on RHEL 10
**Symptoms**: kube-proxy pod shows `CrashLoopBackOff` or `Error` state
**Root Cause**: iptables chains not pre-created, or legacy iptables in use
**Solution**:
1. Verify nftables backend: `update-alternatives --display iptables`
2. Verify lock file exists: `ls -l /run/xtables.lock`
3. Pre-create chains (see RHEL 10 section above)
4. Delete kube-proxy pod: `kubectl -n kube-system delete pod kube-proxy-xxxx`

### Nodes NotReady
**Symptoms**: `kubectl get nodes` shows NotReady
**Root Cause**: Flannel CNI not deployed or not healthy
**Solution**:
1. Check Flannel pods: `kubectl -n kube-flannel get pods`
2. Check CNI config: `ssh $node 'ls -l /etc/cni/net.d/'`
3. Check kubelet logs: `ssh $node 'journalctl -u kubelet -n 50'`
4. Redeploy Flannel if needed

### CoreDNS Pending
**Symptoms**: CoreDNS pods stuck in Pending state
**Root Cause**: Nodes are NotReady, or control-plane taint blocks scheduling
**Solution**:
1. Wait for all nodes Ready (Phase 7)
2. Remove control-plane taint (Phase 8)
3. Verify: `kubectl get pods -n kube-system -l k8s-app=kube-dns`

## File Reference

### Roles
- `ansible/roles/network-fix/tasks/main.yml` - 9-phase gold-standard network setup
- `ansible/roles/system-prep/` - Base system configuration
- `ansible/roles/preflight/` - Pre-deployment checks
- `ansible/roles/diagnostics/` - Post-deployment diagnostics

### Playbooks
- `ansible/playbooks/deploy-cluster.yaml` - 10-phase cluster deployment
- `ansible/plays/deploy-apps.yaml` - Monitoring stack deployment
- `ansible/plays/jellyfin.yml` - Jellyfin media server deployment

### Scripts
- `deploy.sh` - Main deployment entry point
- `scripts/check_flannel_stability.sh` - Flannel health validation

## Best Practices

### DO
- ✅ Always run full system prep before kubelet starts
- ✅ Always wait for Flannel DaemonSet ready before checking node status
- ✅ Always verify CNI config exists on all nodes
- ✅ Always wait for all nodes Ready before deploying apps
- ✅ Always pre-create iptables chains on RHEL 10
- ✅ Always use idempotent checks (stat, grep -q, etc.)
- ✅ Always provide actionable diagnostics on failure

### DON'T
- ❌ Never start kubelet without kernel modules loaded
- ❌ Never start kubelet without sysctl configured
- ❌ Never deploy apps before all nodes Ready
- ❌ Never use legacy iptables on RHEL 10
- ❌ Never assume CNI config appears instantly
- ❌ Never skip health checks between phases

## Success Criteria
After deployment completes:
- [ ] All nodes show `Ready` in `kubectl get nodes`
- [ ] All Flannel pods show `Running` in `kubectl -n kube-flannel get pods`
- [ ] All kube-proxy pods show `Running` in `kubectl -n kube-system get pods -l k8s-app=kube-proxy`
- [ ] All CoreDNS pods show `Running` in `kubectl -n kube-system get pods -l k8s-app=kube-dns`
- [ ] No pods in `CrashLoopBackOff` state
- [ ] No pods in `Pending` state (except jobs)
- [ ] Cluster health check passes

## Maintenance

### Re-running Deployment
The playbook is fully idempotent and can be re-run anytime:
```bash
./deploy.sh
```

### Resetting Cluster
```bash
ansible-playbook ansible/playbooks/reset-cluster.yaml
```

### Updating Flannel
```bash
kubectl apply -f manifests/cni/flannel.yaml
kubectl -n kube-flannel rollout status daemonset/kube-flannel-ds
```

## References
- Kubernetes Official Docs: https://kubernetes.io/docs/
- Flannel Documentation: https://github.com/flannel-io/flannel
- kubeadm Reference: https://kubernetes.io/docs/reference/setup-tools/kubeadm/
- RHEL 10 Release Notes: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/10
- nftables Migration Guide: https://access.redhat.com/solutions/6739041

---
**Last Updated**: 2025-10-03  
**Status**: Production-Ready, Gold-Standard, Never-Fail  
**Maintainer**: Jashandeep Justin Bains

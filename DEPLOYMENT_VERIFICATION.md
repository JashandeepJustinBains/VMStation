# VMStation Kubernetes Deployment Verification Guide

## Overview
This guide provides step-by-step verification procedures for the VMStation Kubernetes cluster deployment. The deployment is designed to be 100% idempotent across mixed environments (Debian Bookworm control-plane + RHEL 10 workers).

## Pre-Deployment Checklist

### 1. Environment Validation
Run on masternode (192.168.4.63):

```bash
# Verify Ansible version (required: core 2.14.18+)
ansible --version

# Verify inventory file exists
cat ansible/inventory/hosts

# Verify SSH connectivity to all nodes
ansible -i ansible/inventory/hosts all -m ping

# Check OS on each node
ansible -i ansible/inventory/hosts all -m shell -a "cat /etc/os-release | grep PRETTY_NAME"
```

**Expected output:**
- masternode: Debian GNU/Linux 12 (bookworm)
- storagenodet3500: Debian GNU/Linux 12 (bookworm)
- homelab: Red Hat Enterprise Linux 10

### 2. Syntax Validation

```bash
# Validate all playbooks
ansible-playbook --syntax-check ansible/playbooks/deploy-cluster.yaml
ansible-playbook --syntax-check ansible/playbooks/reset-cluster.yaml
ansible-playbook --syntax-check ansible/playbooks/verify-cluster.yaml
```

**Expected output:** `playbook: <filename>` with exit code 0 for each

## Deployment Procedures

### Single Deployment

```bash
# Deploy cluster
./deploy.sh

# Wait for completion (typically 5-10 minutes)
# Watch for any errors in output
```

### Reset and Redeploy

```bash
# Reset cluster (removes all K8s config)
./deploy.sh reset

# Type 'yes' when prompted
# Wait for reset completion

# Deploy fresh cluster
./deploy.sh
```

### Two-Cycle Idempotency Test

```bash
# This verifies deploy → reset → deploy works perfectly
./deploy.sh reset && ./deploy.sh && \
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/verify-cluster.yaml
```

## Post-Deployment Verification

### 1. Quick Health Check

```bash
# On masternode, run:
kubectl get nodes -o wide
kubectl get pods -A
```

**Expected output:**
```
NAME                 STATUS   ROLES           AGE   VERSION
masternode           Ready    control-plane   5m    v1.29.15
storagenodet3500     Ready    <none>          4m    v1.29.15
homelab              Ready    <none>          4m    v1.29.15

NAMESPACE       NAME                                   READY   STATUS    RESTARTS
kube-flannel    kube-flannel-ds-xxxxx                  1/1     Running   0
kube-flannel    kube-flannel-ds-yyyyy                  1/1     Running   0
kube-flannel    kube-flannel-ds-zzzzz                  1/1     Running   0
kube-system     coredns-xxxxx                          1/1     Running   0
kube-system     coredns-yyyyy                          1/1     Running   0
kube-system     kube-proxy-xxxxx                       1/1     Running   0
kube-system     kube-proxy-yyyyy                       1/1     Running   0
kube-system     kube-proxy-zzzzz                       1/1     Running   0
```

### 2. Run Comprehensive Verification Playbook

```bash
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/verify-cluster.yaml
```

**Expected output:**
- ✓ kubectl connectivity working
- ✓ All 3 nodes Ready
- ✓ Flannel pods ready: 3/3
- ✓ kube-proxy pods running: 3/3
- ✓ CoreDNS pods running: 2/2
- ✓ No CrashLoopBackOff pods found
- ✓ CNI config present on all nodes
- ✓ Flannel subnet file exists on all nodes
- ✓ Flannel interface exists on all nodes

### 3. CNI Configuration Verification

```bash
# Verify CNI config on Debian nodes
for node in masternode storagenodet3500; do
  echo "=== $node ==="
  ssh root@$node "ls -l /etc/cni/net.d/10-flannel.conflist && cat /etc/cni/net.d/10-flannel.conflist | jq ."
done

# Verify CNI config on RHEL node (homelab)
echo "=== homelab ==="
ssh jashandeepjustinbains@192.168.4.62 "sudo ls -l /etc/cni/net.d/10-flannel.conflist && sudo cat /etc/cni/net.d/10-flannel.conflist | jq ."
```

**Expected output:**
- File exists: `/etc/cni/net.d/10-flannel.conflist`
- Owner: `root:root`
- Mode: `0644` (or `-rw-r--r--`)
- SELinux context (RHEL): `system_u:object_r:etc_t:s0`
- Valid JSON with `name: "cni0"`, `cniVersion: "0.3.1"`, flannel plugin

### 4. Flannel Interface Verification

```bash
# Check Flannel VXLAN interface on all nodes
for node in masternode storagenodet3500; do
  echo "=== $node ==="
  ssh root@$node "ip link show flannel.1"
done

echo "=== homelab ==="
ssh jashandeepjustinbains@192.168.4.62 "sudo ip link show flannel.1"
```

**Expected output:**
```
flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN mode DEFAULT group default
    link/ether <mac> brd ff:ff:ff:ff:ff:ff
```

### 5. Flannel Subnet Verification

```bash
# Check Flannel subnet assignment
for node in masternode storagenodet3500; do
  echo "=== $node ==="
  ssh root@$node "cat /run/flannel/subnet.env"
done

echo "=== homelab ==="
ssh jashandeepjustinbains@192.168.4.62 "sudo cat /run/flannel/subnet.env"
```

**Expected output:**
```
FLANNEL_NETWORK=10.244.0.0/16
FLANNEL_SUBNET=10.244.X.1/24
FLANNEL_MTU=1450
FLANNEL_IPMASQ=true
```

### 6. Network Backend Verification (RHEL 10 Specific)

```bash
# Verify iptables backend on RHEL node
ssh jashandeepjustinbains@192.168.4.62 "sudo update-alternatives --display iptables"
```

**Expected output:**
```
iptables - status is manual.
 link currently points to /usr/sbin/iptables-nft
```

### 7. SELinux Status (RHEL 10 Specific)

```bash
# Check SELinux mode
ssh jashandeepjustinbains@192.168.4.62 "sudo getenforce"

# Check SELinux context on CNI directory
ssh jashandeepjustinbains@192.168.4.62 "sudo ls -lZ /etc/cni/net.d/"
```

**Expected output:**
- getenforce: `Permissive`
- 10-flannel.conflist: `system_u:object_r:etc_t:s0`

### 8. Pod Network Connectivity Test

```bash
# Create test pod and verify DNS resolution
kubectl run test-busybox --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default
```

**Expected output:**
```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes.default
Address 1: 10.96.0.1 kubernetes.default.svc.cluster.local
```

## Troubleshooting

### CrashLoopBackOff on RHEL Node

```bash
# Check Flannel pod logs
kubectl logs -n kube-flannel <pod-name-on-homelab> --previous
kubectl logs -n kube-flannel <pod-name-on-homelab>

# Check kube-proxy logs
kubectl logs -n kube-system <kube-proxy-pod-on-homelab> --previous

# Verify CNI config exists
ssh jashandeepjustinbains@192.168.4.62 "sudo ls -lZ /etc/cni/net.d/"

# Verify iptables backend
ssh jashandeepjustinbains@192.168.4.62 "sudo update-alternatives --display iptables"

# Verify nftables rules
ssh jashandeepjustinbains@192.168.4.62 "sudo nft list table inet filter"
```

### Missing CNI Config

```bash
# Manually trigger network-fix role
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/deploy-cluster.yaml --tags network-fix

# Check Flannel init container logs
kubectl logs -n kube-flannel <pod-name> -c install-cni

# Verify /etc/cni/net.d directory permissions
ssh jashandeepjustinbains@192.168.4.62 "sudo ls -ld /etc/cni/net.d"
```

### Nodes Not Ready

```bash
# Check kubelet status on each node
for node in masternode storagenodet3500; do
  echo "=== $node ==="
  ssh root@$node "systemctl status kubelet"
done

echo "=== homelab ==="
ssh jashandeepjustinbains@192.168.4.62 "sudo systemctl status kubelet"

# Check kubelet logs
kubectl describe node homelab
ssh jashandeepjustinbains@192.168.4.62 "sudo journalctl -u kubelet -n 50 --no-pager"
```

## Success Criteria

After deployment and verification, you should see:

- ✅ All 3 nodes in Ready state
- ✅ No CrashLoopBackOff pods in any namespace
- ✅ Flannel DaemonSet: 3/3 pods Running (one per node)
- ✅ kube-proxy: 3/3 pods Running (one per node)
- ✅ CoreDNS: 2/2 pods Running
- ✅ /etc/cni/net.d/10-flannel.conflist exists on all nodes with correct ownership/permissions
- ✅ flannel.1 interface exists on all nodes
- ✅ /run/flannel/subnet.env exists on all nodes
- ✅ Pod-to-pod networking works (DNS resolution succeeds)
- ✅ RHEL 10 node uses iptables-nft backend
- ✅ SELinux in permissive mode on RHEL node
- ✅ nftables permissive ruleset configured on RHEL node

## Idempotency Validation

To verify 100% idempotency (can run deploy → reset → deploy 100x):

```bash
# Run this loop 5 times minimum
for i in {1..5}; do
  echo "=== Cycle $i ==="
  ./deploy.sh reset
  ./deploy.sh
  ansible-playbook -i ansible/inventory/hosts ansible/playbooks/verify-cluster.yaml
  echo "=== Cycle $i complete ==="
  sleep 10
done
```

**Expected result:** All 5 cycles complete successfully with no errors

## Automated Checks

You can also use the smoke-test script:

```bash
# Quick smoke test
./scripts/smoke-test.sh
```

## Performance Benchmarks

Typical deployment times:
- Fresh deployment: 5-7 minutes
- Reset operation: 2-3 minutes
- Verification playbook: 1-2 minutes
- Total cycle (reset + deploy + verify): 8-12 minutes

## References

- User requirements: `Output_for_Copilot.txt`
- Memory/changelog: `.github/instructions/memory.instruction.md`
- Deployment playbook: `ansible/playbooks/deploy-cluster.yaml`
- Verification playbook: `ansible/playbooks/verify-cluster.yaml`
- Network setup: `ansible/roles/network-fix/tasks/main.yml`
- Flannel manifest: `manifests/cni/flannel.yaml`

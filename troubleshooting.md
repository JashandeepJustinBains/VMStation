# Troubleshooting Guide

Quick diagnostic checks for VMStation clusters.

## Recent Fixes (October 2025)

For recently resolved deployment issues, see [Deployment Fixes Documentation](docs/DEPLOYMENT_FIXES_OCT2025.md):
- **Jellyfin not running on storagenodet3500** - Fixed by adding deployment to Phase 7
- **IPMI exporter-remote pod failures** - Fixed by setting replicas=0 when no credentials
- **Missing dashboard data** - Documented optional scrape targets

## Common Issues

### Worker Node Join Hangs

**Symptom**: Deployment hangs at "Wait for kubelet config to appear (join completion)"

**Causes**:
1. Missing kubeadm binary on master node
2. Network connectivity issues between worker and master
3. Join command failed silently

**Solution**: See [Worker Join Fix Documentation](docs/WORKER_JOIN_FIX.md) for detailed explanation.

**Quick Fix**:
```bash
# On master node, verify kubeadm is installed
which kubeadm
# If missing, install it
./scripts/install-k8s-binaries-manual.sh
```

## 1. Check Cluster Nodes

### Debian Cluster
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide
```

**Expected**: All nodes `Ready`, correct Kubernetes version.

**If not Ready**:
- Check kubelet: `systemctl status kubelet`
- View logs: `journalctl -xeu kubelet`
- Verify CNI: `ls /etc/cni/net.d/`

### RKE2 Cluster
```bash
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes -o wide
```

**If not Ready**:
- Check RKE2: `systemctl status rke2-server`
- View logs: `journalctl -xeu rke2-server`

## 2. Check System Pods

### Debian Cluster
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -o wide
```

**Expected**: All pods `Running`, no `CrashLoopBackOff`.

**Critical pods**:
- `kube-flannel-*` (3 pods, one per node)
- `kube-proxy-*` (3 pods, one per node)
- `coredns-*` (2 pods)

### RKE2 Cluster
```bash
kubectl --kubeconfig=ansible/artifacts/homelab-rke2-kubeconfig.yaml get pods -A
```

**Expected**: All system pods `Running` in `kube-system` namespace.

## 3. Verify CNI Configuration

Check if CNI config exists on all nodes:

```bash
# Debian nodes
ssh root@192.168.4.63 "cat /etc/cni/net.d/10-flannel.conflist"
ssh root@192.168.4.61 "cat /etc/cni/net.d/10-flannel.conflist"

# RHEL node (kubeadm - if mixed deployment)
# OR check RKE2 CNI
ssh jashandeepjustinbains@192.168.4.62 "sudo ls /etc/cni/net.d/"
```

**Expected**: `10-flannel.conflist` exists on Debian nodes.

**If missing**: Re-run deployment.

## 4. Check Flannel DaemonSet

```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-flannel get daemonset
```

**Expected**: `DESIRED` == `READY` == `AVAILABLE`.

**If not**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-flannel get pods -o wide
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-flannel describe pod <pod-name>
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-flannel logs <pod-name>
```

## 5. Verify Binary Installation

On masternode (control plane):
```bash
which kubeadm kubelet kubectl
kubeadm version
kubelet --version
kubectl version --client
```

**Expected**: All binaries found, version v1.29.x.

**If missing**:
- Re-run deployment (binaries auto-install)
- OR check `ansible/roles/install-k8s-binaries/tasks/main.yml` logs

## 6. Check Systemd Services

### Debian Nodes
```bash
systemctl status kubelet
systemctl status containerd
```

**Expected**: Both `active (running)`.

**If not**:
```bash
journalctl -xeu kubelet
journalctl -xeu containerd
```

### RHEL Node (RKE2)
```bash
ssh jashandeepjustinbains@192.168.4.62 "sudo systemctl status rke2-server"
```

**Expected**: `active (running)`.

## 7. Network Connectivity

Test pod-to-pod communication:
```bash
# Deploy test pod
kubectl --kubeconfig=/etc/kubernetes/admin.conf run test-pod --image=busybox --restart=Never -- sleep 3600

# Check pod IP
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pod test-pod -o wide

# Exec into pod and ping another pod
kubectl --kubeconfig=/etc/kubernetes/admin.conf exec -it test-pod -- ping <another-pod-ip>
```

**Expected**: Ping succeeds.

**If fails**:
- Check Flannel: `kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-flannel`
- Check iptables/nftables rules
- Verify sysctl: `sysctl net.bridge.bridge-nf-call-iptables`

## 8. Check Control Plane API

```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf cluster-info
```

**Expected**: Control plane running at `https://192.168.4.63:6443`.

**If not**:
```bash
# Check API server
ssh root@192.168.4.63 "crictl ps | grep kube-apiserver"
ssh root@192.168.4.63 "crictl logs <apiserver-container-id>"
```

## 9. Verify iptables/nftables Configuration

### Debian Nodes (iptables)
```bash
ssh root@192.168.4.63 "iptables -L -t nat | grep KUBE"
```

**Expected**: KUBE-SERVICES, KUBE-POSTROUTING chains exist.

### RHEL Node (nftables)
```bash
ssh jashandeepjustinbains@192.168.4.62 "sudo nft list tables"
```

**Expected**: `inet filter` table exists.

## 10. Check Logs for CrashLoopBackOff

If any pod is in CrashLoopBackOff:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A | grep CrashLoop
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n <namespace> describe pod <pod-name>
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n <namespace> logs <pod-name> --previous
```

**Common causes**:
- Missing iptables chains (RHEL) → Pre-created by network-fix role
- SELinux blocking (RHEL) → Set to permissive
- Incorrect CNI config → Check `/etc/cni/net.d/`
- Readiness probe too aggressive → Adjusted in Flannel manifest

## Quick Reset and Redeploy

If all else fails:
```bash
./deploy.sh reset
./deploy.sh all --with-rke2 --yes
```

This performs a clean deployment from scratch.

## Common Issues and Fixes

### Issue: `kubeadm: not found`
**Fix**: Re-run deployment (binaries auto-install) OR manually install binaries.

### Issue: Flannel pods CrashLoopBackOff
**Fix**: 
- Check CNI config: `/etc/cni/net.d/10-flannel.conflist`
- Check iptables chains on RHEL
- Verify nftables mode enabled in Flannel ConfigMap

### Issue: Nodes remain `NotReady`
**Fix**:
- Check kubelet logs: `journalctl -xeu kubelet`
- Verify CNI: `ls /etc/cni/net.d/`
- Check containerd: `systemctl status containerd`

### Issue: `Unable to connect to the server`
**Fix**:
- Verify KUBECONFIG: `export KUBECONFIG=/etc/kubernetes/admin.conf`
- Check API server: `kubectl --kubeconfig=/etc/kubernetes/admin.conf cluster-info`
- Verify control plane pod: `crictl ps | grep apiserver`

### Issue: RKE2 deployment fails
**Fix**:
- Check vault password: `ansible-vault view ansible/inventory/group_vars/secrets.yml`
- Run with vault: `./deploy.sh rke2 --ask-vault-pass`
- Check RKE2 logs: `sudo journalctl -xeu rke2-server`

### Issue: Jellyfin not running or not on storagenodet3500
**Fix**:
- Verify deployment: `kubectl get pods -n jellyfin -o wide`
- Check node selector: `kubectl describe pod jellyfin -n jellyfin | grep Node-Selectors`
- Expected: Should be scheduled on storagenodet3500
- If missing: Re-run deployment with Phase 7 fixes (see [DEPLOYMENT_FIXES_OCT2025.md](docs/DEPLOYMENT_FIXES_OCT2025.md))

### Issue: IPMI exporter pods in Error state
**Fix**:
- Check if credentials configured: `kubectl get secret ipmi-credentials -n monitoring`
- If no credentials needed: Pods should be at 0 replicas (not Error)
- Verify: `kubectl get deployment ipmi-exporter-remote -n monitoring`
- Expected replicas: 0 (unless credentials configured)
- See [DEPLOYMENT_FIXES_OCT2025.md](docs/DEPLOYMENT_FIXES_OCT2025.md) for details

### Issue: Grafana dashboards empty or missing data
**Fix**:
- Check Prometheus targets: http://192.168.4.63:30090/targets
- Verify core targets UP: kubernetes-nodes, kubernetes-cadvisor, node-exporter
- Optional targets DOWN are OK: rke2-federation, ipmi-exporter-remote
- Check pod logs: `kubectl logs -n monitoring -l app=prometheus`
- See [DEPLOYMENT_FIXES_OCT2025.md](docs/DEPLOYMENT_FIXES_OCT2025.md) for target details

### Issue: Idempotency test fails
**Fix**:
- Review failure: `./tests/test-idempotence.sh`
- Check for non-idempotent tasks in playbooks
- Verify reset cleanup: `./deploy.sh reset` → check `/etc/kubernetes` removed

## Getting Help

If issues persist:
1. Collect diagnostics: `kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A -o wide`
2. Gather logs: `journalctl -xeu kubelet > kubelet.log`
3. Check playbook output for errors
4. Review `archive/legacy-docs/` for historical issues

## Useful Commands

```bash
# Check all nodes
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide

# Check all pods
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A -o wide

# Check specific namespace
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system get pods

# Describe problematic pod
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n <ns> describe pod <pod>

# View pod logs
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n <ns> logs <pod>

# Exec into pod
kubectl --kubeconfig=/etc/kubernetes/admin.conf exec -it <pod> -- /bin/sh

# Check cluster info
kubectl --kubeconfig=/etc/kubernetes/admin.conf cluster-info dump
```

# Flannel CNI Timing Issue - CrashLoopBackOff Fix

## Problem Statement

After deploying the Kubernetes cluster, the following issues were observed in kubectl events:

### Symptoms
1. **Flannel pods crash with BackOff errors** on some nodes (especially homelab/RHEL10)
2. **CoreDNS pods fail to create pod sandbox** with error: `failed to find plugin "flannel" in path [/opt/cni/bin]`
3. **kube-proxy pods enter CrashLoopBackOff**
4. **Missing subnet.env file** error: `open /run/flannel/subnet.env: no such file or directory`

### Example kubectl events:
```
14m  Warning  FailedCreatePodSandBox  pod/coredns-76f75df574-bxkpm
  Failed to create pod sandbox: rpc error: code = Unknown desc = failed to setup network for sandbox
  plugin type="flannel" failed (add): failed to find plugin "flannel" in path [/opt/cni/bin]

14m  Warning  FailedCreatePodSandBox  pod/coredns-76f75df574-bxkpm
  Failed to create pod sandbox: plugin type="flannel" failed (add): 
  failed to load flannel 'subnet.env' file: open /run/flannel/subnet.env: no such file or directory

4m32s  Warning  BackOff  pod/kube-flannel-ds-ppwb4
  Back-off restarting failed container kube-flannel
```

## Root Cause Analysis

### Timeline of the Issue
1. **Flannel DaemonSet is applied** to the cluster
2. **Flannel init containers run successfully** (install-cni-plugin, install-cni)
   - Copy `/opt/cni/bin/flannel` binary
   - Copy `/etc/cni/net.d/10-flannel.conflist` config
3. **Flannel main container (kube-flannel) starts** but takes time to initialize
4. **RACE CONDITION**: CoreDNS and kube-proxy pods are scheduled BEFORE flannel daemon creates `/run/flannel/subnet.env`
5. **Pod sandbox creation fails** because subnet.env doesn't exist yet
6. **Flannel container crashes** due to various reasons (nftables, SELinux, timing issues on RHEL10)
7. **Cascading failures** as pods can't get network connectivity

### Why `kubectl rollout status` Was Insufficient

The original deployment playbook used:
```yaml
- name: Wait for Flannel DaemonSet rollout
  ansible.builtin.shell: |
    kubectl rollout status daemonset/kube-flannel-ds --timeout=180s
```

**Problem**: This command only waits for the DaemonSet to be **deployed** (pods scheduled and containers starting), but **does NOT wait for pods to be Ready**.

The flannel.yaml includes a readinessProbe:
```yaml
readinessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - test -f /run/flannel/subnet.env
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 10
```

This probe checks for `/run/flannel/subnet.env`, which is created by the flannel daemon AFTER it successfully initializes networking. However, the deployment proceeded before this probe passed.

## Solution

### Changes to `ansible/playbooks/deploy-cluster.yaml`

Added comprehensive readiness checks after flannel deployment:

#### 1. Wait for Flannel Pods to be Ready (Not Just Running)
```yaml
- name: Wait for all Flannel pods to be Ready (not just Running)
  ansible.builtin.shell: |
    set -e
    total_nodes=$(kubectl get nodes --no-headers | wc -l)
    ready_flannel=$(kubectl -n kube-flannel get pods -l app=flannel --field-selector=status.phase=Running -o json | \
      jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')
    echo "Flannel pods ready: $ready_flannel / $total_nodes"
    test "$ready_flannel" -eq "$total_nodes"
  retries: 30
  delay: 5
  register: flannel_ready
  until: flannel_ready.rc == 0
```

**What this does:**
- Counts total nodes in the cluster
- Checks how many flannel pods have `status.conditions.Ready == True`
- Waits until **all nodes have a Ready flannel pod**
- Retries for up to 2.5 minutes (30 retries × 5 seconds)

#### 2. Verify subnet.env Exists on All Nodes
```yaml
- name: Verify subnet.env exists on all nodes
  ansible.builtin.shell: |
    kubectl -n kube-flannel get pods -l app=flannel -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | \
    while read node; do
      if [ "$node" = "homelab" ]; then
        ssh jashandeepjustinbains@192.168.4.62 'sudo test -f /run/flannel/subnet.env' || { echo "subnet.env missing on $node"; exit 1; }
      else
        ssh root@$node 'test -f /run/flannel/subnet.env' || { echo "subnet.env missing on $node"; exit 1; }
      fi
      echo "✓ subnet.env exists on $node"
    done
  retries: 10
  delay: 5
  register: subnet_check
  until: subnet_check.rc == 0
```

**What this does:**
- Gets list of nodes from flannel pod specs
- SSH to each node to verify `/run/flannel/subnet.env` exists
- Handles different SSH credentials (root vs. jashandeepjustinbains)
- Retries for up to 50 seconds

#### 3. Verify CNI Flannel Binary Exists
```yaml
- name: Verify CNI flannel binary exists on all nodes
  ansible.builtin.stat:
    path: /opt/cni/bin/flannel
  delegate_to: "{{ item }}"
  loop:
    - masternode
    - storagenodet3500
    - homelab
  register: cni_binary_check
  failed_when: not cni_binary_check.stat.exists
```

**What this does:**
- Verifies the flannel CNI plugin binary is present at `/opt/cni/bin/flannel`
- Fails deployment if binary is missing on any node

## Expected Behavior After Fix

### Deployment Flow
1. ✅ Flannel DaemonSet applied
2. ✅ Wait for DaemonSet rollout (pods scheduled)
3. ✅ **NEW**: Wait for all flannel pods to pass readinessProbe (Ready status)
4. ✅ **NEW**: Verify subnet.env exists on all nodes
5. ✅ **NEW**: Verify flannel binary exists on all nodes
6. ✅ Proceed with verifying all nodes are Ready
7. ✅ CoreDNS and other pods can now successfully create pod sandboxes

### What Should Happen
- No more "failed to find plugin 'flannel'" errors
- No more "failed to load flannel 'subnet.env' file" errors
- Flannel pods stay Running (not CrashLoopBackOff)
- CoreDNS and kube-proxy start successfully
- All pods get proper network connectivity

## Validation

### 1. Check Flannel Pod Status
```bash
kubectl -n kube-flannel get pods -o wide
```
**Expected**: All pods should be `Running` with `1/1 READY`

### 2. Verify subnet.env on Each Node
```bash
# On masternode and storagenodet3500
ssh root@masternode 'cat /run/flannel/subnet.env'
ssh root@storagenodet3500 'cat /run/flannel/subnet.env'

# On homelab (RHEL10)
ssh jashandeepjustinbains@192.168.4.62 'sudo cat /run/flannel/subnet.env'
```
**Expected output:**
```
FLANNEL_NETWORK=10.244.0.0/16
FLANNEL_SUBNET=10.244.X.1/24
FLANNEL_MTU=1450
FLANNEL_IPMASQ=true
```

### 3. Check for CrashLoopBackOff
```bash
kubectl get pods --all-namespaces | grep -i crash
```
**Expected**: No output (no crashing pods)

### 4. Test DNS Resolution
```bash
kubectl run dns-test --image=busybox:1.28 --rm -it --restart=Never -- nslookup kubernetes.default
```
**Expected**: Successful DNS resolution

## Related Issues

This fix addresses the root cause of several related issues documented in:
- `HOMELAB_NODE_FIXES.md` - Flannel CrashLoopBackOff on homelab node
- `COREDNS_UNKNOWN_STATUS_FIX.md` - CoreDNS scheduling issues
- `DEPLOYMENT_VERIFICATION.md` - CNI verification procedures

## Prevention

The enhanced deployment now ensures:
1. **Explicit readiness validation** before proceeding
2. **File-level verification** of critical CNI components
3. **Proper timing** between flannel initialization and pod scheduling
4. **Idempotent deployment** that can recover from partial failures

## Troubleshooting

If flannel pods still fail to reach Ready status after 2.5 minutes:

### 1. Check Flannel Pod Logs
```bash
# Get flannel pod name for a specific node
FLANNEL_POD=$(kubectl -n kube-flannel get pods -l app=flannel --field-selector spec.nodeName=homelab -o name | head -1)

# Check logs
kubectl -n kube-flannel logs $FLANNEL_POD -c kube-flannel
kubectl -n kube-flannel logs $FLANNEL_POD -c kube-flannel --previous
```

### 2. Check Node-Specific Issues

For RHEL10/homelab node:
```bash
# Check SELinux status
ssh jashandeepjustinbains@192.168.4.62 'sudo getenforce'

# Check iptables backend
ssh jashandeepjustinbains@192.168.4.62 'sudo update-alternatives --display iptables'

# Check for nftables conflicts
ssh jashandeepjustinbains@192.168.4.62 'sudo nft list ruleset'

# Check kernel modules
ssh jashandeepjustinbains@192.168.4.62 'lsmod | grep -E "br_netfilter|vxlan|overlay"'
```

### 3. Manual Remediation

If automated fixes fail, use the emergency fix script:
```bash
./scripts/fix-flannel-homelab.sh
```

This script will:
- Set SELinux to permissive
- Load required kernel modules
- Set iptables to legacy mode (if needed)
- Clear stale CNI configurations
- Restart kubelet
- Force flannel pod recreation

## Related Files

- `ansible/playbooks/deploy-cluster.yaml` - Enhanced deployment with readiness checks
- `manifests/cni/flannel.yaml` - Flannel DaemonSet with readinessProbe
- `scripts/fix-flannel-homelab.sh` - Emergency remediation script
- `DEPLOYMENT_VERIFICATION.md` - Post-deployment verification procedures

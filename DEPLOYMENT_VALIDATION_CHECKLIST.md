# Deployment Validation Checklist

## Pre-Deployment

- [ ] SSH access to masternode (192.168.4.63) working
- [ ] Git repo pulled on masternode: `cd /srv/monitoring_data/VMStation && git pull`
- [ ] Backup current config (optional): `kubectl get all -A > backup.yaml`

## Deployment Steps

### 1. Reset Cluster (Clean Slate)
```bash
cd /srv/monitoring_data/VMStation
./deploy.sh reset
```

**Expected Output**:
- Confirmation prompt: Type `yes`
- Nodes drained gracefully
- kubeadm reset on all nodes
- Network interfaces cleaned
- SSH keys preserved
- "CLUSTER RESET COMPLETED SUCCESSFULLY"

**Validation**:
- [ ] No errors during reset
- [ ] Can still SSH to all nodes
- [ ] `kubectl get nodes` returns error (expected - cluster is reset)

### 2. Deploy Cluster
```bash
./deploy.sh
```

**Expected Duration**: 5-10 minutes

**Expected Output Phases**:
1. ✅ Phase 1: System preparation (kernel modules, sysctl)
2. ✅ Phase 2: CNI plugins installation
3. ✅ Phase 3: Control plane initialization
4. ✅ Phase 4: Worker node join
5. ✅ Phase 5: Flannel CNI deployment
6. ✅ Phase 6: Wait for all nodes Ready
7. ✅ Phase 7: Node scheduling configuration
8. ✅ Phase 8: Post-deployment validation
9. ✅ Phase 9: Application deployment

**Validation After Deployment**:
- [ ] No Ansible errors
- [ ] All phases completed
- [ ] Final cluster status shows all nodes Ready

### 3. Immediate Post-Deployment Checks

```bash
# Check nodes
kubectl get nodes -o wide
```

**Expected**:
```
NAME               STATUS   ROLES           AGE   VERSION
homelab            Ready    <none>          5m    v1.29.15
masternode         Ready    control-plane   5m    v1.29.15
storagenodet3500   Ready    <none>          5m    v1.29.15
```

- [ ] All nodes show `Ready`
- [ ] AGE is recent (< 10m)
- [ ] No `NotReady` nodes

```bash
# Check all pods
kubectl get pods -A -o wide
```

**Expected**:
- [ ] All pods in `Running` state
- [ ] **NO** `CrashLoopBackOff`
- [ ] **NO** `Error`
- [ ] **NO** `Pending` (after 5 minutes)

**Critical Pods to Check**:

```bash
# Flannel
kubectl -n kube-flannel get pods -o wide
```
- [ ] 3 pods (one per node)
- [ ] All `Running`
- [ ] RESTARTS = 0 or low (< 3)

```bash
# kube-proxy
kubectl -n kube-system get pods -l k8s-app=kube-proxy -o wide
```
- [ ] 3 pods (one per node)
- [ ] All `Running`
- [ ] RESTARTS = 0 or low (< 3)

```bash
# CoreDNS
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
```
- [ ] 2 pods
- [ ] All `Running`
- [ ] NOT on homelab node (should be on masternode/storage)

```bash
# Monitoring stack
kubectl -n monitoring get pods -o wide
```
- [ ] prometheus, grafana, loki all `Running`
- [ ] All on masternode

```bash
# Jellyfin
kubectl -n jellyfin get pods -o wide
```
- [ ] 1 pod `Running`
- [ ] On storagenodet3500 node

### 4. Check for CrashLoopBackOff
```bash
kubectl get pods -A | grep -i crash
```

**Expected**: Empty output (no matches)

- [ ] No CrashLoopBackOff anywhere
- [ ] If found, note pod name and namespace for investigation

### 5. Stability Test (Wait 5 Minutes)
```bash
# Set a timer for 5 minutes
sleep 300

# Re-check pods
kubectl get pods -A | grep -i crash
```

**Expected**: Still empty

- [ ] No new CrashLoopBackOff after 5 minutes
- [ ] Pod restart counts haven't increased significantly

### 6. Check Logs for Issues

```bash
# Flannel logs (especially on homelab node)
kubectl -n kube-flannel logs -l app=flannel --tail=100
```

**Expected**:
- [ ] No "shutdownHandler sent cancel signal" messages
- [ ] Shows "Starting flannel in nftables mode" (RHEL 10 node)
- [ ] Shows "watching for new subnet leases"
- [ ] No error messages

```bash
# kube-proxy logs (especially on homelab node)
kubectl -n kube-system logs -l k8s-app=kube-proxy --tail=100
```

**Expected**:
- [ ] Shows "Using iptables Proxier"
- [ ] Shows "Caches are synced"
- [ ] No error or warning messages

### 7. Pod Networking Test
```bash
# Create test pod
kubectl run test-pod --image=busybox --command -- sleep 3600

# Wait for Running
kubectl wait --for=condition=Ready pod/test-pod --timeout=60s

# Test DNS resolution
kubectl exec test-pod -- nslookup kubernetes.default

# Test pod-to-pod communication
kubectl exec test-pod -- ping -c 3 10.244.0.1

# Cleanup
kubectl delete pod test-pod
```

**Expected**:
- [ ] Pod reaches `Running` state within 60s
- [ ] DNS resolution works (returns IP addresses)
- [ ] Ping succeeds (0% packet loss)

### 8. Node Network Validation

```bash
# On homelab (RHEL 10) node
ssh homelab
```

```bash
# Check nftables
nft list ruleset | grep -A 5 "chain forward"
# Expected: policy accept

# Check Flannel interface
ip addr show flannel.1
# Expected: flannel.1 exists and is UP

# Check CNI bridge
ip addr show cni0
# Expected: cni0 exists and is UP

# Check kernel modules
lsmod | grep -E 'br_netfilter|overlay|vxlan|nf_conntrack'
# Expected: All loaded

# Exit homelab node
exit
```

**Validation**:
- [ ] nftables FORWARD chain has `policy accept`
- [ ] flannel.1 interface is UP
- [ ] cni0 bridge exists and is UP
- [ ] All required kernel modules loaded

### 9. Extended Stability Test (Optional but Recommended)

```bash
# Watch pods for 10 minutes
watch -n 30 'kubectl get pods -A | grep -v Running'
```

**Expected**: Empty list (all pods Running)

- [ ] All pods remain `Running` for 10 minutes
- [ ] No restarts during observation period
- [ ] No new CrashLoopBackOff

### 10. Idempotency Test (Critical)

```bash
# Test deploy → reset → deploy cycle
for i in {1..3}; do
  echo "=== Iteration $i ==="
  ./deploy.sh reset
  # Type 'yes' when prompted
  
  ./deploy.sh
  
  # Wait for cluster ready
  kubectl wait --for=condition=Ready nodes --all --timeout=300s
  
  # Check for crashes
  if kubectl get pods -A | grep -i crash; then
    echo "❌ FAIL: CrashLoopBackOff detected in iteration $i"
    break
  else
    echo "✅ PASS: Iteration $i completed successfully"
  fi
  
  echo ""
done
```

**Expected**:
- [ ] All 3 iterations complete successfully
- [ ] No CrashLoopBackOff in any iteration
- [ ] Each deployment takes similar time (~5-10 min)

## Success Criteria Summary

✅ **Deployment**:
- All phases complete without errors
- Deployment completes in 5-10 minutes

✅ **Cluster Health**:
- All 3 nodes `Ready`
- All pods `Running` (no CrashLoopBackOff)
- CoreDNS, Flannel, kube-proxy stable on all nodes

✅ **RHEL 10 Specific**:
- Flannel pod on homelab node stays `Running`
- kube-proxy pod on homelab node stays `Running`
- No "Pod sandbox changed" events
- Logs show "Starting flannel in nftables mode"

✅ **Pod Networking**:
- DNS resolution works
- Pod-to-pod communication works
- Test pods can be created and reach Running state

✅ **Stability**:
- Pods remain stable for 10+ minutes
- No unexpected restarts
- Can run deploy → reset → deploy 3x without failures

✅ **Idempotency**:
- Reset always succeeds
- Deploy always succeeds after reset
- No manual intervention required

## Failure Scenarios and Recovery

### If CrashLoopBackOff Detected

1. **Check which pod**:
   ```bash
   kubectl get pods -A | grep -i crash
   ```

2. **Get pod details**:
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   ```

3. **Check logs**:
   ```bash
   kubectl logs <pod-name> -n <namespace>
   ```

4. **Common fixes**:
   - Flannel: Check nftables config, verify `EnableNFTables: true`
   - kube-proxy: Check iptables chains pre-created
   - Any pod: Check events for "SandboxChanged"

### If Nodes Not Ready

1. **Check node status**:
   ```bash
   kubectl describe node <node-name>
   ```

2. **Check kubelet**:
   ```bash
   ssh <node> "systemctl status kubelet"
   ```

3. **Check CNI**:
   ```bash
   ssh <node> "ls -la /etc/cni/net.d/"
   ```

### If Reset Fails

1. **Manual cleanup**:
   ```bash
   # On each node
   ssh <node>
   kubeadm reset --force
   rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd /etc/cni/net.d/*
   systemctl restart containerd
   ```

2. **Re-run reset**:
   ```bash
   ./deploy.sh reset
   ```

## Documentation References

- **Fix Details**: `DEPLOYMENT_FIX_SUMMARY.md`
- **Troubleshooting**: `docs/FLANNEL_CRASHLOOP_FIX.md`
- **Deployment Guide**: `DEPLOYMENT_GUIDE.md`
- **Quick Reference**: `QUICK_COMMAND_REFERENCE.md`

## Time Estimates

- Reset: 2-3 minutes
- Deploy: 5-10 minutes
- Validation: 5 minutes
- Extended stability test: 10 minutes
- Idempotency test (3 iterations): 30-45 minutes

**Total for full validation**: ~1 hour

## Contact/Escalation

If after following this checklist you still encounter CrashLoopBackOff:

1. Capture full state:
   ```bash
   kubectl get pods -A -o wide > pod-status.txt
   kubectl get nodes -o wide > node-status.txt
   kubectl logs -n kube-flannel -l app=flannel --tail=500 > flannel-logs.txt
   kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=500 > kube-proxy-logs.txt
   ssh homelab "nft list ruleset" > homelab-nftables.txt
   ```

2. Review `docs/FLANNEL_CRASHLOOP_FIX.md` troubleshooting section

3. Check if any manual steps were missed in `DEPLOYMENT_FIX_SUMMARY.md`

---

**Last Updated**: October 4, 2025  
**Version**: 1.0 - RHEL 10 nftables fix  
**Tested On**: Debian 12 + RHEL 10 mixed cluster

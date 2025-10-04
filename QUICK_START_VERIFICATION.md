# Quick Start - Verification Commands

## On Masternode (192.168.4.63)

### Step 1: Syntax Validation
```bash
cd /root/VMStation
ansible-playbook --syntax-check ansible/playbooks/deploy-cluster.yaml
ansible-playbook --syntax-check ansible/playbooks/verify-cluster.yaml
```
**Expected:** `playbook: <filename>` for each (exit code 0)

### Step 2: Deploy Cluster
```bash
./deploy.sh
```
**Expected:** 
- Completes in 5-10 minutes
- No errors in output
- Ends with "Deployment completed successfully"

### Step 3: Quick Health Check
```bash
kubectl get nodes
kubectl get pods -A
```
**Expected:**
```
NAME                 STATUS   ROLES           AGE
masternode           Ready    control-plane   5m
storagenodet3500     Ready    <none>          4m
homelab              Ready    <none>          4m
```
All pods in Running state, no CrashLoopBackOff

### Step 4: Run Verification Playbook
```bash
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/verify-cluster.yaml
```
**Expected:**
- ✓ All 3 nodes Ready
- ✓ Flannel pods ready: 3/3
- ✓ kube-proxy pods running: 3/3
- ✓ CoreDNS pods running: 2/2
- ✓ No CrashLoopBackOff pods found
- ✓ CNI config present on all nodes

### Step 5: Idempotency Test (Two Cycles)
```bash
./deploy.sh reset
./deploy.sh
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/verify-cluster.yaml
```
**Expected:** All commands succeed, verification passes

### Step 6: Multi-Cycle Test (Optional)
```bash
for i in {1..5}; do
  echo "=== Cycle $i ==="
  ./deploy.sh reset
  ./deploy.sh
done
```
**Expected:** All 5 cycles complete without errors

## Verification Checklist

After deployment, verify:

- [ ] All 3 nodes show Ready status
- [ ] No CrashLoopBackOff pods in any namespace
- [ ] Flannel DaemonSet: 3/3 pods Running
- [ ] kube-proxy: 3/3 pods Running
- [ ] CoreDNS: 2/2 pods Running
- [ ] CNI config exists on all nodes: `/etc/cni/net.d/10-flannel.conflist`
- [ ] Flannel interface exists on all nodes: `flannel.1`
- [ ] Pod networking works: DNS resolution succeeds

## Quick Troubleshooting

### If CrashLoopBackOff on homelab node:
```bash
# Check Flannel logs
kubectl logs -n kube-flannel $(kubectl get pods -n kube-flannel -o name | grep homelab) --previous

# Verify CNI config
ssh jashandeepjustinbains@192.168.4.62 "sudo ls -l /etc/cni/net.d/"

# Verify iptables backend
ssh jashandeepjustinbains@192.168.4.62 "sudo update-alternatives --display iptables"
```

### If CNI file missing:
```bash
# Re-run network-fix role
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/deploy-cluster.yaml --tags network-fix

# Check init container logs
kubectl logs -n kube-flannel <pod-name> -c install-cni
```

## Success Indicators

✅ **All pods Running within 5 minutes of deployment**
✅ **No manual intervention required post-deployment**
✅ **Can run deploy → reset → deploy repeatedly without errors**
✅ **Verification playbook passes all checks**

## References

- Full verification guide: `DEPLOYMENT_VERIFICATION.md`
- Technical details: `IDEMPOTENCY_FIXES_DETAILS.md`
- Changelog: `.github/instructions/memory.instruction.md`
- User requirements: `Output_for_Copilot.txt`

## Performance Benchmarks

- Fresh deployment: 5-7 minutes
- Reset operation: 2-3 minutes
- Verification playbook: 1-2 minutes
- Total cycle time: 8-12 minutes

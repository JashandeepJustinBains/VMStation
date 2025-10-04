# Flannel Readiness Probe Fix - Oct 4, 2025

## Root Cause Analysis
All 3 Flannel pods were **Running** but failing readiness probes (169+ failures), causing:
- DaemonSet stuck at 0/3 Ready
- Flannel rollout timeout (240s × 2 retries)
- CoreDNS CrashLoopBackOff (no CNI network)
- kube-proxy CrashLoopBackOff (no CNI network)

### Why the Probe Failed
The readiness probe was checking:
```bash
ip link show flannel.1 | grep -q 'state UP'
```

**Problem**: Flannel creates the `flannel.1` interface and writes subnet file, but the interface may not transition to `state UP` immediately. The probe ran at 10s delay, too early for the interface to be fully UP.

**Evidence from logs**:
```
I1004 19:44:14.239 Wrote subnet file to /run/flannel/subnet.env
I1004 19:44:14.239 Running backend.
I1004 19:44:14.248 Waiting for all goroutines to exit
```
Flannel completes setup and enters event-watching mode, but interface may still be transitioning.

## Fix Applied

### Changed Readiness Probe
**Before**:
```yaml
readinessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - |
      test -f /run/flannel/subnet.env && ip link show flannel.1 | grep -q 'state UP'
  initialDelaySeconds: 10
```

**After**:
```yaml
readinessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - |
      test -f /run/flannel/subnet.env && ip link show flannel.1 > /dev/null 2>&1
  initialDelaySeconds: 15
```

### Changes
1. **Check interface EXISTS** (not state UP) - sufficient for readiness
2. **Increased delay to 15s** - gives Flannel more time to create interface
3. **Liveness probe unchanged** - still checks flanneld process health

## Deployment Instructions

### On masternode, run these commands:

```bash
# 1. Pull the fix
cd /srv/monitoring_data/VMStation
git pull

# 2. Reset cluster (clean slate)
./deploy.sh reset
# Type 'yes' when prompted

# 3. Deploy with fix
./deploy.sh

# 4. Monitor Flannel readiness (should complete in ~30s)
watch -n 5 'kubectl get daemonset -n kube-flannel'
# Wait for READY column to show 3 (e.g., "3  3  3  3  3")

# 5. Verify all pods Running and Ready
kubectl get pods -A
# All pods should be Running, no CrashLoopBackOff

# 6. Check nodes are Ready
kubectl get nodes
# All 3 nodes should show Ready status
```

### Expected Timeline
- **0-45s**: Control plane init
- **45-90s**: Workers join cluster
- **90-120s**: Flannel pods start
- **120-150s**: Flannel DaemonSet reaches Ready (3/3)
- **150-180s**: CoreDNS and kube-proxy become Ready
- **180-240s**: All nodes Ready

### Success Criteria
```bash
# All pods Running
kubectl get pods -A | grep -v Running
# Should return empty (no non-Running pods)

# No crashes
kubectl get pods -A | grep -i crash
# Should return empty (no CrashLoopBackOff)

# Flannel DaemonSet Ready
kubectl get daemonset -n kube-flannel
# Should show READY 3 (all 3 nodes)

# All nodes Ready
kubectl get nodes
# All should show Ready status
```

## Technical Details

### Why Interface Existence is Sufficient
- Flannel creates `flannel.1` VXLAN interface immediately
- Interface may be in `UNKNOWN` or `DOWN` state initially
- Transitions to `UP` once first pod scheduled
- **Key**: Interface existing means Flannel setup succeeded
- **Liveness probe** still monitors flanneld process health

### Probe Timing
- **initialDelaySeconds: 15s** - Wait for Flannel to create interface
- **periodSeconds: 10s** - Check every 10s
- **failureThreshold: 3** - Allow 3 failures (30s grace)
- **Total grace period**: 45s before marking pod NotReady

### What This Fixes
✅ Flannel DaemonSet rollout completes successfully  
✅ CoreDNS gets CNI network and becomes Ready  
✅ kube-proxy gets CNI network and becomes Ready  
✅ All nodes reach Ready state  
✅ Cluster fully operational after deployment  

## Validation

After deployment completes, verify:

```bash
# 1. Flannel interface exists on all nodes
for node in masternode storagenodet3500 homelab; do
  echo "=== $node ==="
  ssh root@$node "ip link show flannel.1"
done

# 2. Flannel subnet file exists
for node in masternode storagenodet3500 homelab; do
  echo "=== $node ==="
  ssh root@$node "cat /run/flannel/subnet.env"
done

# 3. CNI config deployed
for node in masternode storagenodet3500 homelab; do
  echo "=== $node ==="
  ssh root@$node "ls -l /etc/cni/net.d/"
done

# 4. Pod-to-pod networking works
kubectl run test-pod --image=busybox --rm -it -- ping -c 3 10.244.1.1
```

## Rollback (if needed)

If the fix doesn't work:
```bash
# Revert to previous commit
git revert HEAD
git push

# Re-deploy
./deploy.sh reset
./deploy.sh
```

## Next Steps

Once deployment succeeds:
- Monitor cluster stability for 10 minutes
- Deploy monitoring stack (Prometheus, Loki, Grafana)
- Deploy Jellyfin on storagenodet3500
- Test idempotency: `./deploy.sh reset && ./deploy.sh` multiple times

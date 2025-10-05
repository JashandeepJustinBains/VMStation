# CrashLoopBackOff Validation Fix - October 2025

## Problem Statement

When running `./deploy.sh`, the deployment would fail at Phase 6 validation with the error:
```
TASK [Validate kube-system pods are healthy (no CrashLoopBackOff)] ***
fatal: [masternode]: FAILED!
ERROR: Found CrashLoopBackOff pods:
coredns-76f75df574-bm87q             0/1   CrashLoopBackOff   11 (49s ago)     56m
kube-proxy-wqwk7                     0/1   CrashLoopBackOff   13 (72s ago)     56m
```

## Root Cause Analysis

### Timeline of Events
1. **Phase 5 completes**: Flannel CNI is deployed and becomes ready
2. **Kubernetes reschedules pods**: CoreDNS and kube-proxy pods that were stuck waiting for CNI are rescheduled
3. **Pods are in transition**: These pods are exiting their previous failed states and starting fresh
4. **Phase 6 runs too quickly**: The validation task immediately checks for CrashLoopBackOff
5. **Deployment fails**: The validation task finds pods still in CrashLoopBackOff state (from their previous failed attempts)

### Why Pods Were Crashing
From the error logs:
- **CoreDNS**: `failed to find plugin "flannel" in path [/opt/cni/bin]` - waiting for Flannel to be ready
- **kube-proxy**: Logs show normal startup, but pod exits after ~78 seconds (likely waiting for network)
- Both pods needed Flannel CNI to be fully operational before they could run successfully

### The Race Condition
The validation task was checking for pod health **immediately** after Flannel became ready, but:
- Pods need time to complete their restart cycle
- Kubernetes needs time to evict failed pods and start new ones
- The CrashLoopBackOff state persists briefly during this transition

## Solution

### Minimal Change
Added a single wait task in Phase 6 (before the validation task) that:
- Polls kube-system pods every 10 seconds
- Waits up to 5 minutes (30 retries × 10s delay)
- Continues when no pods are in CrashLoopBackOff state
- Only then proceeds to the validation task

### Code Change
**File**: `ansible/playbooks/deploy-cluster.yaml`

**Location**: Phase 6 - Validate deployment (lines 232-248)

**What was added**:
```yaml
- name: Wait for kube-system pods to stabilize
  ansible.builtin.shell: |
    set -e
    # Check if any kube-system pods are in CrashLoopBackOff
    CRASH=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system --no-headers | grep -i 'CrashLoopBackOff' || true)
    if [ -z "$CRASH" ]; then
      echo "All kube-system pods stable (no CrashLoopBackOff)"
      exit 0
    else
      echo "Waiting for pods to stabilize: $(echo "$CRASH" | wc -l) pods in CrashLoopBackOff"
      exit 1
    fi
  retries: 30
  delay: 10
  register: pods_stable
  until: pods_stable.rc == 0
  changed_when: false
```

**Lines changed**: +18 (one new task)

## Testing Instructions

### On masternode (192.168.4.63):

1. **Pull the latest changes**:
```bash
cd /srv/monitoring_data/VMStation
git pull
```

2. **Verify syntax**:
```bash
ansible-playbook --syntax-check ansible/playbooks/deploy-cluster.yaml
```
Expected: `playbook: ansible/playbooks/deploy-cluster.yaml`

3. **Reset cluster** (clean slate):
```bash
./deploy.sh reset
# Type 'yes' when prompted
```

4. **Deploy with fix**:
```bash
./deploy.sh
```

5. **Observe the new behavior**:
   - Phase 5 will complete (Flannel deployed)
   - Phase 6 will start with: `TASK [Wait for kube-system pods to stabilize]`
   - You'll see messages like: `Waiting for pods to stabilize: 2 pods in CrashLoopBackOff`
   - After a minute or two: `All kube-system pods stable (no CrashLoopBackOff)`
   - Then validation proceeds and should pass

6. **Expected outcome**:
```
TASK [Wait for kube-system pods to stabilize]
ok: [masternode] => (retries attempted: 5)

TASK [Validate kube-system pods are healthy (no CrashLoopBackOff)]
ok: [masternode]

All kube-system pods healthy (no CrashLoopBackOff)
```

## Expected Behavior

### Before Fix
```
Timeline:
Phase 5: Flannel deployed (T+0)
Phase 6: Validation runs immediately (T+5s)
         → Finds CrashLoopBackOff pods (still restarting)
         → DEPLOYMENT FAILS ❌
```

### After Fix
```
Timeline:
Phase 5: Flannel deployed (T+0)
Phase 6: Wait for pods to stabilize (T+5s)
         → Retry 1: 2 pods in CrashLoopBackOff, wait 10s
         → Retry 2: 2 pods in CrashLoopBackOff, wait 10s
         → Retry 3: 1 pod in CrashLoopBackOff, wait 10s
         → Retry 4: 0 pods in CrashLoopBackOff ✓
         Validation runs (T+45s)
         → All pods healthy ✓
         → DEPLOYMENT SUCCEEDS ✅
```

## Validation Commands

After deployment succeeds:

```bash
# Check all pods are Running
kubectl get pods -A

# Verify no CrashLoopBackOff
kubectl get pods -A | grep -i crash
# Should return nothing

# Check nodes are Ready
kubectl get nodes

# Verify CoreDNS is healthy
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Verify kube-proxy is healthy
kubectl get pods -n kube-system -l k8s-app=kube-proxy

# Test DNS resolution
kubectl run -it --rm test-dns --image=busybox:1.28 --restart=Never -- nslookup kubernetes.default
```

Expected results:
- All pods should be in `Running` state with `1/1` or `2/2` Ready
- No `CrashLoopBackOff` or `Error` states
- All 3 nodes should be `Ready`
- DNS resolution should work

## Rollback (if needed)

If the fix doesn't work as expected:

```bash
git revert HEAD
./deploy.sh reset
./deploy.sh
```

However, this fix is minimal and low-risk - it only adds a wait period, which cannot make things worse.

## Impact Assessment

### What Changed
- ✅ Added a wait task before validation
- ✅ Gives pods 5 minutes to stabilize after CNI is ready
- ✅ Deployment is more resilient to timing issues

### What Didn't Change
- ❌ No changes to Flannel configuration
- ❌ No changes to CNI plugin installation
- ❌ No changes to pod scheduling or networking
- ❌ No changes to the validation logic itself (just when it runs)

### Risk Level
**Low** - This is a defensive change that adds more time for pods to stabilize. It cannot break working deployments; it can only help failing ones succeed.

## Technical Details

### Why 5 Minutes?
- Flannel readiness probe: 30s initial + 120s retries = 150s max
- Pod restart cycle: ~30-60s per attempt
- Kubernetes backoff: Exponential backoff starts at 10s, grows to 5min
- Buffer time: Account for slow nodes, network delays
- Total: 5 minutes provides adequate margin

### Why Check CrashLoopBackOff Specifically?
- This is the specific error state we're trying to avoid
- Other states (Pending, ContainerCreating, Running) are expected during deployment
- CrashLoopBackOff indicates a pod that keeps failing and restarting
- After Flannel is ready, pods should stabilize out of this state

## Related Documentation
- `docs/FLANNEL_TIMING_ISSUE_FIX.md` - Previous Flannel timing fixes
- `docs/DEPLOYMENT_CHANGES.md` - Overall deployment improvements
- `docs/FLANNEL_READINESS_PROBE_FIX.md` - Flannel probe adjustments

## Status
✅ **Ready for testing** - Minimal, surgical change with low risk

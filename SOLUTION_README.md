# SOLUTION: fix-homelab-crashloop.sh Script Improvements

## Problem

You ran `./scripts/fix-homelab-crashloop.sh` and it completed with "Fix complete!" but the pods were still failing:
- `kube-flannel-ds-scng2`: Status = "Completed" (should be "Running")
- `kube-proxy-wwt2w`: Status = "CrashLoopBackOff" (repeatedly crashing)

The script was **silently failing** - running all tasks but not actually fixing the problem.

## Root Cause

The Ansible playbook had `failed_when: false` on critical validation tasks, causing it to:
1. Continue even when pods didn't become Ready
2. Report success even when pods were still unhealthy
3. Provide insufficient diagnostic information

## What I Fixed

### 1. Made the Script Fail Properly ✅

**Changed:**
- Flannel wait: `failed_when: flannel_wait.rc != 0` (was: `failed_when: false`)
- kube-proxy wait: `failed_when: proxy_wait.rc != 0` (was: `failed_when: false`)

**Result**: Script now **fails immediately** if pods don't become Ready within 120 seconds.

### 2. Added Final Validation ✅

**Added comprehensive check:**
```bash
kubectl get pods -A --field-selector spec.nodeName=homelab | grep -E 'CrashLoopBackOff|Error|Completed'
```

**Result**: Even if pods initially start, the script validates they stay healthy.

### 3. Enhanced Error Messages ✅

**Before:**
```
Fix complete!
```
*(Pods still broken)*

**After:**
```
❌ FAILED: Pods on homelab are still not healthy after applying fixes.

Next debugging steps:
1. Review kube-proxy logs above for "exit code 2" errors
2. Review Flannel logs to see why it's exiting (if Completed status)
3. Check iptables backend: Run 'update-alternatives --display iptables' on homelab
4. Verify conntrack is working: Run 'conntrack -L' on homelab
5. Check if Flannel interface exists: Run 'ip link show flannel.1' on homelab
```

### 4. Increased Log Capture ✅

- Changed from 50 lines → **100 lines** for both Flannel and kube-proxy logs
- Captures both current and previous (if crashed) logs

## What to Do Next

### Step 1: Pull and Run the Updated Script

```bash
cd /srv/monitoring_data/VMStation
git pull
chmod +x scripts/fix-homelab-crashloop.sh
./scripts/fix-homelab-crashloop.sh
```

### Step 2A: If the Script NOW Succeeds ✅

You'll see:
```
SUCCESS: All pods on homelab are healthy
```

**This means:**
- The original fixes ARE working
- Pods just needed proper validation to confirm success
- No further action needed

### Step 2B: If the Script Still Fails ❌

You'll see detailed logs and a failure message. **This is GOOD** - it means the script is now correctly identifying the problem instead of hiding it.

**You'll get:**
1. **Flannel pod logs** (100 lines) - showing why it's exiting
2. **kube-proxy pod logs** (100 lines) - showing exit code 2 errors
3. **System diagnostics** - kubelet, containerd journals, iptables state
4. **Specific debugging commands** to run next

### Step 3: Share the Output

If the script fails, **please share the complete output** including:
- The error message at the end
- The Flannel pod logs section
- The kube-proxy pod logs section

This will show the **actual root cause** that the previous script was hiding.

## Expected Scenarios

### Scenario A: Flannel "Completed" Status

**What it means:** Flannel daemon is exiting successfully instead of running continuously.

**Possible causes:**
- Flannel thinks its job is done (wrong args or config)
- Receiving termination signal from kubelet
- Interface confusion on multi-NIC host

**Next steps:**
1. Check Flannel logs for "exiting" or "termination" messages
2. Verify Flannel interface: `ssh homelab "ip link show flannel.1"`
3. Check if multiple network interfaces are confusing Flannel

### Scenario B: kube-proxy "CrashLoopBackOff"

**What it means:** kube-proxy is crashing with exit code 2 (error exit).

**Possible causes:**
- iptables backend mismatch (nft vs legacy)
- Missing iptables chains (should be pre-created by network-fix role)
- conntrack binary issues

**Next steps:**
1. Check kube-proxy logs for specific error messages
2. Verify iptables backend: `ssh homelab "update-alternatives --display iptables"`
3. Verify conntrack works: `ssh homelab "conntrack -L | wc -l"`

## Alternative Fixes (If Needed)

If the current approach doesn't work, the documentation includes alternative fixes:

### Option A: Switch to iptables-legacy

Based on some documentation suggesting RHEL 10 works better with legacy iptables:
```yaml
- alternatives --set iptables /usr/sbin/iptables-legacy
- alternatives --set ip6tables /usr/sbin/ip6tables-legacy
```

### Option B: Specify Flannel Network Interface

If Flannel is confused about which interface to use:
```yaml
args:
- --ip-masq
- --kube-subnet-mgr
- --iface=eth0  # or whatever the primary interface name is
```

## Files Changed

1. **ansible/playbooks/fix-homelab-crashloop.yml**
   - Line 66: Flannel wait now fails if pods don't become Ready
   - Line 133: kube-proxy wait now fails if pods don't become Ready
   - Lines 160-200: Added comprehensive final validation with detailed error messages
   - Lines 87-101, 135-150: Increased log capture to 100 lines

2. **HOMELAB_FIX_SCRIPT_SOLUTION.md** (this file)
   - Complete documentation of the problem and solution

## Summary

✅ **Problem**: Script was silently failing, reporting success when pods were still broken
✅ **Solution**: Script now properly validates pod health and fails with detailed diagnostics if issues persist
✅ **Benefit**: You'll now get actual error messages and logs showing the real root cause

**Run the updated script and share the output - we'll finally see what's actually wrong!**

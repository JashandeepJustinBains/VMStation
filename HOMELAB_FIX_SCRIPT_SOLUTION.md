# Fix Script Improvements - RHEL 10 CrashLoop Issues

## Problem Statement

The `fix-homelab-crashloop.sh` script was running successfully but silently failing to fix the actual pod issues:
- Flannel pod showed "Completed" status (exit code 0) instead of running continuously
- kube-proxy pod showed "CrashLoopBackOff" (exit code 2)
- Script reported "Fix complete!" even though pods were still failing

## Root Cause

The Ansible playbook (`ansible/playbooks/fix-homelab-crashloop.yml`) had several issues:

1. **Silent Failures**: Tasks had `failed_when: false`, allowing the playbook to succeed even when pods didn't become healthy
2. **Insufficient Validation**: No final check to verify pods actually stayed healthy after the fix
3. **Limited Logging**: Only 50 lines of logs were captured, missing critical error details

## Improvements Made

### 1. Fail Fast on Pod Health Issues

**Changed:**
```yaml
# Before - silently continued even if pods didn't become Ready
failed_when: false

# After - playbook fails if pods don't become Ready within timeout
failed_when: proxy_wait.rc != 0
```

**Impact**: The script will now fail immediately if Flannel or kube-proxy pods don't become Ready, rather than proceeding and falsely reporting success.

### 2. Comprehensive Final Validation

**Added:**
```yaml
- name: Final validation - check for unhealthy pods
  ansible.builtin.shell: |
    if kubectl get pods -A --field-selector spec.nodeName=homelab | grep -E 'CrashLoopBackOff|Error|Completed'; then
      echo "FAILURE: Unhealthy pods detected"
      exit 1
    else
      echo "SUCCESS: All pods on homelab are healthy"
      exit 0
    fi
```

**Impact**: The script now actively checks for:
- **CrashLoopBackOff**: Pod is repeatedly crashing
- **Completed**: DaemonSet pod exited when it should run continuously (the Flannel issue)
- **Error**: Pod failed to start

### 3. Enhanced Error Messages

**Added:**
- Detailed error messages explaining what each pod status means
- Specific debugging steps for common root causes:
  - kube-proxy: iptables chain issues, conntrack problems, mode mismatches
  - Flannel: Network interface issues, API watch streams, configuration errors
- Commands to run for further diagnosis

### 4. Increased Log Capture

**Changed:**
```yaml
# Before
--tail=50

# After
--tail=100
```

**Impact**: Captures more log lines to better diagnose issues, especially important for startup errors that may occur early in the logs.

### 5. Removed Duplicate Checks

**Removed:**
- Duplicate "Check for CrashLoopBackOff" task that was less comprehensive
- Redundant validation that didn't provide useful error messages

## What Happens Now

### If the Fix Works
```
SUCCESS: All pods on homelab are healthy
```
- Script completes successfully
- All pods show "Running" status
- Networking functions properly

### If the Fix Fails  
```
❌ FAILED: Pods on homelab are still not healthy after applying fixes.
```
- **Playbook fails with exit code 1** (instead of silently succeeding)
- **Detailed logs are displayed** showing:
  - Flannel pod logs (100 lines)
  - kube-proxy pod logs (100 lines)
  - Pod status information
  - System diagnostics (kubelet, containerd journals)
- **Helpful error message** explains:
  - What each pod status means
  - Common root causes
  - Specific debugging steps to try next

## Next Steps for Debugging

When the script fails, you'll see specific guidance like:

```
Next debugging steps:
1. Review kube-proxy logs above for "exit code 2" errors
2. Review Flannel logs to see why it's exiting (if Completed status)
3. Check iptables backend: Run 'update-alternatives --display iptables' on homelab
4. Verify conntrack is working: Run 'conntrack -L' on homelab
5. Check if Flannel interface exists: Run 'ip link show flannel.1' on homelab
```

## Potential Additional Fixes

Based on documentation review, if the current fixes don't work, consider:

### Option A: Switch to iptables-legacy (Alternative Approach)

Some documentation suggests using `iptables-legacy` instead of `iptables-nft` for RHEL 10:

```yaml
- name: Configure iptables-legacy as default on RHEL systems
  ansible.builtin.command:
    cmd: "{{ item }}"
  loop:
    - alternatives --set iptables /usr/sbin/iptables-legacy
    - alternatives --set ip6tables /usr/sbin/ip6tables-legacy
```

**When to try**: If kube-proxy logs show iptables-related errors even after current fixes.

### Option B: Add Flannel Interface Specification

If Flannel is confused about which network interface to use:

```yaml
# In Flannel DaemonSet args
args:
- --ip-masq
- --kube-subnet-mgr
- --iface=eth0  # or whatever the primary interface is
```

**When to try**: If Flannel logs show "couldn't find interface" or multiple interface errors.

### Option C: Disable Flannel kube-subnet-mgr

If there are issues with Kubernetes API watch streams:

```yaml
args:
- --ip-masq
# Remove or comment out: - --kube-subnet-mgr
```

**When to try**: If Flannel logs show watch errors or API client issues.

## Files Modified

- `ansible/playbooks/fix-homelab-crashloop.yml` - Added proper validation and error handling
- `FIX_SCRIPT_IMPROVEMENTS.md` - This document

## Testing

To test the improved script:

```bash
cd /srv/monitoring_data/VMStation
git pull
chmod +x scripts/fix-homelab-crashloop.sh
./scripts/fix-homelab-crashloop.sh
```

**Expected behavior:**
- If pods become healthy: Script succeeds with "SUCCESS" message
- If pods remain unhealthy: Script fails with detailed error information

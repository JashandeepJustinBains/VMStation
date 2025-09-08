# Spindown/Rejoin Worker Node Fix

## Problem Statement

Worker nodes (192.168.4.61 and 192.168.4.62) were failing to join the Kubernetes cluster after running the spindown subsite to test redeployments. The issue was NOT caused by insufficient timeouts but by stale state and expired tokens after the spindown/redeploy cycle.

## Root Cause Analysis

### Issues After Spindown Process

After running the `00-spindown.yaml` subsite to clean up the environment for redeployment testing, worker nodes could not rejoin the cluster. The root causes were:

1. **Stale Join Tokens**: Bootstrap tokens generated before spindown become invalid after control plane re-initialization
2. **Preserved Invalid kubelet.conf**: Spindown preserves worker kubelet.conf files that reference the old cluster
3. **No Token Regeneration**: Join commands were not refreshed after control plane restart
4. **Insufficient Validation**: No checks for token expiration or cluster connectivity
5. **Stale State Artifacts**: Leftover files from previous join attempts causing conflicts

### Technical Flow Problems

**Before Fix:**
```
Spindown → Control plane reinit → Old join tokens still used → Workers fail to join
```

**Preserved kubelet.conf references old cluster → Workers skip rejoin → No connectivity**

## Solution Implemented

### 1. Enhanced Token Management

**Location**: `ansible/plays/kubernetes/setup_cluster.yaml` (lines ~1129-1145)

**Changes**:
- Clean up existing tokens before generating new ones
- Generate tokens with explicit 24-hour TTL
- Add retry mechanism with backoff for token generation
- Validate token format and required components

**Before:**
```yaml
- name: Get join command
  shell: kubeadm token create --print-join-command
  register: join_command
```

**After:**
```yaml
- name: Ensure any existing tokens are cleaned up before creating new one
  shell: |
    echo "Cleaning up any existing bootstrap tokens..."
    kubeadm token list | awk 'NR>1 {print $1}' | xargs -r -I {} kubeadm token delete {} || true

- name: Get join command with fresh token (24h TTL)
  shell: kubeadm token create --print-join-command --ttl 24h
  register: join_command
  retries: 3
  delay: 5
  until: join_command.rc == 0

- name: Validate join command contains required components
  fail:
    msg: "Generated join command is invalid or incomplete: {{ join_command.stdout }}"
  when: not (join_command.stdout | regex_search('kubeadm join.*--token.*--discovery-token-ca-cert-hash'))
```

### 2. Enhanced kubelet.conf Validation

**Location**: `ansible/plays/kubernetes/setup_cluster.yaml` (lines ~1174-1200)

**Changes**:
- Test both file existence AND cluster connectivity
- Force rejoin if kubelet.conf references old/invalid cluster
- Track reasons for forced rejoins

**Before:**
```yaml
- name: Test kubelet.conf validity by checking if it contains valid cluster info
  shell: |
    if grep -q "server:" /etc/kubernetes/kubelet.conf && grep -q "certificate-authority-data:" /etc/kubernetes/kubelet.conf; then
      echo "valid"
    else
      echo "invalid"
    fi
```

**After:**
```yaml
- name: Test kubelet.conf validity and cluster connectivity
  shell: |
    if [ -f /etc/kubernetes/kubelet.conf ]; then
      if grep -q "server:" /etc/kubernetes/kubelet.conf && grep -q "certificate-authority-data:" /etc/kubernetes/kubelet.conf; then
        # Additional check: try to use the kubeconfig to verify connectivity
        if timeout 10s kubectl --kubeconfig=/etc/kubernetes/kubelet.conf cluster-info >/dev/null 2>&1; then
          echo "valid-and-connected"
        else
          echo "valid-but-disconnected"
        fi
      else
        echo "invalid"
      fi
    else
      echo "missing"
    fi
```

### 3. Join Command Freshness Validation

**Location**: `ansible/plays/kubernetes/setup_cluster.yaml` (lines ~1707-1740)

**Changes**:
- Validate join command age (expire after 23 hours)
- Check join command format and required components
- Add metadata (timestamp, control plane info) to join file

**New Addition:**
```yaml
- name: Validate join command freshness and content before use
  block:
    - name: Validate join command age and content
      shell: |
        if [ ! -f /tmp/kubeadm-join.sh ]; then
          echo "missing"
          exit 0
        fi
        
        # Check if file is older than 23 hours (tokens expire in 24h)
        if [ $(find /tmp/kubeadm-join.sh -mmin +1380 | wc -l) -gt 0 ]; then
          echo "expired"
          exit 0
        fi
        
        # Check if the join command contains required elements
        if grep -q "kubeadm join.*--token.*--discovery-token-ca-cert-hash" /tmp/kubeadm-join.sh; then
          echo "valid"
        else
          echo "malformed"
        fi
      register: join_command_validation
      delegate_to: localhost
      changed_when: false

    - name: Fail if join command is not available or expired
      fail:
        msg: |
          Join command issue detected: {{ join_command_validation.stdout }}
          To resolve:
          1. Ensure the control plane is running
          2. Re-run the setup_cluster playbook to generate a fresh join command
      when: join_command_validation.stdout != "valid"
```

### 4. Pre-join State Cleanup

**Location**: `ansible/plays/kubernetes/setup_cluster.yaml` (lines ~1784-1800)

**Changes**:
- Remove stale join artifacts (backup files, old flags)
- Clean up invalid kubelet.conf files
- Clear any leftover state from previous join attempts

**New Addition:**
```yaml
- name: Clean up any stale join state (post-spindown recovery)
  shell: |
    # Remove any leftover join artifacts that might conflict
    rm -f /etc/kubernetes/kubelet.conf.backup.* 2>/dev/null || true
    rm -f /var/lib/kubelet/kubeadm-flags.env 2>/dev/null || true
    
    # If this was triggered by invalid kubelet.conf, remove it to force fresh join
    if [ "{{ force_rejoin_reason | default('') }}" != "" ]; then
      echo "Removing invalid kubelet.conf (reason: {{ force_rejoin_reason | default('unknown') }})"
      rm -f /etc/kubernetes/kubelet.conf || true
      rm -f /etc/kubernetes/pki/ca.crt || true
    fi
    
    echo "Pre-join cleanup completed"
  when: not kubelet_conf.stat.exists
  changed_when: true
```

## Testing and Validation

### Comprehensive Test Suite

Created `test_spindown_rejoin_fix.sh` which validates:
- ✅ Token cleanup before new generation
- ✅ Join command generation with 24h TTL and retries
- ✅ Join command validation and format checking
- ✅ Timestamped join command with metadata
- ✅ Enhanced kubelet.conf validation with cluster connectivity
- ✅ Force rejoin when kubelet.conf is disconnected from cluster
- ✅ Join command freshness validation (23h threshold)
- ✅ Stale state cleanup before join attempts
- ✅ Force rejoin reason tracking
- ✅ Ansible syntax validation

### Compatibility Testing

- ✅ Existing `test_worker_join_fix.sh` still passes
- ✅ Existing `test_kubelet_join_fix.sh` still passes
- ✅ No breaking changes to existing functionality
- ✅ Minimal surgical changes (only ~60 lines added/modified)

## Expected Results

After applying this fix and running spindown/redeploy cycles:

1. **Token Generation**: Fresh bootstrap tokens are generated after control plane init
2. **State Detection**: Workers detect when their kubelet.conf is invalid or disconnected
3. **Clean Rejoin**: Stale state is cleared before attempting rejoin
4. **Successful Join**: Workers 192.168.4.61 and 192.168.4.62 successfully rejoin with new cluster certificates
5. **Error Prevention**: Clear error messages guide troubleshooting when issues occur

## Backward Compatibility

- ✅ No breaking changes to existing deployments
- ✅ All existing recovery mechanisms preserved
- ✅ Compatible with both RHEL and Debian-based systems
- ✅ Works with existing VMStation deployment workflows
- ✅ Maintains spindown functionality while fixing rejoin issues

## Usage After Fix

### Normal Spindown/Redeploy Cycle
```bash
# 1. Spindown cluster
ansible-playbook -i ansible/inventory.txt ansible/subsites/00-spindown.yaml -e confirm_spindown=true

# 2. Redeploy with fresh tokens and proper validation
./update_and_deploy.sh
```

### Troubleshooting Join Issues
The fix provides clear error messages for:
- Missing join commands
- Expired tokens (> 23 hours old)
- Malformed join commands
- Disconnected kubelet.conf files

## Files Modified

1. **`ansible/plays/kubernetes/setup_cluster.yaml`** - Enhanced token management, validation, and cleanup
2. **`test_spindown_rejoin_fix.sh`** - Comprehensive test validation (new)
3. **`SPINDOWN_REJOIN_FIX.md`** - Documentation (this file)

## Impact Assessment

**Scope**: Targeted fix for post-spindown rejoin failures
**Risk**: Very low - preserves all existing functionality while adding validation
**Benefit**: Resolves the primary blocker preventing workers from rejoining after spindown/redeploy cycles

This fix should resolve the core issue preventing workers 192.168.4.61 and 192.168.4.62 from joining the VMStation Kubernetes cluster after running spindown tests.
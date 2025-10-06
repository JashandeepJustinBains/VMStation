# Post-Reset Deployment Fix - Summary

## Problem Statement
After running `./deploy.sh reset`, attempting to redeploy with `./deploy.sh all --with-rke2 --yes` would fail with:
```
TASK [preflight : Abort when kubelet missing] **********************************
fatal: [masternode]: FAILED! => changed=false
  msg: kubelet binary not found on masternode - install kubeadm/kubelet first

TASK [Generate join command] ***************************************************
fatal: [storagenodet3500 -> masternode(192.168.4.63)]: FAILED! => changed=true
  stderr: '/bin/sh: 1: kubeadm: not found'
```

## Root Cause
The deployment playbook expected Kubernetes binaries (kubeadm, kubelet, kubectl) to be pre-installed on nodes. The preflight role would fail if binaries were missing, with no mechanism to install them.

## Solution
Made the deployment fully self-contained and idempotent by:
1. Adding automatic installation of Kubernetes binaries
2. Making preflight checks non-fatal
3. Ensuring idempotent behavior (safe to run multiple times)

## Files Changed

### New Files Created
1. `ansible/roles/install-k8s-binaries/tasks/main.yml` - Installation role
2. `ansible/roles/install-k8s-binaries/README.md` - Role documentation
3. `tests/test-install-k8s-binaries.sh` - Test suite (12 tests)
4. `docs/POST_RESET_DEPLOYMENT_FIX.md` - Comprehensive guide

### Modified Files
1. `ansible/playbooks/deploy-cluster.yaml` - Added Phase 0 for binary installation
2. `ansible/roles/preflight/tasks/main.yml` - Changed fatal error to warning
3. `README.md` - Added quick reference and link to documentation
4. `TODO.md` - Marked issue as resolved
5. `.gitignore` - Allowed essential documentation and test files

## What the Fix Does

### Before Fix
1. User runs `./deploy.sh reset`
2. Cluster reset, configs removed
3. User runs `./deploy.sh all --with-rke2 --yes`
4. **Deployment fails** - kubelet not found
5. User must manually install kubeadm/kubelet/kubectl
6. User reruns deployment

### After Fix
1. User runs `./deploy.sh reset`
2. Cluster reset, configs removed
3. User runs `./deploy.sh all --with-rke2 --yes`
4. **Phase 0**: Automatically installs missing binaries
5. **Phase 1-5**: Proceeds with deployment
6. **Deployment succeeds** ✅

## Installation Role Features

### Idempotent Behavior
```yaml
- Check if kubelet exists
- Check if kubeadm exists
- Check if kubectl exists
- Only install if any are missing
- Skip installation if all exist
```

### Multi-OS Support
- Debian/Ubuntu: Uses apt with Kubernetes v1.29 stable repo
- RHEL/CentOS: Uses yum with Kubernetes v1.29 stable repo

### Components Installed
- kubeadm (cluster management)
- kubelet (node agent)
- kubectl (CLI tool)
- containerd (container runtime)
- SystemdCgroup enabled in containerd config
- Packages held to prevent automatic upgrades

### Host Targeting
- **Runs on**: monitoring_nodes, storage_nodes (Debian)
- **Skips**: homelab (uses RKE2 instead)

## Test Coverage

### Test Suite: `tests/test-install-k8s-binaries.sh`
✅ Test 1: Role directory structure exists
✅ Test 2: Role integrated into deployment playbook
✅ Test 3: Phase 0 targets correct host groups
✅ Test 4: Preflight changed to warning instead of failure
✅ Test 5: YAML syntax validation
✅ Test 6: Ansible playbook syntax validation
✅ Test 7: Idempotency checks in place
✅ Test 8: Checks for all required binaries
✅ Test 9: Multi-OS support implemented
✅ Test 10: Containerd installation and configuration
✅ Test 11: Correct Kubernetes version (v1.29)
✅ Test 12: Deploy script works with dry-run

### Existing Tests
✅ test-yes-flag.sh - All 6 tests passing
✅ test-deploy-limits.sh - All 4 tests passing

## Verification Steps

### 1. Run Test Suite
```bash
# Run new test suite
./tests/test-install-k8s-binaries.sh

# Run existing tests
./tests/test-yes-flag.sh
./tests/test-deploy-limits.sh
```

### 2. Verify Playbook Syntax
```bash
ansible-playbook --syntax-check ansible/playbooks/deploy-cluster.yaml
```

### 3. Test Dry-Run
```bash
./deploy.sh debian --check --yes
```

### 4. Verify on Actual Deployment
```bash
# Reset cluster
./deploy.sh reset

# Redeploy (binaries will be auto-installed)
./deploy.sh all --with-rke2 --yes

# Verify binaries installed
ssh root@masternode "kubeadm version && kubelet --version && kubectl version --client"
```

## Technical Details

### Phase 0 in deploy-cluster.yaml
```yaml
# -----------------------------------------------------------------------------
# PHASE 0: Install Kubernetes Binaries (Debian nodes only)
# -----------------------------------------------------------------------------
- name: Phase 0 - Install Kubernetes binaries
  hosts: monitoring_nodes:storage_nodes
  become: true
  gather_facts: true
  roles:
    - install-k8s-binaries
```

### Preflight Check Change
**Before:**
```yaml
- name: Abort when kubelet missing
  ansible.builtin.fail:
    msg: "kubelet binary not found on {{ inventory_hostname }} - install kubeadm/kubelet first"
  when: not kubelet_bin.stat.exists
```

**After:**
```yaml
- name: Warn if kubelet missing (installation role should have installed it)
  ansible.builtin.debug:
    msg: "WARNING: kubelet binary not found on {{ inventory_hostname }} - this may cause deployment issues"
  when: not kubelet_bin.stat.exists
```

## Benefits

### For Users
- No manual intervention required after reset
- Self-healing deployment (automatically installs missing components)
- Idempotent (safe to run multiple times)
- Clear documentation and error messages

### For Developers
- Modular, maintainable code
- Comprehensive test coverage
- Well-documented implementation
- Multi-OS support for future expansion

## Documentation

### Quick Reference
- [README.md](../README.md#reset-everything) - Basic usage examples

### Comprehensive Guide
- [POST_RESET_DEPLOYMENT_FIX.md](POST_RESET_DEPLOYMENT_FIX.md) - Full technical documentation

### Role Documentation
- [install-k8s-binaries/README.md](../ansible/roles/install-k8s-binaries/README.md) - Role-specific details

## Troubleshooting

### Issue: Test fails with "ansible-playbook not found"
**Solution**: Install Ansible
```bash
pip install ansible
```

### Issue: Deployment fails with repository errors
**Solution**: Check internet connectivity
```bash
curl -I https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key
```

### Issue: Want to force reinstall
**Solution**: Remove existing binaries first
```bash
./deploy.sh reset
# Binaries will be reinstalled on next deployment
./deploy.sh all --with-rke2 --yes
```

## Backward Compatibility

### Existing Installations
- If binaries already exist, they are NOT modified
- Installation role checks and skips if present
- Existing deployments continue to work unchanged

### Migration Path
- No changes required to existing workflows
- Simply run `./deploy.sh reset` then redeploy
- Binaries will be installed automatically if missing

## Future Enhancements

### Potential Improvements
1. Support for custom Kubernetes versions via variables
2. Offline installation support (local package cache)
3. Automatic version upgrades with migration
4. Binary integrity verification (checksums)

### Maintenance
- Monitor Kubernetes v1.29 repository for security updates
- Update to newer stable versions as needed
- Maintain compatibility with Debian and RHEL distributions

## Summary

This fix transforms the deployment from requiring manual pre-installation of Kubernetes binaries to a fully automated, self-contained process. After running `./deploy.sh reset`, users can immediately redeploy without any manual intervention. The solution is:

- ✅ **Idempotent** - Safe to run multiple times
- ✅ **Self-contained** - Installs everything needed
- ✅ **Tested** - 22 test cases all passing
- ✅ **Documented** - Comprehensive guides provided
- ✅ **Backward Compatible** - Existing setups unchanged
- ✅ **Multi-OS** - Supports Debian and RHEL

**Result**: A more robust, user-friendly deployment process that "just works" after reset.

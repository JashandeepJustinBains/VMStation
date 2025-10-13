# Kubespray Migration Guide

This document describes the migration from the legacy RKE2/kubeadm dual-cluster deployment to a Kubespray-only deployment pipeline.

## Overview

**Migration Date**: October 2025  
**Status**: Complete  
**Impact**: Breaking - RKE2 deployment removed

## What Changed

### Removed
- ✗ RKE2 deployment to homelab node
- ✗ `./deploy.sh rke2` command
- ✗ `./deploy.sh all` two-phase deployment
- ✗ Ansible playbooks: `install-rke2-homelab.yml`, `uninstall-rke2-homelab.yml`
- ✗ Vaulted sudo password requirement for homelab host

### Added
- ✓ Kubespray deployment via `./deploy.sh kubespray`
- ✓ `inventory.ini` - Kubespray-compatible INI format inventory
- ✓ `scripts/activate-kubespray-env.sh` - Environment activation
- ✓ `scripts/run-kubespray.sh` - Kubespray staging
- ✓ `ansible/playbooks/run-preflight-rhel10.yml` - RHEL10 preflight checks

### Changed
- ↻ Default inventory: `ansible/inventory/hosts.yml` → `inventory.ini`
- ↻ Homelab host: Now uses NOPASSWD sudo (no vault password needed)
- ↻ `./deploy.sh all` → redirects to `./deploy.sh kubespray`
- ↻ `./deploy.sh rke2` → shows deprecation error

## New Canonical Workflow

```bash
# Complete deployment from scratch
clear
git pull

# 1. Reset cluster (if needed)
./deploy.sh reset

# 2. Setup auto-sleep monitoring
./deploy.sh setup

# 3. Deploy Kubernetes via Kubespray (RECOMMENDED)
./deploy.sh kubespray

# Alternative: Legacy Debian-only deployment (deprecated)
# ./deploy.sh debian

# 4. Deploy monitoring stack
./deploy.sh monitoring

# 5. Deploy infrastructure services
./deploy.sh infrastructure

# 6. Validate deployment
./scripts/validate-monitoring-stack.sh

# 7. Test sleep/wake cycle
./tests/test-sleep-wake-cycle.sh

# 8. Complete validation
./tests/test-complete-validation.sh
```

## Kubespray Deployment Flow

The `./deploy.sh kubespray` command orchestrates the following steps:

1. **Stage Kubespray**: Clones/updates Kubespray repo, creates venv, installs dependencies
2. **Preflight Checks**: Runs RHEL10 preflight checks on compute_nodes
3. **Cluster Deployment**: Deploys Kubernetes cluster using Kubespray's cluster.yml
4. **KUBECONFIG Setup**: Detects and exports kubeconfig from Kubespray artifacts
5. **Monitoring Stack**: Deploys Prometheus, Grafana, Loki, exporters
6. **Infrastructure Services**: Deploys NTP, Syslog, Kerberos

### Manual Kubespray Deployment

If automated deployment fails (credentials, network access), run manually:

```bash
# Step 1: Stage Kubespray
./scripts/run-kubespray.sh

# Step 2: Run preflight (optional)
ansible-playbook -i inventory.ini \
  ansible/playbooks/run-preflight-rhel10.yml \
  -l compute_nodes

# Step 3: Deploy cluster
cd .cache/kubespray
source .venv/bin/activate
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -b -v

# Step 4: Set KUBECONFIG
source ../../scripts/activate-kubespray-env.sh
# OR
export KUBECONFIG=~/.kube/config
# OR
export KUBECONFIG=.cache/kubespray/inventory/mycluster/artifacts/admin.conf

# Step 5: Continue with monitoring and infrastructure
cd ../..
./deploy.sh monitoring
./deploy.sh infrastructure
```

## Inventory Changes

### Old Inventory (YAML)
```yaml
# ansible/inventory/hosts.yml
compute_nodes:
  hosts:
    homelab:
      ansible_host: 192.168.4.62
      ansible_become_pass: "{{ vault_homelab_sudo_password }}"
```

### New Inventory (INI)
```ini
# inventory.ini
[compute_nodes]
homelab ansible_host=192.168.4.62 ansible_user=jashandeepjustinbains ansible_ssh_private_key_file=~/.ssh/id_k3s

[compute_nodes:vars]
ansible_become=true
ansible_become_method=sudo
# NOTE: homelab uses NOPASSWD sudo - no ansible_become_pass required
```

**Why INI format?** Kubespray uses INI-format inventories. We now have dual inventories:
- `inventory.ini` - Kubespray-compatible (CANONICAL)
- `ansible/inventory/hosts.yml` - Legacy YAML format (kept for backward compatibility)

Both define the same hosts. Use `inventory.ini` for all new workflows.

## Homelab Sudo Password Removal

The homelab host (192.168.4.62) has been configured with NOPASSWD sudo for the deployment user.

**Before**:
```yaml
ansible_become_pass: "{{ vault_homelab_sudo_password }}"
```

**After**:
```yaml
# No ansible_become_pass needed - host configured with NOPASSWD sudo
ansible_become: true
ansible_become_method: sudo
```

**Note**: Other hosts may still require vaulted passwords. This change only applies to the homelab host.

## Rollback Plan

If you need to revert to the pre-migration state:

```bash
# 1. Checkout previous commit before migration
git checkout <commit-before-migration>

# 2. Restore RKE2 playbooks from archive
git mv archive/legacy/ansible/playbooks/install-rke2-homelab.yml ansible/playbooks/
git mv archive/legacy/ansible/playbooks/uninstall-rke2-homelab.yml ansible/playbooks/

# 3. Restore old deploy.sh
git checkout main -- deploy.sh

# 4. Deploy using legacy workflow
./deploy.sh all --with-rke2
```

**Warning**: Rollback is not recommended. The Kubespray workflow is the supported path forward.

## Manual Verification Steps

After migration, verify the deployment:

### 1. Check Inventory
```bash
ansible-inventory -i inventory.ini --list | jq .
```

Should show:
- `kube-master` group with masternode
- `kube-node` group with storagenodet3500 and homelab
- `etcd` group with masternode
- `k8s-cluster:children` group

### 2. Verify Kubespray Staging
```bash
./scripts/run-kubespray.sh
```

Should create `.cache/kubespray` with Kubespray repo and venv.

### 3. Verify Environment Activation
```bash
source scripts/activate-kubespray-env.sh
echo $KUBECONFIG
kubectl cluster-info
```

### 4. Verify Sudo Access
```bash
# Test that homelab doesn't need password
ansible homelab -i inventory.ini -m ping -b
```

Should succeed without vault password prompt.

### 5. Verify Monitoring Stack
```bash
./scripts/validate-monitoring-stack.sh
```

Should show all monitoring components healthy.

## Troubleshooting

### "RKE2 deployment has been removed"
This is expected. Use `./deploy.sh kubespray` instead.

### "ansible_become_pass is undefined"
If you see this for the homelab host, it means the host is not configured with NOPASSWD sudo.  
**Fix**: Configure NOPASSWD sudo on homelab or temporarily add `ansible_become_pass` back.

### "kubectl: command not found" after Kubespray deployment
**Fix**: Ensure KUBECONFIG is set:
```bash
source scripts/activate-kubespray-env.sh
```

### Kubespray deployment fails with "SSH connection failed"
**Causes**:
- SSH key not available
- Host unreachable
- Firewall blocking SSH

**Fix**: 
1. Verify SSH access: `ssh -i ~/.ssh/id_k3s jashandeepjustinbains@192.168.4.62`
2. Check firewall: `sudo firewall-cmd --list-all`
3. Verify inventory: `ansible-inventory -i inventory.ini --list`

### "No kubeconfig file found"
**Possible locations**:
- `~/.kube/config`
- `.cache/kubespray/inventory/mycluster/artifacts/admin.conf`
- `/etc/kubernetes/admin.conf`

**Fix**: Manually set KUBECONFIG:
```bash
export KUBECONFIG=<path-to-kubeconfig>
```

## Dependency Graph

See `.cache/migration/kubespray_dependency_graph.json` for the complete dependency graph of the canonical workflow.

**Canonical Files**:
- `deploy.sh` - Main deployment orchestration
- `inventory.ini` - Kubespray-compatible inventory
- `scripts/run-kubespray.sh` - Kubespray staging
- `scripts/activate-kubespray-env.sh` - Environment activation
- `scripts/validate-monitoring-stack.sh` - Monitoring validation
- `tests/test-sleep-wake-cycle.sh` - Sleep/wake testing
- `tests/test-complete-validation.sh` - Complete validation

**Orphaned Files** (archived):
- `ansible/playbooks/install-rke2-homelab.yml` → `archive/legacy/`
- `ansible/playbooks/uninstall-rke2-homelab.yml` → `archive/legacy/`

See `.cache/migration/orphaned_files.txt` for full analysis.

## FAQ

**Q: Can I still use the Debian-only deployment?**  
A: Yes, `./deploy.sh debian` still works but is deprecated. Use `./deploy.sh kubespray` for new deployments.

**Q: What happened to the two-phase deployment?**  
A: The `./deploy.sh all` command now redirects to `./deploy.sh kubespray`, which is a single-phase deployment.

**Q: Do I need to update my inventory?**  
A: Recommended. Use `inventory.ini` going forward. The old `ansible/inventory/hosts.yml` is kept for backward compatibility.

**Q: Where is the kubeconfig after Kubespray deployment?**  
A: Typically in `~/.kube/config` or `.cache/kubespray/inventory/mycluster/artifacts/admin.conf`. Use `scripts/activate-kubespray-env.sh` to auto-detect.

**Q: Can I revert to RKE2?**  
A: Yes, see the Rollback Plan section. However, Kubespray is the supported path forward.

## Support

For issues or questions:
1. Check this migration guide
2. Review `.cache/migration/orphaned_files.txt`
3. Check `docs/TROUBLESHOOTING.md`
4. Open an issue on GitHub

---

**Migration completed**: October 2025  
**Maintained by**: VMStation Operations Team

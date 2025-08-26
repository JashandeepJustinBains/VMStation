# VMStation Kubernetes Migration - Fixed Issues Summary

## Issues Addressed

### 1. Ansible Collection Warning Fix
**Problem:** `[WARNING]: Collection kubernetes.core does not support Ansible version 2.14.18`

**Solution Applied:**
- Updated `ansible/requirements.yml` with compatible version range: `>=2.4.0,<6.0.0`
- Added collection version checking to `deploy_kubernetes.sh`
- Enhanced error handling for offline environments

**To Apply:**
```bash
# Update collections to compatible versions
ansible-galaxy collection install -r ansible/requirements.yml --force
```

### 2. Node-Specific Storage Configuration
**Problem:** Generic storage configuration not suitable for different node types

**Solution Applied:**
- **monitoring_nodes (192.168.4.63)**: Uses `/srv/monitoring_data` (existing monitoring data)
- **compute_nodes (192.168.4.62)**: Uses `/mnt/storage/kubernetes` (within mounted storage)
- **storage_nodes (192.168.4.61)**: Uses `/var/lib/kubernetes` (root filesystem storage)

**Configuration Added:**
- `storage_paths` in `ansible/group_vars/all.yml.template`
- New playbook: `ansible/plays/kubernetes/setup_storage.yaml`
- Node selectors in monitoring deployment for proper placement

### 3. RHEL 10 Kubernetes Requirements Installation Fix
**Problem:** setup_cluster playbook failed to install Kubernetes requirements on RHEL 10 compute_nodes

**Solution Applied:**
- **Fixed Kubernetes binary download URLs**: Changed from incorrect `stable-{{ kubernetes_version }}` format to proper version detection and `{{ k8s_full_version }}` usage
- **Enhanced dependency installation**: Added explicit installation of required packages (curl, wget, dnf-plugins-core) for RHEL 10+
- **Improved kubelet systemd service**: Added proper systemd unit configuration with kubeadm integration via drop-in files
- **Added binary validation**: Each downloaded binary (kubeadm, kubectl, kubelet) is now validated to ensure successful installation
- **Enhanced systemd management**: Added daemon reload and service verification to ensure kubelet starts correctly
- **Better error handling**: Added fallback mechanisms and proper error detection for package installation failures

**Key Changes Made:**
- Version detection logic that properly fetches latest stable version for specified minor version
- Fallback to `v{{ kubernetes_version }}.0` when version detection fails
- Comprehensive kubelet systemd configuration with proper drop-in files at `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf`
- Binary validation commands to verify each component works before proceeding
- Improved service management with daemon reload and status verification

**To Apply:**
```bash
# The fixes are automatically applied when running setup_cluster.yaml
# Validate fixes with the new validation script
./scripts/validate_rhel10_k8s_fixes.sh
```

## How to Use the Fixes

### Quick Migration (Recommended)
```bash
# 1. Pull the latest changes
git pull origin main

# 2. Update configuration
cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml
# Edit all.yml as needed for your environment

# 3. Validate storage setup
./scripts/validate_k8s_storage.sh

# 4. Validate RHEL 10 fixes
./scripts/validate_rhel10_k8s_fixes.sh

# 5. Deploy Kubernetes with fixed configuration
./deploy_kubernetes.sh
```

### Manual Steps (if needed)
```bash
# Update collections manually
ansible-galaxy collection install kubernetes.core:>=2.4.0,<6.0.0 --force

# Validate syntax
ansible-playbook --syntax-check -i ansible/inventory.txt ansible/plays/kubernetes_stack.yaml

# Check storage configuration
ansible-playbook --syntax-check -i ansible/inventory.txt ansible/plays/kubernetes/setup_storage.yaml

# Check RHEL 10 fixes
ansible-playbook --syntax-check -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml

# Validate RHEL 10 fixes
./scripts/validate_rhel10_k8s_fixes.sh
```

## Validation Commands

### Before Migration
```bash
# Check current Ansible version compatibility
ansible --version
ansible-galaxy collection list | grep kubernetes

# Validate storage directories exist
./scripts/validate_k8s_storage.sh
```

### After Migration
```bash
# Validate Kubernetes deployment
./scripts/validate_k8s_monitoring.sh

# Check persistent storage
kubectl get pv,pvc -A

# Verify monitoring stack
kubectl get pods -n monitoring
```

## Files Modified
- `ansible/requirements.yml` - Collection version compatibility
- `ansible/group_vars/all.yml.template` - Storage paths configuration
- `ansible/plays/kubernetes/setup_storage.yaml` - New storage setup playbook
- `ansible/plays/kubernetes_stack.yaml` - Include storage setup
- `ansible/plays/kubernetes/deploy_monitoring.yaml` - Node-specific placement
- `ansible/plays/kubernetes/setup_cluster.yaml` - **MAJOR IMPROVEMENTS for RHEL 10 support**
- `deploy_kubernetes.sh` - Collection version validation
- `scripts/validate_k8s_storage.sh` - Storage validation script
- `scripts/validate_rhel10_k8s_fixes.sh` - **NEW: RHEL 10 fixes validation script**
- `docs/MIGRATION_GUIDE.md` - Updated troubleshooting guide

## Troubleshooting

### RHEL 10 Specific Issues
If you encounter issues with RHEL 10 Kubernetes installation:
1. Check that required packages are installed: `dnf list installed curl wget dnf-plugins-core`
2. Verify binary downloads: Check `/usr/bin/kubeadm`, `/usr/bin/kubectl`, `/usr/bin/kubelet` exist and are executable
3. Check kubelet service status: `systemctl status kubelet`
4. Review kubelet logs: `journalctl -u kubelet -f`
5. Validate systemd configuration: Check `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf` exists

### General Troubleshooting
If you still get the collection warning:
1. Check your Ansible version: `ansible --version`
2. Update to Ansible 2.15+ if possible
3. Or install a compatible kubernetes.core version for your Ansible version
4. See updated troubleshooting section in `docs/MIGRATION_GUIDE.md`

The storage validation script (`./scripts/validate_k8s_storage.sh`) will help verify that proper directories are created and accessible on each node type.

The RHEL 10 validation script (`./scripts/validate_rhel10_k8s_fixes.sh`) will verify that all fixes for RHEL 10 Kubernetes requirements installation are properly implemented.
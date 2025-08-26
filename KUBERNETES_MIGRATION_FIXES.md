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

# 4. Deploy Kubernetes with fixed configuration
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
- `deploy_kubernetes.sh` - Collection version validation
- `scripts/validate_k8s_storage.sh` - Storage validation script
- `docs/MIGRATION_GUIDE.md` - Updated troubleshooting guide

## Troubleshooting

If you still get the collection warning:
1. Check your Ansible version: `ansible --version`
2. Update to Ansible 2.15+ if possible
3. Or install a compatible kubernetes.core version for your Ansible version
4. See updated troubleshooting section in `docs/MIGRATION_GUIDE.md`

The storage validation script (`./scripts/validate_k8s_storage.sh`) will help verify that proper directories are created and accessible on each node type.
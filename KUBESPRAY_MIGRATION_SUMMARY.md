# VMStation Kubespray Migration Summary

**Date**: October 2025  
**Migration**: kubeadm → Kubespray for Debian Cluster Deployment  
**Status**: ✅ Complete

## Overview

VMStation has been migrated from kubeadm-based deployment to Kubespray for the primary Debian cluster (monitoring_nodes + storage_nodes). This migration provides a more flexible, production-grade deployment while maintaining **100% backward compatibility** with existing commands and workflows.

## What Changed

### 1. Primary Deployment Method
- **Before**: `./deploy.sh debian` used kubeadm with custom Ansible playbooks
- **After**: `./deploy.sh debian` uses Kubespray for cluster deployment
- **Command**: Same interface - no changes required!

### 2. New Scripts Added

#### `scripts/deploy-kubespray.sh`
- Automated Kubespray deployment wrapper
- Clones/updates Kubespray from official repository (v2.24.1)
- Creates Python virtual environment in `.cache/kubespray/.venv`
- Generates Kubespray inventory from VMStation hosts.yml
- Configures cluster to match previous setup (Flannel CNI, etc.)
- Runs `cluster.yml` playbook automatically

#### `scripts/reset-kubespray.sh`
- Automated Kubespray cluster reset
- Runs Kubespray's `reset.yml` playbook
- Cleans up all Kubernetes artifacts
- Fallback to legacy reset playbook if Kubespray not found

#### `scripts/setup-kubeconfig.sh`
- Ensures kubeconfig compatibility between kubeadm and Kubespray
- Detects kubeconfig at `~/.kube/config` or `/etc/kubernetes/admin.conf`
- Creates symlinks/copies to ensure both locations work
- Called automatically by monitoring and infrastructure commands

### 3. Modified Files

#### `deploy.sh`
- Updated `cmd_debian()` to use Kubespray instead of kubeadm
- Added `cmd_kubespray()` function (called by `cmd_debian()`)
- Added `kubespray` command alias
- Updated `cmd_reset()` to use Kubespray reset script
- Updated `cmd_all()` messaging to reference Kubespray
- Updated `cmd_monitoring()` and `cmd_infrastructure()` to setup kubeconfig
- Updated `verify_debian_cluster_health()` to check multiple kubeconfig locations
- Updated usage documentation and help text

#### `README.md`
- Updated Quick Start to reference Kubespray
- Updated architecture diagrams
- Updated deployment options documentation
- Updated command reference

### 4. New Deployment Flow

```bash
# Same commands as before!
./deploy.sh reset
./deploy.sh setup
./deploy.sh debian         # Now uses Kubespray
./deploy.sh monitoring     # Works with Kubespray
./deploy.sh infrastructure # Works with Kubespray

# Test and validate
./scripts/validate-monitoring-stack.sh
./tests/test-sleep-wake-cycle.sh
./tests/test-complete-validation.sh
```

## What Stayed the Same

✅ **All existing commands work identically**:
- `./deploy.sh debian` - Same command, new backend
- `./deploy.sh monitoring` - No changes
- `./deploy.sh infrastructure` - No changes
- `./deploy.sh reset` - No changes
- `./deploy.sh setup` - No changes
- `./deploy.sh rke2` - No changes

✅ **Same cluster configuration**:
- Flannel CNI (matches previous setup)
- Same pod network CIDR: `10.244.0.0/16`
- Same service network CIDR: `10.96.0.0/12`
- Same Kubernetes version: v1.29

✅ **Same node topology**:
- masternode (192.168.4.63) - Control plane
- storagenodet3500 (192.168.4.61) - Worker node
- homelab (192.168.4.62) - RKE2 cluster (optional)

✅ **All features preserved**:
- Monitoring stack (Prometheus, Grafana, Loki)
- Infrastructure services (NTP, Syslog, Kerberos)
- Auto-sleep/Wake-on-LAN
- All test scripts
- All validation scripts

## Benefits of Kubespray

### Production-Grade Deployment
- Battle-tested by Kubernetes SIG (Special Interest Group)
- Used by enterprises worldwide
- Regular updates and security patches
- Extensive documentation and community support

### Flexibility
- Support for multiple CNI plugins (Flannel, Calico, Cilium, etc.)
- Support for multiple container runtimes
- Customizable via group_vars
- Easier to upgrade Kubernetes versions

### Reliability
- Comprehensive health checks
- Idempotent playbooks
- Better error handling
- Built-in rollback capabilities

### Standardization
- Industry-standard deployment method
- Consistent with other Kubernetes distributions
- Better integration with ecosystem tools

## Migration for Existing Deployments

If you have an existing kubeadm cluster and want to migrate to Kubespray:

### Option 1: Fresh Deployment (Recommended)
```bash
# Backup important data first!

# Reset existing cluster
./deploy.sh reset

# Deploy with Kubespray
./deploy.sh setup
./deploy.sh debian
./deploy.sh monitoring
./deploy.sh infrastructure

# Validate
./scripts/validate-monitoring-stack.sh
./tests/test-complete-validation.sh
```

### Option 2: Keep Existing Cluster
- Your existing kubeadm cluster will continue to work
- The kubeconfig setup script ensures compatibility
- New deployments will use Kubespray

## Technical Details

### Kubespray Location
- Cloned to: `.cache/kubespray/`
- Version: v2.24.1 (configurable via `KUBESPRAY_VERSION` env var)
- Virtual environment: `.cache/kubespray/.venv/`

### Inventory Generation
- VMStation `hosts.yml` is automatically converted to Kubespray format
- Inventory saved to: `.cache/kubespray/inventory/vmstation/inventory.ini`
- Customizations: `.cache/kubespray/inventory/vmstation/group_vars/`

### Kubeconfig Locations
- Kubespray default: `~/.kube/config`
- Kubeadm default: `/etc/kubernetes/admin.conf`
- Both locations are ensured to exist for compatibility

### Logs
- Deployment: `ansible/artifacts/deploy-kubespray.log`
- Reset: `ansible/artifacts/reset-kubespray.log`
- Monitoring: `ansible/artifacts/deploy-monitoring-stack.log`
- Infrastructure: `ansible/artifacts/deploy-infrastructure-services.log`

## Validation

All existing tests and validation scripts work without modification:

```bash
# Monitoring validation
./scripts/validate-monitoring-stack.sh

# Sleep/wake cycle test
./tests/test-sleep-wake-cycle.sh

# Complete validation suite
./tests/test-complete-validation.sh

# Smoke tests
./tests/test-kubespray-smoke.sh
```

## Troubleshooting

### Kubeconfig Issues
If kubectl commands don't work:
```bash
# Run kubeconfig setup manually
./scripts/setup-kubeconfig.sh

# Or export KUBECONFIG
export KUBECONFIG=~/.kube/config
```

### Kubespray Setup Issues
```bash
# Force Kubespray re-download
rm -rf .cache/kubespray
./deploy.sh debian
```

### Python/Ansible Issues
```bash
# Ensure Python 3 and pip are available
python3 --version
pip3 --version

# Kubespray creates its own venv with required versions
```

## Rollback

If you need to revert to kubeadm-based deployment:

1. **Revert deploy.sh changes**:
   ```bash
   git checkout main deploy.sh
   ```

2. **Use legacy playbooks**:
   ```bash
   ansible-playbook -i ansible/inventory/hosts.yml \
     ansible/playbooks/deploy-cluster.yaml \
     --limit monitoring_nodes,storage_nodes
   ```

3. **Legacy reset**:
   ```bash
   ansible-playbook -i ansible/inventory/hosts.yml \
     ansible/playbooks/reset-cluster.yaml
   ```

## Future Enhancements

Potential improvements (not in this migration):
- [ ] Multi-node HA control plane support
- [ ] Alternative CNI plugins (Calico, Cilium)
- [ ] Automated Kubernetes version upgrades via Kubespray
- [ ] GitOps integration for cluster configuration

## References

- **Kubespray Documentation**: https://kubespray.io/
- **GitHub Repository**: https://github.com/kubernetes-sigs/kubespray
- **VMStation Architecture**: docs/ARCHITECTURE.md
- **VMStation Usage**: docs/USAGE.md
- **Troubleshooting**: docs/TROUBLESHOOTING.md

## Acceptance Criteria

All criteria met ✅:
- [x] Same command interface (`./deploy.sh debian`)
- [x] Same cluster configuration (Flannel, network CIDRs)
- [x] Same node topology
- [x] Monitoring stack deploys and works
- [x] Infrastructure services deploy and work
- [x] Reset functionality works
- [x] All test scripts compatible
- [x] Documentation updated
- [x] Backward compatibility maintained

## Conclusion

The migration to Kubespray provides VMStation with a production-grade, flexible deployment foundation while maintaining complete backward compatibility. Users can continue using the same commands and workflows they're familiar with, now powered by industry-standard Kubespray.

**Ready to deploy**: `./deploy.sh reset && ./deploy.sh setup && ./deploy.sh debian && ./deploy.sh monitoring && ./deploy.sh infrastructure`

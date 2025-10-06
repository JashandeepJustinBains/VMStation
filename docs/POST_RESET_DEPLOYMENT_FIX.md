# Post-Reset Deployment Fix

## Issue

After running `./deploy.sh reset` to clean up the cluster, attempting to redeploy with `./deploy.sh all --with-rke2 --yes` would fail with errors:
- `kubelet binary not found on masternode`
- `kubeadm: not found` when trying to generate join command

## Root Cause

The deployment playbook previously expected Kubernetes binaries (kubeadm, kubelet, kubectl) to already be installed on the nodes. The `preflight` role would check for these binaries and fail if they were missing, with the assumption that users would manually install them first.

However, this caused issues in several scenarios:
1. **After reset**: If binaries were removed or corrupted during reset
2. **Fresh installations**: New nodes without pre-installed Kubernetes
3. **Version mismatches**: When binaries needed to be reinstalled to match cluster version

## Solution

The deployment process has been enhanced to be fully self-contained and idempotent:

### New Installation Role

A new Ansible role `install-k8s-binaries` has been added that:
- Automatically installs kubeadm, kubelet, kubectl, and containerd
- Configures containerd with SystemdCgroup enabled
- Uses Kubernetes v1.29 stable repository
- Holds package versions to prevent accidental upgrades
- Only installs if binaries are missing (idempotent)
- Supports both Debian/Ubuntu and RHEL/CentOS

### Updated Deployment Flow

The deployment playbook now includes a new **Phase 0**:

```yaml
# Phase 0: Install Kubernetes binaries (if needed)
# Phase 1: System preparation and preflight checks
# Phase 2: CNI plugins installation
# Phase 3: Control plane initialization
# Phase 4: Worker node join
# Phase 5: Flannel CNI deployment
```

### Modified Preflight Checks

The preflight role now:
- Warns about missing binaries instead of failing
- Trusts that Phase 0 has already handled installation
- Continues with deployment even if a warning is shown

## Usage

### Normal Deployment (unchanged)

```bash
# Deploy complete infrastructure
./deploy.sh all --with-rke2 --yes

# Deploy Debian cluster only
./deploy.sh debian

# Deploy RKE2 only
./deploy.sh rke2
```

### After Reset (now works!)

```bash
# Reset the cluster
./deploy.sh reset

# Redeploy - binaries will be automatically installed if missing
./deploy.sh all --with-rke2 --yes
```

### Fresh Node Setup

For new nodes added to the cluster:
1. Add node to inventory
2. Run deployment - binaries will be installed automatically
3. No manual installation required

## What Gets Installed

When binaries are missing, the role installs:

### Debian/Ubuntu Systems
- Kubernetes apt repository (v1.29 stable)
- containerd
- kubeadm
- kubelet
- kubectl

### RHEL/CentOS Systems
- Kubernetes yum repository (v1.29 stable)
- containerd
- kubeadm
- kubelet
- kubectl

## Configuration

### Containerd

The role automatically configures containerd with:
- SystemdCgroup enabled (required for Kubernetes)
- Default configuration from `containerd config default`
- Service enabled and started

### Package Holding

On Debian/Ubuntu, packages are held to prevent automatic upgrades:
```bash
apt-mark hold kubelet kubeadm kubectl
```

This prevents accidental version mismatches during system updates.

## Idempotency

The role is fully idempotent:
- ✅ Running deployment multiple times is safe
- ✅ Existing installations are not modified
- ✅ Only missing binaries are installed
- ✅ Configuration is only applied if needed

Example:
```bash
# First run - installs binaries
./deploy.sh debian

# Second run - skips installation, proceeds with deployment
./deploy.sh debian

# After reset and redeploy - reinstalls only if needed
./deploy.sh reset
./deploy.sh debian
```

## Verification

To verify the installation role is working:

```bash
# Run the test suite
./tests/test-install-k8s-binaries.sh

# Check installed versions on a node
ssh root@masternode "kubeadm version && kubelet --version && kubectl version --client"
```

## Troubleshooting

### Issue: Installation fails with repository errors

**Solution**: Check internet connectivity and ensure the node can reach pkgs.k8s.io

```bash
# Test connectivity
curl -I https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key
```

### Issue: Containerd fails to start

**Solution**: Check containerd configuration

```bash
# View containerd status
systemctl status containerd

# Check configuration
containerd config dump | grep SystemdCgroup

# Restart containerd
systemctl restart containerd
```

### Issue: Binaries exist but are wrong version

**Solution**: Remove old binaries and redeploy

```bash
# Remove old binaries
rm -f /usr/bin/kubeadm /usr/bin/kubelet /usr/bin/kubectl

# Redeploy - will install correct version
./deploy.sh debian
```

## Migration from Manual Installation

If you previously installed Kubernetes manually, the role will:
1. Detect existing binaries
2. Skip installation
3. Proceed with deployment using existing binaries

To force a clean reinstall:
```bash
# Remove existing binaries
./deploy.sh reset

# Redeploy - will install fresh binaries
./deploy.sh all --with-rke2 --yes
```

## Benefits

### Before (Manual Installation Required)
1. User runs `./deploy.sh reset`
2. Binaries removed or corrupted
3. Deployment fails with "kubelet not found"
4. User must manually install kubeadm/kubelet
5. User reruns deployment

### After (Automatic Installation)
1. User runs `./deploy.sh reset`
2. User runs `./deploy.sh all --with-rke2 --yes`
3. Binaries automatically installed if missing
4. Deployment succeeds ✅

## Technical Details

### Files Modified
- `ansible/playbooks/deploy-cluster.yaml` - Added Phase 0
- `ansible/roles/preflight/tasks/main.yml` - Changed to warning
- `ansible/roles/install-k8s-binaries/tasks/main.yml` - New role

### Host Targeting
The installation role only runs on:
- `monitoring_nodes` (Debian - control plane)
- `storage_nodes` (Debian - workers)

It does NOT run on:
- `compute_nodes` / `homelab` (uses RKE2 instead)

### Version Pinning
The role uses Kubernetes v1.29 stable repository to match the cluster version defined in the deployment runbook.

## Related Documentation
- [RKE2 Deployment Runbook](RKE2_DEPLOYMENT_RUNBOOK.md)
- [Cluster Reset Guide](CLUSTER_RESET_GUIDE.md)
- [Test Environment Guide](../TEST_ENVIRONMENT_GUIDE.md)

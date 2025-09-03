# Quick Reference: Flannel CNI Controller Fix

## Problem
- CNI0 interfaces created on worker nodes when they shouldn't be
- Flanneld controller running on worker nodes instead of only masternode
- **Cert-manager installations hanging due to network conflicts**
- **Stale CNI state causing bridge address conflicts**
- **Worker nodes missing CNI plugin infrastructure (NEW FIX)**

## Solution  
Custom Flannel manifest restricts DaemonSet to control plane nodes only.

## Files Changed
1. `ansible/plays/kubernetes/templates/kube-flannel-masteronly.yml` - Custom Flannel manifest
2. `ansible/plays/kubernetes/setup_cluster.yaml` - Uses custom manifest + worker CNI setup
3. `test_flannel_fix.sh` - Pre-deployment validation
4. `test_worker_cni_fix.sh` - Worker CNI infrastructure validation (NEW)
5. `validate_flannel_placement.sh` - Post-deployment validation
6. `FLANNEL_CNI_CONTROLLER_FIX.md` - Detailed documentation

## Usage

### Deploy with fix:
```bash
./update_and_deploy.sh
# OR
ansible-playbook -i ansible/inventory.txt ansible/site.yaml
```

### Validate:
```bash
# Before deployment
./test_flannel_fix.sh
./test_worker_cni_fix.sh

# After deployment  
./validate_flannel_placement.sh

# Troubleshoot CNI issues
./cni_cleanup_diagnostic.sh show
```

## Expected Result
- Flannel only runs on masternode (192.168.4.63)
- No CNI0 on worker nodes (192.168.4.61, 192.168.4.62)
- Cert-manager installs complete without hanging
- Full playbook execution succeeds

## Architecture
```
Control Plane (192.168.4.63)
├── Flannel Controller ✅
├── CNI0 Interface ✅
├── CNI Plugins ✅
└── Network Management ✅

Worker Nodes (192.168.4.61, 192.168.4.62)  
├── No Flannel Daemon ✅
├── No CNI0 Interface ✅
├── CNI Plugins Installed ✅ (NEW)
├── CNI Configuration ✅ (NEW)
└── Pod Networking via Master ✅
```
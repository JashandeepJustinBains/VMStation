# Local-Path Provisioner Storage Path Fix

## Problem Fixed
The deployment was hanging at the "Install kube-prometheus-stack (Prometheus + Grafana)" task because the local-path provisioner was using the default storage location (`/opt/local-path-provisioner`) instead of the desired `/srv/monitoring_data` directory.

## Solution Implemented

### 1. Custom Local-Path Provisioner Configuration
Created `ansible/plays/kubernetes/setup_local_path_provisioner.yaml` that deploys a custom local-path provisioner with:
- Storage path configured to `/srv/monitoring_data/local-path-provisioner`
- All necessary RBAC permissions
- Custom ConfigMap with the correct storage path
- Proper deployment manifests

### 2. Updated Prerequisites
Modified `ansible/plays/setup_monitoring_prerequisites.yaml` to:
- Include `/srv/monitoring_data/local-path-provisioner` in the created directories
- Ensure proper permissions (755) and ownership (root:root)
- Set appropriate SELinux contexts if enabled

### 3. Updated Deployment Pipeline
Modified `ansible/plays/kubernetes_stack.yaml` to:
- Deploy the custom local-path provisioner before monitoring components
- Ensure storage infrastructure is ready before monitoring stack installation

### 4. Updated Permission Scripts
Modified `scripts/fix_monitoring_permissions.sh` to:
- Include the local-path provisioner directory in permission fixes
- Support the new storage path in automated remediation

### 5. Updated Fix Scripts
Modified `scripts/fix_k8s_monitoring_pods.sh` to:
- Reference the custom VMStation local-path provisioner instead of the default one
- Provide correct troubleshooting guidance

## Key Changes

### Files Modified:
1. `ansible/plays/kubernetes/setup_local_path_provisioner.yaml` (NEW) - Custom provisioner deployment
2. `ansible/plays/setup_monitoring_prerequisites.yaml` - Added local-path directory
3. `ansible/plays/kubernetes_stack.yaml` - Added provisioner setup step
4. `scripts/fix_monitoring_permissions.sh` - Added provisioner directory
5. `scripts/fix_k8s_monitoring_pods.sh` - Updated fix suggestions

### Storage Configuration:
- **Before**: Default local-path provisioner used `/opt/local-path-provisioner`
- **After**: Custom local-path provisioner uses `/srv/monitoring_data/local-path-provisioner`

## Directory Structure
The solution creates the following directory structure:
```
/srv/monitoring_data/
├── grafana/
├── prometheus/
├── loki/
├── promtail/
└── local-path-provisioner/    # NEW: PVC storage location
```

## Deployment Order
1. Setup cluster (existing)
2. Setup Helm (existing)
3. Setup cert-manager (existing)
4. **Setup custom local-path provisioner (NEW)**
5. Setup monitoring prerequisites (updated)
6. Deploy monitoring stack (existing)

## Verification
After deployment:
- Storage class `local-path` will use `/srv/monitoring_data/local-path-provisioner`
- Grafana, Prometheus, Loki PVCs will be created in the correct location
- No more hanging at kube-prometheus-stack installation
- All monitoring data stored under `/srv/monitoring_data` as required

## Usage
The fix is automatically included when running:
```bash
./update_and_deploy.sh
```

Or for individual playbook execution:
```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes_stack.yaml
```

The deployment should now complete without hanging, with all persistent volume data correctly stored in `/srv/monitoring_data/local-path-provisioner/`.
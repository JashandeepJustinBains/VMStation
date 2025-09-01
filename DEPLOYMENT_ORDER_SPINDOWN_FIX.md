# VMStation Deployment Order and Spindown Fix

## Problem Summary
The issue was causing hanging/timeout requests to the Kubernetes API server due to:
1. **Incorrect 00-spindown.yaml playbook** not properly closing down the API server and etcd
2. **Wrong deployment order** in update_and_deploy/site.yaml where applications were being deployed before Kubernetes infrastructure was properly initialized

## Root Cause Analysis

### 1. Spindown Issues
The original `00-spindown.yaml` playbook was stopping the kubelet service but:
- Did not explicitly stop the kube-apiserver static pod
- Did not stop etcd static pod  
- Did not force-kill remaining Kubernetes processes
- Left static pod manifests in place, allowing services to restart

### 2. Deployment Order Issues
The original `site.yaml` had the wrong deployment sequence:
```yaml
# WRONG ORDER (original):
- import_playbook: plays/apply_drone_secrets.yml      # Apps before K8s!
- import_playbook: subsites/05-extra_apps.yaml        # Apps before K8s!
- import_playbook: plays/setup_monitoring_prerequisites.yaml
- import_playbook: plays/kubernetes_stack.yaml        # K8s setup too late!
- import_playbook: plays/jellyfin.yml
```

This caused applications to try to deploy before Kubernetes was properly set up and running.

## Solution Implemented

### 1. Enhanced 00-spindown.yaml
Added explicit API server and etcd shutdown logic:
- **Stop static pods**: Move manifests out of `/etc/kubernetes/manifests/`
- **Terminate processes**: Force kill any remaining kube-apiserver, etcd, kubelet processes
- **Wait period**: Allow time for graceful shutdown before force termination
- **Complete cleanup**: Remove all Kubernetes state and configuration

### 2. Fixed Deployment Order in site.yaml
Reordered the playbook imports to follow proper sequence:
```yaml
# CORRECT ORDER (fixed):
- import_playbook: plays/kubernetes_stack.yaml          # K8s infrastructure FIRST
- import_playbook: plays/setup_monitoring_prerequisites.yaml
- import_playbook: plays/apply_drone_secrets.yml        # Apps after K8s
- import_playbook: subsites/05-extra_apps.yaml         # Apps after K8s
- import_playbook: plays/jellyfin.yml
```

### 3. Updated Documentation
- Fixed recommended execution order comments in site.yaml
- Added safety comments about excluded subsites
- Updated individual playbook execution sequence

## Technical Details

### Spindown Improvements
```yaml
# New tasks added to 00-spindown.yaml:
- Stop kube-apiserver static pod (move manifest)
- Stop kube-controller-manager static pod  
- Stop kube-scheduler static pod
- Stop etcd static pod
- Wait for graceful termination (10 seconds)
- Force kill remaining processes (pkill -f)
- Stop and disable kubelet service
```

### Deployment Sequence
```
1. Kubernetes Infrastructure Setup
   ↓
2. Monitoring Prerequisites  
   ↓
3. Application Prerequisites (drone secrets)
   ↓
4. Applications (extra apps, jellyfin)
```

## Testing and Validation

### Tests Created
- `test_deployment_order_fix.sh` - Validates all fixes
- Syntax validation for modified playbooks
- Integration with existing test suite

### Test Results
```
✅ API server shutdown: PASSED
✅ Deployment order: PASSED  
✅ Syntax validation: PASSED
✅ Script functionality: PASSED
```

## Benefits

1. **No More Hanging**: Spindown properly terminates all Kubernetes processes
2. **Correct Initialization**: Kubernetes is set up before applications try to deploy
3. **Reliable Deployment**: Applications can successfully connect to API server
4. **Clean Teardown**: Complete removal of Kubernetes state when needed
5. **Better Error Handling**: Clear sequence prevents dependency issues

## Backward Compatibility

All changes are backward compatible:
- Existing functionality preserved when components are accessible
- Enhanced shutdown works with both kubeadm and manual installations
- Deployment order fix doesn't affect individual playbook execution
- Original timeout and connectivity fixes remain intact

## Usage

### Normal Deployment
```bash
./update_and_deploy.sh
```

### Clean Teardown
```bash
ansible-playbook -i ansible/inventory.txt ansible/subsites/00-spindown.yaml -e confirm_spindown=true
```

### Individual Components (proper order)
```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes_stack.yaml
ansible-playbook -i ansible/inventory.txt ansible/plays/setup_monitoring_prerequisites.yaml
ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml
```

The fixes ensure that VMStation deployment will no longer hang due to improper shutdown or wrong initialization order.
# Homelab Node Networking Issues Fix

## Problem Statement

After multiple runs of `deploy.sh full`, several critical networking issues were observed:

1. **Flannel CrashLoopBackOff** on homelab node (192.168.4.62)
2. **CoreDNS scheduling to homelab instead of masternode** causing crashes
3. **kube-proxy crashes** on homelab node
4. **All monitoring pods stuck in ContainerCreating** for hours
5. **Jellyfin not deploying** to storagenodeT3500
6. **Ansible playbook hanging** on "wait for applications to be ready"

## Root Cause Analysis

The homelab node (192.168.4.62) appears to have CNI networking configuration issues that cause:
- Flannel pod to crash repeatedly
- System pods like kube-proxy to fail
- Network instability affecting the entire cluster

Additionally, CoreDNS was being scheduled to the homelab node instead of being required to run on the control-plane node (masternode), which compounded the networking issues.

## Solutions Implemented

### 1. Enhanced Homelab Node Issue Fix (`scripts/fix_homelab_node_issues.sh`)

This script provides comprehensive remediation:
- **Restarts crashlooping Flannel pods** on homelab node
- **Restarts crashlooping kube-proxy pods** on homelab node  
- **Patches CoreDNS deployment** to require control-plane nodes with proper tolerations
- **Forces restart of stuck ContainerCreating pods**
- **Tests DNS resolution** to verify fixes
- **Provides detailed status reporting**

### 2. CoreDNS Scheduling Improvements

Updated `ansible/plays/setup-cluster.yaml` to:
- **Configure CoreDNS node affinity** to require control-plane nodes
- **Add proper tolerations** for control-plane node taints
- **Apply scheduling configuration** during cluster setup

### 3. Application Deployment Robustness

Enhanced `ansible/plays/deploy-apps.yaml` to:
- **Add nodeSelector to monitoring pods** (Prometheus, Grafana, Loki) to ensure they only run on the control-plane node (masternode) and avoid the problematic homelab node
- **Check CoreDNS health** before waiting for applications
- **Reduce timeout** from 600 to 300 seconds to prevent hanging
- **Provide better error messages** when networking is unstable

### 4. Jellyfin Deployment Improvements  

Enhanced `ansible/plays/jellyfin.yml` to:
- **Verify target storage node readiness** before deployment
- **Improved error handling** with better timeout management
- **Better status reporting** for deployment issues

### 5. Deploy Script Enhancements

Updated `deploy.sh` to:
- **Run homelab node fix** if CoreDNS fixes fail
- **Provide cascading fix approach** for networking issues
- **Better error reporting** and recovery guidance

## Usage

### For Current Issues
If you're experiencing the described problems:

```bash
# Fix homelab node networking issues
./scripts/fix_homelab_node_issues.sh

# Wait for cluster to stabilize
sleep 60

# Deploy applications
./deploy.sh apps

# Verify Jellyfin deployment
kubectl get pods -n jellyfin -o wide
```

### For Fresh Deployments
The fixes are now integrated into the standard deployment:

```bash
# Full deployment with automatic fixes
./deploy.sh full
```

The deployment will automatically:
1. Configure CoreDNS scheduling during cluster setup
2. Apply homelab node fixes if networking issues are detected
3. Deploy monitoring stack with improved error handling
4. Deploy Jellyfin with enhanced robustness

## Prevention

The enhanced cluster setup now includes:
- **Proactive CoreDNS scheduling configuration**
- **Automatic networking issue detection and remediation**  
- **Improved timeout and error handling**
- **Better status reporting and troubleshooting guidance**

## Validation

After applying fixes, verify:

```bash
# Check that no pods are crashlooping
kubectl get pods --all-namespaces | grep -E "(CrashLoopBackOff|Error|Unknown)"

# Verify CoreDNS is on masternode
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# Check Jellyfin deployment
kubectl get pods -n jellyfin -o wide

# Test DNS resolution
kubectl run dns-test --image=busybox:1.28 --rm -it --restart=Never -- nslookup kubernetes.default
```

## Related Files

- `scripts/fix_homelab_node_issues.sh` - Main homelab node issue remediation
- `scripts/fix_coredns_unknown_status.sh` - CoreDNS-specific fixes
- `ansible/plays/setup-cluster.yaml` - Enhanced cluster setup with CoreDNS scheduling
- `ansible/plays/deploy-apps.yaml` - Improved application deployment
- `ansible/plays/jellyfin.yml` - Enhanced Jellyfin deployment
- `deploy.sh` - Updated deployment script with cascading fixes
# VMStation CNI Bridge Fix - Simple Solution

## The Problem

Your Kubernetes cluster was experiencing CNI bridge IP conflicts preventing pods from starting:

```
Failed to create pod sandbox: plugin type="bridge" failed (add): failed to set bridge addr: "cni0" already has an IP address different from 10.244.0.1/16
```

This was causing:
- Jellyfin pod stuck in `ContainerCreating` 
- CoreDNS in `CrashLoopBackOff`
- General pod networking failures

## The Root Cause

1. **CNI Bridge Name Mismatch**: Original flannel config used bridge name "cbr0" but the system created "cni0"
2. **Wrong IP Range**: CNI bridge had wrong IP address (not in 10.244.x.x range)
3. **Complex Manifests**: Original manifests had unnecessary complexity causing scheduling issues

## The Simple Fix

We created minimal, working manifests and a **single command** to fix everything:

```bash
./fix-cluster.sh
```

That's it! This command will:

1. ✅ Reset CNI bridge to correct IP range (10.244.x.x)
2. ✅ Deploy simplified flannel with correct bridge name "cni0"  
3. ✅ Deploy working CoreDNS on control plane
4. ✅ Deploy optimized kube-proxy for mixed OS environment
5. ✅ Deploy simplified Jellyfin that will actually start
6. ✅ Verify everything is working

## What Changed

### New Minimal Manifests

- **`manifests/cni/flannel-minimal.yaml`**: Fixed bridge name from "cbr0" → "cni0"
- **`manifests/network/coredns-minimal.yaml`**: Simplified, scheduled only on control plane
- **`manifests/network/kube-proxy-minimal.yaml`**: Optimized for mixed OS (Debian + RHEL)
- **`manifests/jellyfin/jellyfin-minimal.yaml`**: Removed complex annotations, just works

### Key Fixes

1. **CNI Bridge Configuration**:
   ```yaml
   # OLD (wrong)
   "name": "cbr0"
   
   # NEW (correct)
   "name": "cni0",
   "delegate": {
     "bridge": "cni0"
   }
   ```

2. **CoreDNS Scheduling**: Now runs only on control plane for stability
3. **Jellyfin Simplification**: Removed debug annotations that were causing issues

## Usage

### Quick Fix (Recommended)
```bash
./fix-cluster.sh
```

### Alternative Methods
```bash
# Manual deployment with options
./deploy-single.sh deploy              # Full deployment
./deploy-single.sh network-only        # Just network components
./deploy-single.sh reset-cni           # Just reset CNI bridge

# Ansible approach  
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/minimal-network-fix.yml
```

## After Running the Fix

1. **Check pod status**:
   ```bash
   kubectl get pods --all-namespaces
   ```

2. **Verify CNI bridge**:
   ```bash
   ip addr show cni0
   # Should show IP like 10.244.0.1/16
   ```

3. **Access services**:
   - Jellyfin: http://192.168.4.61:30096
   - Grafana: http://192.168.4.63:30300 (if monitoring deployed)
   - Prometheus: http://192.168.4.63:30090 (if monitoring deployed)

## What's Different from Before

### Old Approach (Complex)
- Multiple scripts to run after deployment
- Complex manifests with debug annotations
- CNI bridge reset as separate manual step
- Required 4+ commands to get working cluster

### New Approach (Simple)
- **Single command**: `./fix-cluster.sh`
- Minimal manifests that just work
- CNI bridge reset integrated into deployment
- Root cause fixed in manifests, not worked around with scripts

## Troubleshooting

If `./fix-cluster.sh` doesn't work:

1. **Check you're on control plane**:
   ```bash
   ls -la /etc/kubernetes/admin.conf
   ```

2. **Check node access**:
   ```bash
   kubectl get nodes
   ```

3. **Manual CNI reset**:
   ```bash
   sudo ./scripts/reset_cni_bridge_minimal.sh
   ```

4. **Check logs**:
   ```bash
   kubectl logs -n kube-flannel -l app=flannel
   kubectl logs -n kube-system -l k8s-app=kube-dns
   ```

## Why This Works

The fix addresses the actual root cause rather than working around symptoms:

1. **Correct CNI Configuration**: Bridge name matches what Kubernetes expects
2. **Proper IP Range**: Ensures 10.244.x.x IPs for pod network
3. **Simplified Scheduling**: Reduces complexity that was causing pod placement issues
4. **Integrated Approach**: CNI reset + manifest deployment in one command

Your cluster now has a **proper, working network foundation** instead of a complex workaround.
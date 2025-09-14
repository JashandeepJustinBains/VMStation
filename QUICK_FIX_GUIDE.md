# Quick Fix Guide for CNI Bridge Issue

## Problem
Jellyfin pod stuck in `ContainerCreating` with error:
```
failed to set bridge addr: "cni0" already has an IP address different from 10.244.1.1/24
```

## Solution Options

### Option 1: Immediate Fix (Recommended)
```bash
# SSH to control plane (192.168.4.63) as root
sudo ./fix_jellyfin_immediate.sh
```

### Option 2: Enhanced Reset  
```bash
# This now properly cleans CNI state
./deploy-cluster.sh reset
```

### Option 3: Comprehensive Fix
```bash
./fix-cluster.sh
```

## Validation
```bash
# Test the fix
./test_cni_bridge_fix.sh

# Check Jellyfin access
curl -I http://192.168.4.61:30096/web/#/home.html
```

## Expected Results
- ✅ Jellyfin pod in `Running` state
- ✅ CNI bridge with 10.244.x.x IP
- ✅ No `ContainerCreating` pods
- ✅ Access to http://192.168.4.61:30096/web/#/home.html

## Files Changed
- `deploy-cluster.sh` - Enhanced reset with CNI cleanup
- `ansible/playbooks/verify-cluster.yml` - Corrected URL validation
- `fix_jellyfin_immediate.sh` - New targeted fix script
- `test_cni_bridge_fix.sh` - Validation test script

## If Still Having Issues
1. Check: `kubectl get events --all-namespaces | grep -i cni`
2. Check: `ip addr show cni0`  
3. Check: `kubectl logs -n kube-flannel -l app=flannel`
4. Run: `sudo scripts/fix_cni_bridge_conflict.sh`
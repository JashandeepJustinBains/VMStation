# CNI Bridge Reset Quick Fix

## Problem
Jellyfin pod (or other pods) stuck in ContainerCreating state with error:
```
Failed to create pod sandbox: plugin type="bridge" failed (add): failed to set bridge addr: "cni0" already has an IP address different from 10.244.x.x/xx
```

## Quick Solution
Run the CNI bridge reset script:
```bash
sudo ./scripts/reset_cni_bridge.sh
```

## What This Script Does
1. **Detects** the CNI bridge IP conflict
2. **Backs up** current CNI configuration 
3. **Stops** kubelet and containerd services safely
4. **Removes** the conflicting cni0 bridge
5. **Clears** CNI network state
6. **Restarts** services to let Flannel recreate the bridge correctly
7. **Verifies** the bridge is recreated with proper IP in 10.244.0.0/16 range

## Expected Result
- CNI bridge (cni0) will have correct IP aligned with Flannel network (10.244.0.0/16)
- Pods will no longer get stuck in ContainerCreating state
- Network configuration aligns with kube-flannel, kube-proxy, and CoreDNS

## Integration
- Run `./scripts/validate_network_prerequisites.sh` first to detect issues
- The validation script will recommend this reset when CNI bridge conflicts are detected
- This is a targeted fix for the specific "cni0 already has IP address different from 10.244.x.x" error

## Safety
- Creates backup of CNI state before making changes
- Only affects the CNI bridge, preserves other network configurations
- Safe to run multiple times
- Minimal service disruption (brief kubelet/containerd restart)

## Troubleshooting
If issues persist after running the reset:
1. Check Flannel pod logs: `kubectl logs -n kube-flannel -l app=flannel`
2. Verify node status: `kubectl get nodes`
3. Check recent events: `kubectl get events --sort-by='.lastTimestamp' | tail -10`
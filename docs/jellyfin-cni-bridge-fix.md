# Fix Jellyfin CNI Bridge IP Conflict

## Problem Description
This script addresses the specific issue where Jellyfin pods fail to create with the error:

```
failed to setup network for sandbox: plugin type="flannel" failed (add): failed to delegate add: failed to set bridge addr: "cni0" already has an IP address different from 10.244.2.1/24
```

This occurs when the CNI bridge (cni0) on a worker node has been assigned an IP address that conflicts with the subnet Flannel expects for that node.

## Quick Fix

Run this command on the Kubernetes control plane node:

```bash
sudo ./fix_jellyfin_cni_bridge_conflict.sh
```

## What the Script Does

1. **Verifies the Problem**: Checks if the Jellyfin pod is stuck in ContainerCreating state due to CNI bridge conflicts
2. **Diagnoses CNI Configuration**: Examines the current cni0 bridge IP and compares it with expected Flannel subnets
3. **Checks Flannel Status**: Validates that Flannel pods are running correctly on storagenodet3500
4. **Applies the Fix**: 
   - Temporarily stops kubelet to prevent pod creation churn
   - Removes the conflicting cni0 bridge
   - Clears cached CNI network state
   - Restarts containerd and kubelet services
5. **Restarts Flannel**: Forces Flannel pod recreation to establish correct network configuration
6. **Recreates Jellyfin Pod**: Deletes the stuck pod and recreates it with proper networking
7. **Monitors Success**: Waits for the pod to reach Running state and validates the fix

## Expected Results

After running the script successfully:

- ✅ Jellyfin pod transitions from ContainerCreating to Running
- ✅ cni0 bridge gets the correct IP address (10.244.2.1/24 for storagenodet3500)
- ✅ No more "failed to set bridge addr" errors in pod events
- ✅ Jellyfin UI becomes accessible at http://192.168.4.61:30096

## Troubleshooting

If the script doesn't resolve the issue:

1. **Check Events**: `kubectl get events -n jellyfin --sort-by='.lastTimestamp'`
2. **Check Flannel Logs**: `kubectl logs -n kube-flannel -l app=flannel`
3. **Check CNI Bridge**: `ip addr show cni0`
4. **Manual Bridge Reset**: 
   ```bash
   sudo ip link set cni0 down
   sudo ip link delete cni0
   sudo systemctl restart containerd
   ```

## Manual Execution Steps

If you prefer to run the fix manually:

1. Stop kubelet: `sudo systemctl stop kubelet`
2. Remove bridge: `sudo ip link delete cni0`
3. Clear CNI state: `sudo rm -rf /var/lib/cni/*`
4. Restart containerd: `sudo systemctl restart containerd`
5. Start kubelet: `sudo systemctl start kubelet`
6. Restart Flannel: `kubectl delete pods -n kube-flannel --all`
7. Recreate Jellyfin: `kubectl delete pod -n jellyfin jellyfin && kubectl apply -f manifests/jellyfin/jellyfin.yaml`

## Related Documentation

- [General CNI Fix Guide](README-CNI-FIX.md)
- [Network Diagnosis Quickstart](NETWORK-DIAGNOSIS-QUICKSTART.md)
- [Cluster Network Reset Runbook](NETWORK_RESET_RUNBOOK.md)
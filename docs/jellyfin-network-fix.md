# Jellyfin Pod Network Connectivity Fix

## Problem
After running the cluster deployment, the Jellyfin pod shows `0/1` ready status despite the container running successfully. The health probes fail with "no route to host" errors when trying to connect to the pod IP.

## Root Cause
The issue is caused by CNI bridge (cni0) configuration problems where the bridge IP is not in the expected Flannel subnet (10.244.0.0/16). This prevents network routing from the kubelet to the pod IP, causing health probe failures.

## Symptoms
```bash
kubectl get pods -n jellyfin
# Shows: jellyfin 0/1 Running

kubectl describe pod -n jellyfin jellyfin
# Shows: Startup probe failed: Get "http://10.244.0.15:8096/": dial tcp 10.244.0.15:8096: connect: no route to host
```

## Solution
Run the network connectivity fix script:

```bash
# From the VMStation repository root
./fix_jellyfin_network_issue.sh
```

This script will:
1. Diagnose the CNI bridge configuration
2. Apply the CNI bridge fix if needed (using `scripts/fix_cni_bridge_conflict.sh`)
3. Restart the Jellyfin pod to reset probe state
4. Verify the pod becomes ready

## Manual Alternative
If you prefer to run the steps manually:

```bash
# Check CNI bridge configuration
ip addr show cni0

# If the IP is not in 10.244.0.0/16, run the fix
sudo ./scripts/fix_cni_bridge_conflict.sh

# Restart the Jellyfin pod
kubectl delete pod -n jellyfin jellyfin
kubectl apply -f manifests/jellyfin/jellyfin.yaml

# Wait for pod to become ready
kubectl wait --for=condition=ready pod/jellyfin -n jellyfin --timeout=600s
```

## Verification
After the fix:
```bash
kubectl get pods -n jellyfin
# Should show: jellyfin 1/1 Running

# Test access
curl http://192.168.4.61:30096
```

## Technical Details
The Jellyfin pod configuration is correct with appropriate timeouts and resource allocation. The issue is purely a network infrastructure problem that affects pod-to-kubelet communication needed for health checks.
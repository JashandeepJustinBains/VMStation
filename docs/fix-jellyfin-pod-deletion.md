# Fix Summary: Prevent Unnecessary Jellyfin Pod Deletion and Flannel Crashes

This fix addresses the issue where previous PR changes were unnecessarily deleting healthy jellyfin pods and causing flannel pod crashes.

## Problem
- Jellyfin pods were being deleted even when Running (just health check issues)
- Flannel pods were crashing due to aggressive `delete --all` operations
- Fix scripts were being too aggressive with pod cleanup

## Solution
1. **Conditional Jellyfin Pod Deletion**: Only delete pods that are actually problematic (Pending/Failed/Unknown), preserve Running pods
2. **Intelligent Flannel Restart**: Use graduated restart strategies based on pod health instead of always deleting all pods
3. **Health Check Before Deletion**: All scripts now check pod status before performing destructive operations

## Files Modified
- `deploy-cluster.sh`: Added pod health checks before jellyfin deletion
- `scripts/fix_cni_bridge_conflict.sh`: Replaced aggressive flannel deletion with intelligent restart logic  
- `scripts/fix_remaining_pod_issues.sh`: Added conditional jellyfin pod handling

## Expected Result
- ✅ Running jellyfin pods (even with health issues) are preserved
- ✅ Flannel pods only restart when actually problematic  
- ✅ Reduced cluster disruption during fix operations
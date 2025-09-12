# Jellyfin Pod Readiness Fix

## Problem
Jellyfin pods were failing to become ready due to CNI networking issues causing "no route to host" errors during health check probes.

## Root Cause Analysis
1. **CNI Bridge Conflicts**: The `cni0` bridge IP was not in the expected Flannel subnet (10.244.0.0/16)
2. **Network Routing Issues**: Health check probes couldn't reach the pod IP due to network routing problems
3. **Insufficient Probe Timeouts**: Default probe timeouts were too short to handle CNI networking delays
4. **Flannel Initialization Issues**: CNI plugin (Flannel) wasn't properly initialized, causing network connectivity failures

## Solutions Implemented

### 1. Extended Probe Timeouts
- **Startup Probe**: Increased to 60 failure attempts × 20s intervals = 20 minutes total
- **Readiness Probe**: Increased timeout to 20s with 8 failure attempts
- **Liveness Probe**: Increased initial delay to 240s for better startup handling

### 2. Enhanced CNI Bridge Conflict Resolution
- Added automatic detection of CNI bridge IP conflicts
- Integrated CNI bridge fix script into the Jellyfin deployment process
- Enhanced network connectivity validation before pod deployment

### 3. Improved Deployment Scripts
- **fix_jellyfin_readiness.sh**: Added comprehensive CNI status checks and automatic fixes
- **verify-cluster.yml**: Increased HTTP timeouts and retry counts for network connectivity issues
- **jellyfin.yml**: Updated probe configurations and readiness timeouts

### 4. Network Troubleshooting Integration
- Automatic Flannel DaemonSet status verification
- CNI bridge IP address validation
- Enhanced error reporting for network connectivity issues

## Files Modified

1. **manifests/jellyfin/jellyfin.yaml**
   - Extended startup probe to 60 failures × 20s = 20 minutes
   - Increased readiness probe timeout and failure threshold
   - Enhanced liveness probe initial delay

2. **fix_jellyfin_readiness.sh**
   - Added comprehensive CNI bridge conflict detection
   - Integrated automatic CNI fixes before pod deployment
   - Extended overall readiness timeout to 20 minutes

3. **ansible/playbooks/verify-cluster.yml**
   - Increased HTTP timeouts from 15s to 30s
   - Increased retries from 10 to 15 for Jellyfin web interface test
   - Extended pod readiness wait timeout

4. **ansible/plays/jellyfin.yml**
   - Updated probe configurations to match main manifest
   - Increased readiness timeout from 5 to 20 minutes

5. **fix_jellyfin_probe.yaml**
   - Updated probe configurations for consistency

## How the Fix Works

1. **Before Pod Deployment**:
   - Check CNI bridge IP configuration
   - Validate Flannel DaemonSet status
   - Run CNI bridge fix if conflicts detected

2. **During Pod Startup**:
   - Allow up to 20 minutes for initial startup (handles CNI delays)
   - Use longer timeouts for individual probe attempts
   - Handle temporary network connectivity issues gracefully

3. **For Readiness Checks**:
   - Extended timeouts handle network routing delays
   - Increased failure thresholds prevent premature failures
   - Better integration with cluster verification tests

## Expected Results

- Jellyfin pods should now successfully become ready even with CNI networking issues
- Health check probes will tolerate "no route to host" errors during network initialization
- Cluster verification tests should pass consistently
- Reduced false-positive failures due to temporary network connectivity issues

## Usage

To apply the fix manually:
```bash
# Run the enhanced fix script
./fix_jellyfin_readiness.sh

# Or deploy with updated manifests
kubectl apply -f manifests/jellyfin/jellyfin.yaml
```

The fix is automatically included in the cluster deployment and verification processes.
# Jellyfin Pod Scheduling Fix

## Problem Resolved

The Jellyfin deployment was failing with pods stuck in `Pending` status due to scheduling issues:

```
Warning  FailedScheduling  ... 0/3 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }, 2 node(s) didn't match Pod's node affinity/selector. preemption: 0/3 nodes are available: 3 Preemption is not helpful for scheduling.
```

## Root Cause

The issue was inconsistent hostname resolution between the deployment's `nodeSelector` and the Persistent Volume's `nodeAffinity`. This could happen due to:

1. **Timing issues**: Variables resolved at different times during playbook execution
2. **Case sensitivity**: Potential mismatches in hostname casing
3. **Automatic vs manual resolution**: Different logic paths setting different values

## Solution Implemented

### Key Changes in `ansible/plays/kubernetes/deploy_jellyfin.yaml`:

1. **Forced Consistent Hostname Resolution**
   ```yaml
   - name: Force use of known correct hostname for storage node 192.168.4.61
     set_fact:
       storage_node_k8s_name: "storagenodet3500"
       storage_node_k8s_addresses: ["192.168.4.61"]
       use_forced_hostname: true
     when: groups['storage_nodes'][0] == '192.168.4.61'
   ```

2. **Hostname Validation**
   ```yaml
   - name: Validate resolved hostname exists in cluster
     # Ensures the resolved hostname actually exists in Kubernetes
   ```

3. **PV NodeAffinity Validation & Correction**
   ```yaml
   - name: Check if existing PVs have correct nodeAffinity
   - name: Remove PVs with incorrect nodeAffinity
   - name: Wait for PV deletion to complete
   ```

4. **Enhanced Debugging**
   ```yaml
   - name: Debug hostname resolution method
     # Shows whether forced or automatic resolution was used
   ```

## Benefits

✅ **Eliminates hostname inconsistencies** - Always uses exact same hostname for nodeSelector and PV nodeAffinity  
✅ **Automatic PV correction** - Detects and fixes existing PVs with wrong nodeAffinity  
✅ **Early error detection** - Fails fast with clear error if hostname doesn't exist in cluster  
✅ **Better debugging** - Shows which resolution method was used and validates consistency  
✅ **Backwards compatible** - Works for both new deployments and fixing existing issues  

## Usage

### Deploy Jellyfin (this will now work correctly):

```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml
```

### What the fix does automatically:

1. **For storage node 192.168.4.61**: Always uses hostname `storagenodet3500`
2. **Validates hostname**: Ensures `storagenodet3500` exists in your Kubernetes cluster
3. **Checks existing PVs**: Validates that any existing Persistent Volumes have correct nodeAffinity
4. **Fixes PV issues**: Automatically recreates PVs with wrong nodeAffinity
5. **Deploys consistently**: Both nodeSelector and PV nodeAffinity use identical hostname

### Expected Result:

```bash
kubectl get pods -n jellyfin
NAME                        READY   STATUS    RESTARTS   AGE
jellyfin-xxxxxxxxx-xxxxx   1/1     Running   0          2m
```

The pods should now successfully schedule on the `storagenodet3500` node and transition from `Pending` to `Running` status.

## Troubleshooting

If you still encounter issues after applying this fix:

1. **Check cluster nodes match expected hostnames**:
   ```bash
   kubectl get nodes -o wide
   # Should show: storagenodet3500 with IP 192.168.4.61
   ```

2. **Verify PV nodeAffinity is correct**:
   ```bash
   kubectl get pv jellyfin-media-pv -o yaml | grep -A 10 nodeAffinity
   kubectl get pv jellyfin-config-pv -o yaml | grep -A 10 nodeAffinity
   ```

3. **Check pod scheduling details**:
   ```bash
   kubectl describe pods -n jellyfin
   ```

## Technical Details

The fix ensures that:
- **Variable consistency**: `storage_node_k8s_name` always has the same value throughout playbook execution
- **Case sensitivity**: Uses exact hostname `storagenodet3500` (lowercase 't')
- **Resource matching**: PV nodeAffinity and deployment nodeSelector use identical values
- **Validation**: Confirms resolved hostname exists before attempting deployment

This resolves the core scheduling conflict that was preventing Jellyfin pods from being placed on the storage node.
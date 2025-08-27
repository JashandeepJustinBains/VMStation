# Jellyfin Deployment Node Affinity Fix

## Problem Statement
The Jellyfin deployment was failing with the error occurring on 192.168.4.63 (monitoring/control plane node) when it should be deployed on 192.168.4.61 (storage node).

## Root Cause Analysis
The issue was not that pods were being scheduled on the wrong node, but rather:

1. **Misleading Error Location**: The Ansible task failure appeared on 192.168.4.63 because that's where the Ansible playbook runs (control plane), not where the pods are scheduled
2. **Complex Hostname Resolution**: The original regex-based hostname resolution could fail in some environments
3. **Insufficient Debugging**: Limited visibility into the actual node resolution and pod scheduling process
4. **Misleading Status Display**: Access URLs pointed to control plane IP instead of actual deployment location

## Solution Implemented

### 1. Enhanced Debugging
```yaml
- name: Debug cluster nodes and storage candidates
  debug:
    msg: |
      Cluster nodes found:
      {% for node in cluster_nodes.resources %}
      - Name: {{ node.metadata.name }}
        Addresses: {{ node.status.addresses | map(attribute='address') | list }}
      {% endfor %}
      
      Storage node candidates: {{ storage_node_candidates }}
      Target storage node from inventory: {{ groups['storage_nodes'][0] }}
```

### 2. Node Validation Logic
```yaml
- name: Validate resolved storage node matches expected storage node
  fail:
    msg: |
      ERROR: Resolved storage node does not match expected storage node!
      Expected: {{ groups['storage_nodes'][0] }}
      Resolved: {{ storage_node_k8s_name }}
  when: >-
    storage_node_k8s_name is defined and 
    groups['storage_nodes'][0] not in storage_node_k8s_addresses
```

### 3. Improved Status Display
```yaml
Access URLs:
- Primary HTTP: http://{{ groups['storage_nodes'][0] }}:30096 (via storage node)
- Primary HTTPS: https://{{ groups['storage_nodes'][0] }}:30920 (via storage node)
- Alternative access via any cluster node: http://{{ ansible_default_ipv4.address }}:30096
```

### 4. Simplified Hostname Resolution
Changed from complex regex that could fail:
```yaml
# OLD (could fail)
storage_node_hostname: "{{ groups['storage_nodes'][0] | regex_replace('^([0-9.]+)$', hostvars[groups['storage_nodes'][0]]['ansible_hostname']) }}"

# NEW (more robust)
storage_node_hostname: "{{ groups['storage_nodes'][0] }}"
```

## Key Improvements

### Before Fix:
- ❌ Misleading error messages showing control plane IP
- ❌ Limited debugging information
- ❌ Complex hostname resolution that could fail
- ❌ Unclear where pods were actually scheduled

### After Fix:
- ✅ Clear debugging showing node resolution process
- ✅ Validation ensures correct storage node selection  
- ✅ Status display shows actual deployment location
- ✅ Primary access URLs point to correct storage node
- ✅ Better error messages for troubleshooting

## Expected Behavior

| Component | Location | Purpose |
|-----------|----------|---------|
| Ansible Playbook Execution | 192.168.4.63 (control plane) | Manages deployment |
| Jellyfin Pods | 192.168.4.61 (storage node) | Runs media server |
| Primary Access | http://192.168.4.61:30096 | User access point |
| NodePort Service | All cluster nodes | Load balancing |

## Troubleshooting Guide

### 1. Check Node Resolution
```bash
# Verify storage node is in cluster
kubectl get nodes -o wide

# Check if node has correct labels
kubectl describe node <storage-node-name>
```

### 2. Verify Pod Scheduling
```bash
# Check where pods are actually scheduled
kubectl get pods -n jellyfin -o wide

# Check pod events for scheduling issues
kubectl describe pods -n jellyfin
```

### 3. Debug Node Selector Issues
```bash
# Check deployment node selector
kubectl get deployment jellyfin -n jellyfin -o yaml | grep -A5 nodeSelector

# Verify node labels match selector
kubectl get nodes --show-labels
```

### 4. Test Service Access
```bash
# Test storage node endpoint (should work)
curl -I http://192.168.4.61:30096/health

# Test control plane endpoint (should also work due to NodePort)
curl -I http://192.168.4.63:30096/health
```

## Prevention

To prevent similar issues in the future:

1. **Always include debugging output** for node resolution in deployment playbooks
2. **Validate resolved nodes** match expected target nodes before deployment
3. **Use simple, robust hostname resolution** instead of complex regex patterns
4. **Display accurate deployment status** showing actual pod locations
5. **Test deployment logic** with simulated cluster nodes

## Related Files Modified

- `ansible/plays/kubernetes/deploy_jellyfin.yaml` - Main deployment playbook with enhanced debugging and validation
# Drone Init Pod Fix - "list object has no element 0" Error

## Problem Statement
When deploying drone-hostpath-init pod on the homelab node, the Ansible playbook fails with:
```
fatal: [192.168.4.62]: FAILED! => {"msg": "The conditional check 'init_pod_info.resources[0].status.phase in ['Succeeded','Failed']' failed. The error was: error while evaluating conditional (init_pod_info.resources[0].status.phase in ['Succeeded','Failed']): list object has no element 0. list object has no element 0"}
```

## Root Causes Identified
1. **Unsafe Array Access**: The Ansible task was accessing `init_pod_info.resources[0]` without checking if the list was empty
2. **Wrong Node Name**: The drone playbook had `apps_node: r430computenode` but the actual node name is `homelab`
3. **Missing Error Handling**: No defensive programming for edge cases where pods fail to be created

## Symptoms
- Pods stuck in "ContainerCreating" state on homelab node (192.168.4.62)
- MongoDB and other apps unable to deploy due to drone deployment failure
- Ansible playbook hanging on drone-hostpath-init pod wait task

## Fix Applied

### 1. Fixed Node Name Mismatch
**File**: `ansible/subsites/07-drone-ci.yaml`
```yaml
# BEFORE
apps_node: r430computenode

# AFTER  
apps_node: homelab
```

### 2. Added Defensive Programming for Pod Status Check
**File**: `ansible/subsites/07-drone-ci.yaml` (lines 295-305)
```yaml
# BEFORE - Unsafe array access
until: init_pod_info.resources[0].status.phase in ['Succeeded','Failed']

# AFTER - Safe with proper validation
until: |
  (init_pod_info.resources | length > 0) and 
  (init_pod_info.resources[0].status is defined) and
  (init_pod_info.resources[0].status.phase is defined) and
  (init_pod_info.resources[0].status.phase in ['Succeeded','Failed'])
failed_when: |
  (init_pod_info.resources | length == 0) or
  ((init_pod_info.resources | length > 0) and 
   (init_pod_info.resources[0].status is defined) and
   (init_pod_info.resources[0].status.phase is defined) and
   (init_pod_info.resources[0].status.phase == 'Failed'))
```

### 3. Added Diagnostic Output
**File**: `ansible/subsites/07-drone-ci.yaml`
```yaml
- name: Show init pod status for troubleshooting
  ansible.builtin.debug:
    msg: |
      === Drone Init Pod Status ===
      Resources found: {{ init_pod_info.resources | length }}
      {% if init_pod_info.resources | length > 0 %}
      Pod phase: {{ init_pod_info.resources[0].status.phase | default('Unknown') }}
      {% else %}
      Pod was not found. Troubleshooting steps provided.
      {% endif %}
```

## Validation
The fix ensures:
- ✅ Empty resources list is handled gracefully
- ✅ Missing status fields don't cause crashes  
- ✅ Proper node targeting (homelab vs r430computenode)
- ✅ Clear diagnostic output for troubleshooting
- ✅ Syntax validation passes

## Testing
Run syntax validation:
```bash
ansible-playbook --syntax-check ansible/subsites/07-drone-ci.yaml
ansible-playbook --syntax-check ansible/subsites/05-extra_apps.yaml
```

Test deployment:
```bash
ansible-playbook -i inventory.txt ansible/subsites/07-drone-ci.yaml --check
```

## Impact
This fix resolves the immediate deployment failure and provides better error handling for future issues. The drone-hostpath-init pod should now:
1. Be scheduled on the correct node (homelab)
2. Handle edge cases gracefully without crashing the deployment
3. Provide clear diagnostics when issues occur

## Prevention
- Always validate array access in Ansible with `| length > 0` checks
- Verify node names match actual cluster topology
- Include diagnostic tasks for complex workflows
- Test playbooks in check mode before deployment
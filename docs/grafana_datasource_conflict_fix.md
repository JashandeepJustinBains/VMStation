# Grafana Datasource Conflict Fix

## Problem
Grafana was experiencing the following error:
```
logger=provisioning t=2025-09-02T18:37:13.902569751Z level=error msg="Failed to provision data sources" error="Datasource provisioning error: datasource.yaml config is invalid. Only one datasource per organization can be marked as default"
```

## Root Cause
The issue was caused by multiple datasources being configured as default:

1. **kube-prometheus-stack Helm chart** automatically creates a default Prometheus datasource when `sidecar.datasources.enabled: true` is set
2. **Manual Prometheus datasource** was being created via ConfigMap with `isDefault: true`
3. **Loki datasource** was created without explicitly setting `isDefault: false`, potentially causing ambiguity

This resulted in a conflict where Grafana detected multiple default datasources.

## Solution
The fix involved three key changes:

### 1. Set Loki Datasource as Non-Default
**File**: `ansible/plays/kubernetes/deploy_monitoring.yaml`

```yaml
# Before
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki-stack:3100
    jsonData:
      maxLines: 1000

# After  
datasources:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki-stack:3100
    isDefault: false  # Explicitly set as non-default
    jsonData:
      maxLines: 1000
```

### 2. Remove Redundant Prometheus Datasource
**File**: `ansible/plays/kubernetes/deploy_monitoring.yaml`

Removed the entire task that manually created the Prometheus datasource ConfigMap:
```yaml
# REMOVED - This was causing the conflict
- name: Create Prometheus datasource for Grafana (provisioning)
  kubernetes.core.k8s:
    state: present
    definition:
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: prometheus-datasource
        namespace: "{{ monitoring_namespace }}"
        labels:
          grafana_datasource: "1"
      stringData:
        prometheus-datasource.yaml: "{{ lookup('file', playbook_dir + '/../../files/grafana_datasources/prometheus-datasource.yaml') }}"
    kubeconfig: /root/.kube/config
```

**Rationale**: kube-prometheus-stack automatically creates a Prometheus datasource when `sidecar.datasources.enabled: true`, making the manual creation redundant and conflicting.

### 3. Update Validation Scripts
**File**: `ansible/plays/kubernetes/monitoring_validation.yaml`

Updated the validation to:
- Check for Grafana deployment readiness instead of the removed manual Prometheus datasource
- Validate that Loki datasource has `isDefault: false`
- Add appropriate documentation about the automatic Prometheus datasource

## How to Apply the Fix

### For New Deployments
Simply run the updated monitoring deployment:
```bash
ansible-playbook -i inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml
```

### For Existing Deployments with the Conflict
1. **Remove the conflicting manual Prometheus datasource** (if it exists):
   ```bash
   kubectl delete configmap prometheus-datasource -n monitoring
   ```

2. **Update the Loki datasource**:
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: loki-datasource
     namespace: monitoring
     labels:
       grafana_datasource: "1"
   data:
     loki-datasource.yaml: |
       apiVersion: 1
       datasources:
         - name: Loki
           type: loki
           access: proxy
           url: http://loki-stack:3100
           isDefault: false
           jsonData:
             maxLines: 1000
   EOF
   ```

3. **Restart Grafana** to pick up the changes:
   ```bash
   kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring
   ```

## Validation
Use the provided validation script to check if the fix worked:
```bash
./scripts/validate_grafana_datasource_fix.sh
```

The script will check:
- ✅ No datasource conflict errors in Grafana logs
- ✅ Loki datasource has `isDefault: false`
- ✅ No manual Prometheus datasource ConfigMap exists
- ✅ Grafana deployment is healthy
- ✅ API accessibility (if available)

## Expected Result
After applying the fix:
- Only one datasource (Prometheus, created by kube-prometheus-stack) is marked as default
- Loki datasource is available but not default
- Grafana logs show successful provisioning without conflicts
- Both Prometheus and Loki datasources are usable in Grafana dashboards

## Technical Notes
- **kube-prometheus-stack behavior**: The chart creates datasources when `grafana.sidecar.datasources.enabled: true` and `grafana.sidecar.datasources.defaultDatasourceEnabled: true`
- **Grafana constraint**: Only one datasource per organization can be marked as default
- **Best practice**: Let Helm charts handle their own resource creation rather than manually duplicating them

## Files Modified
- `ansible/plays/kubernetes/deploy_monitoring.yaml` - Main fix
- `ansible/plays/kubernetes/monitoring_validation.yaml` - Updated validation
- `ansible/files/grafana_datasources/prometheus-datasource.yaml` - Added deprecation notice
- `scripts/validate_grafana_datasource_fix.sh` - New validation script
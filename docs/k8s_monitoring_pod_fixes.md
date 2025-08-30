# Kubernetes Monitoring Pod Fixes

## Overview

This document provides specific fixes for the CrashLoopBackOff issues in your VMStation Kubernetes monitoring stack.

## Failing Pods Analysis

Based on your pod status output:

```
monitoring             kube-prometheus-stack-grafana-878594f88-cdbzt               0/3     Init:CrashLoopBackOff   124 (2m4s ago)    7h13m
monitoring             kube-prometheus-stack-grafana-8c4bb9b97-7prbs               0/3     Init:CrashLoopBackOff   124 (2m26s ago)   7h13m
monitoring             loki-stack-0                                                0/1     CrashLoopBackOff        125 (117s ago)    7h19m
```

## Root Causes and Fixes

### 1. Grafana Pods (Init:CrashLoopBackOff)

**Root Cause:** Grafana init container (`init-chown-data`) cannot change ownership of the data directory to the required UID:GID (472:472).

**Symptoms:**
- Pods stuck in `Init:CrashLoopBackOff` state
- Init container logs show: `chown: /var/lib/grafana: Permission denied`
- Multiple restart attempts with exponential backoff

**Fix Required:** Directory permission correction on the host node

#### Step-by-Step Fix:

1. **Identify the affected PersistentVolume:**
   ```bash
   kubectl -n monitoring get pvc kube-prometheus-stack-grafana -o jsonpath='{.spec.volumeName}'
   kubectl get pv <PV_NAME> -o yaml | grep 'path:'
   ```

2. **Find the hosting node:**
   ```bash
   kubectl get pv <PV_NAME> -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}'
   ```

3. **Fix permissions on the node (run as root on the node):**
   ```bash
   # SSH to the node and run:
   sudo chown -R 472:472 /var/lib/kubernetes/local-path-provisioner/pvc-*_monitoring_kube-prometheus-stack-grafana
   sudo chmod -R 755 /var/lib/kubernetes/local-path-provisioner/pvc-*_monitoring_kube-prometheus-stack-grafana
   ```

4. **Recreate the pods:**
   ```bash
   kubectl -n monitoring delete pod -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=kube-prometheus-stack
   ```

5. **Verify the fix:**
   ```bash
   kubectl -n monitoring get pods | grep grafana
   kubectl -n monitoring logs <new-grafana-pod> -c init-chown-data
   ```

### 2. Loki Pod (CrashLoopBackOff)

**Root Cause:** Invalid `max_retries` field in Loki configuration causing YAML parsing errors.

**Symptoms:**
- Pod stuck in `CrashLoopBackOff` state
- Container logs show: `failed parsing config: /etc/loki/loki.yaml: yaml: unmarshal errors: line 33: field max_retries not found in type validation.plain`

**Fix Required:** Configuration file correction via Helm values override

#### Step-by-Step Fix:

1. **Create a Helm values override file:**
   ```bash
   cat > /tmp/loki-fix-values.yaml << 'EOF'
   loki:
     config:
       table_manager:
         # Remove invalid max_retries field
         retention_deletes_enabled: true
         retention_period: 168h
   EOF
   ```

2. **Test the fix with dry-run:**
   ```bash
   helm -n monitoring upgrade --reuse-values loki-stack grafana/loki-stack -f /tmp/loki-fix-values.yaml --dry-run
   ```

3. **Apply the fix:**
   ```bash
   helm -n monitoring upgrade --reuse-values loki-stack grafana/loki-stack -f /tmp/loki-fix-values.yaml
   ```

4. **Verify the fix:**
   ```bash
   kubectl -n monitoring get pods | grep loki
   kubectl -n monitoring logs loki-stack-0 --tail=50
   helm -n monitoring status loki-stack
   ```

## Automated Fix Tool

For automated diagnosis and fix recommendations, use:

```bash
# Safe mode (diagnostic commands only)
./scripts/fix_k8s_monitoring_pods.sh

# Include destructive commands
./scripts/fix_k8s_monitoring_pods.sh --auto-approve
```

## Prevention

To prevent these issues in future deployments:

### 1. Grafana Permission Prevention

Add proper init containers or security contexts in your Helm values:

```yaml
grafana:
  initContainers:
    - name: init-chown-data
      image: busybox:1.31.1
      command: ['sh', '-c', 'chown -R 472:472 /var/lib/grafana']
      securityContext:
        runAsUser: 0
      volumeMounts:
        - name: storage
          mountPath: /var/lib/grafana
  securityContext:
    runAsUser: 472
    runAsGroup: 472
    fsGroup: 472
```

### 2. Loki Configuration Prevention

Validate Loki configuration before deployment:

```bash
# Check configuration validity
kubectl -n monitoring get secret loki-stack -o jsonpath='{.data.loki\.yaml}' | base64 -d | yq eval '.'
```

Use validated Helm values:

```yaml
loki:
  config:
    table_manager:
      retention_deletes_enabled: true
      retention_period: 168h
      # Do not include max_retries field
```

## Related Tools

- **`scripts/analyze_k8s_monitoring_diagnostics.sh`** - Detailed Grafana/Loki issue analysis
- **`scripts/diagnose_monitoring_permissions.sh`** - Permission-specific diagnostics  
- **`scripts/get_copilot_prompt.sh --show`** - Premium Copilot troubleshooting prompt

## Verification Commands

After applying fixes, verify the monitoring stack is healthy:

```bash
# Check all monitoring pods
kubectl -n monitoring get pods -o wide

# Check pod readiness
kubectl -n monitoring get pods | grep -E "(Running|Ready)"

# Check for any remaining CrashLoopBackOff
kubectl -n monitoring get pods | grep -E "(CrashLoopBackOff|Init:CrashLoopBackOff)"

# Check recent events
kubectl -n monitoring get events --sort-by='.lastTimestamp' | tail -20
```

## Summary

The fixes required are:

1. **Directory Permissions** - Fix ownership on the host node for Grafana data directory
2. **Configuration File** - Remove invalid `max_retries` field from Loki configuration via Helm values

Both fixes target the root causes of your CrashLoopBackOff issues and should restore your monitoring stack to a healthy state.
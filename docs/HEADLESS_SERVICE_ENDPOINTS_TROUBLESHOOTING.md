# Headless Service Endpoints Troubleshooting Guide

**Date:** October 2025  
**Component:** Monitoring Stack (Prometheus, Loki)  
**Issue:** Empty endpoints for headless services causing DNS resolution failures

## Overview

This guide helps diagnose and fix issues where Prometheus and Loki headless services have **empty endpoints**, causing Grafana to fail with DNS resolution errors like:

```
Status: 500. Message: Get "http://loki:3100/...": dial tcp: lookup loki on 10.96.0.10:53: no such host
Status: 500. Message: Get "http://prometheus:9090/...": dial tcp: lookup prometheus on 10.96.0.10:53: no such host
```

## Understanding Headless Services

### What are Headless Services?

Headless services (`ClusterIP: None`) are used with StatefulSets to provide:
- Stable network identity for each pod
- Direct pod-to-pod communication
- DNS records for individual pods

### Key Characteristics

- **No virtual IP**: Service has `clusterIP: None`
- **DNS-based discovery**: DNS resolves to pod IPs directly
- **Requires endpoints**: DNS only works when endpoints (ready pods) exist
- **FQDN required**: Must use full domain name (e.g., `prometheus.monitoring.svc.cluster.local`)

### Why Endpoints Matter

For headless services:
- **Empty endpoints = DNS fails**: No pod IPs to return
- **Not ready pods = empty endpoints**: Only `Ready` pods become endpoints
- **Label mismatch = empty endpoints**: Service selector must match pod labels

## Diagnostic Checklist

Run these commands to identify the root cause:

### 1. Check Pod Status and Location

```bash
kubectl get pods -n monitoring -o wide
```

**Look for:**
- ✅ Pods in `Running` state with `READY 1/1`
- ❌ Pods in `Pending`, `CrashLoopBackOff`, or `ImagePullBackOff`
- ❌ Pods showing `0/1` ready (not passing readiness probe)

### 2. Check StatefulSets/Deployments

```bash
kubectl get statefulset,deploy -n monitoring
```

**Look for:**
- ✅ `READY` column shows `1/1` (all replicas ready)
- ❌ `READY` column shows `0/1` (no replicas ready)
- ❌ StatefulSet missing entirely

### 3. Inspect Service Selectors

```bash
kubectl get svc prometheus -n monitoring -o yaml
kubectl get svc loki -n monitoring -o yaml
```

**Look for** the `spec.selector` section:

```yaml
# Prometheus service selector (correct)
selector:
  app.kubernetes.io/name: prometheus
  app.kubernetes.io/component: monitoring
```

```yaml
# Loki service selector (correct)
selector:
  app.kubernetes.io/name: loki
  app.kubernetes.io/component: logging
```

### 4. Inspect Pod Labels

```bash
kubectl get pods -n monitoring --show-labels
```

Or for specific components:

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o wide --show-labels
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki -o wide --show-labels
```

**Verify:** Pod labels match the service selector exactly.

### 5. Check Endpoints Directly

```bash
kubectl get endpoints -n monitoring prometheus
kubectl get endpoints -n monitoring loki
```

**Expected output when working:**
```
NAME         ENDPOINTS           AGE
prometheus   10.244.0.123:9090   5m
loki         10.244.0.124:3100   5m
```

**Problem output (empty endpoints):**
```
NAME         ENDPOINTS   AGE
prometheus   <none>      5m
loki         <none>      5m
```

### 6. Describe Service and Pods

```bash
kubectl describe svc prometheus -n monitoring
kubectl describe svc loki -n monitoring
```

```bash
# Get pod names first
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# Describe specific pod
kubectl describe pod prometheus-0 -n monitoring
```

### 7. Check Pod Logs

```bash
kubectl logs -n monitoring prometheus-0 --tail=200
kubectl logs -n monitoring loki-0 --tail=200
```

**Common errors to look for:**
- Permission denied on `/prometheus` or `/loki`
- WAL recovery failures
- Init container failures

### 8. Check PVC/PV Status

```bash
kubectl get pvc -n monitoring
kubectl get pv
```

**Look for:**
- ❌ PVCs in `Pending` state (pods can't start)
- ✅ PVCs in `Bound` state
- ❌ PVs missing or misconfigured

## Common Root Causes and Fixes

### A) Service Selector and Pod Labels Don't Match

**Symptom:** Pods exist and are running, but endpoints are empty.

**Diagnosis:**
```bash
# Get service selector
kubectl get svc prometheus -n monitoring -o jsonpath='{.spec.selector}'

# Get pod labels
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.labels}'
```

**Fix 1: Update service selector** (quick fix):

```bash
# Example: Update Prometheus service selector
kubectl patch svc prometheus -n monitoring -p '{"spec":{"selector":{"app.kubernetes.io/name":"prometheus","app.kubernetes.io/component":"monitoring"}}}'
```

**Fix 2: Update StatefulSet labels** (proper long-term fix):

Edit the StatefulSet template to ensure pod labels match:

```bash
kubectl edit statefulset prometheus -n monitoring
```

Update the `template.metadata.labels` section:

```yaml
spec:
  template:
    metadata:
      labels:
        app: prometheus
        app.kubernetes.io/name: prometheus
        app.kubernetes.io/component: monitoring
```

Then restart pods:

```bash
kubectl rollout restart statefulset prometheus -n monitoring
```

### B) Pods Not Running / CrashLoopBackOff

**Symptom:** No prometheus/loki pods, or pods in `CrashLoopBackOff`, init containers failing.

**Diagnosis:**
```bash
kubectl get pods -n monitoring
kubectl describe pod prometheus-0 -n monitoring
kubectl logs prometheus-0 -n monitoring --tail=100
```

**Common causes:**

#### 1. Permission Errors on PersistentVolumes

**Error in logs:**
```
opening storage failed: lock DB directory: open /prometheus/lock: permission denied
```

**Fix:**
```bash
# On the node where PV is hosted (masternode)
# Prometheus runs as UID 65534
ssh root@masternode 'chown -R 65534:65534 /srv/monitoring_data/prometheus'
ssh root@masternode 'chmod -R 755 /srv/monitoring_data/prometheus'

# Loki runs as UID 10001
ssh root@masternode 'chown -R 10001:10001 /srv/monitoring_data/loki'
ssh root@masternode 'chmod -R 755 /srv/monitoring_data/loki'
```

Then recreate pods:
```bash
kubectl delete pod -n monitoring prometheus-0 loki-0
```

#### 2. Image Pull Errors

**Error:** `ImagePullBackOff` or `ErrImagePull`

**Fix:**
- Verify image name and tag in manifest
- Check network connectivity to Docker Hub / Quay.io
- Verify image repository credentials if using private registry

#### 3. Init Container Failures

**Check init container logs:**
```bash
kubectl logs prometheus-0 -n monitoring -c init-chown-data
```

**Fix:** Usually permission-related, apply fixes from #1 above.

### C) PVCs Stuck in Pending → Pods Never Start

**Symptom:** PVCs remain in `Pending` state, pods stuck in `ContainerCreating` or `CrashLoop`.

**Diagnosis:**
```bash
kubectl get pvc -n monitoring
kubectl describe pvc prometheus-storage-prometheus-0 -n monitoring
kubectl get pv
```

**Common causes:**

#### 1. No PersistentVolume Available

**Fix:** Create the required PersistentVolume:

```bash
# Apply the PV manifest
kubectl apply -f manifests/monitoring/prometheus-pv.yaml
kubectl apply -f manifests/monitoring/loki-pv.yaml
```

#### 2. PV/PVC Name Mismatch

StatefulSets create PVCs automatically with the pattern:
```
{volumeClaimTemplate.name}-{statefulset.name}-{ordinal}
```

For example:
- Prometheus: `prometheus-storage-prometheus-0`
- Loki: `loki-data-loki-0`

**Fix:** Ensure PV `claimRef` matches the auto-generated PVC name:

```yaml
# In prometheus-pv.yaml
spec:
  claimRef:
    name: prometheus-storage-prometheus-0  # Must match StatefulSet VCT
    namespace: monitoring
```

#### 3. Directory Doesn't Exist on Node

**Fix:** Create directories on the storage node:

```bash
ssh root@masternode 'mkdir -p /srv/monitoring_data/{prometheus,loki,grafana}'
ssh root@masternode 'chown -R 65534:65534 /srv/monitoring_data/prometheus'
ssh root@masternode 'chown -R 10001:10001 /srv/monitoring_data/loki'
```

#### 4. Node Affinity Mismatch

**Fix:** Ensure PV node affinity matches the node where StatefulSet is scheduled:

```yaml
# In PV manifest
nodeAffinity:
  required:
    nodeSelectorTerms:
    - matchExpressions:
      - key: kubernetes.io/hostname
        operator: In
        values:
        - masternode  # Must match actual node name
```

### D) Grafana Using Wrong DNS Names

**Symptom:** Grafana shows "no such host" errors even when endpoints exist.

**Diagnosis:** Check Grafana datasource configuration:

```bash
kubectl get configmap grafana-datasources -n monitoring -o yaml
```

**Problem:** Using short names:
```yaml
url: http://prometheus:9090
url: http://loki:3100
```

**Fix:** Use FQDNs for headless services:

```yaml
url: http://prometheus.monitoring.svc.cluster.local:9090
url: http://loki.monitoring.svc.cluster.local:3100
```

Update the ConfigMap:
```bash
kubectl edit configmap grafana-datasources -n monitoring
```

Then restart Grafana:
```bash
kubectl rollout restart deployment grafana -n monitoring
```

## Automated Diagnostic Script

Run the automated diagnostic script:

```bash
./tests/test-headless-service-endpoints.sh
```

This script checks all the items in this guide and provides specific recommendations.

## Quick Temporary Fix

If you need Grafana dashboards working immediately while troubleshooting:

**Use NodePort services instead:**

```yaml
# In Grafana datasources ConfigMap
datasources:
- name: Prometheus
  url: http://192.168.4.63:30090  # prometheus-external NodePort
- name: Loki
  url: http://192.168.4.63:31100  # loki-external NodePort
```

This bypasses cluster DNS and headless services entirely.

## Verification Steps

After applying fixes, verify everything works:

### 1. Check Endpoints Are Populated

```bash
kubectl get endpoints -n monitoring prometheus loki
```

**Expected:**
```
NAME         ENDPOINTS           AGE
prometheus   10.244.0.123:9090   10m
loki         10.244.0.124:3100   10m
```

### 2. Test DNS Resolution

```bash
# From within a pod in the cluster
kubectl run -it --rm dns-test --image=busybox --restart=Never -n monitoring -- \
  nslookup prometheus.monitoring.svc.cluster.local
```

**Expected:** Should return pod IP addresses.

### 3. Test HTTP Connectivity

```bash
# Access Prometheus via NodePort
curl -s http://192.168.4.63:30090/-/healthy
# Expected: Healthy

# Access Loki via NodePort
curl -s http://192.168.4.63:31100/ready
# Expected: ready
```

### 4. Check Grafana Dashboards

1. Open Grafana: `http://192.168.4.63:30300`
2. Navigate to any dashboard
3. **Expected:** No DNS errors, data loads correctly

## Prevention Best Practices

### 1. Always Use FQDNs for Headless Services

```yaml
# Good
url: http://prometheus.monitoring.svc.cluster.local:9090

# Bad (will fail for headless services)
url: http://prometheus:9090
```

### 2. Verify Labels Match Selectors

When creating StatefulSets, ensure:
- `spec.selector.matchLabels` matches `spec.template.metadata.labels`
- Service `spec.selector` matches pod labels
- All required label keys are present

### 3. Include Readiness Probes

Pods must pass readiness probes to become endpoints:

```yaml
readinessProbe:
  httpGet:
    path: /-/ready
    port: 9090
  initialDelaySeconds: 30
  periodSeconds: 10
```

### 4. Use Startup Probes for Slow-Starting Apps

Stateful apps like Prometheus and Loki need time to recover WAL:

```yaml
startupProbe:
  httpGet:
    path: /-/ready
    port: 9090
  failureThreshold: 60  # 10 minutes
  periodSeconds: 10
```

### 5. Pre-create PVs with Correct Ownership

Before deploying StatefulSets:

```bash
# Create directories
ssh root@masternode 'mkdir -p /srv/monitoring_data/{prometheus,loki}'

# Set ownership
ssh root@masternode 'chown 65534:65534 /srv/monitoring_data/prometheus'
ssh root@masternode 'chown 10001:10001 /srv/monitoring_data/loki'

# Apply PV manifests
kubectl apply -f manifests/monitoring/prometheus-pv.yaml
kubectl apply -f manifests/monitoring/loki-pv.yaml
```

## Related Documentation

- [Deployment Fixes - Part 2](DEPLOYMENT_FIXES_OCT2025_PART2.md) - Original DNS fix documentation
- [PVC Fix Guide](PVC_FIX_OCT2025.md) - PersistentVolume troubleshooting
- [Monitoring Quick Reference](MONITORING_QUICK_REFERENCE.md) - Common monitoring commands
- [Troubleshooting Guide](TROUBLESHOOTING_GUIDE.md) - General troubleshooting

## Summary

**Empty endpoints for headless services are usually caused by:**

1. **Pods not ready** → Fix permission errors, PVC issues, crashes
2. **Label mismatch** → Ensure service selector matches pod labels exactly
3. **PVCs pending** → Create PVs, fix node affinity, create directories
4. **Wrong DNS names** → Use FQDNs for headless services

**Quick diagnostic:** Run `./tests/test-headless-service-endpoints.sh`

**Remember:** Headless services require:
- Ready pods with matching labels
- FQDN usage (not short names)
- Functional PVC/PV bindings

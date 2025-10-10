# Quick Reference: Headless Service Empty Endpoints

**Problem:** Prometheus and Loki headless services have empty endpoints → DNS fails → Grafana can't connect

**Quick diagnostic:** `./tests/test-headless-service-endpoints.sh`

---

## Diagnostic Commands (Ordered)

Run these in order to identify the issue:

### 1. Check Pod Status

```bash
kubectl get pods -n monitoring -o wide
```

**Look for:** Running pods with READY 1/1 status

### 2. Check StatefulSets/Deployments

```bash
kubectl get statefulset,deploy -n monitoring
```

**Look for:** READY column showing 1/1 (all replicas ready)

### 3. Check Service Configuration

```bash
kubectl get svc prometheus loki -n monitoring -o yaml
```

**Look for:** `spec.selector` - note the label keys and values

### 4. Check Pod Labels

```bash
kubectl get pods -n monitoring --show-labels
```

**Verify:** Pod labels match service selector exactly

### 5. Check PVC Status

```bash
kubectl get pvc -n monitoring
```

**Look for:** All PVCs in Bound status (not Pending)

### 6. Check Endpoints

```bash
kubectl get endpoints -n monitoring prometheus loki
```

**Problem if:** ENDPOINTS column shows `<none>`

### 7. Describe Service

```bash
kubectl describe svc prometheus -n monitoring
kubectl describe svc loki -n monitoring
```

**Look for:** Endpoints section at bottom

### 8. Describe Pod (if present)

```bash
kubectl describe pod prometheus-0 -n monitoring
kubectl describe pod loki-0 -n monitoring
```

**Look for:** Events showing errors

---

## Common Root Causes

### A) Label Mismatch (Pods exist, endpoints empty)

**Quick check:**
```bash
# Get service selector
kubectl get svc prometheus -n monitoring -o jsonpath='{.spec.selector}'

# Get pod labels
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.labels}'
```

**Fix (patch service):**
```bash
kubectl patch svc prometheus -n monitoring -p '{"spec":{"selector":{"app.kubernetes.io/name":"prometheus","app.kubernetes.io/component":"monitoring"}}}'

kubectl patch svc loki -n monitoring -p '{"spec":{"selector":{"app.kubernetes.io/name":"loki","app.kubernetes.io/component":"logging"}}}'
```

**OR Fix (update StatefulSet labels):**
```bash
kubectl edit statefulset prometheus -n monitoring
# Update template.metadata.labels to match service selector

kubectl rollout restart statefulset prometheus -n monitoring
```

### B) Pods Crashed / Not Running

**Check status:**
```bash
kubectl get pods -n monitoring
```

**Common: Permission errors**

Check logs:
```bash
kubectl logs prometheus-0 -n monitoring --tail=100
kubectl logs loki-0 -n monitoring --tail=100
```

Look for: `permission denied` on `/prometheus` or `/loki`

**Fix:**
```bash
# On masternode (where PVs are located)
ssh root@masternode 'chown -R 65534:65534 /srv/monitoring_data/prometheus'
ssh root@masternode 'chown -R 10001:10001 /srv/monitoring_data/loki'
ssh root@masternode 'chmod -R 755 /srv/monitoring_data/{prometheus,loki}'

# Recreate pods
kubectl delete pod prometheus-0 loki-0 -n monitoring
```

### C) PVCs Pending (Pods can't start)

**Check:**
```bash
kubectl get pvc -n monitoring
kubectl get pv
```

**Fix: Create missing PVs**
```bash
kubectl apply -f manifests/monitoring/prometheus-pv.yaml
kubectl apply -f manifests/monitoring/loki-pv.yaml
```

**Fix: Create directories on node**
```bash
ssh root@masternode 'mkdir -p /srv/monitoring_data/{prometheus,loki}'
ssh root@masternode 'chown 65534:65534 /srv/monitoring_data/prometheus'
ssh root@masternode 'chown 10001:10001 /srv/monitoring_data/loki'
```

### D) Grafana DNS Error (Endpoints exist but wrong URL)

**Symptom:** Endpoints are populated but Grafana shows "no such host"

**Check datasources:**
```bash
kubectl get configmap grafana-datasources -n monitoring -o yaml | grep url:
```

**Fix: Use FQDNs**
```bash
kubectl edit configmap grafana-datasources -n monitoring
```

Change:
```yaml
# Before
url: http://prometheus:9090
url: http://loki:3100

# After
url: http://prometheus.monitoring.svc.cluster.local:9090
url: http://loki.monitoring.svc.cluster.local:3100
```

Restart Grafana:
```bash
kubectl rollout restart deployment grafana -n monitoring
```

---

## Temporary Quick Fix

**Use NodePort services** (bypasses DNS):

```yaml
# In Grafana datasources
- name: Prometheus
  url: http://192.168.4.63:30090  # prometheus-external NodePort
- name: Loki
  url: http://192.168.4.63:31100  # loki-external NodePort
```

---

## Verification After Fix

```bash
# 1. Endpoints should have IPs
kubectl get endpoints prometheus loki -n monitoring

# 2. Pods should be Running and Ready
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

# 3. Health checks should pass
curl -s http://192.168.4.63:30090/-/healthy  # Should return: Healthy
curl -s http://192.168.4.63:31100/ready      # Should return: ready

# 4. Grafana should work
# Open http://192.168.4.63:30300 and check dashboards load
```

---

## Decision Tree

```
Empty endpoints?
├─ Yes
│  ├─ Pods exist?
│  │  ├─ Yes, Running
│  │  │  ├─ Ready (1/1)?
│  │  │  │  ├─ Yes → Check label mismatch (A)
│  │  │  │  └─ No → Check readiness probe logs
│  │  │  └─ Check pod labels match service selector
│  │  └─ No / CrashLoop
│  │     ├─ Check logs for permission errors (B)
│  │     ├─ Check PVC status (C)
│  │     └─ Check init containers
│  └─ Check if StatefulSet exists
│
└─ No (endpoints exist)
   └─ Grafana DNS error?
      └─ Use FQDNs, not short names (D)
```

---

## Key Concepts

**Headless Service:** `ClusterIP: None` - No virtual IP, DNS resolves to pod IPs

**Empty Endpoints Means:**
1. No pods with matching labels
2. Pods exist but not Ready
3. Pods don't exist (StatefulSet scaled to 0 or crashed)

**DNS Resolution Requires:**
1. Headless service with endpoints
2. FQDN usage: `service.namespace.svc.cluster.local`
3. Pods must be Ready (passing readiness probe)

---

**Full guide:** `docs/HEADLESS_SERVICE_ENDPOINTS_TROUBLESHOOTING.md`

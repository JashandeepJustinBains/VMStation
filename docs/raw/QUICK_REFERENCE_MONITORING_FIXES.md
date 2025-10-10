# Quick Reference: Monitoring Stack Fixes

## TL;DR - Apply All Fixes

```bash
# Option 1: Run automated script (recommended)
cd /home/runner/work/VMStation/VMStation
sudo ./scripts/apply-monitoring-fixes.sh

# Option 2: Manual application (step-by-step below)
```

---

## Manual Fix Application

### Fix 1: Blackbox Exporter (Config Error)

```bash
# Apply fixed config
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/prometheus.yaml

# Restart deployment
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/blackbox-exporter -n monitoring

# Verify
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring wait \
  --for=condition=available deployment/blackbox-exporter --timeout=300s

kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring logs deployment/blackbox-exporter --tail=50

# Test endpoint
curl -I http://192.168.4.63:9115/metrics
```

**Expected**: HTTP 200 OK, logs show "Server is ready to receive web requests"

---

### Fix 2: Loki (Schema Error)

```bash
# Apply fixed config
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/loki.yaml

# Restart deployment
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/loki -n monitoring

# Verify
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring wait \
  --for=condition=available deployment/loki --timeout=300s

kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring logs deployment/loki --tail=50

# Test endpoint
curl http://192.168.4.63:31100/ready
```

**Expected**: Response "ready", logs show "Loki started"

---

### Fix 3: Jellyfin (Scheduling)

```bash
# Ensure all nodes are schedulable
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --no-headers | \
  awk '{print $1}' | \
  xargs -n1 kubectl --kubeconfig=/etc/kubernetes/admin.conf uncordon

# Check node status
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes

# Verify Jellyfin scheduling
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n jellyfin get pods -o wide

# If still pending, check events
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n jellyfin describe pod jellyfin

# Wait for ready
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n jellyfin wait \
  --for=condition=ready pod/jellyfin --timeout=600s
```

**Expected**: Jellyfin pod Running on storagenodet3500

---

## Verification Checklist

```bash
# 1. All pods running
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods
# Expected: All pods Running, 0 restarts

# 2. Endpoints healthy
curl -I http://192.168.4.63:9115/metrics  # Blackbox (200 OK)
curl http://192.168.4.63:31100/ready      # Loki ("ready")
curl -I http://192.168.4.63:30300         # Grafana (200 OK)
curl -I http://192.168.4.63:30090         # Prometheus (200 OK)

# 3. Jellyfin accessible
curl -I http://192.168.4.61:30096/health  # Jellyfin (200 OK)

# 4. No events errors
kubectl --kubeconfig=/etc/kubernetes/admin.conf get events -n monitoring --sort-by='.lastTimestamp' | tail -20
```

---

## Rollback (If Needed)

```bash
# Revert to previous configs
cd /home/runner/work/VMStation/VMStation
git checkout HEAD~3 -- manifests/monitoring/prometheus.yaml
git checkout HEAD~3 -- manifests/monitoring/loki.yaml
git checkout HEAD~3 -- ansible/playbooks/deploy-cluster.yaml

# Re-apply old configs
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/prometheus.yaml
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/loki.yaml

# Restart deployments
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/blackbox-exporter -n monitoring
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/loki -n monitoring
```

---

## Troubleshooting

### Blackbox still crashing?

```bash
# Check config syntax
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get configmap blackbox-exporter-config -o yaml

# Verify timeout is at module level (not nested in dns:)
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get configmap blackbox-exporter-config -o jsonpath='{.data.blackbox\.yml}' | grep -A 5 dns
```

### Loki still crashing?

```bash
# Check schema config
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get configmap loki-config -o yaml | grep -A 10 schema_config

# Verify period is 24h (not 168h)
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get configmap loki-config -o jsonpath='{.data.local-config\.yaml}' | grep period
```

### Jellyfin still pending?

```bash
# Check node schedulability
kubectl --kubeconfig=/etc/kubernetes/admin.conf describe node storagenodet3500 | grep -A 5 Taints

# Check if node is cordoned
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
# Should NOT show "SchedulingDisabled"

# Force uncordon if needed
kubectl --kubeconfig=/etc/kubernetes/admin.conf uncordon storagenodet3500
```

---

## Key File Changes Summary

| File | Change | Lines |
|------|--------|-------|
| `manifests/monitoring/prometheus.yaml` | Moved `timeout` field to module level | 517-532 |
| `manifests/monitoring/loki.yaml` | Changed `period: 168h` to `period: 24h` | 49 |
| `ansible/playbooks/deploy-cluster.yaml` | Added node uncordon task | After 422 |
| `ansible/playbooks/deploy-cluster.yaml` | Fixed WoL SSH user | 751 |

---

## Documentation

- **Full Diagnostics**: [docs/BLACKBOX_EXPORTER_DIAGNOSTICS.md](../docs/BLACKBOX_EXPORTER_DIAGNOSTICS.md)
- **Fix Summary**: [docs/MONITORING_STACK_FIXES_OCT2025.md](../docs/MONITORING_STACK_FIXES_OCT2025.md)
- **Architecture**: [architecture.md](../architecture.md)

---

## Contact

For issues or questions:
1. Check logs: `kubectl -n monitoring logs deployment/<pod-name>`
2. Review events: `kubectl get events -n monitoring --sort-by='.lastTimestamp'`
3. Consult documentation in `/docs` directory

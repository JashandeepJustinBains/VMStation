# Loki ConfigMap Drift Prevention - Quick Start

## Problem
Loki pods crash with: `failed parsing config: field wal_directory not found in type storage.Config`

## Immediate Fix

### Step 1: Run the fix playbook
```bash
cd /home/runner/work/VMStation/VMStation
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/fix-loki-config.yaml
```

This will:
- ✅ Reapply correct ConfigMap from repository
- ✅ Set proper ownership on `/srv/monitoring_data/loki` (UID 10001)
- ✅ Restart Loki deployment
- ✅ Verify Loki becomes ready

### Step 2: Verify Loki is running
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring -l app=loki
kubectl --kubeconfig=/etc/kubernetes/admin.conf logs -n monitoring -l app=loki --tail=20
```

Expected: Pod status `Running`, logs show no config errors.

## Prevention

### Check for drift regularly
```bash
./tests/test-loki-config-drift.sh
```

This detects:
- Invalid fields like `wal_directory` in ConfigMap
- Mismatches between repository and cluster config
- Invalid schema period (must be 24h for boltdb-shipper)

### Include in CI/CD
Add to your validation pipeline:
```bash
./tests/test-complete-validation.sh
```

This runs all monitoring tests including Loki config drift detection.

## Common Issues

### Issue: "field wal_directory not found"
**Cause**: In-cluster ConfigMap has invalid `wal_directory` field  
**Fix**: Run `ansible-playbook ansible/playbooks/fix-loki-config.yaml`

### Issue: "period: 168h" causes boltdb-shipper errors
**Cause**: Schema config must use 24h period  
**Fix**: Repository already has correct config, run fix playbook to sync

### Issue: Permission denied writing to /tmp/loki
**Cause**: PVC backing directory has wrong ownership  
**Fix**: Fix playbook handles this automatically (sets UID 10001)

## What's in the Repository (Correct Config)

The `manifests/monitoring/loki.yaml` ConfigMap is the **source of truth**:

```yaml
storage_config:
  boltdb_shipper:
    active_index_directory: /tmp/loki/index
    cache_location: /tmp/loki/index_cache
    shared_store: filesystem
  filesystem:
    directory: /tmp/loki/chunks
```

**Note**: No `wal_directory` field (this is invalid for Loki 2.9.2)

```yaml
schema_config:
  configs:
  - from: 2020-10-24
    store: boltdb-shipper
    object_store: filesystem
    schema: v11
    index:
      prefix: index_
      period: 24h  # MUST be 24h
```

## Workflow

```
┌─────────────────────────────────────┐
│ Edit manifests/monitoring/loki.yaml │
│ (repository)                        │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ Run fix playbook                    │
│ ansible-playbook fix-loki-config    │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ ConfigMap synced to cluster         │
│ Loki deployment restarted           │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│ Run drift test to verify            │
│ ./tests/test-loki-config-drift.sh   │
└─────────────────────────────────────┘
```

## Advanced: Manual Sync (Alternative)

If you prefer manual steps:

```bash
# 1. Apply Loki manifest
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/loki.yaml

# 2. Set ownership on host
ssh root@192.168.4.63 'chown -R 10001:10001 /srv/monitoring_data/loki'

# 3. Restart deployment
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/loki -n monitoring

# 4. Wait for ready
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout status deployment/loki -n monitoring --timeout=180s
```

## Documentation

- **Full Guide**: [docs/LOKI_CONFIG_DRIFT_PREVENTION.md](../docs/LOKI_CONFIG_DRIFT_PREVENTION.md)
- **Playbook**: [ansible/playbooks/fix-loki-config.yaml](../ansible/playbooks/fix-loki-config.yaml)
- **Test**: [tests/test-loki-config-drift.sh](../tests/test-loki-config-drift.sh)
- **Troubleshooting**: [troubleshooting.md](../troubleshooting.md#issue-loki-pods-in-crashloopbackoff)

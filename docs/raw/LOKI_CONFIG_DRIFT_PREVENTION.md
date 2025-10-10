# Loki ConfigMap Drift Prevention and Automation

## Problem Overview

Loki pods were experiencing CrashLoopBackOff errors due to configuration drift between the repository and the in-cluster ConfigMap. The specific issue was:

- **Symptom**: Multiple Loki pods stuck in CrashLoopBackOff immediately after starting
- **Error**: `failed parsing config: /etc/loki/local-config.yaml: yaml: unmarshal errors: line 40: field wal_directory not found in type storage.Config`
- **Root Cause**: The in-cluster ConfigMap `monitoring/loki-config` contained an invalid key `wal_directory` that Loki 2.9.2 doesn't recognize
- **Secondary Issue**: WAL directory permissions (resolved by ensuring proper ownership of `/srv/monitoring_data/loki`)

## Solution Implemented

### 1. Ansible Playbook for Loki Maintenance

Created `ansible/playbooks/fix-loki-config.yaml` to provide idempotent automation for:

- **ConfigMap Sync**: Reapplies `manifests/monitoring/loki.yaml` from the repository to ensure the ConfigMap matches the source of truth
- **Permission Fix**: Ensures `/srv/monitoring_data/loki` is owned by UID 10001 (Loki runtime user)
- **Deployment Restart**: Gracefully restarts the Loki deployment to pick up configuration changes
- **Health Validation**: Verifies Loki becomes ready after the restart

**Usage**:
```bash
ansible-playbook ansible/playbooks/fix-loki-config.yaml
```

This playbook is safe to run repeatedly (idempotent) and should be used whenever:
- Loki ConfigMap drift is detected
- Loki pods are in CrashLoopBackOff due to config errors
- After manual changes to the repository ConfigMap
- As part of routine cluster maintenance

### 2. Config Drift Detection Test

Created `tests/test-loki-config-drift.sh` to validate:

- Repository manifest exists and is parseable
- ConfigMap can be extracted from the repository file
- Repository config does NOT contain invalid fields like `wal_directory`
- In-cluster ConfigMap matches the repository version (when cluster is accessible)
- Loki schema config uses `period: 24h` (required for boltdb-shipper)

**Usage**:
```bash
./tests/test-loki-config-drift.sh
```

This test is integrated into the complete validation suite:
```bash
./tests/test-complete-validation.sh
```

## Valid Loki Configuration

The repository ConfigMap (`manifests/monitoring/loki.yaml`) contains the **correct** configuration:

### Storage Config (Valid for Loki 2.9.2)

```yaml
storage_config:
  boltdb_shipper:
    active_index_directory: /tmp/loki/index
    cache_location: /tmp/loki/index_cache
    shared_store: filesystem
  filesystem:
    directory: /tmp/loki/chunks
```

**Important**: The `storage_config` section does NOT contain `wal_directory` - this field is invalid for Loki 2.9.2.

### Schema Config (Required for boltdb-shipper)

```yaml
schema_config:
  configs:
  - from: 2020-10-24
    store: boltdb-shipper
    object_store: filesystem
    schema: v11
    index:
      prefix: index_
      period: 24h  # MUST be 24h for boltdb-shipper
```

## Preventing Future Drift

### Best Practices

1. **Always apply from repository**: Use `kubectl apply -f manifests/monitoring/loki.yaml` rather than editing the ConfigMap directly
2. **Run drift detection**: Include `test-loki-config-drift.sh` in your CI/CD pipeline
3. **Use the fix playbook**: Run `ansible/playbooks/fix-loki-config.yaml` after any repository updates
4. **Version control**: Keep all ConfigMap changes in git, never apply ad-hoc changes to the cluster

### Automated Maintenance Schedule

Add to your maintenance runbook:

```bash
# Weekly: Validate configuration matches repository
./tests/test-loki-config-drift.sh

# As needed: Sync configuration and restart Loki
ansible-playbook ansible/playbooks/fix-loki-config.yaml
```

### Integration with Deployment

The main deployment playbook (`ansible/playbooks/deploy-cluster.yaml`) already:
- Creates `/srv/monitoring_data/loki` with proper ownership (UID 10001)
- Applies Loki manifest from repository
- Waits for Loki to become ready

For existing deployments, run the fix playbook to ensure consistency.

## Troubleshooting

### Loki Pods in CrashLoopBackOff

**Symptoms**:
```bash
kubectl get pods -n monitoring | grep loki
# loki-xxxxx  0/1  CrashLoopBackOff  5  3m
```

**Check logs**:
```bash
kubectl logs -n monitoring -l app=loki --tail=50
```

If you see `field wal_directory not found` or similar config parse errors:

1. Run the fix playbook:
   ```bash
   ansible-playbook ansible/playbooks/fix-loki-config.yaml
   ```

2. Verify Loki becomes ready:
   ```bash
   kubectl get pods -n monitoring -l app=loki
   kubectl logs -n monitoring -l app=loki --tail=20
   ```

### Permission Denied Errors

If Loki logs show permission denied for `/tmp/loki`:

1. The fix playbook handles this, but you can also manually fix on the host:
   ```bash
   ssh root@masternode
   chown -R 10001:10001 /srv/monitoring_data/loki
   chmod -R 755 /srv/monitoring_data/loki
   ```

2. Restart the Loki pod:
   ```bash
   kubectl rollout restart deployment/loki -n monitoring
   ```

### ConfigMap Drift Detected

If `test-loki-config-drift.sh` reports drift:

1. Review what changed:
   ```bash
   kubectl get configmap loki-config -n monitoring -o yaml | less
   ```

2. If the in-cluster config is incorrect, run the fix playbook:
   ```bash
   ansible-playbook ansible/playbooks/fix-loki-config.yaml
   ```

3. If the repository needs updating (rare - validate first):
   ```bash
   # Extract current cluster config
   kubectl get configmap loki-config -n monitoring -o yaml > /tmp/loki-config.yaml
   
   # Review and manually update manifests/monitoring/loki.yaml if needed
   # Then commit to git and reapply
   ```

## Architecture Notes

### Init Container

The Loki deployment includes an init container that:
- Creates the WAL directory at `/tmp/loki/wal`
- Sets ownership to UID 10001
- Creates a symlink from `/wal` to `/tmp/loki/wal` (for compatibility)

This runs before the main Loki container starts, ensuring directories exist with correct permissions.

### Volume Mounts

The Loki container mounts:
- `/etc/loki` from the `loki-config` ConfigMap (read-only)
- `/tmp/loki` from the `loki-storage` PVC (read-write)

The PVC is backed by hostPath `/srv/monitoring_data/loki` on the control plane node.

## References

- [Loki 2.9.2 Configuration Reference](https://grafana.com/docs/loki/v2.9.x/configuration/)
- [boltdb-shipper Storage](https://grafana.com/docs/loki/v2.9.x/operations/storage/boltdb-shipper/)
- Repository: `manifests/monitoring/loki.yaml`
- Fix Playbook: `ansible/playbooks/fix-loki-config.yaml`
- Drift Test: `tests/test-loki-config-drift.sh`

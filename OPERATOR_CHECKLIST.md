# VMStation Manifest Reorganization - Operator Checklist

## Quick Summary

**Status:** Ready for operator review and approval
**Risk Level:** LOW
**Files Modified:** 0 existing files (only additions)
**Files Added:** 90+ files (staging, docs, config)

## Migration Deliverables

✅ `migration-plan.json` - Detailed analysis of all 10 manifests
✅ `migration-proposal.patch` - Infrastructure additions (no logic changes)
✅ `migration-risk-report.md` - Risk assessment and manual verification steps
✅ `manifests/staging-debian-bookworm/` - 10 manifests ready for deployment
✅ `manifests/staging-rhel10/` - Empty, reserved for future use
✅ `docs/raw/` - 49 documentation files consolidated
✅ `docs/INDEX.md` - Documentation index with merge suggestions
✅ `ansible/group_vars/all/monitoring_manifests.yml` - Path variable configuration

## Step-by-Step Review Process

### Step 1: Review Migration Plan

```bash
# View the migration plan
cat migration-plan.json | python3 -m json.tool | less

# Quick summary
cat migration-plan.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f'Total manifests: {len(data)}')
for d in data:
    print(f'{d[\"source_path\"].split(\"/\")[-1]:30} -> {d[\"destination\"]:20} ({d[\"reason\"]})')
"
```

**Expected output:**
- 10 manifests analyzed
- All target `debian-bookworm`
- Clear reasons for each classification

### Step 2: Inspect Staging Directories

```bash
# List staged manifests
ls -lh manifests/staging-debian-bookworm/
ls -lh manifests/staging-rhel10/

# Compare staging with source
diff -r manifests/monitoring/ manifests/staging-debian-bookworm/

# Should show no differences (files are exact copies)
```

**Expected result:** Staging files are identical to source files

### Step 3: Review Risk Assessment

```bash
# Read the risk report
cat migration-risk-report.md | less
```

**Key points to verify:**
- Overall risk level: LOW
- No ambiguous classifications
- All PVs have clear node affinity
- DaemonSets properly configured

### Step 4: Review Documentation Consolidation

```bash
# Check documentation index
cat docs/INDEX.md | less

# Verify all docs copied
ls -1 docs/raw/ | wc -l  # Should show 49 files

# Review merge suggestions in INDEX.md
grep -A 20 "Suggested Documentation Merges" docs/INDEX.md
```

### Step 5: Run Client-Side Validation

```bash
# Validate YAML syntax of all staging files
for f in manifests/staging-debian-bookworm/*.yaml; do
  echo "Validating $f..."
  python3 -c "import yaml; yaml.safe_load_all(open('$f'))" && echo "✅ OK" || echo "❌ FAIL"
done

# Run yamllint if available
yamllint -d relaxed manifests/staging-debian-bookworm/*.yaml

# Client-side kubectl dry-run (no cluster needed)
for f in manifests/staging-debian-bookworm/*.yaml; do
  echo "Testing $f..."
  kubectl apply --dry-run=client -f "$f"
done
```

**Expected result:** All files should pass YAML parsing and client-side validation

### Step 6: Cluster-Side Validation (If Cluster Available)

⚠️ **Important:** Only run these if you have cluster credentials and want to validate against a running cluster

```bash
# Verify cluster is accessible
kubectl cluster-info
kubectl get nodes

# Check current PV/PVC status
kubectl get pv
kubectl get pvc -A

# Server-side dry-run (does NOT apply changes)
for f in manifests/staging-debian-bookworm/*.yaml; do
  echo "Server validation: $f..."
  kubectl apply --dry-run=server -f "$f"
done
```

**Expected result:** All manifests should pass server-side validation

### Step 7: Verify Directory Permissions

Ensure storage directories exist with correct permissions:

```bash
# On masternode (192.168.4.63)
ls -ld /srv/monitoring_data/
ls -ld /srv/monitoring_data/prometheus  # Should be 65534:65534
ls -ld /srv/monitoring_data/loki        # Should be 10001:10001
ls -ld /srv/monitoring_data/grafana     # Should be 472:472

# If directories don't exist or have wrong permissions, fix them:
# sudo mkdir -p /srv/monitoring_data/{prometheus,loki,grafana}
# sudo chown 65534:65534 /srv/monitoring_data/prometheus
# sudo chown 10001:10001 /srv/monitoring_data/loki
# sudo chown 472:472 /srv/monitoring_data/grafana
# sudo chmod 755 /srv/monitoring_data/*
```

## Migration Execution Options

### Option A: Move Files Using Git (Recommended)

This preserves file history:

```bash
# Create final destination directories
mkdir -p manifests/debian-bookworm
mkdir -p manifests/rhel10

# Move files using git mv (preserves history)
for f in manifests/staging-debian-bookworm/*.yaml; do
  filename=$(basename "$f")
  git mv "$f" "manifests/debian-bookworm/$filename"
done

# Move READMEs
git mv manifests/staging-debian-bookworm/README.md manifests/debian-bookworm/
git mv manifests/staging-rhel10/README.md manifests/rhel10/

# Optional: Remove original monitoring files (after confirming everything works)
# git rm manifests/monitoring/*.yaml

# Commit
git add manifests/debian-bookworm/ manifests/rhel10/
git commit -m "Reorganize monitoring manifests into platform-specific directories

- Move 10 manifests to debian-bookworm (control-plane)
- Create rhel10 directory for future use
- Add READMEs explaining platform targeting
- Based on migration-plan.json analysis"

# Push to repository
git push origin <your-branch>
```

### Option B: Copy Files (Simpler, Loses History)

```bash
# Create final directories
mkdir -p manifests/debian-bookworm
mkdir -p manifests/rhel10

# Copy staging files
cp -r manifests/staging-debian-bookworm/* manifests/debian-bookworm/
cp manifests/staging-rhel10/README.md manifests/rhel10/

# Add to git
git add manifests/debian-bookworm/ manifests/rhel10/
git commit -m "Add platform-specific manifest directories"
git push origin <your-branch>
```

### Option C: Deploy from Staging (Test First)

Test deployment without moving files:

```bash
# Deploy directly from staging
kubectl apply -f manifests/staging-debian-bookworm/prometheus-pv.yaml
kubectl apply -f manifests/staging-debian-bookworm/grafana-pv.yaml
kubectl apply -f manifests/staging-debian-bookworm/loki-pv.yaml
kubectl apply -f manifests/staging-debian-bookworm/promtail-pv.yaml

# Wait for PVs to be available
kubectl get pv

# Deploy applications
kubectl apply -f manifests/staging-debian-bookworm/node-exporter.yaml
kubectl apply -f manifests/staging-debian-bookworm/kube-state-metrics.yaml
kubectl apply -f manifests/staging-debian-bookworm/loki.yaml
kubectl apply -f manifests/staging-debian-bookworm/ipmi-exporter.yaml
kubectl apply -f manifests/staging-debian-bookworm/prometheus.yaml
kubectl apply -f manifests/staging-debian-bookworm/grafana.yaml

# Verify deployment
kubectl get pods -n monitoring
kubectl get pvc -n monitoring
```

## Applying the Patch

The migration-proposal.patch file is informational and adds the variable configuration:

```bash
# The patch mainly documents the changes; key file already created:
ls -l ansible/group_vars/all/monitoring_manifests.yml

# If you want to use the variable in playbooks (optional):
# Edit ansible/playbooks/deploy-monitoring-stack.yaml
# Replace hardcoded paths like:
#   /srv/monitoring_data/VMStation/manifests/monitoring/prometheus.yaml
# With:
#   {{ monitoring_manifests_dir }}/prometheus.yaml
```

## Post-Migration Verification

After applying the migration:

```bash
# Verify all pods are running
kubectl get pods -n monitoring -o wide

# Check node placement (should all be on masternode/control-plane)
kubectl get pods -n monitoring -o wide | grep -v NAME | awk '{print $7}'

# Verify PV bindings
kubectl get pv
kubectl get pvc -n monitoring

# Test monitoring access
# Grafana: http://192.168.4.63:30300
# Prometheus: http://192.168.4.63:30900

# Check logs for any issues
kubectl logs -n monitoring -l app=prometheus --tail=50
kubectl logs -n monitoring -l app=loki --tail=50
kubectl logs -n monitoring -l app=grafana --tail=50
```

## Rollback Procedure

If issues occur:

```bash
# Option 1: Redeploy from original manifests
kubectl delete -f manifests/staging-debian-bookworm/
kubectl apply -f manifests/monitoring/

# Option 2: Restore from Git
git checkout manifests/monitoring/
kubectl apply -f manifests/monitoring/

# Option 3: Reset cluster (if operator resets for each deployment anyway)
./deploy.sh reset
./deploy.sh debian
```

## Optional: Update Playbooks to Use Variable

After confirming the migration works, you can optionally update playbooks:

```bash
# Example change in ansible/playbooks/deploy-monitoring-stack.yaml:

# Before:
- name: "Deploy Prometheus"
  command: kubectl apply -f /srv/monitoring_data/VMStation/manifests/monitoring/prometheus.yaml

# After:
- name: "Deploy Prometheus"
  command: kubectl apply -f {{ monitoring_manifests_dir }}/prometheus.yaml
  # Original path: /srv/monitoring_data/VMStation/manifests/monitoring/prometheus.yaml
```

Files with path references (23 total):
- ansible/playbooks/deploy-cluster.yaml (10 refs)
- ansible/playbooks/deploy-monitoring-stack.yaml (6 refs)
- ansible/playbooks/fix-loki-config.yaml (1 ref)
- ansible/playbooks/deploy-syslog-service.yaml (2 refs)
- ansible/playbooks/deploy-ntp-service.yaml (1 ref)
- ansible/playbooks/deploy-kerberos-service.yaml (1 ref)
- scripts/apply-monitoring-fixes.sh (2 refs)

## Final Checklist

Before marking migration complete:

- [ ] Reviewed migration-plan.json
- [ ] Inspected staging directories
- [ ] Read migration-risk-report.md
- [ ] Ran client-side validation (YAML + kubectl --dry-run=client)
- [ ] Ran server-side validation (if cluster available)
- [ ] Verified storage directory permissions
- [ ] Chose migration execution option (A, B, or C)
- [ ] Executed migration
- [ ] Verified pods running correctly
- [ ] Tested monitoring access (Grafana/Prometheus)
- [ ] Checked logs for errors
- [ ] Documented any issues or deviations
- [ ] (Optional) Updated playbooks to use {{ monitoring_manifests_dir }}

## Support Information

If you encounter issues:

1. Check migration-risk-report.md for known considerations
2. Review validation output from Step 5/6 above
3. Check kubectl logs for specific error messages
4. Verify node labels: `kubectl get nodes --show-labels`
5. Confirm PV node affinity matches node labels

## Summary Commands

Quick copy-paste commands for the impatient operator:

```bash
# Full review
cat migration-plan.json | python3 -m json.tool | less
cat migration-risk-report.md | less
ls -lh manifests/staging-debian-bookworm/

# Validate
for f in manifests/staging-debian-bookworm/*.yaml; do
  kubectl apply --dry-run=client -f "$f"
done

# Execute migration (git mv approach)
mkdir -p manifests/{debian-bookworm,rhel10}
for f in manifests/staging-debian-bookworm/*.yaml; do
  git mv "$f" "manifests/debian-bookworm/$(basename $f)"
done
git mv manifests/staging-debian-bookworm/README.md manifests/debian-bookworm/
git mv manifests/staging-rhel10/README.md manifests/rhel10/
git add -A
git commit -m "Reorganize monitoring manifests into platform-specific directories"
git push

# Verify deployment
kubectl get pods -n monitoring -o wide
kubectl get pv,pvc -n monitoring
```

---
**Migration Prepared:** 2025-10-09
**Automation Version:** VMStation Reorganization v1.0
**Repository:** /home/runner/work/VMStation/VMStation

# VMStation Manifest Migration Risk Report

## Executive Summary

This report identifies potential risks and ambiguities in the proposed manifest reorganization from `manifests/monitoring/` into platform-specific directories (`debian-bookworm` and `rhel10`).

**Overall Risk Level:** LOW - All manifests have clear node affinity targeting control-plane nodes

## Findings

### Classification Results

All 10 monitoring manifests were successfully classified and target the **debian-bookworm** (control-plane) destination:

- **Total manifests analyzed:** 10
- **Targeting debian-bookworm:** 10
- **Targeting rhel10:** 0
- **Parse errors:** 0
- **Ambiguous classifications:** 0

### Manifest Classifications

#### PV-Sensitive Manifests (4 files)
These contain PersistentVolumes with clear node affinity to control-plane:

1. **grafana-pv.yaml**
   - Classification: PV-sensitive, hostPath
   - Reason: PV nodeAffinity: node-role.kubernetes.io/control-plane
   - Risk: LOW - Clear affinity defined
   
2. **loki-pv.yaml**
   - Classification: PV-sensitive, hostPath
   - Reason: PV nodeAffinity: node-role.kubernetes.io/control-plane
   - Risk: LOW - Clear affinity defined
   
3. **prometheus-pv.yaml**
   - Classification: PV-sensitive, hostPath
   - Reason: PV nodeAffinity: node-role.kubernetes.io/control-plane
   - Risk: LOW - Clear affinity defined
   
4. **promtail-pv.yaml**
   - Classification: PV-sensitive, hostPath
   - Reason: PV nodeAffinity: node-role.kubernetes.io/control-plane
   - Risk: LOW - Clear affinity defined

#### StatefulSet Manifests (2 files)
These use volumeClaimTemplates and have nodeSelector:

5. **loki.yaml**
   - Classification: volumeClaimTemplates, StatefulSet
   - Reason: template.spec.nodeSelector: control-plane
   - Risk: LOW - Explicit nodeSelector
   
6. **prometheus.yaml**
   - Classification: volumeClaimTemplates, StatefulSet
   - Reason: template.spec.nodeSelector: control-plane
   - Risk: LOW - Explicit nodeSelector

#### DaemonSet Manifests (2 files)
These are intended for cluster-wide deployment:

7. **node-exporter.yaml**
   - Classification: hostPath, DaemonSet
   - Reason: DaemonSet default (cluster-wide)
   - Risk: LOW - Generic DaemonSet with tolerations for control-plane
   - **Note:** This DaemonSet should run on ALL nodes (both debian and RHEL) but starts in debian-bookworm as the primary cluster
   
8. **ipmi-exporter.yaml**
   - Classification: hostPath, DaemonSet
   - Reason: template.spec.nodeSelector: control-plane
   - Risk: LOW - Explicitly targets control-plane

#### Generic/Service Manifests (2 files)

9. **grafana.yaml**
   - Classification: Generic
   - Reason: template.spec.nodeSelector: control-plane
   - Risk: LOW - Clear nodeSelector
   
10. **kube-state-metrics.yaml**
    - Classification: Generic
    - Reason: template.spec.nodeSelector: control-plane
    - Risk: LOW - Clear nodeSelector

## Validation Status

### YAML Parsing
✅ All 10 manifests have valid YAML syntax

### kubectl dry-run
⚠️ Cannot validate without cluster connection (expected)
- All files returned connection errors to http://localhost:8080
- This is expected behavior without active cluster
- **Operator action required:** Run kubectl dry-run validation on target cluster

### yamllint
✅ 8 of 10 manifests pass yamllint with no issues
⚠️ 2 manifests have minor style warnings (loki.yaml, prometheus.yaml)
- These are cosmetic and do not affect functionality
- Warnings are related to line length or indentation style

## Risk Assessment by Category

### HIGH RISK Items
**None identified**

### MEDIUM RISK Items
**None identified**

### LOW RISK Items

1. **DaemonSets and Multi-Platform Deployment**
   - **Issue:** node-exporter.yaml is classified as cluster-wide but placed in debian-bookworm
   - **Impact:** When RHEL10 nodes join, they should also run node-exporter
   - **Mitigation:** The DaemonSet has tolerations to run on all nodes; the manifest location is just for organization
   - **Operator Action:** Verify node-exporter deploys to RHEL10 nodes when they join

2. **Validation Without Live Cluster**
   - **Issue:** Cannot run full kubectl validation without cluster credentials
   - **Impact:** Some manifest errors might only appear at deployment time
   - **Mitigation:** All manifests have valid YAML syntax and structure
   - **Operator Action:** Run `kubectl apply --dry-run=server` on live cluster before migration

## Ambiguous Items Requiring Manual Review

**None identified** - All manifests have clear targeting through nodeSelector or nodeAffinity

## Recommended Manual Verification Steps

Before applying the migration:

1. **Verify PersistentVolume Bindings**
   ```bash
   kubectl get pv
   kubectl get pvc -A
   ```
   Confirm no similarly-named PVs are currently bound (operator confirmed cluster reset)

2. **Validate Manifests Against Live Cluster**
   ```bash
   for f in manifests/staging-debian-bookworm/*.yaml; do
     kubectl apply --dry-run=server -f "$f"
   done
   ```

3. **Check Directory Permissions**
   Verify `/srv/monitoring_data/` subdirectories exist with correct permissions:
   - `/srv/monitoring_data/prometheus` → 65534:65534
   - `/srv/monitoring_data/loki` → 10001:10001
   - `/srv/monitoring_data/grafana` → 472:472

4. **Review DaemonSet Distribution**
   After migration, verify node-exporter runs on all nodes:
   ```bash
   kubectl get pods -n monitoring -o wide | grep node-exporter
   ```

## Migration Path Dependencies

### Files to Update After Migration

The following files reference manifest paths and need updates:

1. **ansible/playbooks/deploy-cluster.yaml** (10 references)
2. **ansible/playbooks/deploy-monitoring-stack.yaml** (6 references)
3. **ansible/playbooks/fix-loki-config.yaml** (1 reference)
4. **scripts/apply-monitoring-fixes.sh** (2 references)
5. **scripts/fix-monitoring-permissions.sh** (3 references)

All path updates are included in the migration-proposal.patch file.

## Conclusion

The migration plan is **LOW RISK** with no critical blockers identified. All manifests have clear platform targeting through nodeSelectors and nodeAffinity. The primary consideration is ensuring proper kubectl validation against a live cluster before final migration.

### Next Steps

1. ✅ Review this risk report
2. ⏳ Review migration-plan.json for detailed per-file analysis
3. ⏳ Inspect staging directories (manifests/staging-debian-bookworm/)
4. ⏳ Review migration-proposal.patch for path updates
5. ⏳ Run manual validation steps listed above
6. ⏳ Apply patch and move files using provided operator commands

---
**Report Generated:** 2025-10-09
**Analyst:** VMStation Reorganization Automation
**Repository:** /home/runner/work/VMStation/VMStation

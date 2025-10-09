# CrashLoopBackOff Fixes - Quick Reference

This document provides a quick overview of the monitoring stack CrashLoopBackOff fixes that have been implemented and verified in this repository.

## Status: ✅ ALL FIXES VERIFIED

All three critical CrashLoopBackOff issues have been **successfully fixed and validated**:

| Issue | Status | Fix Location | Verification |
|-------|--------|--------------|--------------|
| Blackbox Exporter | ✅ Fixed | `manifests/monitoring/prometheus.yaml:528-529` | Test passes |
| Loki Schema | ✅ Fixed | `manifests/monitoring/loki.yaml:49` | Test passes |
| Node Scheduling | ✅ Fixed | `ansible/playbooks/deploy-cluster.yaml:424-428` | Test passes |

## Quick Validation

Run the automated test to verify all fixes:

```bash
bash tests/test-crashloopbackoff-fixes.sh
```

Expected output:
```
✅ ALL CRASHLOOPBACKOFF FIXES VERIFIED

Passed:  7
Warnings: 0
Failed:  0
```

## The Three Fixes Explained

### 1. Blackbox Exporter CrashLoopBackOff ✅

**Problem**: `field timeout not found in type config.plain`

**Fix**: Moved `timeout` from nested prober config to module level

```yaml
# ✅ CORRECT (current)
dns:
  prober: dns
  timeout: 5s        # At module level
  dns:
    query_name: kubernetes.default.svc.cluster.local
```

**File**: `manifests/monitoring/prometheus.yaml` lines 527-532

---

### 2. Loki CrashLoopBackOff ✅

**Problem**: `boltdb-shipper works best with 24h periodic index config`

**Fix**: Changed index period from 168h to 24h

```yaml
# ✅ CORRECT (current)
schema_config:
  configs:
  - from: 2020-10-24
    store: boltdb-shipper
    index:
      period: 24h    # Changed from 168h
```

**File**: `manifests/monitoring/loki.yaml` line 49

---

### 3. Jellyfin Pod Pending ✅

**Problem**: `1 node(s) were unschedulable` - storagenodet3500 was cordoned

**Fix**: Added uncordon task before pod deployments

```yaml
# ✅ CORRECT (current)
- name: "Ensure all nodes are schedulable (uncordon)"
  shell: |
    kubectl get nodes --no-headers | awk '{print $1}' | \
    xargs -n1 kubectl uncordon
```

**File**: `ansible/playbooks/deploy-cluster.yaml` lines 424-428

---

## Documentation

- **[CRASHLOOPBACKOFF_FIXES_VERIFIED.md](CRASHLOOPBACKOFF_FIXES_VERIFIED.md)** - Comprehensive verification report with detailed analysis
- **[tests/test-crashloopbackoff-fixes.sh](tests/test-crashloopbackoff-fixes.sh)** - Automated validation test script
- **[docs/BLACKBOX_EXPORTER_DIAGNOSTICS.md](docs/BLACKBOX_EXPORTER_DIAGNOSTICS.md)** - Detailed diagnostic report
- **[docs/MONITORING_STACK_FIXES_OCT2025.md](docs/MONITORING_STACK_FIXES_OCT2025.md)** - Original fix documentation

## Expected Deployment State

After deployment, all pods should be in `Running` state:

```bash
# Monitoring namespace
kubectl get pods -n monitoring
NAME                                   READY   STATUS
prometheus-xxxxx                       1/1     Running
grafana-xxxxx                          1/1     Running
loki-xxxxx                             1/1     Running    # ✅ Was CrashLoopBackOff
blackbox-exporter-xxxxx                1/1     Running    # ✅ Was CrashLoopBackOff
node-exporter-xxxxx                    1/1     Running
promtail-xxxxx                         1/1     Running

# Jellyfin namespace
kubectl get pods -n jellyfin -o wide
NAME       READY   STATUS    NODE
jellyfin   1/1     Running   storagenodet3500   # ✅ Was Pending
```

## Access URLs

Once deployed, services are accessible at:

- **Prometheus**: http://192.168.4.63:30090
- **Grafana**: http://192.168.4.63:30300 (admin/admin)
- **Loki**: http://192.168.4.63:31100
- **Jellyfin**: http://192.168.4.61:30096

## History

These fixes were originally implemented in PR #382 and have been verified as correctly applied in the current repository state.

**Original Fix Date**: October 8, 2025  
**Verification Date**: October 9, 2025  
**Status**: Production-ready ✅

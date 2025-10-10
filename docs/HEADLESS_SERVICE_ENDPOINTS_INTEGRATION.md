# Headless Service Endpoints Diagnostic - Integration Guide

## Overview

The headless service endpoints diagnostic tools (`test-headless-service-endpoints.sh`) integrate with the existing VMStation monitoring validation suite to provide comprehensive validation of Kubernetes service endpoints for Prometheus and Loki.

## Architecture

### Component Stack

```
┌─────────────────────────────────────────────────┐
│           Grafana Dashboards                    │
│  (Requires working datasource connections)      │
└────────────────┬────────────────────────────────┘
                 │
                 ├─ http://prometheus.monitoring.svc.cluster.local:9090
                 └─ http://loki.monitoring.svc.cluster.local:3100
                 │
┌────────────────▼────────────────────────────────┐
│         Headless Services                       │
│  - prometheus (ClusterIP: None)                 │
│  - loki (ClusterIP: None)                       │
└────────────────┬────────────────────────────────┘
                 │ DNS resolves to:
                 │
┌────────────────▼────────────────────────────────┐
│         Service Endpoints                       │
│  - Pod IPs backing the services                 │
│  - Only includes Ready pods                     │
│  - Must match service selector labels           │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│         StatefulSet Pods                        │
│  - prometheus-0 (app.kubernetes.io/name=...)    │
│  - loki-0 (app.kubernetes.io/name=...)          │
└─────────────────────────────────────────────────┘
```

### Diagnostic Coverage

| Layer | Existing Tests | New Diagnostic |
|-------|---------------|----------------|
| **HTTP Access** | `test-monitoring-access.sh` | - |
| **Dashboard Data** | `test-monitoring-exporters-health.sh` | - |
| **Log Aggregation** | `test-loki-validation.sh` | - |
| **Service Endpoints** | ❌ Not covered | ✅ `test-headless-service-endpoints.sh` |
| **Pod Health** | Partial | ✅ Comprehensive |
| **Label Matching** | ❌ Not covered | ✅ Full validation |
| **PVC/PV Status** | ❌ Not covered | ✅ Checks binding |
| **DNS Resolution** | ❌ Not covered | ✅ In-cluster test |

## Integration Points

### 1. Complete Validation Suite

The diagnostic is integrated into `test-complete-validation.sh`:

```bash
# Phase 2: Monitoring Health Validation
run_test_suite "Headless Service Endpoints" \
  "tests/test-headless-service-endpoints.sh" || true
```

**Position:** After monitoring access tests, before sleep/wake cycle  
**Type:** Non-destructive (read-only checks)

### 2. Standalone Usage

```bash
# Direct execution
./tests/test-headless-service-endpoints.sh

# From repository root
cd /path/to/VMStation
./tests/test-headless-service-endpoints.sh
```

### 3. CI/CD Pipeline Integration

```yaml
# Example GitLab CI
test-monitoring:
  script:
    - ./tests/test-monitoring-config-validation.sh
    - ./tests/test-headless-service-endpoints.sh  # Add this
  only:
    - merge_requests
    - main
```

## Test Flow

```
1. Check Namespace Exists
   └─ monitoring namespace present?
   
2. Check Pod Status
   ├─ Prometheus pods exist?
   ├─ Prometheus pods Ready?
   ├─ Loki pods exist?
   └─ Loki pods Ready?
   
3. Check StatefulSets
   ├─ Prometheus StatefulSet exists?
   ├─ Replicas: Ready/Desired
   ├─ Loki StatefulSet exists?
   └─ Replicas: Ready/Desired
   
4. Check Service Selectors
   ├─ Prometheus service selector
   └─ Loki service selector
   
5. Check Pod Labels
   ├─ Prometheus pod labels match selector?
   └─ Loki pod labels match selector?
   
6. Check Endpoints
   ├─ Prometheus endpoints populated?
   └─ Loki endpoints populated?
   
7. Check PVC Status
   ├─ Any PVCs pending?
   └─ PVCs bound?
   
8. Check Pod Failures
   └─ Any pods in CrashLoopBackOff?
   
9. Verify Headless Configuration
   ├─ Prometheus ClusterIP: None?
   └─ Loki ClusterIP: None?
   
10. Test DNS Resolution
    ├─ Create test pod
    ├─ nslookup prometheus.monitoring.svc.cluster.local
    ├─ nslookup loki.monitoring.svc.cluster.local
    └─ Cleanup test pod
```

## When to Use

### Use this diagnostic when:

✅ Grafana shows "no such host" DNS errors  
✅ Dashboards show "No data" despite Prometheus being accessible via NodePort  
✅ After deploying/updating Prometheus or Loki  
✅ After changing service configurations  
✅ Before troubleshooting DNS issues  
✅ As part of monitoring stack validation  

### Skip this diagnostic when:

❌ No Kubernetes cluster access  
❌ Monitoring namespace doesn't exist  
❌ Running on non-Kubernetes environments  

## Relationship to Other Tests

### Complementary Tests

1. **test-monitoring-access.sh**
   - Tests HTTP accessibility via NodePort
   - Validates anonymous access
   - **Complements:** Checks external access layer
   - **This test checks:** Internal Kubernetes service layer

2. **test-loki-validation.sh**
   - Tests Loki functionality and log ingestion
   - Validates Promtail connectivity
   - **Complements:** Checks log pipeline
   - **This test checks:** Loki service endpoints

3. **test-monitoring-exporters-health.sh**
   - Tests metrics collection
   - Validates exporter health
   - **Complements:** Checks data collection
   - **This test checks:** Service/pod infrastructure

### Diagnostic Workflow

```
Issue: Grafana shows "no such host"
│
├─ Run: test-headless-service-endpoints.sh
│  │
│  ├─ Endpoints empty?
│  │  │
│  │  ├─ Pods not Ready?
│  │  │  └─ Check logs, fix permissions → DEPLOYMENT_FIXES_OCT2025_PART2.md
│  │  │
│  │  ├─ Label mismatch?
│  │  │  └─ Fix service selector or pod labels → This guide
│  │  │
│  │  └─ PVC pending?
│  │     └─ Fix PV configuration → PVC_FIX_OCT2025.md
│  │
│  └─ Endpoints exist but DNS fails?
│     └─ Check Grafana datasource uses FQDN → DEPLOYMENT_FIXES_OCT2025_PART2.md
│
└─ Verify fix:
   ├─ Re-run test-headless-service-endpoints.sh
   ├─ Run test-monitoring-access.sh
   └─ Check Grafana dashboards
```

## Documentation Cross-References

### Primary Documentation

- **HEADLESS_SERVICE_ENDPOINTS_TROUBLESHOOTING.md** - Comprehensive troubleshooting guide
- **HEADLESS_SERVICE_ENDPOINTS_QUICK_REFERENCE.md** - Quick command reference

### Related Fixes

- **DEPLOYMENT_FIXES_OCT2025_PART2.md** - Original DNS resolution fix (FQDN usage)
- **PVC_FIX_OCT2025.md** - PersistentVolume binding issues
- **TROUBLESHOOTING_GUIDE.md** - General troubleshooting

### Test Documentation

- **tests/README.md** - Complete test suite documentation
- **VALIDATION_TEST_GUIDE.md** - Validation test guide

## Exit Codes

The diagnostic script uses standard exit codes:

- **0** - All checks passed or warnings only
- **1** - Critical failures (cannot connect to cluster, namespace missing)

Note: Individual test failures don't cause script exit (uses `|| true` pattern in suite)

## Maintenance

### Adding New Checks

To add a new validation check:

1. Add test section in `test-headless-service-endpoints.sh`
2. Follow existing pattern (echo header, run checks, log results)
3. Update test count in header comment
4. Update this documentation

### Updating for New Services

If adding more headless services (e.g., Alertmanager):

1. Add service checks in test sections 4-6
2. Add pod label checks in test section 5
3. Add endpoint checks in test section 6
4. Update documentation

## Example Output

### Healthy State

```
[6/10] Checking service endpoints...
✓ Prometheus endpoints: 10.244.0.123:9090
✓ Loki endpoints: 10.244.0.124:3100
```

### Empty Endpoints (Problem)

```
[6/10] Checking service endpoints...
✗ Prometheus service has NO endpoints (empty)
ℹ This means pods are not matching the service selector or pods are not ready
✗ Loki service has NO endpoints (empty)
ℹ This means pods are not matching the service selector or pods are not ready
```

### Detailed Diagnosis

```
[5/10] Checking pod labels match service selectors...
ℹ Prometheus pod labels:
  map[app:prometheus app.kubernetes.io/component:monitoring app.kubernetes.io/name:prometheus]
✓ Prometheus pod has correct app.kubernetes.io/name label
✓ Prometheus pod has correct app.kubernetes.io/component label
```

## Summary

The headless service endpoints diagnostic fills a critical gap in the VMStation monitoring validation suite by checking the Kubernetes service/endpoints layer that sits between external HTTP access (tested by other tools) and the actual pod health. It's essential for diagnosing "no such host" DNS errors and ensuring that headless services are properly configured with populated endpoints.

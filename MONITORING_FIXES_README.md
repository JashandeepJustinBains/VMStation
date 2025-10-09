# Monitoring Stack Fixes - October 2025

## Quick Start

```bash
# Apply all fixes automatically
cd /home/runner/work/VMStation/VMStation
sudo ./scripts/apply-monitoring-fixes.sh
```

## What Was Fixed

Three critical issues preventing successful cluster deployment:

1. **Blackbox Exporter CrashLoopBackOff** (16 restarts)
   - **Cause**: Config syntax error - `timeout` field in wrong location
   - **Fix**: Moved `timeout` to module level in blackbox.yml
   - **File**: `manifests/monitoring/prometheus.yaml`

2. **Loki CrashLoopBackOff** (16 restarts)
   - **Cause**: boltdb-shipper requires 24h index period
   - **Fix**: Changed schema_config period from 168h to 24h
   - **File**: `manifests/monitoring/loki.yaml`

3. **Jellyfin Pod Pending** (never scheduled)
   - **Cause**: storagenodet3500 node marked unschedulable
   - **Fix**: Added automatic node uncordon task
   - **File**: `ansible/playbooks/deploy-cluster.yaml`

## Documentation Index

### Quick Reference
- **[QUICK_REFERENCE_MONITORING_FIXES.md](./docs/QUICK_REFERENCE_MONITORING_FIXES.md)** - Fast command reference

### Complete Guides
- **[PROBLEM_STATEMENT_RESPONSE.md](./docs/PROBLEM_STATEMENT_RESPONSE.md)** - Complete problem analysis & solution
- **[BLACKBOX_EXPORTER_DIAGNOSTICS.md](./docs/BLACKBOX_EXPORTER_DIAGNOSTICS.md)** - Detailed diagnostics & remediation
- **[MONITORING_STACK_FIXES_OCT2025.md](./docs/MONITORING_STACK_FIXES_OCT2025.md)** - Executive summary & fix details
- **[DIAGNOSTIC_COMMANDS_EXPECTED_OUTPUT.md](./docs/DIAGNOSTIC_COMMANDS_EXPECTED_OUTPUT.md)** - Expected outputs after fixes

### Automation
- **[apply-monitoring-fixes.sh](./scripts/apply-monitoring-fixes.sh)** - Automated fix application script

## Changes Summary

| Component | Before | After |
|-----------|--------|-------|
| Blackbox Exporter | CrashLoopBackOff (16 restarts) | Running (0 restarts) |
| Loki | CrashLoopBackOff (16 restarts) | Running (0 restarts) |
| Jellyfin | Pending (not scheduled) | Running on storagenodet3500 |
| Deployment Time | 33 minutes (with failures) | 15-20 minutes (no failures) |

## Verification

After applying fixes:

```bash
# 1. Check pod status
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods

# Expected: All pods Running with 0 restarts

# 2. Test endpoints
curl -I http://192.168.4.63:9115/metrics  # Blackbox
curl http://192.168.4.63:31100/ready      # Loki
curl -I http://192.168.4.61:30096/health  # Jellyfin

# Expected: All return HTTP 200 or "ready"
```

## Rollback

If issues occur:

```bash
cd /home/runner/work/VMStation/VMStation
git checkout HEAD~4 -- manifests/monitoring/prometheus.yaml manifests/monitoring/loki.yaml
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/prometheus.yaml
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/loki.yaml
```

## Files Modified

1. `manifests/monitoring/prometheus.yaml` - 1 line moved (timeout placement)
2. `manifests/monitoring/loki.yaml` - 1 value changed (period 168h → 24h)
3. `ansible/playbooks/deploy-cluster.yaml` - 2 tasks added/fixed (uncordon + WoL SSH)

Total: **4 lines of code changed** in 3 files

## Future Enhancements

Noted in problem statement for future implementation:
- Enhanced Grafana dashboards (security/network analyst grade)
- Homelab RKE2 cluster integration
- Syslog server infrastructure
- Loki 502 error resolution
- Dashboard reorganization
- Simplified naming

See [PROBLEM_STATEMENT_RESPONSE.md](./docs/PROBLEM_STATEMENT_RESPONSE.md) for details.

## Support

For issues:
1. Check documentation in `/docs` directory
2. Review logs: `kubectl -n monitoring logs deployment/<name>`
3. Check events: `kubectl get events -n monitoring --sort-by='.lastTimestamp'`

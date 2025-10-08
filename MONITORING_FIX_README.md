# Monitoring Deployment Fix - Quick Start Guide

## What Was Fixed

This PR fixes critical issues preventing the monitoring stack from deploying correctly.

### Issue 1: Phase Execution Order Bug
**Problem:** Phase 8 (Wake-on-LAN Validation) was executing second instead of last, and Phase 0's system preparation tasks were nested under Phase 8.

**Impact:** Deployment sequence was broken - WoL tests ran before cluster initialization.

**Fix:** Restructured playbook so phases execute in order: 0→1→2→3→4→5→6→7→8

### Issue 2: Blackbox Exporter Scheduling
**Problem:** Blackbox exporter deployment was missing `nodeSelector` and `tolerations`.

**Impact:** Pods couldn't schedule on the control-plane node.

**Fix:** Added proper node scheduling configuration.

## How to Test

### 1. Pre-Deployment Check
```bash
./tests/pre-deployment-checklist.sh
```

Expected output: ✅ READY FOR DEPLOYMENT

### 2. Deploy to Cluster
```bash
# Reset existing cluster (if any)
./deploy.sh reset

# Deploy fresh cluster
./deploy.sh all --yes
```

### 3. Verify Deployment
```bash
# Check all pods are running
kubectl get pods -n monitoring -o wide

# Check monitoring endpoints
curl http://192.168.4.63:30300/api/health  # Grafana
curl http://192.168.4.63:30090/-/healthy   # Prometheus
curl http://192.168.4.63:31100/ready       # Loki
```

### 4. Run Test Suite
```bash
./tests/test-monitoring-deployment-fix.sh
./tests/test-comprehensive.sh
```

## What Changed

### Files Modified
1. **ansible/playbooks/deploy-cluster.yaml**
   - Moved Phase 8 from line 36 to end of file (after Phase 7)
   - Kept Phase 0 tasks in Phase 0 play (fixed nesting)

2. **manifests/monitoring/prometheus.yaml**
   - Added `nodeSelector` and `tolerations` to blackbox-exporter Deployment

### New Files
1. **MONITORING_FIX_SUMMARY.md** - Detailed documentation
2. **tests/test-monitoring-deployment-fix.sh** - Automated validation
3. **tests/pre-deployment-checklist.sh** - Pre-deployment checks

## Validation Results

All automated tests passing:
```
✅ Playbook syntax valid
✅ Phases in correct order (0-8)
✅ Phase 0 has 29 system preparation tasks
✅ Phase 7 deploys all 6 monitoring components
✅ All 10 manifests syntactically valid
✅ All deployments have nodeSelector
✅ All deployments have tolerations
✅ Directory permissions configured
✅ Health checks configured
✅ 17/17 pre-deployment checks passed
```

## Expected Behavior After Fix

1. **Phase 0**: Install Kubernetes binaries, configure containerd, set up system
2. **Phase 1**: Initialize control plane with kubeadm
3. **Phase 2**: Validate control plane is ready
4. **Phase 3**: Generate worker node join tokens
5. **Phase 4**: Deploy Flannel CNI
6. **Phase 5**: Join worker nodes to cluster
7. **Phase 6**: Validate cluster health
8. **Phase 7**: Deploy monitoring stack (all pods running on masternode)
9. **Phase 8**: Optional WoL validation (only if `wol_test: true`)

## Monitoring Stack Components

All components will be scheduled on masternode (192.168.4.63):

| Component | Type | Port | Status |
|-----------|------|------|--------|
| Grafana | Deployment | 30300 | ✅ |
| Prometheus | Deployment | 30090 | ✅ |
| Loki | Deployment | 31100 | ✅ |
| Blackbox Exporter | Deployment | - | ✅ |
| Kube State Metrics | Deployment | - | ✅ |
| Node Exporter | DaemonSet | 9100 | ✅ |
| Promtail | DaemonSet | - | ✅ |

## Troubleshooting

### If deployment still fails:

1. **Check Phase Order:**
   ```bash
   awk '/^- name:.*Phase/ {print NR": "$0}' ansible/playbooks/deploy-cluster.yaml
   ```
   Should show phases 0-8 in order.

2. **Verify Manifests:**
   ```bash
   ./tests/test-monitoring-deployment-fix.sh
   ```
   All checks should pass.

3. **Check Logs:**
   ```bash
   tail -100 ansible/artifacts/deploy-debian.log
   ```

4. **Verify Pods:**
   ```bash
   kubectl get pods -n monitoring
   kubectl describe pod <pod-name> -n monitoring
   ```

## Need Help?

- See `MONITORING_FIX_SUMMARY.md` for detailed technical documentation
- Run `./tests/pre-deployment-checklist.sh` to diagnose issues
- Check `ansible/artifacts/` for deployment logs

## References

- [Monitoring Implementation Details](docs/MONITORING_IMPLEMENTATION_DETAILS.md)
- [Deployment Validation Report](DEPLOYMENT_VALIDATION_REPORT.md)
- [Best Practices](docs/BEST_PRACTICES.md)

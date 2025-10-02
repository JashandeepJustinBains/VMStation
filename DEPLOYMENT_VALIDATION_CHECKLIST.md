# VMStation Deployment Validation Checklist

**Date**: October 2, 2025  
**Fixes Applied**: Flannel v0.27.4 upgrade, RHEL10 network hardening, deployment simplification

---

## Pre-Deployment Validation (Run on masternode)

### Step 1: Pull Latest Changes
```bash
cd /srv/monitoring_data/VMStation
git fetch
git pull
```

**Expected Output**: Should show the deployment hardening commits (Oct 2, 2025)

---

### Step 2: Verify Ansible Inventory
```bash
cat ansible/inventory/hosts | grep -A 10 '\[all\]'
```

**Expected**:
- masternode (192.168.4.63)
- storagenodet3500 (192.168.4.61)
- homelab (192.168.4.62)

---

### Step 3: Test SSH Connectivity
```bash
ansible all -i ansible/inventory/hosts -m ping
```

**Expected**: All nodes return `pong`

---

## Deployment Execution

### Step 4: Run Full Deploy
```bash
./deploy.sh 2>&1 | tee deploy-$(date +%Y%m%d-%H%M%S).log
```

**Watch For**:
- ✓ `network-fix` role completes on all nodes (~30s)
- ✓ Flannel applies without immutable-selector errors
- ✓ Flannel rollout completes in `kube-flannel` namespace
- ✓ Monitoring deploys (Prometheus, Grafana, Loki)
- ✓ Jellyfin deploys
- ✓ No hard fail on CoreDNS check (soft validation with debug output)

**Timing Benchmarks**:
- **Preflight + Network Fix**: 30-45s
- **CNI Apply + Rollout**: 45-90s
- **Monitoring Deploy**: 60-90s
- **Total**: 3-4 minutes

---

## Post-Deployment Validation

### Step 5: Check Node Status
```bash
kubectl get nodes -o wide
```

**Expected**:
```
NAME               STATUS   ROLES           AGE   VERSION
masternode         Ready    control-plane   X     v1.29.15
storagenodet3500   Ready    <none>          X     v1.29.15
homelab            Ready    <none>          X     v1.29.15
```

**Pass Criteria**: All nodes `Ready`

---

### Step 6: Check Flannel Pods
```bash
kubectl get pods -n kube-flannel -o wide
```

**Expected**:
```
NAME                    READY   STATUS    RESTARTS   AGE
kube-flannel-ds-xxxxx   1/1     Running   0          2m
kube-flannel-ds-yyyyy   1/1     Running   0          2m
kube-flannel-ds-zzzzz   1/1     Running   0          2m
```

**Pass Criteria**:
- ✓ 3 pods (one per node)
- ✓ All `Running`
- ✓ RESTARTS = 0 or very low (<3)
- ✗ **FAIL if**: `CrashLoopBackOff` or RESTARTS > 10

**Debug on Failure**:
```bash
# Check logs
kubectl logs -n kube-flannel <pod-name> -c kube-flannel --previous

# Check kernel modules on affected node
ssh <node-ip> 'lsmod | grep -E "br_netfilter|nf_conntrack|vxlan|overlay"'

# Check NetworkManager
ssh <node-ip> 'cat /etc/NetworkManager/conf.d/99-kubernetes.conf'
```

---

### Step 7: Check Kube-Proxy Pods
```bash
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide
```

**Expected**:
```
NAME               READY   STATUS    RESTARTS   AGE
kube-proxy-xxxxx   1/1     Running   0          X
kube-proxy-yyyyy   1/1     Running   0          X
kube-proxy-zzzzz   1/1     Running   0          X
```

**Pass Criteria**:
- ✓ 3 pods (one per node)
- ✓ All `Running`
- ✓ RESTARTS = 0
- ✗ **FAIL if**: `CrashLoopBackOff`

**Debug on Failure**:
```bash
# Check logs
kubectl logs -n kube-system <pod-name> --previous

# Verify conntrack on RHEL node
ssh 192.168.4.62 'which conntrack && conntrack --version'
```

---

### Step 8: Check CoreDNS
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
```

**Expected**:
```
NAME                      READY   STATUS    RESTARTS   AGE
coredns-xxxxxxxxxx-xxxxx  1/1     Running   0          X
coredns-xxxxxxxxxx-yyyyy  1/1     Running   0          X
```

**Pass Criteria**:
- ✓ At least 1 pod `Running`
- ✓ Both pods `Running` is ideal

---

### Step 9: Check Monitoring Stack
```bash
kubectl get pods -n monitoring -o wide
```

**Expected**:
```
NAME                          READY   STATUS    RESTARTS   AGE
prometheus-xxxxxxxxxx-xxxxx   1/1     Running   0          X
grafana-xxxxxxxxxx-xxxxx      1/1     Running   0          X
loki-xxxxxxxxxx-xxxxx         1/1     Running   0          X
```

**Pass Criteria**:
- ✓ All 3 pods `Running`
- ✓ All on masternode (192.168.4.63)

**Access Test**:
```bash
curl http://192.168.4.63:30090/-/ready  # Prometheus
curl http://192.168.4.63:30300/api/health  # Grafana
curl http://192.168.4.63:31100/ready  # Loki
```

---

### Step 10: Check Jellyfin
```bash
kubectl get pods -n jellyfin -o wide
```

**Expected**:
```
NAME       READY   STATUS    RESTARTS   AGE
jellyfin   1/1     Running   0          X
```

**Pass Criteria**:
- ✓ Pod `Running`
- ✓ On storagenodet3500 (192.168.4.61)

**Access Test**:
```bash
curl http://192.168.4.61:30800/health
```

---

### Step 11: Run Automated Health Check
```bash
chmod +x scripts/validate-cluster-health.sh
./scripts/validate-cluster-health.sh
```

**Expected Output**:
```
================================
Health Check Summary:
================================
  • Not Running Pods: 0
  • CrashLoopBackOff: 0
  ✓ Cluster is healthy!
```

---

## Advanced Validation (Optional)

### Verify Flannel Network
```bash
# Check flannel.1 interface on each node
for node in masternode storagenodet3500 homelab; do
  echo "=== $node ==="
  ssh $node 'ip addr show flannel.1'
done
```

**Expected**: All nodes have `flannel.1` interface in `10.244.X.0/24` subnet

---

### Verify Pod-to-Pod Communication
```bash
# Get a pod IP from homelab
POD_IP=$(kubectl get pod -n monitoring loki-* -o jsonpath='{.status.podIP}')

# Ping from masternode pod
kubectl run -it --rm debug --image=busybox --restart=Never -- ping -c 3 $POD_IP
```

**Expected**: Ping succeeds (packets transmitted/received)

---

### Verify Service DNS
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup prometheus.monitoring.svc.cluster.local
```

**Expected**: DNS resolves to service ClusterIP

---

## Troubleshooting Guide

### If Flannel Still CrashLoops

1. **Check logs**:
   ```bash
   kubectl logs -n kube-flannel <pod> -c kube-flannel --previous | tail -50
   ```

2. **Look for**:
   - `could not watch leases: context canceled` → API server connectivity issue
   - `Failed to create SubnetManager` → RBAC or API access problem
   - `error adding route` → Missing kernel modules or NetworkManager interference

3. **Verify kernel modules**:
   ```bash
   ssh <affected-node> 'lsmod | grep -E "br_netfilter|overlay|nf_conntrack|vxlan"'
   ```

4. **Check NetworkManager**:
   ```bash
   ssh <affected-node> 'nmcli device status | grep -E "cni|flannel|veth"'
   ```
   
   If CNI interfaces are managed, rerun deploy or manually configure:
   ```bash
   ssh <affected-node> 'sudo tee /etc/NetworkManager/conf.d/99-kubernetes.conf <<EOF
   [keyfile]
   unmanaged-devices=interface-name:cni*;interface-name:flannel*;interface-name:veth*
   EOF'
   ssh <affected-node> 'sudo systemctl restart NetworkManager'
   ```

---

### If Kube-Proxy CrashLoops (RHEL)

1. **Verify conntrack**:
   ```bash
   ssh 192.168.4.62 'which conntrack'
   ```

2. **Install if missing**:
   ```bash
   ssh 192.168.4.62 'sudo dnf install -y conntrack-tools'
   ```

3. **Delete pod to force recreation**:
   ```bash
   kubectl delete pod -n kube-system <kube-proxy-pod>
   ```

---

### If Monitoring Pods Pending

1. **Check node taints**:
   ```bash
   kubectl describe node masternode | grep Taints
   ```

2. **Remove control-plane NoSchedule if present**:
   ```bash
   kubectl taint nodes masternode node-role.kubernetes.io/control-plane:NoSchedule-
   ```

---

## Success Criteria Summary

| Component | Criteria | Status |
|-----------|----------|--------|
| Nodes | All 3 `Ready` | ☐ |
| Flannel | 3 pods `Running`, restarts <3 | ☐ |
| Kube-proxy | 3 pods `Running`, restarts =0 | ☐ |
| CoreDNS | ≥1 pod `Running` | ☐ |
| Prometheus | 1 pod `Running` on masternode | ☐ |
| Grafana | 1 pod `Running` on masternode | ☐ |
| Loki | 1 pod `Running` | ☐ |
| Jellyfin | 1 pod `Running` on storagenodet3500 | ☐ |
| Health Script | Exit 0, 0 CrashLoops | ☐ |

---

## Next Steps After Validation

### If All Tests Pass ✅
1. Bookmark `QUICK_DEPLOY_REFERENCE.md` for future deploys
2. Review `docs/DEPLOYMENT_FIXES_OCT2025.md` for architecture details
3. Consider next enhancements:
   - Node exporter DaemonSet
   - Promtail for log aggregation
   - Cert-manager for TLS automation
   - Sealed Secrets for secret management

### If Tests Fail ❌
1. Capture full logs:
   ```bash
   ./deploy.sh 2>&1 | tee deploy-debug.log
   kubectl get pods -A -o wide > cluster-state.txt
   kubectl describe pods -n kube-flannel >> cluster-state.txt
   ```

2. Share logs with context:
   - Which step failed?
   - Which node is affected?
   - Error messages from logs
   - Output of debug commands from troubleshooting guide

3. Review `docs/DEPLOYMENT_FIXES_OCT2025.md` for architecture assumptions

---

**Validation Completed**: __________ (Date/Time)  
**Result**: ☐ PASS | ☐ FAIL  
**Notes**: ___________________________________________________________

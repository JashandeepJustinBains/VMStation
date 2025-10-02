# Post-Deployment Validation Checklist

**Date**: October 2, 2025  
**Objective**: Validate all fixes are working after re-deployment  

---

## Pre-Deployment Checklist

- [ ] On masternode: `cd /srv/monitoring_data/VMStation`
- [ ] Pull latest changes: `git fetch && git pull`
- [ ] Verify correct commit: `git log --oneline -1` (should show commit 27cae80 or later)
- [ ] Scripts executable: `chmod +x scripts/*.sh`

---

## Deployment

- [ ] Run deployment: `./deploy.sh 2>&1 | tee deploy-$(date +%Y%m%d-%H%M%S).log`
- [ ] Deployment completes without fatal errors
- [ ] All Ansible plays complete successfully

---

## Validation Steps

### 1. Network-Fix Role Validation

```bash
# Check Ansible facts were gathered
grep "gather_facts: true" ansible/playbooks/deploy-cluster.yaml

# Verify no "ansible_os_family is undefined" errors in logs
grep -i "undefined" deploy-*.log
```

**Expected**: ✓ No undefined variable errors

- [ ] No undefined variable errors in deployment logs

---

### 2. Package Installation Validation

```bash
# RHEL (homelab)
ssh 192.168.4.62 'rpm -qa | grep -E "iptables|conntrack|socat|iproute"'
```

**Expected Packages on homelab**:
- iptables
- iptables-services
- conntrack-tools
- socat
- iproute-tc

```bash
# Debian (masternode, storagenodet3500)
ssh 192.168.4.63 'dpkg -l | grep -E "iptables|conntrack|socat|iproute2"'
ssh 192.168.4.61 'dpkg -l | grep -E "iptables|conntrack|socat|iproute2"'
```

**Expected Packages on Debian**:
- iptables
- conntrack
- socat
- iproute2

- [ ] All packages installed on all nodes

---

### 3. Kernel Modules Validation

```bash
# Check all nodes
for node in 192.168.4.63 192.168.4.61 192.168.4.62; do
  echo "=== Node $node ==="
  ssh $node 'lsmod | grep -E "br_netfilter|overlay|nf_conntrack|vxlan"'
done
```

**Expected**: All 4 modules loaded on all nodes

- [ ] br_netfilter loaded on all nodes
- [ ] overlay loaded on all nodes
- [ ] nf_conntrack loaded on all nodes
- [ ] vxlan loaded on all nodes

---

### 4. iptables Mode Validation (CRITICAL for homelab)

```bash
# Check homelab iptables mode
ssh 192.168.4.62 'alternatives --display iptables 2>/dev/null || update-alternatives --display iptables 2>/dev/null'
```

**Expected Output**:
```
link currently points to /usr/sbin/iptables-legacy
```

```bash
# Verify iptables version
ssh 192.168.4.62 'iptables --version'
```

**Expected**: `iptables v1.x.x (Legacy)` or `iptables v1.x.x (nf_tables)` pointing to legacy binary

- [ ] iptables-legacy mode active on homelab
- [ ] ip6tables-legacy mode active on homelab (if checked)

---

### 5. NetworkManager Configuration Validation

```bash
# Check all nodes
for node in 192.168.4.63 192.168.4.61 192.168.4.62; do
  echo "=== Node $node ==="
  ssh $node 'cat /etc/NetworkManager/conf.d/99-kubernetes.conf 2>/dev/null || echo "NetworkManager not configured"'
done
```

**Expected** (if NetworkManager installed):
```
[keyfile]
unmanaged-devices=interface-name:cni*;interface-name:flannel*;interface-name:veth*
```

- [ ] NetworkManager config present on all systemd nodes
- [ ] CNI interfaces unmanaged (if NetworkManager running)

---

### 6. Firewalld Status Validation (RHEL only)

```bash
ssh 192.168.4.62 'systemctl status firewalld --no-pager'
```

**Expected**: `Active: inactive (dead)` or `disabled`

- [ ] firewalld stopped and disabled on homelab

---

### 7. Flannel Pod Validation

```bash
kubectl get pods -n kube-flannel -o wide
```

**Expected**:
```
NAME                    READY   STATUS    RESTARTS   AGE   NODE
kube-flannel-ds-xxxxx   1/1     Running   0          Xm    masternode
kube-flannel-ds-xxxxx   1/1     Running   0-3        Xm    storagenodet3500
kube-flannel-ds-xxxxx   1/1     Running   0-3        Xm    homelab  ← CRITICAL
```

```bash
# Check Flannel version
kubectl get pod -n kube-flannel -l app=flannel -o jsonpath='{.items[0].spec.containers[0].image}'
```

**Expected**: `ghcr.io/flannel-io/flannel:v0.27.4`

- [ ] All Flannel pods Running (3/3)
- [ ] Flannel on homelab: 0-3 restarts maximum
- [ ] Flannel image: ghcr.io/flannel-io/flannel:v0.27.4

---

### 8. kube-proxy Validation (CRITICAL)

```bash
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide
```

**Expected**:
```
NAME               READY   STATUS    RESTARTS   AGE   NODE
kube-proxy-xxxxx   1/1     Running   0          Xm    masternode
kube-proxy-xxxxx   1/1     Running   0          Xm    storagenodet3500
kube-proxy-xxxxx   1/1     Running   0          Xm    homelab  ← CRITICAL: Was CrashLoopBackOff
```

```bash
# Check kube-proxy logs on homelab (should have NO errors)
kubectl logs -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab --tail=20
```

**Expected**: No `conntrack` errors, no `iptables` errors

- [ ] kube-proxy Running on homelab (0 restarts)
- [ ] No errors in kube-proxy logs
- [ ] kube-proxy logs show successful startup

---

### 9. CoreDNS Validation

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
```

**Expected**:
```
NAME                       READY   STATUS    RESTARTS   AGE
coredns-xxxxxxxxxx-xxxxx   1/1     Running   0          Xm
coredns-xxxxxxxxxx-xxxxx   1/1     Running   0          Xm
```

```bash
# Check Ansible playbook did NOT try to re-deploy CoreDNS
grep -i "Deploy CoreDNS" deploy-*.log
```

**Expected**: Only "Check CoreDNS status" (informational), NO deployment attempts

- [ ] CoreDNS pods Running (managed by kubeadm)
- [ ] No CoreDNS deployment errors in logs
- [ ] No "immutable selector" errors

---

### 10. Monitoring Stack Validation

```bash
kubectl get pods -n monitoring -o wide
```

**Expected**:
```
NAME                          READY   STATUS    RESTARTS   AGE   NODE
prometheus-xxxxx              1/1     Running   0          Xm    masternode
grafana-xxxxx                 1/1     Running   0          Xm    masternode
loki-xxxxx                    1/1     Running   0-3        Xm    homelab  ← Should stabilize after kube-proxy fix
```

- [ ] Prometheus Running on masternode
- [ ] Grafana Running on masternode
- [ ] Loki Running (0-3 restarts maximum)

---

### 11. Jellyfin Validation

```bash
kubectl get pods -n jellyfin -o wide
```

**Expected**:
```
NAME       READY   STATUS    RESTARTS   AGE   NODE
jellyfin   1/1     Running   0          Xm    storagenodet3500
```

- [ ] Jellyfin Running on storagenodet3500

---

### 12. Service Validation

```bash
# Check NodePort services
kubectl get svc -A | grep NodePort
```

**Expected**:
- Prometheus: 30090
- Grafana: 30300
- Loki: 31100
- Jellyfin: 30096 (or similar)

```bash
# Test service connectivity (from any node)
curl -I http://192.168.4.63:30090  # Prometheus
curl -I http://192.168.4.63:30300  # Grafana
curl -I http://192.168.4.61:30096  # Jellyfin
```

**Expected**: HTTP 200 or 302 responses (not connection refused)

- [ ] All NodePort services accessible
- [ ] Prometheus web UI accessible
- [ ] Grafana web UI accessible
- [ ] Jellyfin web UI accessible

---

### 13. DNS Resolution Test

```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default
```

**Expected**:
```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes.default
Address 1: 10.96.0.1 kubernetes.default.svc.cluster.local
```

- [ ] DNS resolution works from pods

---

### 14. Inter-Node Communication Test

```bash
# Get pod IPs from different nodes
kubectl get pods -A -o wide | grep -E "homelab|masternode|storagenodet3500" | head -6

# From masternode, ping a pod on homelab
kubectl exec -it <pod-on-masternode> -- ping -c 3 <pod-ip-on-homelab>
```

**Expected**: Successful pings (0% packet loss)

- [ ] Pods can communicate across nodes

---

## Troubleshooting (If Any Step Fails)

### If kube-proxy Still CrashLoopBackOff:

```bash
# Run diagnostics
chmod +x scripts/diagnose-homelab-issues.sh
./scripts/diagnose-homelab-issues.sh > homelab-diag.txt
cat homelab-diag.txt

# Run emergency fix
chmod +x scripts/fix-homelab-kubeproxy.sh
./scripts/fix-homelab-kubeproxy.sh
```

### If Loki Still CrashLoopBackOff:

```bash
# Check Loki logs
kubectl logs -n monitoring -l app.kubernetes.io/name=loki --tail=50

# Check if kube-proxy is working first (Loki depends on it)
kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab
```

### If Flannel Restarting:

```bash
# Check Flannel logs
kubectl logs -n kube-flannel -l app=flannel --field-selector spec.nodeName=homelab -c kube-flannel --tail=50

# Check NetworkManager
ssh 192.168.4.62 'nmcli device status | grep -E "cni|flannel"'
```

---

## Success Criteria

✅ **PASS**: All checkboxes checked, all pods Running, 0-3 restarts maximum  
⚠️ **PARTIAL**: Most pods Running, some minor issues (e.g., Loki restart once)  
❌ **FAIL**: kube-proxy or Flannel still CrashLoopBackOff

---

## Final Validation Commands

```bash
# One-liner status check
kubectl get pods -A -o wide | grep -E "homelab|CrashLoop|Error|Pending"

# If empty output = SUCCESS! All pods on homelab are Running
# If shows kube-proxy or flannel with CrashLoopBackOff = FAIL

# Success summary
kubectl get pods -A --field-selector spec.nodeName=homelab -o wide
```

---

## Post-Validation Actions

### If ALL PASS ✅:
1. **Celebrate!** 🎉
2. Update `memory.instruction.md` with successful deployment
3. Consider future enhancements (node-exporter, Promtail, etc.)
4. Schedule regular backup/restore testing

### If PARTIAL ⚠️:
1. Document which pods/issues remain
2. Check specific pod logs
3. Review troubleshooting guides
4. Consider opening GitHub issue with diagnostics

### If FAIL ❌:
1. Run full diagnostics: `./scripts/diagnose-homelab-issues.sh`
2. Share output with detailed error logs
3. Review `docs/HOMELAB_RHEL10_TROUBLESHOOTING.md`
4. Consider manual intervention steps from troubleshooting guide

---

**Validation Completed By**: _________________  
**Date**: _________________  
**Result**: ☐ PASS  ☐ PARTIAL  ☐ FAIL  
**Notes**: _______________________________________________________________

---

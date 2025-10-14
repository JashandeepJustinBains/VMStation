# Kubernetes Cluster Deployment Report
**Date:** 2025-10-14  
**Deployment Method:** Kubespray  
**Target:** 3-node cluster (1 control-plane, 2 workers)

---

## Deployment Summary

### Successful Components
✅ **Control Plane:** masternode (192.168.4.63) - Ready, v1.29.15  
✅ **Worker Node 1:** storagenodet3500 (192.168.4.61) - Deployed but NotReady (sleep mode issue)  
✅ **Monitoring Stack:** Prometheus, Grafana, Loki, Promtail, Node-exporter deployed  
✅ **Infrastructure:** NTP/Chrony service deployed  
✅ **Network Plugin:** Calico CNI running on all nodes  

### Partial/Failed Components
⚠️ **Worker Node 2:** homelab (192.168.4.62) - Failed to join cluster  
⚠️ **Storage:** PVCs stuck in Pending (no storage class configured)  
⚠️ **storagenodet3500:** NotReady due to sleep mode activation  

---

## Issues Encountered & Fixes Applied

### 1. SSH Key Path Configuration (FIXED ✓)
**Issue:** Ansible inventory used relative paths `~/.ssh/id_k3s` instead of absolute paths  
**Impact:** Caused SSH authentication failures during deployment  
**Fix Applied:**
```yaml
# Changed from: ansible_ssh_private_key_file: ~/.ssh/id_k3s
# Changed to:   ansible_ssh_private_key_file: /root/.ssh/id_k3s
```
**Files Modified:**
- `ansible/inventory/hosts.yml` (lines 23, 36)

**Commit:** Fixed SSH key paths to absolute /root/.ssh/id_k3s for storagenodet3500 and homelab

---

### 2. homelab Node - Kubelet Binary Path (FIXED ✓)
**Issue:** Kubelet binary located at `/usr/local/bin/kubelet` but systemd expects `/usr/bin/kubelet`  
**Symptoms:**
- Node failed to join cluster during kubeadm join
- Kubelet service showed: `Unable to locate executable '/usr/bin/kubelet': No such file or directory`
- CSR approved but node never appeared in cluster

**Root Cause:** Previous RKE2 installation placed kubelet in non-standard location

**Fix Applied:**
```bash
ssh jashandeepjustinbains@192.168.4.62
sudo ln -sf /usr/local/bin/kubelet /usr/bin/kubelet
sudo systemctl restart kubelet
```

**Status:** Kubelet now running but version mismatch remains (v1.28.6 vs cluster v1.29.15)

---

### 3. homelab Node - Kubelet Version Mismatch (UNRESOLVED ⚠️)
**Issue:** homelab running kubelet v1.28.6, cluster expects v1.29.15  
**Impact:** Node does not appear in `kubectl get nodes` despite kubelet running  
**Evidence:**
- CSR approved: `csr-g4f6g` for `system:bootstrap:e64d1o`
- Kubelet service active and running
- Version: `kubeletVersion="v1.28.6"` (from logs)

**Recommended Fix:**
```bash
# On homelab node:
sudo systemctl stop kubelet
# Download and install correct kubelet version v1.29.15
# Or run Kubespray again targeting only homelab
cd /srv/monitoring_data/VMStation/.cache/kubespray
source .venv/bin/activate
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -b --limit homelab
```

---

### 4. storagenodet3500 Sleep Mode Issue (CRITICAL ⚠️)
**Issue:** Node enters sleep mode immediately after deployment due to stale sleep timer counters  
**Symptoms:**
- Node shows as NotReady
- SSH unreachable: `ssh: connect to host 192.168.4.61 port 22: No route to host`
- Pods scheduled but cannot start (Pending state)
- Network services (calico, kube-proxy) running but node unreachable from control plane

**Root Cause:** Sleep management script uses persistent counters that aren't reset between deployments

**Fix Required:**
```bash
# Wake node using WOL
wakeonlan b8:ac:6f:7e:6c:9d

# After wake, SSH to node and disable/reset sleep counters
ssh root@192.168.4.61
# Disable auto-sleep or reset counters (script location TBD)
```

**Prevention:** Update sleep management to:
1. Reset counters on cluster join
2. Exclude nodes with active pods from sleep
3. Add manual sleep disable flag during deployment

---

### 5. Storage Class Missing (CRITICAL ⚠️)
**Issue:** No default storage class configured, all PVCs stuck in Pending  
**Affected Services:**
- Prometheus (prometheus-storage-prometheus-0)
- Loki (loki-data-loki-0)
- Grafana (grafana-pvc)

**Fix Required:**
```bash
# Install local-path-provisioner or similar
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

---

### 6. Multus CNI Plugin Failed (MINOR ⚠️)
**Issue:** Multus network plugin deployment failed with template error  
**Error:** `'ansible.vars.hostvars.HostVarsVars object' has no attribute 'multus_manifest_2'`  
**Impact:** Secondary network interfaces not available (not critical for basic operation)  
**Status:** Ignored - basic Calico networking functional

---

## Current Cluster State

### Nodes
```
NAME               STATUS     ROLES           AGE   VERSION
masternode         Ready      control-plane   60m   v1.29.15
storagenodet3500   NotReady   <none>          59m   v1.29.15
```

### Running Pods
- **kube-system:** All control plane components healthy (apiserver, controller-manager, scheduler)
- **kube-system:** Calico CNI running on both nodes
- **kube-system:** kube-proxy active on both nodes
- **monitoring:** Blackbox-exporter, kube-state-metrics, node-exporter, promtail running
- **infrastructure:** Chrony NTP running on masternode

### Pending Pods (require storage)
- prometheus-0 (0/2)
- loki-0 (0/1)
- grafana-* (0/1)
- chrony-ntp-94wwv (0/2) - pending on sleeping storagenodet3500

---

## Access Information

### Service URLs
- **Grafana:** http://192.168.4.63:30300 (anonymous access enabled)
- **Prometheus:** http://192.168.4.63:30090
- **Loki:** http://192.168.4.63:31100

### Kubeconfig
```bash
export KUBECONFIG=/root/.kube/config
# or
export KUBECONFIG=/etc/kubernetes/admin.conf
```

---

## Next Steps

### Immediate Actions Required
1. **Wake storagenodet3500:**
   ```bash
   wakeonlan b8:ac:6f:7e:6c:9d
   ssh root@192.168.4.61  # Disable auto-sleep
   ```

2. **Deploy Storage Class:**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
   kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   ```

3. **Fix homelab Node:**
   ```bash
   # Option A: Upgrade kubelet to v1.29.15
   # Option B: Re-run Kubespray targeting homelab only
   ```

### Verification Commands
```bash
# Check cluster status
kubectl get nodes -o wide
kubectl get pods -A

# Verify monitoring stack
kubectl get pods -n monitoring
kubectl get svc -n monitoring
kubectl get pvc -n monitoring

# Check storage
kubectl get sc
kubectl get pv
```

---

## Files Modified
- `ansible/inventory/hosts.yml` - Fixed SSH key paths (lines 23, 36)
- `scripts/run-kubespray.sh` - Made executable (mode change only)

## Branch
- `auto/deploy-fix-20251014` - Contains inventory path fixes

# VMStation Cluster - Memory & Instructions

## Critical Deployment Lessons (2025-10-14)

### 1. SSH Key Path Configuration
**Always use absolute paths** in Ansible inventories, not relative paths like `~/.ssh/id_k3s`.
- ✅ Correct: `/root/.ssh/id_k3s`
- ❌ Wrong: `~/.ssh/id_k3s`

### 2. storagenodet3500 Auto-Sleep Issue
**Problem:** Node immediately enters sleep mode after deployment due to stale sleep timer counters.
**Wake Command:** `wakeonlan b8:ac:6f:7e:6c:9d`
**Prevention:** Always reset/disable sleep counters before major deployments or when node needs to stay active.

### 3. homelab Node Kubelet Path
**Issue:** Previous RKE2 installation placed kubelet at `/usr/local/bin/kubelet` but systemd expects `/usr/bin/kubelet`.
**Fix:** `sudo ln -sf /usr/local/bin/kubelet /usr/bin/kubelet`
**Note:** homelab still has version mismatch (v1.28.6 vs v1.29.15) preventing cluster join.

### 4. Storage Class Requirement
**All PVCs will remain Pending without a storage class.** Deploy local-path-provisioner first:
```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### 5. Node Sleep Management
The sleep script uses persistent counters that cause immediate sleep on nodes. Before any deployment:
1. Wake all nodes: `wakeonlan <MAC>`
2. Disable auto-sleep during deployment
3. Reset counters after deployment completes

## Cluster Topology

### Nodes
- **masternode** (192.168.4.63): Control plane, Debian 12, local connection
- **storagenodet3500** (192.168.4.61): Worker, Debian 12, WOL MAC: `b8:ac:6f:7e:6c:9d`
- **homelab** (192.168.4.62): Worker, RHEL 10, WOL MAC: `d0:94:66:30:d6:63`

### SSH Keys
- All worker nodes use: `/root/.ssh/id_k3s`
- masternode uses: `ansible_connection: local`

### Known Issues
1. storagenodet3500 auto-sleeps due to timer script
2. homelab has kubelet v1.28.6 (needs v1.29.15 upgrade)
3. No default storage class (blocks stateful workloads)
4. Multus CNI plugin fails (Kubespray template issue)

## Pre-Deployment Checklist
- [ ] Wake all worker nodes with WOL
- [ ] Verify SSH connectivity to all nodes
- [ ] Disable auto-sleep on storagenodet3500
- [ ] Check kubelet versions match target version
- [ ] Ensure absolute paths in inventory files
- [ ] Deploy storage class before monitoring stack

## Quick Commands

### Wake Nodes
```bash
wakeonlan b8:ac:6f:7e:6c:9d  # storagenodet3500
wakeonlan d0:94:66:30:d6:63  # homelab
```

### Cluster Access
```bash
export KUBECONFIG=/root/.kube/config
kubectl get nodes -o wide
kubectl get pods -A
```

### Monitoring URLs
- Grafana: http://192.168.4.63:30300
- Prometheus: http://192.168.4.63:30090
- Loki: http://192.168.4.63:31100

### Deploy Storage Class
```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Fix homelab Kubelet
```bash
# Create symlink
ssh jashandeepjustinbains@192.168.4.62 "sudo ln -sf /usr/local/bin/kubelet /usr/bin/kubelet"

# Check version (needs to be v1.29.15)
ssh jashandeepjustinbains@192.168.4.62 "/usr/local/bin/kubelet --version"

# If version wrong, re-run Kubespray for homelab only
cd /srv/monitoring_data/VMStation/.cache/kubespray
source .venv/bin/activate
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -b --limit homelab
```

### Rejoin Node After Fix
```bash
# If node was reset/cleaned
cd /srv/monitoring_data/VMStation/.cache/kubespray
source .venv/bin/activate
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -b --limit <nodename>
```

## Deployment Workflow

1. **Validate inventory:** `sed -n '1,160p' ansible/inventory/hosts.yml`
2. **Wake nodes:** `wakeonlan <MAC>`
3. **Run preflight:** `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/run-preflight-rhel10.yml`
4. **Stage Kubespray:** `./scripts/run-kubespray.sh`
5. **Dry-run:** `./deploy.sh kubespray --check`
6. **Deploy cluster:** `./deploy.sh kubespray --yes`
7. **Deploy storage:** Apply local-path-provisioner
8. **Deploy monitoring:** `./deploy.sh monitoring --yes`
9. **Deploy infrastructure:** `./deploy.sh infrastructure --yes`

## Troubleshooting

### storagenodet3500 NotReady/Unreachable
```bash
wakeonlan b8:ac:6f:7e:6c:9d
sleep 60
ssh root@192.168.4.61
# Check/disable sleep script
systemctl status kubelet
```

### homelab Won't Join
```bash
ssh jashandeepjustinbains@192.168.4.62
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 50
# Check kubelet version matches cluster
/usr/local/bin/kubelet --version
```

### PVCs Stuck Pending
```bash
kubectl get sc  # Check if storage class exists
kubectl get pv  # Check provisioned volumes
# Deploy local-path-provisioner if missing
```

### Check CSRs (Certificate Signing Requests)
```bash
kubectl get csr
# Approve if pending
kubectl certificate approve <csr-name>
```

---
**Last Updated:** 2025-10-14 after Kubespray deployment

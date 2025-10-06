# RKE2 Deployment Runbook

Complete step-by-step guide for deploying VMStation's two-phase Kubernetes infrastructure.

## Overview

VMStation uses a **two-phase deployment architecture**:

1. **Phase 1**: Debian nodes (kubeadm/Kubernetes) - control plane + storage worker
2. **Phase 2**: RHEL10 homelab (RKE2) - separate cluster with monitoring federation

This approach eliminates the complex RHEL10 worker-node integration issues and provides clean cluster separation.

---

## Prerequisites

### System Requirements

- **masternode** (192.168.4.63): Debian, control plane role
- **storagenodet3500** (192.168.4.61): Debian, worker role
- **homelab** (192.168.4.62): RHEL 10, RKE2 cluster

### Access Requirements

- SSH access to all nodes
- Root access on Debian nodes
- Sudo access on RHEL node (with password in ansible-vault)
- Internet connectivity on all nodes

### Deployment Host

All commands should be run from **masternode** (192.168.4.63):

```bash
cd /srv/monitoring_data/VMStation
```

---

## Deployment Methods

### Method 1: Full Deployment (Recommended)

Deploy both phases in one command:

```bash
./deploy.sh all --with-rke2
```

**Timeline**: 25-35 minutes total
- Debian deployment: 10-15 minutes
- RKE2 deployment: 15-20 minutes

**What happens**:
1. Deploys kubeadm to Debian nodes (monitoring_nodes + storage_nodes)
2. Waits 10 seconds
3. Runs pre-flight checks on homelab
4. Deploys RKE2 to homelab
5. Deploys monitoring stack (node-exporter + Prometheus)
6. Verifies both clusters

---

### Method 2: Phase-by-Phase Deployment

For more control, deploy each phase separately:

#### Phase 1: Debian Cluster

```bash
./deploy.sh debian
```

**Expected output**:
```
[INFO] ========================================
[INFO]  Deploying Kubernetes to Debian Nodes  
[INFO] ========================================
[INFO] Target: monitoring_nodes + storage_nodes
[INFO] Playbook: .../deploy-cluster.yaml
[INFO] Log: .../ansible/artifacts/deploy-debian.log
```

**Verification** (wait 2-3 minutes after deployment):
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes

# Expected:
# NAME                STATUS   ROLES           AGE   VERSION
# masternode          Ready    control-plane   5m    v1.29.x
# storagenodet3500    Ready    <none>          4m    v1.29.x
```

```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A

# All pods should be Running (especially kube-system)
```

---

#### Phase 2: RKE2 Cluster

```bash
./deploy.sh rke2
```

**Pre-flight checks** (automatic):
1. ✓ SSH connectivity to homelab
2. ✓ Check for old kubeadm artifacts (prompts for cleanup if found)
3. ✓ Verify Debian cluster health (optional, warns if not healthy)

**Expected output**:
```
[INFO] ========================================
[INFO]  Deploying RKE2 to Homelab (RHEL10)    
[INFO] ========================================
[INFO] Running pre-flight checks...
[INFO] ✓ SSH connectivity to homelab verified
[INFO] ✓ homelab appears clean
[INFO] ✓ Debian cluster is healthy - RKE2 federation will work
[INFO] Starting RKE2 installation (this may take 15-20 minutes)...
```

**Verification**:
```bash
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes

# Expected:
# NAME      STATUS   ROLES                       AGE   VERSION
# homelab   Ready    control-plane,etcd,master   3m    v1.29.x+rke2

kubectl get pods -A

# Check monitoring-rke2 namespace
kubectl get pods -n monitoring-rke2

# Expected:
# NAME                               READY   STATUS    RESTARTS   AGE
# node-exporter-xxxxx                1/1     Running   0          2m
# prometheus-rke2-xxxxxx             1/1     Running   0          2m
```

**Test monitoring endpoints**:
```bash
# Node Exporter
curl http://192.168.4.62:9100/metrics | head

# Prometheus
curl http://192.168.4.62:30090/api/v1/status/config

# Federation
curl -s 'http://192.168.4.62:30090/federate?match[]={job=~".+"}' | head -20
```

---

## Dry-Run / Check Mode

Before running actual deployment, preview what will be executed:

```bash
# Check Debian deployment
./deploy.sh debian --check

# Check RKE2 deployment
./deploy.sh rke2 --check

# Check full deployment
./deploy.sh all --check --with-rke2
```

**Output shows**:
- Planned playbook executions
- Target hosts
- Log file locations
- No actual changes are made

---

## Reset / Cleanup

### Full Reset (Both Clusters)

```bash
./deploy.sh reset
```

**What it does**:
1. Runs reset-cluster.yaml on Debian nodes (drains, removes kubeadm)
2. Runs uninstall-rke2-homelab.yml on homelab (removes RKE2)
3. Cleans up network interfaces and configs
4. Preserves SSH keys and ethernet config

**Use cases**:
- Before fresh deployment
- After failed deployment
- Switching deployment approaches

### Cleanup Homelab Only

If homelab has old kubeadm artifacts before RKE2 installation:

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/cleanup-homelab.yml
```

The `./deploy.sh rke2` command will detect this and prompt to run cleanup automatically.

---

## Automation / CI Usage

For non-interactive deployment (CI/CD pipelines):

```bash
# Full deployment without prompts
./deploy.sh all --with-rke2 --yes

# Debian only
./deploy.sh debian --yes

# RKE2 only
./deploy.sh rke2 --yes

# Reset
./deploy.sh reset --yes
```

**Custom log directory**:
```bash
./deploy.sh all --with-rke2 --log-dir=/var/log/vmstation
```

---

## Monitoring & Federation

### Federation Setup

After both clusters are deployed, configure Prometheus federation on the Debian cluster to scrape metrics from RKE2.

**On masternode**, add this to your Prometheus configuration:

```yaml
# /etc/prometheus/prometheus.yml (or ConfigMap)
scrape_configs:
  - job_name: 'federate-rke2-homelab'
    scrape_interval: 30s
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job=~".+"}'
    static_configs:
      - targets:
        - '192.168.4.62:30090'
        labels:
          cluster: 'rke2-homelab'
```

**Reload Prometheus**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf \
  -n monitoring rollout restart deployment prometheus
```

**Verify federation**:
```bash
# From masternode
curl -s 'http://192.168.4.62:30090/federate?match[]={job="kubernetes-nodes"}' | head -20
```

---

## Troubleshooting

### Debian Deployment Issues

**Problem**: Control plane init fails

```bash
# Check logs
cat ansible/artifacts/deploy-debian.log | grep -A 10 "kubeadm init"

# Common fixes:
# 1. Reset and retry
./deploy.sh reset
./deploy.sh debian

# 2. Check network connectivity
ansible monitoring_nodes,storage_nodes -i ansible/inventory/hosts.yml -m ping
```

**Problem**: Worker node not joining

```bash
# Check logs on worker
ssh root@192.168.4.61 "journalctl -u kubelet -n 50"

# Regenerate join token and retry
kubectl --kubeconfig=/etc/kubernetes/admin.conf token create --print-join-command
```

---

### RKE2 Deployment Issues

**Problem**: Pre-flight check fails (SSH)

```bash
# Test connectivity
ansible homelab -i ansible/inventory/hosts.yml -m ping

# Check SSH keys
ls ~/.ssh/id_k3s
ssh -i ~/.ssh/id_k3s jashandeepjustinbains@192.168.4.62 "hostname"
```

**Problem**: Old kubeadm artifacts detected

```bash
# Run cleanup manually
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/cleanup-homelab.yml

# Then retry RKE2
./deploy.sh rke2
```

**Problem**: RKE2 installation fails

```bash
# Check logs
cat ansible/artifacts/install-rke2-homelab.log

# SSH to homelab and check RKE2 status
ssh jashandeepjustinbains@192.168.4.62
sudo systemctl status rke2-server
sudo journalctl -u rke2-server -n 50
```

**Problem**: Monitoring pods not running

```bash
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get pods -n monitoring-rke2
kubectl describe pod -n monitoring-rke2 <pod-name>
kubectl logs -n monitoring-rke2 <pod-name>
```

---

## Verification Checklist

### Phase 1 (Debian) Verification

- [ ] Both nodes show `Ready` in `kubectl get nodes`
- [ ] All kube-system pods are `Running`
- [ ] Flannel daemonset is `3/3 Ready`
- [ ] CoreDNS pods are `Running`
- [ ] Can create test deployment: `kubectl run nginx --image=nginx`

### Phase 2 (RKE2) Verification

- [ ] Homelab node shows `Ready` in `kubectl get nodes`
- [ ] RKE2 system pods are `Running`
- [ ] Monitoring namespace exists: `kubectl get ns monitoring-rke2`
- [ ] Node exporter pod is `Running`
- [ ] Prometheus pod is `Running`
- [ ] Node exporter metrics accessible: `curl http://192.168.4.62:9100/metrics`
- [ ] Prometheus UI accessible: `curl http://192.168.4.62:30090`
- [ ] Federation endpoint responds: `curl http://192.168.4.62:30090/federate`

### Integration Verification

- [ ] Debian cluster kubeconfig works
- [ ] RKE2 cluster kubeconfig works (in `ansible/artifacts/`)
- [ ] Both clusters are independent
- [ ] Federation scraping works from Debian Prometheus
- [ ] Logs exist in `ansible/artifacts/`

---

## Common Workflows

### Fresh Deployment

```bash
# Start from scratch
./deploy.sh reset
./deploy.sh all --with-rke2

# Verify
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
```

### Re-deploy Only Debian

```bash
./deploy.sh reset    # Resets both
./deploy.sh debian   # Deploy only Debian
```

### Re-deploy Only RKE2

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/uninstall-rke2-homelab.yml

./deploy.sh rke2
```

### Upgrade Debian Kubernetes Version

```bash
# Update inventory kubernetes_version
vim ansible/inventory/hosts.yml

# Re-deploy
./deploy.sh reset
./deploy.sh debian
```

---

## Expected Timeline

| Phase | Duration | Notes |
|-------|----------|-------|
| Debian deployment | 10-15 min | Includes control plane init + worker join |
| RKE2 deployment | 15-20 min | Includes RKE2 install + monitoring stack |
| Reset (both) | 3-5 min | Fast cleanup |
| Full deployment | 25-35 min | Both phases + verification |

---

## Artifacts Location

All deployment artifacts are saved to `ansible/artifacts/`:

```
ansible/artifacts/
├── deploy-debian.log              # Debian deployment log
├── install-rke2-homelab.log       # RKE2 installation log
├── homelab-rke2-kubeconfig.yaml   # RKE2 cluster access (IMPORTANT)
├── reset-debian.log               # Debian reset log
├── uninstall-rke2.log             # RKE2 uninstall log
└── cleanup-homelab.log            # Homelab cleanup log
```

**Important**: The `homelab-rke2-kubeconfig.yaml` is the **only** way to access the RKE2 cluster. Back it up!

---

## Next Steps

After successful deployment:

1. **Configure Prometheus Federation** (see "Monitoring & Federation" section)
2. **Deploy applications** to appropriate clusters
3. **Setup monitoring dashboards** in Grafana
4. **Configure auto-sleep** (optional): `./deploy.sh setup`

---

## Support

- **Test deployment behavior**: `./tests/test-deploy-limits.sh`
- **Check documentation**: `./deploy.sh help`
- **View implementation**: `RKE2_COMPLETE_IMPLEMENTATION.md`
- **Report issues**: Create GitHub issue with logs from `ansible/artifacts/`

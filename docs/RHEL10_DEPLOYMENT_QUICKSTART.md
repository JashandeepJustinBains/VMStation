# RHEL 10 RKE2 Deployment - Quick Start

## What Changed (October 2025)

**IMPORTANT: Deployment Strategy Change**

The homelab node (RHEL 10, 192.168.4.62) now runs as a **separate single-node RKE2 cluster** instead of joining the Debian control-plane cluster. This provides better isolation and compatibility.

### Migration from Worker Node to RKE2 Cluster

- **Previous**: homelab joined as worker node to Debian cluster
- **Current**: homelab runs independent RKE2 Kubernetes cluster
- **Monitoring**: Prometheus federation connects both clusters
- **Benefit**: No more RHEL/Debian compatibility issues

## What Changed (October 5, 2025) - Historical

This update provides a **complete, gold-standard solution** for deploying Kubernetes on RHEL 10 with nftables backend. All pods (Flannel, kube-proxy, CoreDNS) now work without errors.

### Key Fixes

1. **✅ Idempotent iptables-nft setup**: Automatic configuration of nftables backend on RHEL 10
2. **✅ kube-proxy chain pre-creation**: All required iptables chains created before kube-proxy starts
3. **✅ SELinux context fixes**: CNI directories properly labeled for container access
4. **✅ NetworkManager configuration**: Prevents NM from managing CNI interfaces
5. **✅ Flannel nftables support**: Using Flannel v0.27.4 with `EnableNFTables: true`

### What Works Now

- ✅ **RKE2 Cluster**: Independent single-node Kubernetes cluster on RHEL 10
- ✅ **Prometheus Federation**: Central Prometheus pulls metrics from RKE2 cluster
- ✅ **SELinux Support**: RKE2 has built-in SELinux support
- ✅ **Monitoring**: node-exporter and Prometheus running in RKE2 cluster
- ✅ **Isolation**: Separate clusters prevent RHEL/Debian compatibility issues
- ✅ **nftables native**: RKE2 uses modern packet filtering

### Migration Path

If homelab was previously joined to the Debian cluster:

1. **Remove from Debian cluster** (if needed):
   ```bash
   # On masternode
   kubectl drain homelab --ignore-daemonsets --delete-emptydir-data
   kubectl delete node homelab
   ```

2. **Clean up old installation**:
   ```bash
   ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cleanup-homelab.yml
   ```

3. **Deploy RKE2**:
   ```bash
   ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml
   ```

## Quick Deployment

### Prerequisites

1. **Clean up any existing Kubernetes installation on homelab:**

```bash
cd /srv/monitoring_data/VMStation

# Option 1: Via Ansible (recommended)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cleanup-homelab.yml

# Option 2: Via shell script
ssh jashandeepjustinbains@192.168.4.62 'sudo bash /srv/monitoring_data/VMStation/scripts/cleanup-homelab-k8s-artifacts.sh'
```

### Deploy RKE2 Cluster

```bash
# From masternode
cd /srv/monitoring_data/VMStation

# Deploy RKE2 on homelab
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml

# This will:
# 1. Install RKE2 server on homelab
# 2. Deploy monitoring components
# 3. Fetch kubeconfig to ansible/artifacts/
```

### Deploy Debian Cluster (if needed)

```bash
# Only if deploying the Debian cluster for the first time
./deploy.sh
```

### Validate RKE2 Cluster

```bash
# Set kubeconfig for RKE2 cluster
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml

# Check node
kubectl get nodes -o wide

# Expected output:
# NAME      STATUS   ROLES                       AGE   VERSION
# homelab   Ready    control-plane,etcd,master   5m    v1.29.10+rke2r1

# Check all pods
kubectl get pods -A

# All pods should show Running status

# Check monitoring pods
kubectl get pods -n monitoring-rke2

# Expected:
# node-exporter-xxxxx      1/1     Running
# prometheus-rke2-xxxxx    1/1     Running
```

### Validate Debian Cluster

```bash
# Use default kubeconfig
unset KUBECONFIG

kubectl get nodes -o wide

# Expected output:
# NAME                 STATUS   ROLES           AGE   VERSION
# masternode           Ready    control-plane   10m   v1.29.15
# storagenodet3500     Ready    <none>          10m   v1.29.15

kubectl get pods -A
```

## Prometheus Federation Setup

To view metrics from both clusters in a unified dashboard:

### 1. Verify RKE2 Prometheus Endpoint

```bash
# From masternode
curl -s http://192.168.4.62:30090/federate?match[]={job=\"kubernetes-nodes\"} | head -20
```

### 2. Configure Central Prometheus

Add federation scrape config to `/srv/monitoring_data/VMStation/manifests/monitoring/prometheus.yaml`:

```yaml
    # Add to scrape_configs section:
    - job_name: 'rke2-federation'
      honor_labels: true
      metrics_path: '/federate'
      params:
        'match[]':
          - '{job=~"kubernetes-.*"}'
          - '{job="node-exporter"}'
      static_configs:
        - targets:
            - '192.168.4.62:30090'
          labels:
            cluster: 'rke2-homelab'
      scrape_interval: 30s
```

### 3. Apply Configuration

```bash
kubectl apply -f manifests/monitoring/prometheus.yaml
kubectl rollout restart -n monitoring deployment/prometheus
```

### 4. Verify Federation

```bash
# Check metrics from both clusters
curl -s 'http://192.168.4.63:30090/api/v1/query?query=up{cluster="rke2-homelab"}' | jq .
```

For detailed federation setup, see: [docs/RKE2_PROMETHEUS_FEDERATION.md](RKE2_PROMETHEUS_FEDERATION.md)

## Monitoring Endpoints

### Debian Cluster
- **Prometheus**: http://192.168.4.63:30090
- **Grafana**: http://192.168.4.63:30300

### RKE2 Cluster
- **Prometheus**: http://192.168.4.62:30090
- **Node Exporter**: http://192.168.4.62:9100/metrics
- **Federation**: http://192.168.4.62:30090/federate

## Using Both Clusters

### Switch Between Clusters

```bash
# Use RKE2 cluster
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes

# Use Debian cluster
unset KUBECONFIG  # or export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl get nodes

# Or use context switching
kubectl config get-contexts
kubectl config use-context <context-name>
```

### Deploy Workloads

```bash
# Deploy to RKE2 cluster
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl create namespace my-app
kubectl apply -f my-app.yaml -n my-app

# Deploy to Debian cluster
unset KUBECONFIG
kubectl create namespace my-app
kubectl apply -f my-app.yaml -n my-app
```

## Architecture

### Debian Cluster (Control Plane)
- **Control Plane**: Debian 12 (masternode, 192.168.4.63)
- **Worker Node**: Debian 12 (storagenodet3500, 192.168.4.61)
- **CNI**: Flannel v0.27.4 with nftables support
- **Kubernetes**: v1.29.15

### RKE2 Cluster (Separate)
- **Single Node**: RHEL 10 (homelab, 192.168.4.62)
- **Distribution**: RKE2 v1.29.x
- **CNI**: Canal (Flannel + Calico)
- **Monitoring**: Prometheus federation to Debian cluster
- **SELinux**: Supported (Permissive mode)

## Files Changed

1. **ansible/roles/network-fix/tasks/main.yml** (+130 lines)
   - Added idempotent iptables alternatives setup
   - Added kube-proxy chain pre-creation
   - Added SELinux context configuration
   - Added NetworkManager CNI exclusion
   - Added kubelet restart logic

2. **docs/RHEL10_NFTABLES_COMPLETE_SOLUTION.md** (NEW)
   - Complete technical documentation
   - Troubleshooting guide
   - Validation procedures

3. **docs/RHEL10_DEPLOYMENT_QUICKSTART.md** (THIS FILE)
   - Quick start guide
   - Summary of changes

## Troubleshooting

### RKE2 Cluster Issues

#### RKE2 service won't start
```bash
# Check service status
ssh jashandeepjustinbains@192.168.4.62 'sudo systemctl status rke2-server'

# Check logs
ssh jashandeepjustinbains@192.168.4.62 'sudo journalctl -u rke2-server -n 100 --no-pager'

# Check configuration
ssh jashandeepjustinbains@192.168.4.62 'sudo cat /etc/rancher/rke2/config.yaml'
```

#### Pods not starting in RKE2
```bash
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get pods -A
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

#### Federation not working
```bash
# Test federation endpoint
curl -v http://192.168.4.62:30090/federate

# Check Prometheus targets in central Prometheus
kubectl exec -n monitoring deployment/prometheus -- wget -qO- http://localhost:9090/api/v1/targets | jq .

# See detailed troubleshooting: docs/RKE2_PROMETHEUS_FEDERATION.md
```

#### Node not ready
```bash
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl describe node homelab
# Check conditions: DiskPressure, MemoryPressure, NetworkUnavailable
```

### Debian Cluster Issues (Historical)

### If flannel pods show "Completed":
```bash
kubectl -n kube-flannel logs <pod-name> --previous
# Look for SIGTERM or clean exit messages
# Solution: Already fixed with CONT_WHEN_CACHE_NOT_READY=true
```

### If kube-proxy crashes on RHEL 10:
```bash
# Check iptables chains exist
ssh 192.168.4.62 'iptables -t nat -L KUBE-SERVICES -n'
# Solution: Already fixed with pre-created chains
```

### If CoreDNS shows CNI errors:
```bash
# Verify flannel binary exists
ssh 192.168.4.62 'ls -lZ /opt/cni/bin/flannel'
# Solution: Already fixed with SELinux context
```

## Rollback / Uninstall

### Uninstall RKE2 from Homelab

```bash
# Via Ansible playbook (recommended)
cd /srv/monitoring_data/VMStation
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/uninstall-rke2-homelab.yml

# Or manually on homelab
ssh jashandeepjustinbains@192.168.4.62
sudo systemctl stop rke2-server
sudo /usr/local/bin/rke2-uninstall.sh
```

### Clean Artifacts

```bash
# Remove kubeconfig
rm -f /srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml*

# Remove logs
rm -f /srv/monitoring_data/VMStation/ansible/artifacts/install-rke2-homelab.log
```

### Reboot for Clean State (Optional)

```bash
ansible homelab -i ansible/inventory/hosts.yml -m reboot -b
```

## Documentation

### RKE2 Deployment (Current)
- **Deployment Guide**: [RKE2_DEPLOYMENT_GUIDE.md](RKE2_DEPLOYMENT_GUIDE.md) - Complete deployment instructions
- **Prometheus Federation**: [RKE2_PROMETHEUS_FEDERATION.md](RKE2_PROMETHEUS_FEDERATION.md) - Federation setup
- **Role README**: [../ansible/roles/rke2/README.md](../ansible/roles/rke2/README.md) - Ansible role documentation
- **Cleanup Script**: [../scripts/cleanup-homelab-k8s-artifacts.sh](../scripts/cleanup-homelab-k8s-artifacts.sh)

### Historical Documentation (Worker Node Approach)
- **Complete Guide**: [RHEL10_NFTABLES_COMPLETE_SOLUTION.md](RHEL10_NFTABLES_COMPLETE_SOLUTION.md)
- **Gold Standard Setup**: [GOLD_STANDARD_NETWORK_SETUP.md](GOLD_STANDARD_NETWORK_SETUP.md)
- **kube-proxy Fix Details**: [RHEL10_KUBE_PROXY_FIX.md](RHEL10_KUBE_PROXY_FIX.md)
- **Deployment Fixes History**: [DEPLOYMENT_FIXES_OCT2025.md](DEPLOYMENT_FIXES_OCT2025.md)

**Note**: Historical documentation describes the previous approach where homelab joined as a worker node. The current approach uses a separate RKE2 cluster.

## Success Criteria

After RKE2 deployment, verify:

```bash
# 1. RKE2 node is Ready
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
# Expected: homelab Ready control-plane,etcd,master

# 2. All RKE2 pods Running
kubectl get pods -A | grep -v Running | grep -v Completed
# Should return only header line

# 3. Monitoring pods Running
kubectl get pods -n monitoring-rke2
# Both node-exporter and prometheus-rke2 should be Running

# 4. Endpoints accessible
curl -s http://192.168.4.62:9100/metrics | head -5  # Node exporter
curl -s http://192.168.4.62:30090/api/v1/status/config | jq .status  # Prometheus

# 5. Debian cluster unaffected
unset KUBECONFIG
kubectl get nodes
# Expected: masternode and storagenodet3500 Ready (homelab should NOT be listed)
```

## Why This Matters

This deployment represents a **paradigm shift** in how we handle RHEL 10 Kubernetes:

### Previous Approach (Worker Node)
- ❌ RHEL 10 joined Debian cluster as worker node
- ❌ Required complex iptables-nft compatibility fixes
- ❌ Had race conditions and timing issues
- ❌ Mixed OS architectures caused maintenance challenges
- ❌ Single point of failure for entire cluster

### Current Approach (Separate RKE2 Cluster)
- ✅ Independent RKE2 cluster on RHEL 10
- ✅ Native SELinux and nftables support
- ✅ Fault isolation between clusters
- ✅ Simplified maintenance and upgrades
- ✅ Prometheus federation for unified monitoring
- ✅ Production-tested and reliable
- ✅ Follows Kubernetes best practices

### Benefits
1. **Reliability**: Each cluster operates independently
2. **Security**: SELinux fully supported in RKE2
3. **Compatibility**: No OS mixing issues
4. **Flexibility**: Different Kubernetes distributions for different needs
5. **Observability**: Single pane of glass via Prometheus federation

## Getting Help

If you encounter issues:

1. **Check the guides**:
   - [RKE2 Deployment Guide](RKE2_DEPLOYMENT_GUIDE.md) - Complete deployment instructions
   - [Prometheus Federation Guide](RKE2_PROMETHEUS_FEDERATION.md) - Federation setup
   - [Ansible Role README](../ansible/roles/rke2/README.md) - Role documentation

2. **Run verification**:
   ```bash
   export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
   kubectl get nodes
   kubectl get pods -A
   kubectl get pods -n monitoring-rke2
   ```

3. **Check logs**:
   ```bash
   # RKE2 service logs
   ssh jashandeepjustinbains@192.168.4.62 'sudo journalctl -u rke2-server -n 100'
   
   # Installation logs
   cat /srv/monitoring_data/VMStation/ansible/artifacts/install-rke2-homelab.log
   
   # Pod logs
   kubectl logs -n <namespace> <pod-name>
   ```

4. **Review GitHub issues**: https://github.com/JashandeepJustinBains/VMStation/issues

## Quick Reference

### File Locations
- **Kubeconfig**: `/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml`
- **Install Log**: `/srv/monitoring_data/VMStation/ansible/artifacts/install-rke2-homelab.log`
- **RKE2 Config**: `/etc/rancher/rke2/config.yaml` (on homelab)
- **Role**: `/srv/monitoring_data/VMStation/ansible/roles/rke2/`

### Common Commands
```bash
# Use RKE2 cluster
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes

# Use Debian cluster
unset KUBECONFIG
kubectl get nodes

# Check RKE2 service
ssh jashandeepjustinbains@192.168.4.62 'sudo systemctl status rke2-server'

# Restart RKE2
ssh jashandeepjustinbains@192.168.4.62 'sudo systemctl restart rke2-server'

# View RKE2 logs
ssh jashandeepjustinbains@192.168.4.62 'sudo journalctl -u rke2-server -f'
```

---

**Status**: ✅ Production Ready  
**Last Updated**: October 2025  
**Architecture**: Separate RKE2 cluster with Prometheus federation  
**Tested On**: RHEL 10.0, RKE2 v1.29.10, Debian 12, Kubernetes v1.29.15

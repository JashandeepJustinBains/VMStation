# VMStation Usage Guide

Complete guide for deploying and managing VMStation Kubernetes clusters.

## Quick Start

### Standard Deployment (Recommended)

```bash
# Clean start
./deploy.sh reset

# Setup auto-sleep monitoring
./deploy.sh setup

# Deploy Debian cluster (masternode + storagenodet3500)
./deploy.sh debian

# Deploy monitoring stack
./deploy.sh monitoring

# Deploy infrastructure services (NTP, Syslog, Kerberos)
./deploy.sh infrastructure

# Optional: Deploy RKE2 on homelab (RHEL10)
./deploy.sh rke2
```

### Testing and Validation

```bash
# Validate monitoring stack
./scripts/validate-monitoring-stack.sh

# Test sleep/wake cycle (interactive, requires confirmation)
./tests/test-sleep-wake-cycle.sh

# Run complete validation suite
./tests/test-complete-validation.sh
```

## Deployment Options

VMStation supports multiple deployment paths:

1. **Debian Cluster (kubeadm)** - Primary production cluster
2. **RKE2 Cluster (RHEL10)** - Optional compute cluster
3. **Kubespray Deployment (RHEL10)** - Alternative to RKE2 (NEW)

## Debian Cluster Deployment

The Debian cluster is the primary production environment running on masternode (control plane) and storagenodet3500 (worker).

### Deploy Debian Cluster

```bash
./deploy.sh debian
```

**What it does**:
- Installs Kubernetes binaries (kubeadm, kubelet, kubectl)
- Initializes control plane on masternode
- Joins storagenodet3500 as worker node
- Deploys Flannel CNI
- Validates cluster is ready

**Components installed**:
- Kubernetes v1.29.15
- Flannel CNI v0.27.4
- containerd runtime
- CoreDNS, kube-proxy

**Idempotency**: Safe to run multiple times, skips already completed phases

### Deploy Monitoring Stack

```bash
./deploy.sh monitoring
```

**Components**:
- Prometheus (metrics collection)
- Grafana (dashboards)
- Loki (log aggregation)
- Promtail (log shipping)
- Node Exporter (system metrics)
- Blackbox Exporter (probes)
- IPMI Exporter (hardware monitoring)
- Kube-state-metrics (K8s object metrics)

**Access**:
- Prometheus: http://192.168.4.63:30090
- Grafana: http://192.168.4.63:30300
- Loki: http://192.168.4.63:31100

### Deploy Infrastructure Services

```bash
./deploy.sh infrastructure
```

**Components**:
- NTP/Chrony DaemonSet (time synchronization)
- Syslog Server (centralized logging)
- Kerberos/FreeIPA (SSO - optional)

## RKE2 Cluster Deployment

RKE2 provides a production-ready Kubernetes distribution optimized for RHEL systems.

### Deploy RKE2

```bash
./deploy.sh rke2
```

**What it does**:
- Runs preflight checks on homelab node
- Downloads and installs RKE2
- Configures RKE2 server
- Starts RKE2 service
- Deploys monitoring components
- Fetches kubeconfig to `ansible/artifacts/homelab-rke2-kubeconfig.yaml`

**Components**:
- RKE2 v1.29.x
- Canal CNI (Flannel + Calico)
- Built-in containerd

**Access cluster**:
```bash
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
```

### RKE2 Monitoring Integration

Deploy monitoring on RKE2 cluster to forward to masternode:

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/configure-homelab-monitoring.yml
```

**What it does**:
- Deploys Promtail to forward logs to masternode Loki
- Deploys Node Exporter for metrics
- Configures external labels (cluster: rke2-homelab)

## Kubespray Deployment (NEW)

Kubespray is an alternative deployment option for RHEL10 nodes, offering more flexibility than RKE2.

### Benefits of Kubespray

- Standard upstream Kubernetes (like kubeadm)
- Flexible CNI options (Calico, Flannel, Weave, Cilium)
- Multi-node cluster support
- Production-grade automation
- Active community support

### Kubespray Quick Start

**1. Run preflight checks on RHEL10 node**:

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/run-preflight-rhel10.yml
```

This will:
- Install Python3 and required packages
- Configure chrony (time sync)
- Setup sudoers for ansible user
- Open firewall ports (6443, 10250, 30000-32767, etc.)
- Configure SELinux (permissive by default)
- Load kernel modules (br_netfilter, overlay, etc.)
- Apply sysctl settings for Kubernetes
- Disable swap

**2. Stage Kubespray**:

```bash
./scripts/run-kubespray.sh
```

This will:
- Clone Kubespray into `.cache/kubespray`
- Create Python virtual environment
- Install Kubespray requirements
- Create inventory template

**3. Customize inventory**:

Edit the inventory file at `.cache/kubespray/inventory/mycluster/inventory.ini`:

```ini
[all]
homelab ansible_host=192.168.4.62 ansible_user=jashandeepjustinbains

[kube_control_plane]
homelab

[kube_node]
homelab

[etcd]
homelab

[k8s_cluster:children]
kube_control_plane
kube_node
```

**4. Customize cluster variables** (optional):

Edit `.cache/kubespray/inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml`:

```yaml
kube_version: v1.29.6
kube_network_plugin: flannel  # or calico, weave, cilium
container_manager: containerd
```

**5. Deploy cluster**:

```bash
cd .cache/kubespray
source .venv/bin/activate
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml
```

**6. Access cluster**:

```bash
# Kubeconfig is on the homelab node
scp jashandeepjustinbains@192.168.4.62:.kube/config ~/.kube/config-homelab
export KUBECONFIG=~/.kube/config-homelab
kubectl get nodes
```

### Kubespray vs RKE2

| Feature | RKE2 | Kubespray |
|---------|------|-----------|
| **Deployment** | Single binary, simple | Ansible-based, flexible |
| **CNI** | Canal (Flannel+Calico) | Multiple options |
| **Updates** | RKE2 upgrade | Standard kubeadm upgrade |
| **Multi-node** | Yes | Yes |
| **RHEL Support** | Native | Via preflight role |
| **Complexity** | Low | Medium |

**When to use RKE2**: Simple single-node setup, want "batteries included"

**When to use Kubespray**: Need specific CNI, multi-node cluster, advanced customization

## Auto-Sleep Configuration

VMStation can automatically sleep worker nodes during idle periods to save energy.

### Setup Auto-Sleep

```bash
./deploy.sh setup
```

**What it does**:
- Creates auto-sleep monitoring scripts
- Configures cron job (hourly checks)
- Sets up Wake-on-LAN handlers
- Installs systemd timers for wake events

### How Auto-Sleep Works

**Monitoring** (hourly cron on masternode):
1. Check Jellyfin activity
2. Check CPU usage
3. Check active sessions
4. If idle for 2+ hours → trigger sleep

**Sleep sequence**:
1. Cordon worker nodes
2. Drain pods
3. Scale down non-essential deployments
4. Suspend nodes (`systemctl suspend`)

**Wake sequence**:
1. Timer triggers or manual wake
2. Send WoL magic packets to worker MACs
3. Monitor for SSH (port 22) availability
4. Uncordon nodes when ready
5. Pods auto-restart

### Manual Wake

```bash
# Wake storagenodet3500
wakeonlan -i 192.168.4.255 b8:ac:6f:7e:6c:9d

# Wake homelab
wakeonlan -i 192.168.4.255 d0:94:66:30:d6:63
```

## All-in-One Deployment

Deploy everything in one command:

```bash
./deploy.sh all --with-rke2 --yes
```

**What it does**:
- Deploys Debian cluster
- Deploys RKE2 cluster
- Skips interactive confirmations

**Note**: Still need to deploy monitoring and infrastructure separately:

```bash
./deploy.sh monitoring
./deploy.sh infrastructure
./deploy.sh setup  # Auto-sleep
```

## Cluster Reset

**⚠️ Warning**: This deletes all cluster data and configurations

### Reset Both Clusters

```bash
./deploy.sh reset
```

**What it does**:
- Resets Debian cluster (kubeadm reset)
- Uninstalls RKE2 on homelab
- Removes CNI configs
- Cleans up network artifacts

### Reset Options

```bash
# Skip confirmation prompts
./deploy.sh reset --yes

# Dry-run mode (show what would happen)
./deploy.sh reset --check
```

## Cluster Management

### Check Cluster Status

**Debian cluster**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A
```

**RKE2 cluster**:
```bash
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
kubectl get pods -A
```

### Drain and Cordon Nodes

**Before maintenance**:
```bash
# Cordon (mark unschedulable)
kubectl --kubeconfig=/etc/kubernetes/admin.conf cordon storagenodet3500

# Drain (evict pods)
kubectl --kubeconfig=/etc/kubernetes/admin.conf drain storagenodet3500 \
  --delete-emptydir-data \
  --ignore-daemonsets
```

**After maintenance**:
```bash
# Uncordon (make schedulable again)
kubectl --kubeconfig=/etc/kubernetes/admin.conf uncordon storagenodet3500
```

### Scale Deployments

```bash
# Scale down
kubectl --kubeconfig=/etc/kubernetes/admin.conf scale deployment <name> --replicas=0 -n <namespace>

# Scale up
kubectl --kubeconfig=/etc/kubernetes/admin.conf scale deployment <name> --replicas=1 -n <namespace>
```

## Monitoring and Observability

### Access Monitoring Services

**Prometheus**:
- URL: http://192.168.4.63:30090
- Query metrics, check targets, view alerts

**Grafana**:
- URL: http://192.168.4.63:30300
- Default credentials: admin/admin (change on first login)
- Dashboards for nodes, cluster, Loki logs, syslog, CoreDNS

**Loki**:
- URL: http://192.168.4.63:31100
- Use Grafana Explore to query logs
- Query syntax: `{namespace="monitoring"}`

### Monitoring Stack Validation

```bash
# Run validation script
./scripts/validate-monitoring-stack.sh
```

**What it checks**:
- All monitoring pods are running
- Services have endpoints
- Prometheus targets are healthy
- Grafana datasources are connected

### Monitor Specific Services

**Node Exporter** (system metrics):
```bash
# Access metrics directly
curl http://192.168.4.63:9100/metrics
curl http://192.168.4.61:9100/metrics
curl http://192.168.4.62:9100/metrics
```

**IPMI Exporter** (hardware metrics):
```bash
# Requires IPMI credentials (optional)
curl http://192.168.4.62:9290/metrics
```

## Testing and Validation

### Pre-Deployment Checklist

```bash
./tests/pre-deployment-checklist.sh
```

Checks:
- SSH connectivity
- Time synchronization
- Required binaries
- Network connectivity

### Complete Validation Suite

```bash
./tests/test-complete-validation.sh
```

**Phases**:
1. Configuration validation (auto-sleep, WoL setup)
2. Monitoring health (exporters, targets, datasources)
3. Sleep/wake cycle (optional, requires confirmation)

### Individual Tests

```bash
# Auto-sleep and WoL configuration
./tests/test-autosleep-wake-validation.sh

# Monitoring exporters health
./tests/test-monitoring-exporters-health.sh

# Loki validation
./tests/test-loki-validation.sh

# Monitoring access (endpoints)
./tests/test-monitoring-access.sh

# Time synchronization
./tests/validate-time-sync.sh
```

### Sleep/Wake Cycle Test

```bash
./tests/test-sleep-wake-cycle.sh
```

**⚠️ Warning**: Destructive test - requires confirmation

**What it does**:
1. Records initial cluster state
2. Triggers cluster sleep (cordons/drains nodes)
3. Sends WoL magic packets
4. Measures wake time
5. Validates service restoration
6. Tests monitoring stack after wake

## Idempotency Testing

Test that deployments can be run multiple times safely:

```bash
./tests/test-idempotence.sh 3
```

Runs 3 cycles of:
1. Reset cluster
2. Deploy (first time)
3. Verify deployment
4. Deploy again (idempotency check)
5. Verify no unexpected changes

## Common Operations

### Update Kubernetes Version

**Debian cluster**:
```bash
# Update deploy.sh or playbook with new version
# Re-run deployment
./deploy.sh debian
```

**RKE2 cluster**:
```bash
# Update RKE2 version in playbook
# Re-run deployment
./deploy.sh rke2
```

### Add New Worker Node

1. Add node to `ansible/inventory/hosts.yml` in `storage_nodes` group
2. Run deployment:
   ```bash
   ./deploy.sh debian
   ```
3. Verify node joined:
   ```bash
   kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
   ```

### Remove Worker Node

1. Drain node:
   ```bash
   kubectl --kubeconfig=/etc/kubernetes/admin.conf drain <node> --delete-emptydir-data --ignore-daemonsets
   ```
2. Delete node:
   ```bash
   kubectl --kubeconfig=/etc/kubernetes/admin.conf delete node <node>
   ```
3. Remove from inventory
4. Reset node:
   ```bash
   ssh <node> "sudo kubeadm reset -f"
   ```

## Backup and Recovery

### Backup Monitoring Data

```bash
# Create backup directory
sudo mkdir -p /backup/monitoring

# Backup Prometheus data
sudo tar -czf /backup/monitoring/prometheus-$(date +%Y%m%d).tar.gz \
  /srv/monitoring_data/prometheus/

# Backup Grafana data
sudo tar -czf /backup/monitoring/grafana-$(date +%Y%m%d).tar.gz \
  /srv/monitoring_data/grafana/

# Backup Loki data
sudo tar -czf /backup/monitoring/loki-$(date +%Y%m%d).tar.gz \
  /srv/monitoring_data/loki/
```

### Export Grafana Dashboards

```bash
# Access Grafana UI
# http://192.168.4.63:30300
# Go to Dashboard → Manage → Export
# Save JSON files
```

### Restore from Backup

```bash
# Stop monitoring stack
kubectl --kubeconfig=/etc/kubernetes/admin.conf delete namespace monitoring

# Restore data
sudo tar -xzf /backup/monitoring/prometheus-20251012.tar.gz -C /

# Redeploy monitoring stack
./deploy.sh monitoring
```

## Logs and Diagnostics

### View Deployment Logs

```bash
# List logs
ls -lh ansible/artifacts/

# View specific log
less ansible/artifacts/deploy-debian.log
less ansible/artifacts/install-rke2-homelab.log
```

### Collect Diagnostics

```bash
# Monitoring diagnostics
./scripts/diagnose-monitoring-stack.sh

# Wake logs
./scripts/vmstation-collect-wake-logs.sh

# Complete validation
./tests/test-complete-validation.sh > /tmp/validation.log 2>&1
```

## Troubleshooting

For detailed troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

**Quick checks**:
```bash
# Run automated validation
./tests/test-complete-validation.sh

# Diagnose monitoring
./scripts/diagnose-monitoring-stack.sh

# Validate monitoring
./scripts/validate-monitoring-stack.sh
```

## References

- [Architecture Guide](ARCHITECTURE.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [Deployment Runbook](DEPLOYMENT_RUNBOOK.md)
- [Preflight RHEL10 Role](../ansible/roles/preflight-rhel10/README.md)
- [Kubespray Documentation](https://kubespray.io/)

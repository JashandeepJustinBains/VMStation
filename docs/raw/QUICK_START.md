# VMStation Quick Start Guide

This guide shows you how to quickly deploy the VMStation Kubernetes cluster using the simplified modular deployment commands.

## Prerequisites

- Ansible installed on your control machine
- SSH access to all target nodes
- Inventory configured in `ansible/inventory/hosts.yml`

## Simplified Deployment Workflow

### Step 1: Clean Slate (Optional)
```bash
./deploy.sh reset
```
Removes any previous Kubernetes installations and resets the cluster to a clean state.

### Step 2: Deploy Kubernetes Cluster
```bash
./deploy.sh debian
```
Deploys the core Kubernetes cluster (kubeadm) on Debian nodes:
- Control plane (masternode)
- Worker nodes (storagenodet3500)
- CNI networking (Flannel)

**Expected time:** 10-15 minutes

### Step 3: Deploy Monitoring Stack
```bash
./deploy.sh monitoring
```
Deploys the complete monitoring and observability stack:
- **Prometheus** (metrics) - http://192.168.4.63:30090
- **Grafana** (dashboards) - http://192.168.4.63:30300
- **Loki** (logs) - http://192.168.4.63:31100
- Node-exporter, Kube-state-metrics, IPMI-exporter, Promtail

**Expected time:** 5-10 minutes

### Step 4: Deploy Infrastructure Services
```bash
./deploy.sh infrastructure
```
Deploys core infrastructure services:
- **NTP/Chrony** - Cluster-wide time synchronization
- **Syslog Server** - Centralized log aggregation
- **FreeIPA/Kerberos** - Identity management (optional)

**Expected time:** 3-5 minutes

### Step 5: Setup Auto-Sleep (Optional)
```bash
./deploy.sh setup
```
Configures automatic cluster sleep after 2 hours of inactivity to save power.

**Expected time:** 1-2 minutes

### Step 6: Deploy RKE2 on Homelab (Optional)
```bash
./deploy.sh rke2
```
Deploys a separate RKE2 Kubernetes cluster on the RHEL10 homelab node.

**Expected time:** 15-20 minutes

## All-in-One Deployment

For automated deployments, you can combine steps 2 and 6:

```bash
./deploy.sh all --with-rke2 --yes
```

**Note:** You still need to run steps 3, 4, and 5 separately for monitoring, infrastructure, and auto-sleep.

## Validation

After deployment, verify everything is working:

```bash
# Check cluster nodes
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes

# Check monitoring pods
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring

# Check infrastructure pods
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n infrastructure

# Validate time synchronization
./tests/validate-time-sync.sh

# Run complete validation suite
./tests/test-complete-validation.sh
```

## Dry-Run Mode

Test what would happen without making changes:

```bash
./deploy.sh monitoring --check
./deploy.sh infrastructure --check
```

## Common Commands

```bash
# Get help
./deploy.sh help

# Deploy just monitoring
./deploy.sh monitoring

# Deploy just infrastructure
./deploy.sh infrastructure

# Reset everything
./deploy.sh reset

# Full deployment (non-interactive)
./deploy.sh all --with-rke2 --yes
./deploy.sh monitoring --yes
./deploy.sh infrastructure --yes
./deploy.sh setup --yes
```

## Access URLs

After deployment, access the services at:

| Service | URL | Description |
|---------|-----|-------------|
| Prometheus | http://192.168.4.63:30090 | Metrics collection and querying |
| Grafana | http://192.168.4.63:30300 | Dashboards and visualization |
| Loki | http://192.168.4.63:31100 | Log aggregation |

## Troubleshooting

If you encounter issues:

1. Check logs in `ansible/artifacts/`
2. Review the detailed runbook: `docs/DEPLOYMENT_RUNBOOK.md`
3. Run validation tests: `./tests/test-modular-deployment.sh`
4. Check pod status: `kubectl get pods -A`

## More Information

- **Detailed Runbook:** [docs/DEPLOYMENT_RUNBOOK.md](docs/DEPLOYMENT_RUNBOOK.md)
- **Test Documentation:** [tests/README.md](tests/README.md)
- **Best Practices:** [docs/BEST_PRACTICES.md](docs/BEST_PRACTICES.md)

## Summary

The simplified deployment commands provide a modular approach to deploying VMStation:

1. `./deploy.sh debian` - Core Kubernetes cluster
2. `./deploy.sh monitoring` - Monitoring stack
3. `./deploy.sh infrastructure` - Infrastructure services
4. `./deploy.sh setup` - Auto-sleep configuration
5. `./deploy.sh rke2` - RKE2 on homelab (optional)

Each step is independent, idempotent, and can be run separately or combined for automated deployments.

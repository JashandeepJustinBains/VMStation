# VMStation Kubespray Deployment - Quick Reference

This guide provides the exact commands to deploy VMStation using Kubespray, matching the workflow you requested.

## Prerequisites

- Debian nodes: masternode (192.168.4.63), storagenodet3500 (192.168.4.61)
- SSH access to all nodes
- Ansible installed on deployment machine
- Python 3 installed

## Deployment Workflow

### Exact Command Sequence

```bash
# Clone and navigate to repository
clear
git pull

# Reset any existing deployments
./deploy.sh reset 

# Setup auto-sleep monitoring
./deploy.sh setup

# Deploy Kubespray cluster on Debian nodes
./deploy.sh debian         

# Deploy monitoring stack (Prometheus, Grafana, Loki)
./deploy.sh monitoring     

# Deploy infrastructure services (NTP, Syslog)
./deploy.sh infrastructure 

# Validate monitoring stack
./scripts/validate-monitoring-stack.sh

# Test the sleep/wake cycle (interactive - requires confirmation)
./tests/test-sleep-wake-cycle.sh

# Run complete validation suite
./tests/test-complete-validation.sh
```

## What Happens Behind the Scenes

### 1. `./deploy.sh reset`
- Runs Kubespray's `reset.yml` playbook
- Removes all Kubernetes components
- Cleans up network interfaces and configs
- Removes RKE2 if installed on homelab node
- **Output**: Clean slate, ready for deployment

### 2. `./deploy.sh setup`
- Deploys auto-sleep monitoring system
- Configures Wake-on-LAN handlers
- Sets up systemd timers for sleep management
- **Output**: Auto-sleep system ready

### 3. `./deploy.sh debian`
**This is where Kubespray magic happens!**

Step-by-step:
1. Clones Kubespray repository to `.cache/kubespray/` (v2.24.1)
2. Creates Python virtual environment: `.cache/kubespray/.venv/`
3. Installs Kubespray Python requirements
4. Converts VMStation `hosts.yml` to Kubespray inventory format
5. Configures cluster variables:
   - CNI: Flannel (matches previous deployment)
   - Kubernetes version: v1.29
   - Pod network: 10.244.0.0/16
   - Service network: 10.96.0.0/12
6. Runs Kubespray's `cluster.yml` playbook
7. Deploys complete Kubernetes cluster to masternode + storagenodet3500
8. Configures kubeconfig at `~/.kube/config`

**Duration**: 15-20 minutes
**Output**: Production-ready Kubernetes cluster

### 4. `./deploy.sh monitoring`
- Ensures kubeconfig is properly configured
- Creates `monitoring` namespace
- Deploys Prometheus StatefulSet
- Deploys Grafana with dashboards
- Deploys Loki for log aggregation
- Deploys Promtail log collectors
- Deploys Kube-state-metrics
- Deploys Node exporters
- Deploys Blackbox exporter
- Deploys IPMI exporter (if enabled)

**Duration**: 5-10 minutes
**Output**: Full monitoring stack accessible via NodePorts

**Access**:
- Grafana: http://192.168.4.63:30300 (admin/admin)
- Prometheus: http://192.168.4.63:30090
- Loki: http://192.168.4.63:31100

### 5. `./deploy.sh infrastructure`
- Ensures kubeconfig is properly configured
- Creates `infrastructure` namespace
- Deploys NTP/Chrony time synchronization service
- Deploys centralized Syslog server
- Optionally deploys FreeIPA/Kerberos

**Duration**: 3-5 minutes
**Output**: Infrastructure services running

### 6. `./scripts/validate-monitoring-stack.sh`
Validates:
- ✅ Prometheus pod Running and Ready
- ✅ Loki pod Running and Ready
- ✅ Grafana pod Running and Ready
- ✅ Services have endpoints
- ✅ Prometheus can reach targets
- ✅ Loki can receive logs
- ✅ ConfigMaps are valid

**Duration**: 1-2 minutes
**Output**: Pass/Fail report with specific issues

### 7. `./tests/test-sleep-wake-cycle.sh`
**Interactive** - requires confirmation before proceeding

Tests:
1. Records initial cluster state
2. Cordons and drains worker nodes
3. Suspends worker nodes (actual hardware sleep)
4. Sends Wake-on-LAN packets
5. Measures wake time (up to 120s timeout)
6. Validates nodes rejoin cluster
7. Uncordons nodes
8. Verifies all pods return to Running state

**Duration**: 5-10 minutes
**Output**: Pass/Fail with timing metrics

### 8. `./tests/test-complete-validation.sh`
Master validation suite that runs:
- Auto-sleep/wake configuration validation
- Monitoring exporters health checks
- Loki log aggregation validation
- ConfigMap drift prevention checks
- Headless service endpoints validation
- Optional: Sleep/wake cycle test (if confirmed)

**Duration**: 10-15 minutes
**Output**: Comprehensive test report

## Verification Commands

After deployment, verify everything is working:

```bash
# Check cluster nodes
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check monitoring namespace
kubectl get pods -n monitoring
kubectl get svc -n monitoring

# Check infrastructure namespace
kubectl get pods -n infrastructure
kubectl get svc -n infrastructure

# Check node status
kubectl get nodes -o wide

# Check cluster info
kubectl cluster-info
```

## Key Differences from kubeadm

### Advantages of Kubespray
1. **Production-grade**: Used by enterprises worldwide
2. **Flexible**: Easy to customize CNI, runtime, versions
3. **Maintained**: Regular updates from Kubernetes SIG
4. **Standardized**: Industry-standard deployment method
5. **Reliable**: Comprehensive health checks and idempotency

### What's the Same
1. **Commands**: Exact same `./deploy.sh` commands
2. **Configuration**: Same Flannel CNI, same network CIDRs
3. **Features**: All monitoring, infrastructure, auto-sleep features
4. **Tests**: All validation scripts work unchanged

## Troubleshooting

### If deployment fails:

```bash
# Check logs
tail -f ansible/artifacts/deploy-kubespray.log

# Verify Python and Ansible
python3 --version
ansible --version

# Check network connectivity
ansible monitoring_nodes,storage_nodes -i ansible/inventory/hosts.yml -m ping

# Force clean start
rm -rf .cache/kubespray
./deploy.sh reset
./deploy.sh debian
```

### If kubectl doesn't work:

```bash
# Setup kubeconfig
./scripts/setup-kubeconfig.sh

# Or manually set
export KUBECONFIG=~/.kube/config

# Verify
kubectl cluster-info
```

## Log Files

All operations log to `ansible/artifacts/`:
- `deploy-kubespray.log` - Main Kubespray deployment
- `reset-kubespray.log` - Cluster reset
- `deploy-monitoring-stack.log` - Monitoring deployment
- `deploy-infrastructure-services.log` - Infrastructure deployment
- `setup-autosleep.log` - Auto-sleep setup

## Alternative Commands

```bash
# Dry-run to see what would happen
./deploy.sh debian --check

# Auto-yes for non-interactive deployment
./deploy.sh reset --yes
./deploy.sh debian --yes
./deploy.sh monitoring --yes

# Deploy everything at once
./deploy.sh all --with-rke2

# Just the kubespray command
./deploy.sh kubespray  # Same as 'debian'
```

## Expected Timeline

| Step | Duration | Cumulative |
|------|----------|------------|
| git pull | 10s | 10s |
| reset | 2-3m | 3m |
| setup | 1-2m | 5m |
| debian (Kubespray) | 15-20m | 25m |
| monitoring | 5-10m | 35m |
| infrastructure | 3-5m | 40m |
| validate-monitoring-stack.sh | 1-2m | 42m |
| test-sleep-wake-cycle.sh | 5-10m | 52m |
| test-complete-validation.sh | 10-15m | 67m |

**Total**: ~1 hour for complete deployment and validation

## Success Indicators

You'll know everything worked when:

✅ All `kubectl get pods -A` show Running/Completed
✅ All `kubectl get nodes` show Ready
✅ Grafana accessible at http://192.168.4.63:30300
✅ Prometheus accessible at http://192.168.4.63:30090
✅ All validation tests pass
✅ Worker nodes can sleep and wake successfully

## Next Steps

After successful deployment:

1. **Configure Grafana**: 
   - Login to http://192.168.4.63:30300
   - Change default password
   - Explore pre-configured dashboards

2. **Test Sleep/Wake**:
   - Wait for idle period (configured in auto-sleep)
   - Watch nodes automatically sleep
   - Verify Wake-on-LAN brings them back

3. **Monitor the Stack**:
   - Check Prometheus targets
   - View metrics in Grafana
   - Query logs in Loki

4. **Optional - Deploy RKE2**:
   ```bash
   ./deploy.sh rke2
   ```

## That's It!

You now have a production-ready Kubernetes cluster deployed with Kubespray, complete with monitoring, infrastructure services, and automated power management - all using the exact same commands as before.

**Questions?** Check:
- `KUBESPRAY_MIGRATION_SUMMARY.md` - Detailed migration guide
- `README.md` - Project overview
- `docs/ARCHITECTURE.md` - Architecture details
- `docs/USAGE.md` - Complete usage guide
- `docs/TROUBLESHOOTING.md` - Troubleshooting guide

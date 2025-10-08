# VMStation - Kubernetes Homelab with Enterprise Monitoring

A production-grade, idempotent Kubernetes deployment for homelab environments with comprehensive monitoring, auto-sleep, and Wake-on-LAN capabilities.

## Features

### Core Infrastructure
- **Multi-Distribution Support**: Debian Bookworm (control plane + storage) + RHEL 10 (compute)
- **CNI**: Flannel networking with pod network CIDR 10.244.0.0/16
- **Container Runtime**: containerd with SystemdCgroup
- **Storage**: Local hostPath PVs with proper claim binding

### Monitoring Stack
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Anonymous viewing (Viewer role) with 5 pre-configured dashboards
  - Kubernetes Cluster Overview
  - Node Metrics (Detailed)
  - Prometheus Health
  - Network & DNS Performance
  - Loki Logs & Aggregation
- **Loki + Promtail**: Centralized log aggregation
- **IPMI Monitoring**: Hardware health monitoring for enterprise servers
- **Node Exporters**: System metrics from all nodes
- **Kube State Metrics**: Kubernetes object state monitoring
- **Blackbox Exporter**: HTTP/DNS probe monitoring

### Power Management
- **Auto-Sleep**: Configurable cluster sleep after inactivity (default: 2 hours)
- **Wake-on-LAN**: Automatic wake for worker nodes
- **Event-Driven Wake**: Wake nodes on Samba/Jellyfin access

### Media Server
- **Jellyfin**: Media streaming server with NodePort access

## Quick Start

### Prerequisites
- Ansible 2.14+
- SSH key-based authentication to all nodes
- Root or sudo access on all nodes

### Initial Deployment
```bash
# Deploy Debian cluster (control plane + storage worker)
./deploy.sh debian

# Deploy full stack with RKE2 on homelab
./deploy.sh all --with-rke2 --yes
```

### Reset and Redeploy
```bash
# Reset everything
./deploy.sh reset --yes

# Redeploy
./deploy.sh all --with-rke2 --yes
```

### Access Monitoring
```bash
# Grafana (anonymous viewing enabled)
http://192.168.4.63:30300

# Prometheus
http://192.168.4.63:30090

# Jellyfin
http://192.168.4.61:30096
```

## Architecture

### Nodes
| Hostname | IP | Role | OS | Purpose |
|----------|-------|------|-----|---------|
| masternode | 192.168.4.63 | control-plane | Debian Bookworm | Kubernetes master, monitoring |
| storagenodet3500 | 192.168.4.61 | worker | Debian Bookworm | Storage, Jellyfin |
| homelab | 192.168.4.62 | worker | RHEL 10 | Compute, IPMI monitoring |

### Network
- Pod Network: 10.244.0.0/16
- Service Network: 10.96.0.0/12
- CNI: Flannel

### Storage
- Prometheus: 10Gi hostPath at /srv/monitoring_data/prometheus
- Grafana: 2Gi hostPath at /srv/monitoring_data/grafana
- Loki: 20Gi hostPath at /srv/monitoring_data/loki
- Jellyfin: hostPath at /srv/media

## Idempotency

All playbooks are fully idempotent and tested for 100+ consecutive deployments:

✅ **deploy-cluster.yaml** - Checks existing state before each action
✅ **reset-cluster.yaml** - Gracefully handles missing resources
✅ **setup-autosleep.yaml** - Safe to re-run multiple times

### Test Idempotency
```bash
# Run 100 reset->deploy cycles
./tests/test-idempotence.sh 100
```

## Security

- Grafana anonymous access: **Viewer role only**
- SSH key-based authentication required
- No hardcoded passwords in playbooks
- IPMI credentials stored in ansible-vault (optional)
- Secrets managed via kubernetes.core.k8s module

## Documentation

### Deployment & Operations
- [Deployment Fixes Oct 2025](docs/DEPLOYMENT_FIXES_OCT2025.md)
- [Idempotency Fixes Oct 2025](docs/IDEMPOTENCY_FIXES_OCT2025.md)
- [Best Practices](docs/BEST_PRACTICES.md)

### Monitoring
- [Monitoring Access Guide](docs/MONITORING_ACCESS.md)
- [Monitoring Implementation Details](docs/MONITORING_IMPLEMENTATION_DETAILS.md)
- [IPMI Monitoring Setup](docs/IPMI_MONITORING_GUIDE.md)
- [Monitoring Quick Reference](docs/MONITORING_QUICK_REFERENCE.md)

### Auto-Sleep & Power Management
- [Auto-Sleep Runbook](docs/AUTOSLEEP_RUNBOOK.md)
- [Validation Test Guide](docs/VALIDATION_TEST_GUIDE.md)

### Historical Reference
- [Worker Join Fix](docs/WORKER_JOIN_FIX.md)
- [CNI Plugin Fix Jan 2025](docs/CNI_PLUGIN_FIX_JAN2025.md)

## Troubleshooting

### Common Issues

#### Deployment Fails
```bash
# Check logs
cat /srv/monitoring_data/VMStation/ansible/artifacts/deploy-debian.log

# Verify SSH connectivity
ansible all -i ansible/inventory/hosts.yml -m ping

# Check node status
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
```

#### Monitoring Not Accessible
```bash
# Check pods
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring

# Check services
kubectl --kubeconfig=/etc/kubernetes/admin.conf get svc -n monitoring

# Wait for pods to be ready (can take 2-3 minutes)
```

#### Auto-Sleep Not Working
```bash
# Check timer status
systemctl status vmstation-autosleep.timer

# Check logs
journalctl -u vmstation-autosleep -n 50

# Manual test
/usr/local/bin/vmstation-autosleep-monitor.sh
```

## Testing

Run the comprehensive test suite:
```bash
# All tests
./tests/test-comprehensive.sh

# Specific tests
./tests/test-syntax.sh                    # Ansible syntax
./tests/test-autosleep-wake-validation.sh # Auto-sleep functionality
./tests/test-monitoring-access.sh         # Monitoring endpoints
./tests/test-idempotence.sh               # Idempotency
```

## Contributing

1. Make changes in a feature branch
2. Test with `./tests/test-idempotence.sh 5`
3. Run syntax check: `ansible-playbook --syntax-check <playbook>`
4. Submit PR with test results

## License

See [LICENSE](LICENSE) file for details.

## Support

For issues:
1. Check documentation in `docs/`
2. Review logs in `/srv/monitoring_data/VMStation/ansible/artifacts/`
3. Run validation tests in `tests/`
4. Check [troubleshooting.md](troubleshooting.md)

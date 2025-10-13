# VMStation

A homelab Kubernetes environment with automated deployment, monitoring, and power management.

## Overview

VMStation provides a production-ready Kubernetes setup using **Kubespray** for deployment automation.

- **Primary Deployment**: Kubespray - Production-grade Kubernetes deployment
- **Legacy Option**: kubeadm (Debian nodes) - Deprecated but supported
- **Monitoring**: Prometheus, Grafana, Loki, exporters
- **Power Management**: Wake-on-LAN, auto-sleep
- **Infrastructure**: NTP/Chrony, Syslog, Kerberos (optional)

## Quick Start

```bash
# Clone repository
git clone https://github.com/JashandeepJustinBains/VMStation.git
cd VMStation

# Deploy full stack with Kubespray (RECOMMENDED)
./deploy.sh reset
./deploy.sh setup
./deploy.sh kubespray  # Deploys cluster + monitoring + infrastructure

# Validate deployment
./scripts/validate-monitoring-stack.sh
./tests/test-complete-validation.sh
```

## Alternative Quick Start (Legacy Debian-only)

```bash
# Deploy to Debian nodes only (deprecated)
./deploy.sh reset
./deploy.sh setup
./deploy.sh debian
./deploy.sh monitoring
./deploy.sh infrastructure

# Validate deployment
./scripts/validate-monitoring-stack.sh
./tests/test-complete-validation.sh
```

## Features

### 🚀 Automated Deployment
- **Kubespray Integration** - Production-grade Kubernetes deployment
- **Idempotent Ansible playbooks** - Safe to run multiple times
- **Single command deployment** - `./deploy.sh kubespray` for complete stack
- **Pre-flight checks** - Validates requirements before deployment
- **Multi-cluster support** - Debian (kubeadm) + RHEL10 (Kubespray)

### 📊 Complete Monitoring Stack
- **Prometheus** - Metrics collection and alerting
- **Grafana** - Dashboards and visualization
- **Loki** - Log aggregation
- **Node Exporter** - System metrics (CPU, memory, disk)
- **IPMI Exporter** - Hardware monitoring (optional)
- **Blackbox Exporter** - HTTP/DNS probes

**Access**: 
- Grafana: http://192.168.4.63:30300
- Prometheus: http://192.168.4.63:30090

### ⚡ Wake-on-LAN Power Management
- **Auto-sleep** - Automatically sleep idle worker nodes
- **Wake-on-LAN** - Remote wake via magic packets
- **State tracking** - Monitor suspend/wake cycles
- **Energy savings** - Reduce power consumption during idle periods

### 🔧 Infrastructure Services
- **NTP/Chrony** - Cluster-wide time synchronization
- **Syslog Server** - Centralized logging
- **Kerberos/FreeIPA** - SSO and identity management (optional)

### 🎯 Deployment Options

1. **Kubespray (RECOMMENDED)** - Production-grade Kubernetes deployment for all nodes
2. **Debian kubeadm (LEGACY)** - kubeadm deployment to Debian nodes only

> **Migration Notice**: RKE2 deployment has been deprecated and replaced by Kubespray. See [docs/MIGRATION.md](docs/MIGRATION.md) for details.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Kubernetes Cluster (Kubespray)                      │
├─────────────────────────────────────────────────────┤
│ masternode (192.168.4.63) - Control Plane           │
│   - Kubernetes API Server                            │
│   - Monitoring Stack (Prometheus, Grafana, Loki)    │
│   - Always-on                                        │
├─────────────────────────────────────────────────────┤
│ storagenodet3500 (192.168.4.61) - Worker            │
│   - Jellyfin (media streaming)                       │
│   - Storage workloads                                │
│   - Auto-sleep enabled                               │
├─────────────────────────────────────────────────────┤
│ homelab (192.168.4.62) - Worker (RHEL10)            │
│   - General compute workloads                        │
│   - Node Exporter                                    │
│   - Auto-sleep enabled                               │
└─────────────────────────────────────────────────────┘
```

**Deployment Methods**:
- **Kubespray** (default): All nodes via Kubespray cluster.yml
- **kubeadm** (legacy): Debian nodes only (monitoring + storage)

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed architecture and [docs/MIGRATION.md](docs/MIGRATION.md) for Kubespray migration details.

## Node Specifications

| Node | IP | OS | Role | Auto-Sleep |
|------|----|----|------|------------|
| masternode | 192.168.4.63 | Debian 12 | Control Plane | ❌ Always-on |
| storagenodet3500 | 192.168.4.61 | Debian 12 | Worker, Storage | ✅ Yes |
| homelab | 192.168.4.62 | RHEL 10 | Compute | ✅ Yes |

## Deployment Options

### Option 1: Full Kubespray Deployment (RECOMMENDED)

```bash
./deploy.sh reset
./deploy.sh setup
./deploy.sh kubespray  # Deploys cluster + monitoring + infrastructure
```

### Option 2: Legacy Debian-only Deployment

```bash
./deploy.sh reset
./deploy.sh setup
./deploy.sh debian
./deploy.sh monitoring
./deploy.sh infrastructure
```

## Documentation
./deploy.sh reset
./deploy.sh setup
./deploy.sh debian
./deploy.sh monitoring
./deploy.sh infrastructure

# Prepare RHEL10 node
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/run-preflight-rhel10.yml

# Stage and deploy Kubespray
./scripts/run-kubespray.sh
# Follow on-screen instructions
```

See [docs/USAGE.md](docs/USAGE.md) for complete deployment guide.

## Commands Reference

### Deployment

```bash
./deploy.sh kubespray       # Deploy Kubespray cluster (RECOMMENDED)
./deploy.sh debian          # Deploy Debian cluster (LEGACY)
./deploy.sh monitoring      # Deploy monitoring stack
./deploy.sh infrastructure  # Deploy infrastructure services
./deploy.sh setup           # Setup auto-sleep monitoring
./deploy.sh reset           # Reset cluster
```

### Validation

```bash
./scripts/validate-monitoring-stack.sh     # Validate monitoring
./tests/test-complete-validation.sh        # Complete validation suite
./tests/test-sleep-wake-cycle.sh           # Test sleep/wake cycle
```

### Diagnostics

```bash
./scripts/diagnose-monitoring-stack.sh     # Diagnose monitoring issues
./scripts/remediate-monitoring-stack.sh    # Fix common problems
./scripts/vmstation-collect-wake-logs.sh   # Collect wake logs
```

### Kubespray

```bash
./scripts/run-kubespray.sh                 # Stage Kubespray
ansible-playbook ... run-preflight-rhel10.yml  # Preflight checks
```

## Monitoring Access

| Service | URL | Purpose |
|---------|-----|---------|
| Grafana | http://192.168.4.63:30300 | Dashboards |
| Prometheus | http://192.168.4.63:30090 | Metrics |
| Loki | http://192.168.4.63:31100 | Logs |

**Default Grafana credentials**: admin/admin (change on first login)

## Testing and Validation

### Automated Tests

```bash
# Pre-deployment checks
./tests/pre-deployment-checklist.sh

# Complete validation (recommended)
./tests/test-complete-validation.sh

# Individual tests
./tests/test-autosleep-wake-validation.sh
./tests/test-monitoring-exporters-health.sh
./tests/test-loki-validation.sh
./tests/test-monitoring-access.sh
```

### Idempotency Testing

```bash
# Test deployment idempotency (3 cycles)
./tests/test-idempotence.sh 3
```

## Troubleshooting

### Quick Diagnostics

```bash
# Check cluster status
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A

# Validate monitoring
./scripts/validate-monitoring-stack.sh

# Run complete validation
./tests/test-complete-validation.sh
```

### Common Issues

**Monitoring stack not working**:
```bash
./scripts/diagnose-monitoring-stack.sh
./scripts/remediate-monitoring-stack.sh
```

**Loki CrashLoopBackOff**:
```bash
# Check permissions
sudo chown -R 10001:10001 /srv/monitoring_data/loki

# Redeploy
./deploy.sh monitoring
```

**Node not Ready**:
```bash
# Check kubelet
systemctl status kubelet
journalctl -xeu kubelet

# Uncordon if cordoned
kubectl --kubeconfig=/etc/kubernetes/admin.conf uncordon <node>
```

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for detailed troubleshooting.

## Documentation

- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Complete architecture documentation
- **[USAGE.md](docs/USAGE.md)** - Deployment and usage guide
- **[TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** - Troubleshooting guide
- **[DEPLOYMENT_RUNBOOK.md](docs/DEPLOYMENT_RUNBOOK.md)** - Step-by-step deployment
- **[TODO.md](TODO.md)** - Project roadmap and tasks

## Repository Structure

```
VMStation/
├── deploy.sh                       # Main deployment script
├── ansible/
│   ├── inventory/hosts.yml         # Cluster inventory
│   ├── playbooks/                  # Ansible playbooks
│   └── roles/
│       └── preflight-rhel10/       # RHEL10 preflight checks (NEW)
├── scripts/
│   ├── run-kubespray.sh            # Kubespray wrapper (NEW)
│   ├── validate-monitoring-stack.sh
│   ├── diagnose-monitoring-stack.sh
│   └── vmstation-event-wake.sh     # Wake-on-LAN handler
├── tests/
│   ├── test-complete-validation.sh
│   ├── test-sleep-wake-cycle.sh
│   └── ...
├── docs/
│   ├── ARCHITECTURE.md             # Architecture guide (NEW)
│   ├── USAGE.md                    # Usage guide (NEW)
│   ├── TROUBLESHOOTING.md          # Troubleshooting (NEW)
│   └── ...
└── manifests/
    └── monitoring/                 # Monitoring manifests
```

## Requirements

### Hardware

- **masternode**: 4 CPU, 8GB RAM, 100GB disk (always-on)
- **storagenodet3500**: 4 CPU, 8GB RAM, 500GB+ disk (auto-sleep)
- **homelab**: 4 CPU, 8GB RAM, 100GB disk (auto-sleep)

### Software

- **Debian nodes**: Debian 12 (Bookworm)
- **RHEL node**: RHEL 10 or compatible
- **Network**: All nodes on same subnet, Wake-on-LAN enabled

### Tools

- Ansible 2.9+
- Python 3.8+
- SSH access to all nodes

## Contributing

This is a personal homelab project, but suggestions and improvements are welcome!

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Roadmap

See [TODO.md](TODO.md) for current tasks and future plans:

- [ ] High availability for monitoring stack
- [ ] GitOps with ArgoCD/Flux
- [ ] External secrets operator
- [ ] Automated backup and DR
- [ ] Service mesh (Istio/Linkerd)

## License

See [LICENSE](LICENSE) file.

## Acknowledgments

- **Kubernetes** - Container orchestration
- **RKE2** - Rancher Kubernetes Engine
- **Kubespray** - Production-ready Kubernetes deployment
- **Prometheus** & **Grafana** - Monitoring and visualization
- **Loki** - Log aggregation
- **Ansible** - Automation

## Support

For issues and questions:

1. Check [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
2. Run automated diagnostics
3. Review deployment logs in `ansible/artifacts/`
4. Open an issue on GitHub

---

**VMStation** - A production-ready homelab Kubernetes environment

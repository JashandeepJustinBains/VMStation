# VMStation

A homelab Kubernetes environment with automated deployment, monitoring, and power management.

## Overview

VMStation provides a production-ready Kubernetes setup using a two-cluster architecture:

- **Debian Cluster** (Kubespray): Production workloads, storage, monitoring
- **RKE2 Cluster** (RHEL10): Compute, testing, optional federation

## Quick Start

```bash
# Clone repository
git clone https://github.com/JashandeepJustinBains/VMStation.git
cd VMStation

# Deploy Debian cluster with Kubespray
./deploy.sh reset
./deploy.sh setup
./deploy.sh debian

# Deploy monitoring stack
./deploy.sh monitoring

# Deploy infrastructure services
./deploy.sh infrastructure

# Validate deployment
./scripts/validate-monitoring-stack.sh
./tests/test-complete-validation.sh
```

## Features

### 🚀 Automated Deployment
- **Idempotent Ansible playbooks** - Safe to run multiple times
- **Single command deployment** - `./deploy.sh` wrapper script
- **Pre-flight checks** - Validates requirements before deployment
- **Multi-cluster support** - Debian (Kubespray) + RHEL10 (RKE2)

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

### 🎯 Three Deployment Options

1. **Kubespray (Debian nodes)** - Recommended for production, flexible and battle-tested
2. **RKE2 (RHEL10)** - Simple, batteries-included Kubernetes for RHEL
3. **Legacy kubeadm (deprecated)** - Original deployment method, use Kubespray instead

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Debian Cluster (Kubespray)                          │
├─────────────────────────────────────────────────────┤
│ masternode (192.168.4.63)                           │
│   - Control Plane                                    │
│   - Monitoring Stack (Prometheus, Grafana, Loki)    │
│   - Always-on                                        │
├─────────────────────────────────────────────────────┤
│ storagenodet3500 (192.168.4.61)                     │
│   - Worker Node                                      │
│   - Jellyfin (media streaming)                       │
│   - Auto-sleep enabled                               │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ RKE2 Cluster (RHEL10)                               │
├─────────────────────────────────────────────────────┤
│ homelab (192.168.4.62)                              │
│   - Single-node cluster                              │
│   - Node Exporter                                    │
│   - Optional: Prometheus federation                  │
│   - Auto-sleep enabled                               │
└─────────────────────────────────────────────────────┘
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed architecture.

## Node Specifications

| Node | IP | OS | Role | Auto-Sleep |
|------|----|----|------|------------|
| masternode | 192.168.4.63 | Debian 12 | Control Plane | ❌ Always-on |
| storagenodet3500 | 192.168.4.61 | Debian 12 | Worker, Storage | ✅ Yes |
| homelab | 192.168.4.62 | RHEL 10 | Compute | ✅ Yes |

## Deployment Options

### Option 1: Kubespray Cluster Only (Recommended)

```bash
./deploy.sh reset
./deploy.sh setup
./deploy.sh debian          # Now uses Kubespray
./deploy.sh monitoring
./deploy.sh infrastructure
```

### Option 2: Kubespray + RKE2

```bash
./deploy.sh reset
./deploy.sh setup
./deploy.sh debian          # Kubespray on Debian nodes
./deploy.sh monitoring
./deploy.sh infrastructure
./deploy.sh rke2            # RKE2 on RHEL10 node
```

### Option 3: Legacy Kubespray Manual Setup

```bash
# Prepare RHEL10 node
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/run-preflight-rhel10.yml

# Stage and manually deploy Kubespray
./scripts/run-kubespray.sh
# Follow on-screen instructions
```

See [docs/USAGE.md](docs/USAGE.md) for complete deployment guide.

## Commands Reference

### Deployment

```bash
./deploy.sh debian          # Deploy Kubespray cluster on Debian nodes
./deploy.sh kubespray       # Same as 'debian' - Deploy Kubespray cluster
./deploy.sh rke2            # Deploy RKE2 cluster (RHEL10)
./deploy.sh monitoring      # Deploy monitoring stack
./deploy.sh infrastructure  # Deploy infrastructure services
./deploy.sh setup           # Setup auto-sleep monitoring
./deploy.sh reset           # Reset all clusters
./deploy.sh all --with-rke2 # Deploy everything
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

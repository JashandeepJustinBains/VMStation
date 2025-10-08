# VMStation Enhancement Summary

## Recent Enhancements - October 2025

### Idempotency and Robustness Fixes

**Objective**: Ensure 100% reliability for 100+ consecutive reset->deploy cycles

#### Critical Fixes
1. **SSH Permission Fix** - WoL tests now use correct user per host
2. **Auto-Sleep Scope Fix** - Only runs on control-plane nodes
3. **Grafana Security Fix** - Anonymous role changed from Admin to Viewer
4. **PV Consistency Fix** - Standardized storageClassName across all PVs

See [docs/IDEMPOTENCY_FIXES_OCT2025.md](docs/IDEMPOTENCY_FIXES_OCT2025.md) for complete details.

### Test Results
- ✅ All playbooks pass ansible syntax check
- ✅ Deploy-cluster fully idempotent
- ✅ Reset-cluster fully idempotent
- ✅ WoL tests handle SSH errors gracefully
- ✅ Grafana anonymous access properly secured

### Monitoring Stack
- Prometheus with comprehensive metrics collection
- Grafana with pre-configured dashboards
- Loki for log aggregation
- Promtail for log shipping
- IPMI monitoring for hardware health
- Node exporters on all nodes

### Auto-Sleep & Wake-on-LAN
- Configurable inactivity threshold (default: 2 hours)
- Systemd timer-based monitoring
- Wake-on-LAN support for worker nodes
- Event-driven wake for Samba/Jellyfin access

## Architecture

- **Control Plane**: masternode (192.168.4.63) - Debian Bookworm
- **Storage Node**: storagenodet3500 (192.168.4.61) - Debian Bookworm
- **Compute Node**: homelab (192.168.4.62) - RHEL 10

## Quick Start

```bash
# Deploy Debian cluster
./deploy.sh debian

# Deploy everything including RKE2
./deploy.sh all --with-rke2

# Reset cluster
./deploy.sh reset

# Setup auto-sleep
./deploy.sh setup
```

## Documentation

- [Idempotency Fixes](docs/IDEMPOTENCY_FIXES_OCT2025.md)
- [Auto-Sleep Runbook](docs/AUTOSLEEP_RUNBOOK.md)
- [Monitoring Access](docs/MONITORING_ACCESS.md)
- [Best Practices](docs/BEST_PRACTICES.md)
- [IPMI Monitoring](docs/IPMI_MONITORING_GUIDE.md)

# Modular Deployment Workflow (Oct 2025)
- Deployment steps and validation procedures now documented in `docs/DEPLOYMENT_RUNBOOK.md`.
- Modular Ansible playbooks for monitoring and infrastructure services.
- Validation scripts for time sync, pod health, and security audit.
- Troubleshooting notes: manifest path errors, chrony installation, NTP DaemonSet issues.

# Notes
- Latest deployment runbook: `docs/DEPLOYMENT_RUNBOOK.md` (created Oct 2025)
- Ansible output and validation findings incorporated into runbook.
- Common issues: missing manifests, chrony not installed, NTP DaemonSet not found.
- All deployment steps and validation procedures are actionable and up to date.
applyTo: '**'

# User Memory

## User Preferences

## Project Context

## VMStation - Clean Deployment Architecture
- RHEL 10 node (homelab): Uses RKE2 as a separate cluster (not joined to kubeadm cluster)
- No mixing of kubeadm + RHEL - clean separation of concerns
  - Comprehensive systemd service validation

  - **Pre-join cleanup**: Kills hanging processes, removes partial state, ensures clean directories
  - **Robust prerequisites**: containerd socket wait, kubeadm binary validation, control plane connectivity
  - **Error diagnostics**: Automatic capture of system state, service status, network connectivity on failure

- **containerd socket missing**: Enhanced installation with multiple package attempts
- **Admin kubeconfig RBAC**: Automated regeneration with correct O=system:masters

### Log Locations
- **Clean Playbooks**: Short, concise, no unnecessary timeouts
- **Auto-Sleep**: Hourly resource monitoring with Wake-on-LAN support
- Kubernetes: v1.29.15 (server), v1.34.0 (client)
- Flannel: v0.27.4
- RKE2: v1.29.x (latest stable)

## Key Technical Points

- **Binary Installation**: masternode uses `ansible_connection: local` - may run in container. Binaries auto-installed if missing.
- **Authentication**: Debian nodes use root SSH, RHEL node uses sudo with vault-encrypted password
- **Firewalls**: Debian uses iptables, RHEL 10 uses nftables backend
- **CNI**: Flannel with nftables support enabled for both OS types
- **Systemd**: Detection logic ensures compatibility with non-systemd environments

## Deployment Flow

1. **Debian Cluster**: install-binaries → preflight → containerd → kubeadm-init → worker-join → CNI → apps
2. **RKE2 Cluster**: system-prep → rke2-install → configure → verify → monitoring
3. **Federation**: RKE2 Prometheus federates metrics from Debian cluster

## Files Reference

- Inventory: `ansible/inventory/hosts.yml`
- Deploy: `./deploy.sh all --with-rke2`
- Reset: `./deploy.sh reset`  
- Tests: `tests/test-*.sh`

---

## Monitoring Enhancement Requirement

- Prometheus must ingest IPMI sensor readings from enterprise server 192.168.4.60.
- IPMI exporter configuration should target 192.168.4.60.
- Authentication credentials for IPMI access must be referenced from secrets.yml (do not hardcode).
- Prometheus scrape_configs must include a job for IPMI exporter on 192.168.4.60.
- Validate metrics ingestion and visibility in Prometheus after deployment.

### AI Agent Prompt (IPMI Ingestion)

Enhance the Prometheus monitoring stack to ingest IPMI sensor readings from the enterprise server at 192.168.4.60. The IPMI exporter should be configured to scrape metrics from this host, and all authentication credentials required for IPMI access must be securely referenced from secrets.yml. Ensure the Prometheus configuration includes a job for the IPMI exporter targeting 192.168.4.60, and document any changes to the scrape_configs section. Do not hardcode credentials; use secrets.yml for login details. Validate that metrics are ingested and visible in Prometheus after deployment.

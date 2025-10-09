# Modular Deployment Workflow (Oct 2025)
- Simplified deployment commands via `deploy.sh`:
  - `./deploy.sh debian` - Deploy Kubernetes cluster
  - `./deploy.sh monitoring` - Deploy monitoring stack (Prometheus, Grafana, Loki)
  - `./deploy.sh infrastructure` - Deploy infrastructure services (NTP, Syslog, Kerberos)
  - `./deploy.sh setup` - Setup auto-sleep monitoring
  - `./deploy.sh rke2` - Deploy RKE2 on homelab (optional)
- Complete workflow documented in `docs/DEPLOYMENT_RUNBOOK.md`
- Validation scripts for time sync, pod health, and security audit
- Dry-run mode available with `--check` flag

# Notes
- Latest deployment runbook: `docs/DEPLOYMENT_RUNBOOK.md` (created Oct 2025)
- Ansible output and validation findings incorporated into runbook.
- Common issues: missing manifests, chrony not installed, NTP DaemonSet not found.
- All deployment steps and validation procedures are actionable and up to date.

## Deployment Fixes (October 2025 - Part 2)

### Critical Issues Resolved
1. **Prometheus CrashLoopBackOff**: Permission denied on `/prometheus/lock`
   - Root Cause: Modular playbook `deploy-monitoring-stack.yaml` created directories with root:root ownership
   - Fix: Updated directory creation to use proper UIDs (65534 for Prometheus, 10001 for Loki, 472 for Grafana)
   - File: `ansible/playbooks/deploy-monitoring-stack.yaml`

2. **Loki Startup Failures**: HTTP 503 errors, permission denied on `/loki`
   - Root Cause: Same ownership issue + insufficient startup probe timeout for WAL recovery
   - Fix: Proper ownership + increased startup probe failureThreshold from 30 to 60 (10 minutes)
   - File: `manifests/monitoring/loki.yaml`

3. **Grafana DNS Resolution Errors**: `lookup loki on 10.96.0.10:53: no such host`
   - Root Cause: Headless services (ClusterIP: None) require FQDN for DNS resolution
   - Fix: Changed datasource URLs from short names to FQDNs (e.g., `prometheus.monitoring.svc.cluster.local:9090`)
   - File: `manifests/monitoring/grafana.yaml`

### Quick Fix Script
- Created `scripts/fix-monitoring-permissions.sh` for immediate resolution of existing deployments
- Fixes ownership, deletes/recreates pods, waits for readiness
- Usage: `./scripts/fix-monitoring-permissions.sh`

### Documentation
- **User Guide**: `DEPLOYMENT_ISSUE_RESOLUTION_SUMMARY.md` (repository root)
- **Technical Analysis**: `docs/DEPLOYMENT_FIXES_OCT2025_PART2.md`
- **Updated Runbook**: `docs/DEPLOYMENT_RUNBOOK.md` with troubleshooting section

### Lessons Learned
- Modular playbooks must maintain parity with original deploy-cluster.yaml for critical settings
- Headless Kubernetes services always require FQDN DNS resolution
- Container UIDs must match directory ownership: Prometheus (65534), Loki (10001), Grafana (472)
- Loki WAL recovery can take 5+ minutes; plan probe timeouts accordingly

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

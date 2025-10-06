---
applyTo: '**'
---

# User Memory

## User Preferences
- Programming languages: Ansible YAML, shell scripting, Kubernetes manifests
- Code style preferences: Clean, idempotent, well-documented automation
- Development environment: Windows 11 development, Linux Kubernetes target environment
- Communication style: Direct, technical, no emojis, comprehensive solutions

## Project Context
- Current project type: Kubernetes homelab deployment automation
- Tech stack: Ansible, kubeadm, containerd, Flannel CNI, RKE2
- Architecture patterns: Two-phase deployment (Debian nodes with kubeadm, RHEL nodes with RKE2)
- Key requirements: Idempotent, robust, automated deployment without manual intervention

## VMStation - Clean Deployment Architecture

**Current Approach (Post-Revamp)**:
- Debian nodes (masternode, storagenodet3500): Use kubeadm for Kubernetes v1.29.x
- RHEL 10 node (homelab): Uses RKE2 as a separate cluster (not joined to kubeadm cluster)
- No mixing of kubeadm + RHEL - clean separation of concerns

Previous RHEL Kubernetes integration issues have been archived. See `archive/legacy-docs/` for historical context.

## Infrastructure

**masternode (192.168.4.63)**:
- OS: Debian Bookworm
- Role: Kubernetes control-plane (kubeadm)
- Services: Monitoring dashboards, log/metrics ingestion
- Always-on for network services

**storagenodet3500 (192.168.4.61)**:
- OS: Debian Bookworm  
- Role: Kubernetes worker (kubeadm)
- Services: Jellyfin streaming, SAMBA storage
- Minimal pod scheduling for bandwidth optimization

**homelab (192.168.4.62)**:
- OS: RHEL 10
- Role: RKE2 single-node cluster
- Services: Compute workloads, VM testing, monitoring federation
- Uses RKE2 (not kubeadm)

## Recent Major Fixes Applied

### Enhanced install-k8s-binaries Role
- Location: `ansible/roles/install-k8s-binaries/tasks/main.yml`
- Improvements:
  - Robust containerd installation with multiple package attempts (containerd.io, containerd)
  - Unit file validation and reinstall logic if service missing
  - Removed RHEL/CentOS installation block (RKE2 handles those nodes)
  - Added admin kubeconfig regeneration with proper RBAC (O=system:masters)
  - Comprehensive systemd service validation

### Comprehensive Worker Join Implementation
- Location: `ansible/playbooks/deploy-cluster.yaml` Phase 4
- Features:
  - **Idempotent behavior**: Checks existing join status, skips if already joined
  - **Pre-join cleanup**: Kills hanging processes, removes partial state, ensures clean directories
  - **Robust prerequisites**: containerd socket wait, kubeadm binary validation, control plane connectivity
  - **Retry logic**: 3 attempts with 30-second delays for join operations
  - **Comprehensive logging**: Detailed logs to `/var/log/kubeadm-join.log` and failure diagnostics
  - **Health validation**: kubelet service start, config file existence, service health checks
  - **Error diagnostics**: Automatic capture of system state, service status, network connectivity on failure

## Troubleshooting Knowledge Base

### Common Issues Resolved
- **containerd socket missing**: Enhanced installation with multiple package attempts
- **Admin kubeconfig RBAC**: Automated regeneration with correct O=system:masters
- **Worker join hanging**: Comprehensive cleanup, retry logic, process management
- **kubelet crash-loop**: Proper config file validation and service health checks
- **Partial join state**: Thorough cleanup of artifacts before retry attempts

### Log Locations
- Join success: `/var/log/kubeadm-join.log`
- Join failure diagnostics: `/var/log/kubeadm-join-failure.log`
- System logs: `journalctl -u kubelet` and `journalctl -u containerd`

## Deployment Requirements

- **Idempotency**: `deploy.sh` → `deploy.sh reset` → `deploy.sh` must work 100 times in a row with zero failures
- **OS Awareness**: Debian Bookworm (iptables) vs RHEL 10 (nftables) handled correctly
- **No Post-Deployment Fixes**: All pods (kube-proxy, flannel, coredns) must work on first deployment
- **Clean Playbooks**: Short, concise, no unnecessary timeouts
- **Auto-Sleep**: Hourly resource monitoring with Wake-on-LAN support

## Software Versions

- Ansible: core 2.14.18+ (Python 3.11+)
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

See `archive/legacy-docs/` for historical troubleshooting notes and prior implementation details.

---
title: VMStation Modular Deployment Runbook
date: 2025-10-09
---

# VMStation Modular Deployment Runbook

## Overview
This document provides step-by-step instructions for deploying the VMStation monitoring and infrastructure stack using modular Ansible playbooks and validation scripts. It incorporates recent findings and troubleshooting notes from deployment output and the TODO checklist.

## Prerequisites
- Ensure all required manifests exist in `manifests/monitoring/` and `manifests/infrastructure/`.
- Verify Ansible inventory and playbooks are up to date.
- Confirm system time sync and chrony installation on all nodes.

## Deployment Steps

### 1. Preparation
```
clear
git pull
./tests/pre-deployment-checklist.sh
./deploy.sh reset
```
**Purpose of `deploy.sh reset`:**
Resets the cluster state by cleaning up previous deployments, removing partial or failed resources, and ensuring all directories and services are in a clean state before redeployment. This step is critical for avoiding configuration drift and deployment errors.

### 2. Deploy Monitoring Stack
```
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/deploy-monitoring-stack.yaml
```
- Components: Prometheus, Grafana, Loki, Promtail, Kube-state-metrics, Node-exporter, Blackbox-exporter, IPMI-exporter
- Troubleshooting:
  - If you see `error: the path .../prometheus.yaml does not exist`, verify the manifest location and filename.
  - Ensure `/srv/monitoring_data/loki` exists and is owned by UID 10001 (Loki).

### 3. Deploy Infrastructure Services
```
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/deploy-infrastructure-services.yaml
```
- Services: NTP/Chrony, Syslog Server, FreeIPA/Kerberos
- Troubleshooting:
  - If you see `error: the path .../chrony-ntp.yaml does not exist`, verify the manifest location and filename.
  - If `chrony` is not installed on control plane, install it and configure time sync.

### 4. Validate Time Sync
```
./tests/validate-time-sync.sh
```
- Ensure NTP DaemonSet is present and pod count matches node count.
- If NTP pods are missing, check DaemonSet manifest and node selectors.
- If chrony is not installed, install and configure on all nodes.

### 5. Deploy with Enhancements
```
./deploy.sh all --with-rke2 --yes
```
**Purpose of `deploy.sh all --with-rke2 --yes`:**
Performs a full deployment of the VMStation stack spliting the deployment into 2 stages 1: the debian bookworm nodes masternode (always on kubernetes control-plane + NTP server + Kerberos server + DNS server + monitoring stack) as well as the storagenodet3500 which hosts the jellyfin server and media files. Stage 2 is to deploy the homelab compute node which needs to run RKE2 Kubernetes cluster due to RHEL10 not allowing regular kubernetes setup. The `--with-rke2` flag ensures the RKE2 cluster is included, and `--yes` auto-confirms all prompts for a non-interactive, streamlined deployment. This step provisions all required services and applies the latest configuration and monitoring improvements.

### 6. Setup Auto-Sleep
```
./deploy.sh setup
```

### 7. Run Security Audit
```
./tests/test-security-audit.sh
```

### 8. Run Complete Validation Suite
```
./tests/test-complete-validation.sh
```

### 9. Run Individual Tests
```
./tests/test-monitoring-exporters-health.sh
./tests/test-deployment-fixes.sh
```

## Common Issues & Fixes
- **Manifest Not Found:** Ensure all referenced manifests exist and paths are correct.
- **Chrony Not Installed:** Install chrony on control plane and all nodes, then re-run validation.
- **NTP DaemonSet Missing:** Check manifest and node selectors; ensure correct namespace.
- **Pod Permission Errors:** Verify PVC/hostPath ownership and permissions.

## Validation Checklist
- [ ] All monitoring and infrastructure pods are running
- [ ] Time sync validated (chrony installed, NTP DaemonSet healthy)
- [ ] Security audit passes
- [ ] All dashboards show expected data
- [ ] Prometheus targets are up

## Troubleshooting References
- See `docs/MONITORING_STACK_FIXES_OCT2025.md` for recent fixes
- See `docs/VALIDATION_IMPLEMENTATION_SUMMARY.md` for validation procedures
- See `docs/IDM_DEPLOYMENT.md` for FreeIPA/Kerberos deployment

---
For further debugging, use `kubectl cluster-info dump` and check Ansible playbook logs for error details.

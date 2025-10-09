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
```bash
clear
git pull
./tests/pre-deployment-checklist.sh
./deploy.sh reset
```
**Purpose of `deploy.sh reset`:**
Resets the cluster state by cleaning up previous deployments, removing partial or failed resources, and ensuring all directories and services are in a clean state before redeployment. This step is critical for avoiding configuration drift and deployment errors.

### 2. Deploy Debian Cluster
```bash
./deploy.sh debian
```
**Purpose:** Deploys the core Kubernetes cluster (kubeadm) on Debian nodes (masternode + storagenodet3500). This includes Phases 0-6 from the deployment playbook: system preparation, control plane initialization, CNI deployment, worker node join, and cluster validation.

**Components:**
- Kubernetes control plane (API server, controller manager, scheduler, etcd)
- Flannel CNI networking
- Worker nodes joined to cluster
- Basic cluster validation

**Troubleshooting:**
- If deployment fails, check logs at `ansible/artifacts/deploy-debian.log`
- Verify nodes are ready: `kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes`

### 3. Deploy Monitoring Stack
```bash
./deploy.sh monitoring
```
**Purpose:** Deploys the complete monitoring and observability stack.

**Components:**
- Prometheus (metrics time-series database)
- Grafana (dashboards and visualization)
- Loki (log aggregation)
- Promtail (log shipper)
- Kube-state-metrics (K8s object metrics)
- Node-exporter (system metrics)
- Blackbox-exporter (probes)
- IPMI-exporter (hardware monitoring)

**Access URLs (assuming masternode at 192.168.4.63):**
- Prometheus: http://192.168.4.63:30090
- Grafana: http://192.168.4.63:30300
- Loki: http://192.168.4.63:31100

**Troubleshooting:**
- Check logs at `ansible/artifacts/deploy-monitoring-stack.log`
- Verify pods: `kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring`
- If you see `error: the path .../prometheus.yaml does not exist`, verify the manifest location and filename.
- Ensure `/srv/monitoring_data/loki` exists and is owned by UID 10001 (Loki).

### 4. Deploy Infrastructure Services
```bash
./deploy.sh infrastructure
```
**Purpose:** Deploys core infrastructure services for enterprise operations.

**Services:**
- NTP/Chrony (cluster-wide time synchronization)
- Syslog Server (centralized log aggregation from external devices)
- FreeIPA/Kerberos (identity management and SSO - optional)

**Troubleshooting:**
- Check logs at `ansible/artifacts/deploy-infrastructure-services.log`
- Verify pods: `kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n infrastructure`
- If you see `error: the path .../chrony-ntp.yaml does not exist`, verify the manifest location and filename.
- If `chrony` is not installed on control plane, install it and configure time sync.

### 5. Validate Time Sync
```bash
./tests/validate-time-sync.sh
```
**Purpose:** Verify cluster-wide time synchronization is working correctly.

**Checks:**
- Ensure NTP DaemonSet is present and pod count matches node count
- Verify time drift is < 1 second across all nodes
- Confirm NTP sources are reachable

**Troubleshooting:**
- If NTP pods are missing, check DaemonSet manifest and node selectors
- If chrony is not installed, install and configure on all nodes

### 6. Setup Auto-Sleep
```bash
./deploy.sh setup
```
**Purpose:** Configure automatic cluster sleep after inactivity to save power.

**Features:**
- Monitors cluster for active pods every 15 minutes
- Triggers sleep after 2 hours of inactivity
- Preserves cluster state for quick wake-up

### 7. Deploy RKE2 (Optional - RHEL10 Homelab Node)
```bash
./deploy.sh rke2
```
**Purpose:** Deploy RKE2 Kubernetes cluster on the homelab RHEL10 node. This is a separate cluster from the Debian cluster.

**Note:** The homelab node runs RHEL10 which requires RKE2 instead of kubeadm. This creates a federation setup where the RKE2 cluster can federate metrics to the Debian cluster's Prometheus.

**Artifacts:**
- Kubeconfig: `ansible/artifacts/homelab-rke2-kubeconfig.yaml`
- Federation endpoint: http://192.168.4.62:30090/federate

### 8. Complete Deployment (All-in-One)
```bash
./deploy.sh all --with-rke2 --yes
```
**Purpose:** Run all deployment steps in sequence (Debian + RKE2). Use this for automated deployments or when deploying from scratch.

**Note:** This combines steps 2 and 7 above. You still need to run steps 3, 4, and 6 separately for monitoring, infrastructure, and auto-sleep.

## Validation and Testing

### 9. Run Security Audit
```bash
./tests/test-security-audit.sh
```

### 10. Run Complete Validation Suite
```bash
./tests/test-complete-validation.sh
```

### 11. Run Individual Tests
```bash
./tests/test-monitoring-exporters-health.sh
./tests/test-deployment-fixes.sh
```

## Quick Reference

### Simplified Deployment Commands
```bash
# Full deployment workflow (recommended)
./deploy.sh reset                  # Clean slate
./deploy.sh debian                 # Deploy Kubernetes cluster
./deploy.sh monitoring             # Deploy monitoring stack
./deploy.sh infrastructure         # Deploy infrastructure services
./deploy.sh setup                  # Setup auto-sleep
./deploy.sh rke2                   # Deploy RKE2 (optional)

# All-in-one (cluster only, still need monitoring/infrastructure)
./deploy.sh all --with-rke2 --yes

# Individual service deployment
./deploy.sh monitoring             # Just monitoring stack
./deploy.sh infrastructure         # Just infrastructure services

# Dry-run mode (see what would happen)
./deploy.sh monitoring --check
./deploy.sh infrastructure --check
```

### Access URLs
Assuming masternode at 192.168.4.63:
- **Prometheus:** http://192.168.4.63:30090
- **Grafana:** http://192.168.4.63:30300
- **Loki:** http://192.168.4.63:31100

## Common Issues & Fixes
- **Manifest Not Found:** Ensure all referenced manifests exist and paths are correct.
- **Chrony Not Installed:** Install chrony on control plane and all nodes, then re-run validation.
- **NTP DaemonSet Missing:** Check manifest and node selectors; ensure correct namespace.
- **Pod Permission Errors:** Verify PVC/hostPath ownership and permissions.

## Validation Checklist
- [ ] Debian cluster deployed successfully (`kubectl get nodes`)
- [ ] All monitoring pods are running (`kubectl get pods -n monitoring`)
- [ ] All infrastructure pods are running (`kubectl get pods -n infrastructure`)
- [ ] Time sync validated (chrony installed, NTP DaemonSet healthy)
- [ ] Security audit passes
- [ ] Grafana dashboards show expected data (http://192.168.4.63:30300)
- [ ] Prometheus targets are up (http://192.168.4.63:30090/targets)

## Troubleshooting References
- See `docs/MONITORING_STACK_FIXES_OCT2025.md` for recent fixes
- See `docs/VALIDATION_IMPLEMENTATION_SUMMARY.md` for validation procedures
- See `docs/IDM_DEPLOYMENT.md` for FreeIPA/Kerberos deployment

---
For further debugging, use `kubectl cluster-info dump` and check Ansible playbook logs for error details.

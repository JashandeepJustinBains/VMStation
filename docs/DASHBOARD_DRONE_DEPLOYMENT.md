# Kubernetes Dashboard and Drone CI/CD Deployment Guide

This document provides instructions for deploying the Kubernetes Dashboard and Drone CI/CD with monitoring integration on VMStation infrastructure.

## Overview

The deployment consists of:
1. **Kubernetes Dashboard** - Web UI for cluster management
2. **Drone CI/CD with Gitea** - Complete CI/CD pipeline with Git server
3. **Monitoring Integration** - Grafana dashboards and Prometheus alerts

## Prerequisites

- VMStation Kubernetes cluster running (monitoring, compute, storage nodes)
- Existing monitoring stack (Prometheus, Grafana, Loki) deployed
- kubectl access from monitoring node
- Ansible with kubernetes.core collection

## Deployment Steps

### 1. Deploy Kubernetes Dashboard

```bash
# Run from the repository root
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_dashboard.yaml
```

**What it does:**
- Creates `kubernetes-dashboard` namespace
- Deploys Kubernetes Dashboard v2.7.0
- Configures NodePort service on port 30443
- Creates admin user with cluster-admin permissions
- Sets up ServiceMonitor for Prometheus monitoring

**Access:**
- URL: `https://192.168.4.63:30443`
- Authentication: Bearer token (displayed after deployment)

### 2. Deploy Drone CI/CD

```bash
# Run from the repository root
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_drone.yaml
```

**What it does:**
- Creates `localhost.localdomain` namespace on compute nodes
- Deploys Gitea (Git server) with persistent storage
- Deploys Drone server and runner
- Configures NodePort services:
  - Gitea: port 30300
  - Drone: port 30080
- Sets up RBAC permissions for Drone runner
- Creates ServiceMonitor for monitoring

**Access:**
- Gitea: `http://192.168.4.62:30300`
- Drone: `http://192.168.4.62:30080`

### 3. Configure Monitoring

The playbooks automatically create:
- **ServiceMonitors** for Prometheus scraping
- **Grafana Dashboards** for visualization
- **PrometheusRules** for alerting on Drone CI/CD health

## Post-Deployment Configuration

### Kubernetes Dashboard Setup

1. Access the dashboard at `https://192.168.4.63:30443`
2. Accept the self-signed certificate warning
3. Select "Token" authentication
4. Use the admin token provided during deployment

### Drone CI/CD Setup

1. **Setup Gitea:**
   - Access `http://192.168.4.62:30300`
   - Complete initial setup with admin user
   - Create OAuth2 application for Drone integration

2. **Configure Drone:**
   - Access `http://192.168.4.62:30080`
   - Complete OAuth integration with Gitea
   - Create your first repository with `.drone.yml`

### Example .drone.yml

```yaml
kind: pipeline
type: kubernetes
name: default

steps:
- name: test
  image: alpine
  commands:
  - echo "Hello VMStation CI/CD!"
  
- name: build
  image: alpine
  commands:
  - echo "Building application..."
  when:
    branch:
    - main
```

## Monitoring and Observability

### Grafana Dashboards

Access Grafana at `http://192.168.4.63:30300`:

1. **Kubernetes Dashboard Overview**
   - Pod status and health
   - Resource utilization
   - Access metrics

2. **Drone CI/CD Overview**
   - Build pipeline activity
   - Pod health and status
   - Resource consumption

### Prometheus Alerts

Configured alerts for:
- Pod failures in both namespaces
- High CPU/Memory usage
- Service unavailability

### Log Aggregation

Loki automatically collects logs from:
- All Kubernetes Dashboard pods
- All Drone CI/CD pods (Gitea, Drone server, runner)
- Any pods deployed by Drone pipelines

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Monitoring     │    │  Compute        │    │  Storage        │
│  192.168.4.63   │    │  192.168.4.62   │    │  192.168.4.61   │
├─────────────────┤    ├─────────────────┤    ├─────────────────┤
│ • Prometheus    │    │ • Drone Server  │    │ • Persistent    │
│ • Grafana       │    │ • Drone Runner  │    │   Storage       │
│ • Loki          │    │ • Gitea         │    │                 │
│ • K8s Dashboard │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Validation

Use the validation script to check deployment status:

```bash
# Run validation
./scripts/validate_dashboard_drone.sh
```

## Troubleshooting

### Common Issues

1. **Pod Not Starting:**
   ```bash
   kubectl describe pod <pod-name> -n <namespace>
   kubectl logs <pod-name> -n <namespace>
   ```

2. **Service Not Accessible:**
   ```bash
   kubectl get svc -n <namespace>
   kubectl get endpoints -n <namespace>
   ```

3. **Storage Issues:**
   ```bash
   kubectl get pvc -n <namespace>
   kubectl describe pvc <pvc-name> -n <namespace>
   ```

### Log Access

- **Real-time logs:** `kubectl logs -f <pod-name> -n <namespace>`
- **Historical logs:** Access via Grafana → Explore → Loki
- **Monitoring logs:** Check Grafana dashboards for visual representations

## Security Considerations

- Dashboard uses cluster-admin token (use role-based access in production)
- Drone credentials stored in Kubernetes secrets
- All services exposed via NodePort (consider Ingress for production)
- OAuth2 integration between Gitea and Drone for authentication

## Namespaces Created

- `kubernetes-dashboard` - Kubernetes Dashboard components
- `localhost.localdomain` - Drone CI/CD and Gitea components
- `monitoring` - Enhanced with new ServiceMonitors and dashboards

All pods deployed by Drone CI/CD pipelines will be automatically monitored by the existing Prometheus/Grafana/Loki stack.
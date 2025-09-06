# VMStation Masternode-Only Monitoring Deployment Guide

## Overview

This document describes how to deploy the VMStation Kubernetes monitoring stack (Prometheus, Alertmanager, Grafana, Loki) to run exclusively on the masternode, ensuring that monitoring components do not schedule on other nodes like storage or compute nodes.

## Configuration Overview

### Scheduling Mode: Strict

The monitoring deployment is configured with `monitoring_scheduling_mode: strict` in `ansible/group_vars/all.yml`, which ensures:

1. **Hostname-based node selector**: All monitoring components use `kubernetes.io/hostname: <masternode-hostname>` 
2. **Control-plane tolerations**: Components can schedule on nodes with control-plane taints
3. **Exclusive scheduling**: Monitoring pods will ONLY run on the masternode (192.168.4.63)

### Node Configuration

- **Masternode (192.168.4.63)**: Runs ALL monitoring components
  - Prometheus
  - Grafana 
  - AlertManager
  - Loki
  - Node Exporter (as DaemonSet on all nodes)

- **Storage Node (192.168.4.61)**: NO monitoring components (only Node Exporter)
- **Compute Node (192.168.4.62)**: NO monitoring components (only Node Exporter)

## Deployment Steps

### 1. Pre-deployment Checks

Run the monitoring prerequisite checks:

```bash
ansible-playbook -i ansible/inventory.txt ansible/subsites/03-monitoring.yaml
```

This will verify:
- Kubernetes connectivity
- Required namespaces
- Prometheus Operator CRDs
- Directory permissions
- SELinux contexts

### 2. Deploy Monitoring Stack

Deploy the monitoring stack with masternode-only scheduling:

```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml
```

This deployment will:
- Install kube-prometheus-stack (Prometheus + Grafana + AlertManager)
- Install Loki stack for log aggregation
- Configure all components with strict masternode scheduling
- Set up proper tolerations for control-plane nodes
- Provision Grafana dashboards and datasources

### 3. Validate Deployment

Verify that all monitoring components are running on the masternode only:

```bash
./scripts/validate_masternode_monitoring.sh
```

This script will check:
- Pod distribution across nodes
- Node scheduling compliance
- Grafana dashboard availability
- Datasource configuration

## Configuration Details

### Node Selector Configuration

In strict mode, all monitoring components use:
```yaml
nodeSelector:
  kubernetes.io/hostname: <masternode-hostname>
```

### Tolerations Configuration

All components include tolerations for control-plane nodes:
```yaml
tolerations:
  - key: "node-role.kubernetes.io/control-plane"
    operator: "Exists"
    effect: "NoSchedule"
  - key: "node-role.kubernetes.io/master"
    operator: "Exists"
    effect: "NoSchedule"
```

### Component-Specific Settings

#### Prometheus
- **Storage**: 5Gi persistent volume
- **Retention**: 30 days
- **NodePort**: 30090

#### Grafana
- **Storage**: 5Gi persistent volume
- **Admin password**: admin (change in production)
- **NodePort**: 30300
- **Dashboards**: Prometheus, Loki, and Node metrics dashboards

#### AlertManager
- **Storage**: 2Gi persistent volume
- **NodePort**: 30903

#### Loki
- **Storage**: 10Gi persistent volume
- **NodePort**: 31100
- **Configuration**: Optimized to prevent crashloops

## Access URLs

Once deployed, monitoring services are available at:

- **Grafana**: http://192.168.4.63:30300 (admin/admin)
- **Prometheus**: http://192.168.4.63:30090
- **AlertManager**: http://192.168.4.63:30903
- **Loki**: http://192.168.4.63:31100

## Grafana Configuration

### Datasources

1. **Prometheus** (default): Automatically configured by kube-prometheus-stack
2. **Loki** (non-default): Manually configured for log aggregation

### Dashboards

Three dashboards are automatically provisioned:
1. **Prometheus Dashboard**: Prometheus server metrics and status
2. **Loki Dashboard**: Log aggregation and query metrics  
3. **Node Dashboard**: Host-level metrics from Node Exporter

## Troubleshooting

### Common Issues

1. **Pods Pending**: Check node taints and labels
   ```bash
   kubectl get nodes --show-labels
   kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints[*].key}{"\n"}{end}'
   ```

2. **Permission Errors**: Verify storage directories exist
   ```bash
   sudo mkdir -p /srv/monitoring_data
   sudo chmod 755 /srv/monitoring_data
   ```

3. **Storage Issues**: Check local-path provisioner
   ```bash
   kubectl get storageclass local-path
   ```

### Scripts for Troubleshooting

- `scripts/validate_masternode_monitoring.sh`: Validate deployment
- `scripts/fix_monitoring_scheduling.sh`: Fix scheduling issues
- `scripts/test_masternode_config.sh`: Test configuration before deployment

## Security Considerations

- Change default Grafana password in production
- Consider using TLS for service communication
- Review firewall rules for NodePort services
- Implement proper backup strategies for persistent volumes

## Scaling Considerations

- This configuration prioritizes isolation over high availability
- For production, consider multi-node scheduling with anti-affinity rules
- Monitor resource usage on the masternode to prevent overload
- Consider external storage for large-scale deployments
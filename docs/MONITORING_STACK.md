# VMStation Monitoring Stack Documentation

## Overview

The VMStation monitoring stack provides comprehensive observability for the Kubernetes homelab cluster through a complete monitoring, logging, and alerting solution.

## Architecture

### Components

#### 1. Prometheus (Metrics Collection & Alerting)
- **Purpose**: Time-series metrics collection and alerting engine
- **Location**: Control plane node (masternode)
- **Access**: http://192.168.4.63:30090
- **Key Features**:
  - Comprehensive scrape configurations for all cluster components
  - Built-in alerting rules for cluster health
  - 30-day metric retention
  - Service discovery for automatic target detection

#### 2. Grafana (Visualization & Dashboards)
- **Purpose**: Metrics visualization and dashboard platform
- **Location**: Control plane node (masternode)
- **Access**: http://192.168.4.63:30300
- **Credentials**: admin/admin (change in production)
- **Key Features**:
  - Pre-configured datasources (Prometheus, Loki)
  - Four comprehensive dashboards
  - Automatic dashboard provisioning

#### 3. Loki (Log Aggregation)
- **Purpose**: Centralized log aggregation and querying
- **Location**: Control plane node (masternode)
- **Access**: http://192.168.4.63:31100
- **Key Features**:
  - Container log aggregation
  - Kubernetes system logs
  - Grafana integration for log visualization

#### 4. Node Exporter (System Metrics)
- **Purpose**: Detailed system-level metrics collection
- **Deployment**: DaemonSet on all nodes
- **Key Metrics**:
  - CPU usage and utilization
  - Memory usage and swap
  - Disk I/O and space
  - Network interface statistics
  - System load and uptime
  - Hardware sensors (temperature, fan speed)

#### 5. Kube State Metrics (Kubernetes Metrics)
- **Purpose**: Expose Kubernetes object state metrics
- **Location**: Control plane node (masternode)
- **Key Metrics**:
  - Pod status and lifecycle
  - Deployment rollout status
  - Service endpoint counts
  - Persistent volume claims
  - Node capacity and allocation
  - Resource quota usage

## Prometheus Configuration

### Scrape Configurations

The Prometheus instance scrapes metrics from multiple sources:

1. **Kubernetes API Server** (`kubernetes-apiservers`)
   - Endpoint: default/kubernetes:https
   - TLS with service account authentication

2. **Kubernetes Nodes** (`kubernetes-nodes`)
   - Node kubelet metrics
   - TLS with service account authentication

3. **cAdvisor** (`kubernetes-cadvisor`)
   - Container metrics from kubelet
   - CPU, memory, network, disk per container

4. **Node Exporter** (`node-exporter`)
   - System-level metrics from all nodes
   - Auto-discovered via service endpoints

5. **Kube State Metrics** (`kube-state-metrics`)
   - Kubernetes object state metrics
   - Static configuration to monitoring namespace service

6. **Pods with Annotations** (`kubernetes-pods`)
   - Pods with `prometheus.io/scrape: "true"` annotation
   - Automatic port and path detection

7. **Service Endpoints** (`kubernetes-service-endpoints`)
   - Services with prometheus annotations
   - Auto-discovery and relabeling

### Alerting Rules

Prometheus includes comprehensive alerting rules in three groups:

#### kubernetes-apps
- **KubePodCrashLooping**: Pod restarting >0 times per 10min
- **KubePodNotReady**: Pod in Pending/Unknown state >5min
- **KubeDeploymentReplicasMismatch**: Deployment replica count mismatch

#### kubernetes-nodes
- **KubeNodeNotReady**: Node not ready >5min (critical)
- **KubeNodeMemoryPressure**: Node experiencing memory pressure
- **KubeNodeDiskPressure**: Node experiencing disk pressure

#### node-exporter
- **NodeHighCPUUsage**: CPU >80% for 5min
- **NodeHighMemoryUsage**: Memory >80% for 5min
- **NodeDiskSpaceLow**: Disk space <10% (critical)

## Grafana Dashboards

### 1. VMStation Kubernetes Cluster Overview
**UID**: `k8s-cluster-dash`

**Panels**:
- Total Nodes (stat)
- Nodes Ready (stat)
- Total Pods (stat)
- Pods Running (stat)
- Node CPU Usage (timeseries)
- Node Memory Usage (timeseries)
- Pod Status Distribution (stacked timeseries)
- Network Traffic (timeseries)

**Use Cases**:
- Quick cluster health overview
- Resource utilization trends
- Pod distribution across nodes

### 2. VMStation Node Metrics
**UID**: `node-dash`

**Panels**:
- CPU Usage (timeseries) - per instance
- Memory Usage (timeseries) - per instance
- Disk Usage (timeseries) - per instance
- Network I/O (timeseries) - rx/tx per interface

**Use Cases**:
- Detailed node performance analysis
- Capacity planning
- Troubleshooting node issues

### 3. VMStation Prometheus Metrics
**UID**: `prom-dash`

**Panels**:
- Prometheus Instances (stat)
- Targets Up (stat)
- Targets Down (stat)
- Time Series (stat)
- HTTP Request Rate (timeseries)
- Query Duration (timeseries) - p50, p95, p99

**Use Cases**:
- Prometheus health monitoring
- Query performance analysis
- Scrape target validation

### 4. VMStation Loki Logs
**UID**: `loki-dash`

**Panels**:
- Kubernetes System Logs (logs panel)
- Monitoring Stack Logs (logs panel)
- Log Rate by Namespace (timeseries)

**Use Cases**:
- Centralized log viewing
- Log pattern analysis
- Troubleshooting application issues

## Deployment

### Automatic Deployment
The monitoring stack is automatically deployed during cluster setup:

```bash
./deploy.sh debian
# or
./deploy.sh all --with-rke2
```

### Manual Deployment
Deploy monitoring components individually:

```bash
# From control plane node with KUBECONFIG set
kubectl apply -f manifests/monitoring/prometheus.yaml
kubectl apply -f manifests/monitoring/grafana.yaml
kubectl apply -f manifests/monitoring/loki.yaml
kubectl apply -f manifests/monitoring/node-exporter.yaml
kubectl apply -f manifests/monitoring/kube-state-metrics.yaml
```

### Via Ansible Playbook
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/plays/deploy-apps.yaml
```

## Accessing Dashboards

### Grafana
1. Navigate to: http://192.168.4.63:30300
2. Login: admin/admin
3. Browse dashboards from the left menu

### Prometheus
1. Navigate to: http://192.168.4.63:30090
2. Use the expression browser for queries
3. Check targets: Status → Targets

### Loki
1. Access via Grafana (Explore → Loki datasource)
2. Direct API: http://192.168.4.63:31100

## Monitoring Queries

### Useful PromQL Queries

**Node CPU Usage**:
```promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Node Memory Usage**:
```promql
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

**Pod CPU Usage by Namespace**:
```promql
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (namespace)
```

**Pod Memory Usage by Namespace**:
```promql
sum(container_memory_working_set_bytes{container!=""}) by (namespace)
```

**Node Disk Space**:
```promql
(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100
```

### Useful LogQL Queries

**All logs from namespace**:
```logql
{namespace="kube-system"}
```

**Error logs**:
```logql
{namespace="monitoring"} |= "error" or "Error" or "ERROR"
```

**Pod-specific logs**:
```logql
{namespace="monitoring", pod=~"prometheus-.*"}
```

## Troubleshooting

### Prometheus Not Scraping Targets

**Symptoms**: Targets show as "down" in Prometheus UI

**Diagnosis**:
```bash
kubectl -n monitoring logs deployment/prometheus
kubectl -n monitoring describe pod <prometheus-pod>
```

**Common Causes**:
- Network policies blocking access
- Service account permissions
- TLS certificate issues

### Grafana Dashboards Not Loading

**Symptoms**: Dashboards appear empty or show errors

**Diagnosis**:
```bash
# Check datasource configuration
kubectl -n monitoring get configmap grafana-datasources -o yaml

# Check Grafana logs
kubectl -n monitoring logs deployment/grafana
```

**Solutions**:
- Verify Prometheus service is accessible
- Check datasource URL in Grafana settings
- Reload dashboards

### Node Exporter Not Running

**Symptoms**: Missing node metrics in Prometheus

**Diagnosis**:
```bash
kubectl -n monitoring get daemonset node-exporter
kubectl -n monitoring get pods -l app.kubernetes.io/name=node-exporter
```

**Solutions**:
- Check DaemonSet status
- Verify node taints and tolerations
- Check node-exporter logs

### Loki Logs Not Appearing

**Symptoms**: Empty log panels in Grafana

**Diagnosis**:
```bash
# Check Loki service
kubectl -n monitoring get svc loki
kubectl -n monitoring logs deployment/loki

# Test Loki API directly
curl http://192.168.4.63:31100/ready
```

**Solutions**:
- Verify Loki datasource in Grafana
- Check Loki storage configuration
- Ensure log collectors are running

## Performance Tuning

### Prometheus

**Memory Usage**:
- Default: 256Mi request, 1Gi limit
- Adjust based on metric cardinality
- Monitor with `prometheus_tsdb_head_series`

**Storage**:
- Default: emptyDir (ephemeral)
- For persistence, use PersistentVolume
- Retention: 30 days (configurable via `--storage.tsdb.retention.time`)

### Grafana

**Resource Limits**:
- Default: 128Mi request, 256Mi limit
- Increase for many dashboards/users

**Dashboard Optimization**:
- Limit time ranges
- Use appropriate refresh intervals
- Aggregate high-cardinality metrics

### Node Exporter

**Excluded Collectors**:
- Virtual network devices (veth, docker, flannel)
- Temporary filesystems
- Reduces metric cardinality

## Security Considerations

### RBAC

**Prometheus Service Account**:
- ClusterRole with read-only access
- Required permissions:
  - Get, list, watch: nodes, pods, services, endpoints
  - Get: /metrics non-resource URL

**Kube State Metrics Service Account**:
- ClusterRole with read-only access to Kubernetes objects
- Extensive permissions for state metrics

### Network Security

**Service Types**:
- NodePort for external access
- ClusterIP for internal communication

**Recommendations**:
- Use NetworkPolicies to restrict access
- Enable TLS for production deployments
- Rotate admin credentials

### Data Retention

**Prometheus**:
- 30-day retention by default
- Adjust based on storage capacity

**Loki**:
- In-memory storage (ephemeral)
- Configure persistent storage for production

## Maintenance

### Updating Components

**Update Prometheus**:
```bash
# Edit image tag in manifest
vim manifests/monitoring/prometheus.yaml
kubectl apply -f manifests/monitoring/prometheus.yaml
```

**Update Dashboards**:
```bash
# Edit dashboard JSON
vim ansible/files/grafana_dashboards/node-dashboard.json
# Redeploy via playbook
ansible-playbook ansible/plays/deploy-apps.yaml
```

### Backup and Recovery

**Prometheus Data**:
```bash
# Snapshot current data
kubectl -n monitoring exec deployment/prometheus -- tar czf /tmp/prometheus-backup.tar.gz /prometheus

# Copy to host
kubectl -n monitoring cp prometheus-<pod>:/tmp/prometheus-backup.tar.gz ./prometheus-backup.tar.gz
```

**Grafana Dashboards**:
- Dashboards stored as ConfigMaps
- Version controlled in `ansible/files/grafana_dashboards/`
- Backup: `kubectl get configmap -n monitoring -o yaml > grafana-backup.yaml`

## Future Enhancements

### Planned Features
- Distributed tracing with Jaeger/OpenTelemetry
- Application performance monitoring
- Custom business metrics exporters
- Log retention and archival policies
- Alertmanager for alert routing
- Prometheus federation to RKE2 cluster

### Scaling Considerations
- Prometheus sharding for high cardinality
- Thanos for long-term storage
- Multi-cluster monitoring
- High-availability Grafana

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Node Exporter](https://github.com/prometheus/node_exporter)
- [Kube State Metrics](https://github.com/kubernetes/kube-state-metrics)

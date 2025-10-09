# Homelab Monitoring Integration Guide

## Overview

This guide explains how to integrate the homelab RHEL 10 node (running RKE2) with the VMStation masternode monitoring stack for centralized logging and metrics.

## Architecture

The homelab node at `192.168.4.62` runs its own RKE2 cluster due to RHEL 10 specific Kubernetes requirements. However, all monitoring data (logs and metrics) are centralized to the masternode at `192.168.4.63`.

```
┌─────────────────────────────────────────────────────────┐
│ Masternode (192.168.4.63) - Debian Bookworm            │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │  Prometheus  │  │     Loki     │  │   Grafana    │ │
│  │   :30090     │  │    :31100    │  │    :30300    │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│         ▲                 ▲                            │
│         │                 │                            │
└─────────┼─────────────────┼────────────────────────────┘
          │                 │
          │ Metrics         │ Logs
          │ (Federation     │ (Promtail)
          │  & Direct)      │
          │                 │
┌─────────┼─────────────────┼────────────────────────────┐
│         │                 │                            │
│ Homelab Node (192.168.4.62) - RHEL 10 + RKE2          │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ Node Exporter│  │   Promtail   │  │IPMI Exporter │ │
│  │    :9100     │  │              │  │    :9290     │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│                                                         │
│  RKE2 Cluster (Optional):                              │
│  ┌──────────────┐                                      │
│  │  Prometheus  │  (For local monitoring & federation) │
│  │    :30090    │                                      │
│  └──────────────┘                                      │
└─────────────────────────────────────────────────────────┘
```

## Components

### 1. Log Forwarding (Promtail)

Promtail runs as a DaemonSet in the homelab RKE2 cluster and forwards all logs to the masternode Loki instance.

**Configuration:**
- **Target**: `http://192.168.4.63:31100/loki/api/v1/push`
- **Labels**: 
  - `cluster: rke2-homelab`
  - `node: homelab`
  - `job: kubernetes-pods` or `system-logs`

**Log Sources:**
- Kubernetes pod logs from `/var/log/pods`
- System logs from `/var/log/*.log`

### 2. Metrics Collection

Metrics are collected via multiple methods:

#### a. Direct Node Exporter Scrape
Prometheus on the masternode directly scrapes the node-exporter running on the homelab node.

**Target**: `192.168.4.62:9100`  
**Job**: `homelab-node-exporter`  
**Labels**: `node=homelab, cluster=rke2-homelab`

#### b. IPMI Hardware Metrics
IPMI exporter collects hardware metrics (temperature, fans, power) from the enterprise server.

**Target**: `192.168.4.62:9290`  
**Job**: `ipmi-exporter`  
**Metrics**: Temperature, fan speed, power consumption, voltage

#### c. RKE2 Federation (Optional)
If Prometheus is deployed in the RKE2 cluster, metrics can be federated to the masternode.

**Target**: `192.168.4.62:30090/federate`  
**Job**: `rke2-federation`

## Deployment Steps

### Prerequisites

1. RKE2 installed on homelab node:
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml
```

2. Masternode monitoring stack deployed:
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/deploy-cluster.yaml
```

### Step 1: Configure Homelab Monitoring

Deploy Promtail and Node Exporter on the homelab RKE2 cluster:

```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/configure-homelab-monitoring.yml
```

This playbook will:
- Create the `monitoring` namespace in RKE2
- Deploy Promtail DaemonSet with masternode Loki as the target
- Deploy Node Exporter DaemonSet
- Test connectivity to masternode Loki
- Display deployment status

### Step 2: Verify Log Forwarding

Check that logs are being received:

1. Access Grafana at `http://192.168.4.63:30300`
2. Navigate to Explore → Select Loki datasource
3. Query: `{cluster="rke2-homelab"}`
4. You should see logs from the homelab node

### Step 3: Verify Metrics Collection

Check Prometheus targets:

1. Access Prometheus at `http://192.168.4.63:30090`
2. Navigate to Status → Targets
3. Verify the following targets are UP:
   - `homelab-node-exporter` (192.168.4.62:9100)
   - `ipmi-exporter` (192.168.4.62:9290)
   - `rke2-federation` (192.168.4.62:30090) - if RKE2 Prometheus is deployed

### Step 4: View Dashboards

In Grafana, check the following dashboards:

1. **VMStation Kubernetes Cluster Overview**: Shows masternode cluster status
2. **Node Metrics - Detailed System Monitoring**: Includes homelab node metrics
3. **IPMI Hardware Monitoring - RHEL 10 Enterprise Server**: Hardware health for homelab
4. **Loki Logs & Aggregation**: Combined logs from all clusters
5. **Network & DNS Performance**: Blackbox probe results including Loki health

## Troubleshooting

### No Logs from Homelab

**Check Promtail pods:**
```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl get pods -n monitoring -l app=promtail
kubectl logs -n monitoring -l app=promtail
```

**Test Loki connectivity:**
```bash
curl -X POST "http://192.168.4.63:31100/loki/api/v1/push" \
  -H "Content-Type: application/json" \
  -d '{
    "streams": [
      {
        "stream": {
          "job": "test",
          "cluster": "rke2-homelab"
        },
        "values": [
          ["'$(date +%s)000000000'", "Test log"]
        ]
      }
    ]
  }'
```

**Check masternode Loki:**
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf logs -n monitoring -l app=loki
```

### No Metrics from Homelab

**Check node-exporter is running:**
```bash
curl http://192.168.4.62:9100/metrics
```

**Check Prometheus scrape status:**
1. Access Prometheus UI: `http://192.168.4.63:30090`
2. Go to Status → Targets
3. Look for errors on `homelab-node-exporter` target

**Check firewall:**
```bash
# On homelab node
sudo firewall-cmd --list-ports
# Should include 9100/tcp and 9290/tcp
```

### Loki Query Errors

If you see error: "queries require at least one regexp or equality matcher":

**Bad query (empty-compatible):**
```logql
{namespace!="kube-system"}  # ❌ WRONG
```

**Good query (non-empty-compatible):**
```logql
{job=~".+"}  # ✅ CORRECT
{job="kubernetes-pods", namespace!="kube-system"}  # ✅ CORRECT
{cluster="rke2-homelab"}  # ✅ CORRECT
```

All Loki queries must have at least one label matcher that is not empty-compatible.

### Blackbox Probe Failing for Loki

The blackbox exporter probes:
- `http://loki.monitoring.svc.cluster.local:3100/ready`

**Check Loki readiness:**
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf exec -n monitoring deploy/loki -- \
  wget -qO- http://localhost:3100/ready
```

Should return: `ready`

**Check Loki service:**
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get svc -n monitoring loki
```

## Configuration Files

### Loki Dashboard Queries

All Loki dashboard queries have been updated to use proper matchers:

- **Log Volume**: `sum by (namespace) (rate({job=~".+"}[1m]))`
- **Application Logs**: `{job=~".+"} | namespace !~ "kube-system|kube-flannel|monitoring"`
- **System Logs**: `{job=~".+", namespace="kube-system"}`
- **Monitoring Logs**: `{job=~".+", namespace="monitoring"}`
- **Error Logs**: `sum by (namespace, pod) (rate({job=~".+"} |= "error" [5m]))`

### Promtail Configuration

Promtail on homelab is configured with:

```yaml
clients:
  - url: http://192.168.4.63:31100/loki/api/v1/push
    external_labels:
      cluster: rke2-homelab
      node: homelab

scrape_configs:
- job_name: kubernetes-pods
  relabel_configs:
  - replacement: kubernetes-pods
    target_label: job
```

## Maintenance

### Redeploying Monitoring on Homelab

If you need to redeploy the monitoring components:

```bash
# Remove existing deployment
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
kubectl delete namespace monitoring

# Redeploy
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/configure-homelab-monitoring.yml
```

### Updating Loki Configuration

After updating Loki configuration on masternode:

```bash
# Apply updated manifests
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/monitoring/loki.yaml

# Restart Loki
kubectl --kubeconfig=/etc/kubernetes/admin.conf rollout restart deployment/loki -n monitoring
```

### Monitoring Stack Health

Check overall monitoring health:

```bash
# Masternode
./tests/test-loki-validation.sh
./tests/test-monitoring-access.sh

# Check all targets in Prometheus
curl -s http://192.168.4.63:30090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, lastError: .lastError}'
```

## Integration with Other Systems

### Alert Manager (Future)

When Alert Manager is deployed, alerts can be configured for:
- Homelab node down (no metrics received)
- High temperature from IPMI sensors
- Disk space low on homelab node
- Missing logs from homelab cluster

### Service Discovery

The current setup uses static configuration. For dynamic service discovery, consider:
- Prometheus Operator with ServiceMonitor CRDs
- Consul for service registration
- Kubernetes API for pod discovery across clusters

## Security Considerations

1. **Network Access**: Ensure ports 9100, 9290, 31100 are accessible from masternode to homelab
2. **Authentication**: Consider adding authentication for Loki push endpoint in production
3. **TLS**: Use TLS for log and metric transmission in production environments
4. **Firewall**: Configure firewall rules to allow only masternode → homelab traffic

## Performance Tuning

### Loki Retention

Current retention: 168h (7 days)

To increase:
```yaml
# In manifests/monitoring/loki.yaml
table_manager:
  retention_period: 720h  # 30 days
```

### Promtail Rate Limiting

If log volume is high, configure rate limiting in Promtail:

```yaml
clients:
  - url: http://192.168.4.63:31100/loki/api/v1/push
    backoff_config:
      min_period: 100ms
      max_period: 10s
      max_retries: 10
```

## References

- [Loki Configuration](https://grafana.com/docs/loki/latest/configuration/)
- [Promtail Configuration](https://grafana.com/docs/loki/latest/clients/promtail/configuration/)
- [Prometheus Federation](https://prometheus.io/docs/prometheus/latest/federation/)
- [RKE2 Documentation](https://docs.rke2.io/)

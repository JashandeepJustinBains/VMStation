# RKE2 Prometheus Federation Setup Guide

This document describes how to configure the central Prometheus instance on the Debian control-plane cluster to federate metrics from the RKE2 cluster running on the homelab node.

## Overview

**Architecture:**
- **RKE2 Cluster**: Single-node Kubernetes cluster on homelab (192.168.4.62) with its own Prometheus instance
- **Central Prometheus**: Existing Prometheus on Debian control-plane cluster (masternode 192.168.4.63)
- **Federation**: Central Prometheus pulls selected metrics from RKE2 Prometheus via `/federate` endpoint

**Benefits:**
- Unified monitoring dashboard showing both clusters
- No changes to existing Debian cluster workloads
- Separate cluster isolation while maintaining observability
- Minimal network overhead (only federated metrics are transferred)

## Prerequisites

- RKE2 cluster installed and running on homelab (completed by `install-rke2-homelab.yml`)
- RKE2 Prometheus accessible at `http://192.168.4.62:30090`
- Central Prometheus running on masternode (192.168.4.63)
- Network connectivity between masternode and homelab on port 30090

## Federation Endpoint Verification

Before configuring federation, verify the RKE2 Prometheus federation endpoint is accessible:

```bash
# From masternode (192.168.4.63)
curl -s 'http://192.168.4.62:30090/federate?match[]={job="kubernetes-nodes"}' | head -20

# Expected output: Prometheus metrics in text format
# Example:
# node_cpu_seconds_total{cluster="rke2-homelab",cpu="0",mode="idle",...} 12345.67
```

If this fails, check:
1. RKE2 Prometheus pod is running: `kubectl --kubeconfig=ansible/artifacts/homelab-rke2-kubeconfig.yaml get pods -n monitoring-rke2`
2. Service is accessible: `kubectl --kubeconfig=ansible/artifacts/homelab-rke2-kubeconfig.yaml get svc -n monitoring-rke2`
3. Firewall allows port 30090: `ssh 192.168.4.62 'sudo firewall-cmd --list-ports'` (or check iptables/nftables)

## Option A: Configure Federation (Recommended)

### Step 1: Update Central Prometheus ConfigMap

The central Prometheus configuration is stored in a ConfigMap in the `monitoring` namespace.

**Location:** `/home/runner/work/VMStation/VMStation/manifests/monitoring/prometheus.yaml`

Add the following scrape configuration to the `scrape_configs` section of the ConfigMap:

```yaml
    # Federation from RKE2 homelab cluster
    - job_name: 'rke2-federation'
      honor_labels: true
      honor_timestamps: true
      metrics_path: '/federate'
      params:
        'match[]':
          # Federate all Kubernetes metrics
          - '{job=~"kubernetes-.*"}'
          # Federate node-exporter metrics
          - '{job="node-exporter"}'
          # Federate Prometheus itself
          - '{job="prometheus"}'
          # Federate any custom application metrics
          - '{job=~".*",namespace="monitoring-rke2"}'
      static_configs:
        - targets:
            - '192.168.4.62:30090'
          labels:
            cluster: 'rke2-homelab'
            environment: 'homelab'
            source: 'federation'
      relabel_configs:
        # Preserve cluster label from source
        - source_labels: [cluster]
          target_label: source_cluster
          action: replace
        # Add cluster identifier if not present
        - target_label: cluster
          replacement: 'rke2-homelab'
          action: replace
      scrape_interval: 30s
      scrape_timeout: 25s
```

### Step 2: Apply the Updated Configuration

```bash
# From repository root on masternode
cd /srv/monitoring_data/VMStation

# Apply the updated Prometheus configuration
kubectl apply -f manifests/monitoring/prometheus.yaml

# Reload Prometheus configuration (if web.enable-lifecycle is enabled)
kubectl exec -n monitoring deployment/prometheus -- curl -X POST http://localhost:9090/-/reload

# Or restart Prometheus pod to pick up new config
kubectl rollout restart -n monitoring deployment/prometheus
```

### Step 3: Verify Federation is Working

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="rke2-federation")'

# Or access Prometheus UI at http://192.168.4.63:30090
# Navigate to Status > Targets and look for "rke2-federation"
```

Check for metrics from RKE2 cluster:

```bash
# Query for RKE2 node metrics
curl -s 'http://192.168.4.63:30090/api/v1/query?query=up{cluster="rke2-homelab"}' | jq .

# Query for specific federated metrics
curl -s 'http://192.168.4.63:30090/api/v1/query?query=node_cpu_seconds_total{cluster="rke2-homelab"}' | jq .
```

Expected result: Metrics from RKE2 cluster should appear with `cluster="rke2-homelab"` label.

## Option B: Static Scrape Configuration (Alternative)

If federation is not desired, you can configure central Prometheus to directly scrape the RKE2 node-exporter and API server.

Add these scrape configurations instead:

```yaml
    # Scrape RKE2 node-exporter directly
    - job_name: 'rke2-node-exporter'
      static_configs:
        - targets:
            - '192.168.4.62:9100'
          labels:
            cluster: 'rke2-homelab'
            node: 'homelab'
      scrape_interval: 15s

    # Scrape RKE2 Kubernetes API server metrics
    - job_name: 'rke2-apiserver'
      scheme: https
      tls_config:
        insecure_skip_verify: true
      bearer_token_file: /path/to/rke2-token  # Requires token configuration
      static_configs:
        - targets:
            - '192.168.4.62:6443'
          labels:
            cluster: 'rke2-homelab'
      metrics_path: /metrics
      scrape_interval: 30s
```

**Note:** Option B requires managing credentials and provides less comprehensive metrics than federation.

## Complete Central Prometheus Configuration Example

Here's a complete example of the central Prometheus ConfigMap with RKE2 federation added:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      scrape_timeout: 10s
      
    scrape_configs:
    # Existing scrape configs (Debian cluster)
    - job_name: 'kubernetes-apiservers'
      kubernetes_sd_configs:
      - role: endpoints
      scheme: https
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: default;kubernetes;https
    
    - job_name: 'kubernetes-nodes'
      kubernetes_sd_configs:
      - role: node
      scheme: https
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        insecure_skip_verify: true
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
    
    - job_name: 'kubernetes-cadvisor'
      kubernetes_sd_configs:
      - role: node
      scheme: https
      metrics_path: /metrics/cadvisor
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        insecure_skip_verify: true
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
    
    # NEW: RKE2 Federation
    - job_name: 'rke2-federation'
      honor_labels: true
      honor_timestamps: true
      metrics_path: '/federate'
      params:
        'match[]':
          - '{job=~"kubernetes-.*"}'
          - '{job="node-exporter"}'
          - '{job="prometheus"}'
      static_configs:
        - targets:
            - '192.168.4.62:30090'
          labels:
            cluster: 'rke2-homelab'
            environment: 'homelab'
            source: 'federation'
      scrape_interval: 30s
      scrape_timeout: 25s
```

## Grafana Dashboard Configuration

To visualize metrics from both clusters in Grafana:

1. **Add cluster filter**: Use the `cluster` label to filter/separate metrics
   ```promql
   node_cpu_seconds_total{cluster="rke2-homelab"}
   ```

2. **Create multi-cluster dashboard**: Use template variables
   ```
   Variable: cluster
   Query: label_values(up, cluster)
   ```

3. **Compare clusters**: Use queries like
   ```promql
   sum by (cluster) (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
   ```

## Troubleshooting

### Federation endpoint not accessible

```bash
# Test from masternode
curl -v http://192.168.4.62:30090/federate

# Check Prometheus pod logs on RKE2
kubectl --kubeconfig=ansible/artifacts/homelab-rke2-kubeconfig.yaml logs -n monitoring-rke2 -l app=prometheus-rke2

# Check service
kubectl --kubeconfig=ansible/artifacts/homelab-rke2-kubeconfig.yaml get svc -n monitoring-rke2
```

### No metrics appearing in central Prometheus

```bash
# Check target health in central Prometheus
kubectl exec -n monitoring deployment/prometheus -- wget -qO- http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="rke2-federation")'

# Look for errors
kubectl logs -n monitoring -l app=prometheus --tail=100 | grep rke2
```

### Metrics have wrong labels

Ensure `honor_labels: true` is set in the federation scrape config. This preserves labels from the source Prometheus.

### High memory usage on central Prometheus

Federation can increase memory usage. Reduce the match criteria:

```yaml
params:
  'match[]':
    # Only federate node metrics
    - '{job="node-exporter"}'
```

## Security Considerations

1. **Network Security**: Ensure only authorized hosts can access the federation endpoint (port 30090)
2. **TLS**: Consider enabling TLS for the federation endpoint in production
3. **Authentication**: RKE2 Prometheus federation endpoint is unauthenticated by default
4. **Metrics Filtering**: Only federate necessary metrics to reduce attack surface

## Maintenance

### Updating Federation Config

When adding new metrics or jobs to RKE2 Prometheus, update the match criteria in central Prometheus:

```yaml
params:
  'match[]':
    - '{job="new-job-name"}'
```

Then reload central Prometheus configuration.

### Monitoring Federation Health

Create alerts for federation health:

```yaml
- alert: FederationDown
  expr: up{job="rke2-federation"} == 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "RKE2 federation endpoint is down"
    description: "Central Prometheus cannot reach RKE2 Prometheus for federation"
```

## References

- [Prometheus Federation Documentation](https://prometheus.io/docs/prometheus/latest/federation/)
- [RKE2 Documentation](https://docs.rke2.io/)
- VMStation RKE2 Role: `ansible/roles/rke2/README.md`
- RKE2 Deployment Guide: `docs/RKE2_DEPLOYMENT_GUIDE.md`

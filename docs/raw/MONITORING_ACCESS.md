# VMStation Monitoring Access Guide

This document describes how to access monitoring endpoints without authentication for operational visibility.

## Overview

VMStation monitoring stack is configured for **anonymous read-only access** to enable easy monitoring without login requirements. This is suitable for homelab environments where network access is already controlled.

## Monitoring Endpoints

### Grafana Dashboard Access

**URL**: `http://192.168.4.63:30300`

**Access Method**: Anonymous (No Login Required)

Grafana is configured with anonymous access enabled by default. You can:
- View all dashboards without logging in
- Access read-only dashboards automatically
- No credentials needed for viewing metrics

**Configuration Details**:
```yaml
Environment Variables:
  GF_AUTH_ANONYMOUS_ENABLED: "true"
  GF_AUTH_ANONYMOUS_ORG_ROLE: "Viewer"
  GF_AUTH_BASIC_ENABLED: "true"
```

**Admin Access** (if needed):
- Username: `admin`
- Password: `admin` (change in production)
- URL: Same as above - click "Sign in" at bottom of page

### Prometheus Metrics

**URL**: `http://192.168.4.63:30090`

**Access Method**: Direct HTTP (No Authentication)

Prometheus exposes metrics without authentication for easy federation and monitoring.

**Available Endpoints**:
- `/metrics` - Prometheus self-metrics
- `/api/v1/query` - Query API
- `/api/v1/query_range` - Range query API
- `/federate` - Federation endpoint
- `/targets` - Target status

**Example Queries**:
```bash
# Check Prometheus health
curl http://192.168.4.63:30090/-/healthy

# View all metrics
curl http://192.168.4.63:30090/api/v1/label/__name__/values

# Query node CPU usage
curl -G http://192.168.4.63:30090/api/v1/query \
  --data-urlencode 'query=node_cpu_seconds_total'

# Federation endpoint (all metrics)
curl 'http://192.168.4.63:30090/federate?match[]={job=~".+"}'
```

### Node Exporter Metrics

**Debian Nodes**:
- Master: `http://192.168.4.63:9100/metrics`
- Storage: `http://192.168.4.61:9100/metrics`

**RHEL Node** (RKE2):
- Homelab: `http://192.168.4.62:9100/metrics`

**Access Method**: Direct HTTP (No Authentication)

Node exporter provides system-level metrics (CPU, memory, disk, network).

**Example**:
```bash
# Get all node metrics
curl http://192.168.4.63:9100/metrics

# Filter specific metrics
curl http://192.168.4.63:9100/metrics | grep node_cpu
```

## RKE2 Cluster Monitoring

### RKE2 Prometheus Federation

**URL**: `http://192.168.4.62:30090/federate`

**Access Method**: Direct HTTP (No Authentication)

The RKE2 cluster on homelab node exposes its own Prometheus instance that can be federated with the main cluster.

**Federation Configuration** (on Debian cluster):
```yaml
scrape_configs:
- job_name: 'rke2-federation'
  honor_labels: true
  metrics_path: '/federate'
  params:
    'match[]':
      - '{job=~".+"}'
  static_configs:
  - targets:
    - '192.168.4.62:30090'
```

## Security Considerations

### Network-Level Security

The monitoring stack is designed for homelab use with these assumptions:
1. **Network isolation**: Cluster is on a private network (192.168.4.0/24)
2. **Firewall protection**: External access controlled at network perimeter
3. **Read-only access**: Anonymous users have viewer role only

### For Production Use

If deploying in a production environment, consider:

1. **Enable Authentication**:
```yaml
# Disable anonymous access
GF_AUTH_ANONYMOUS_ENABLED: "false"
```

2. **Use Ingress with TLS**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
spec:
  tls:
  - hosts:
    - grafana.yourdomain.com
    secretName: grafana-tls
  rules:
  - host: grafana.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000
```

3. **Configure OAuth/LDAP** for Grafana authentication

4. **Enable Prometheus BasicAuth** or use a reverse proxy

## Troubleshooting

### Cannot Access Grafana

1. **Check pod status**:
```bash
kubectl get pods -n monitoring
kubectl logs -n monitoring deployment/grafana
```

2. **Verify service**:
```bash
kubectl get svc -n monitoring grafana
```

3. **Check NodePort availability**:
```bash
# From masternode
curl http://localhost:30300
# From external host
curl http://192.168.4.63:30300
```

### Cannot Access Prometheus

1. **Check pod status**:
```bash
kubectl get pods -n monitoring
kubectl logs -n monitoring deployment/prometheus
```

2. **Verify targets**:
```bash
curl http://192.168.4.63:30090/api/v1/targets
```

3. **Check metrics scraping**:
```bash
# Should return metrics
curl http://192.168.4.63:9100/metrics
```

### No Metrics Showing in Grafana

1. **Verify Prometheus datasource**:
   - Open Grafana
   - Go to Configuration → Data Sources
   - Check "Prometheus" datasource connection
   - Test connection should succeed

2. **Check Prometheus targets**:
   - Open `http://192.168.4.63:30090/targets`
   - All targets should be "UP"

3. **Verify pods can reach Prometheus**:
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://prometheus.monitoring.svc.cluster.local:9090/metrics
```

## Dashboard Access

### Default Dashboards

After deployment, the following dashboards are available:

1. **Kubernetes Cluster Overview**
   - URL: Auto-loaded as home dashboard
   - Shows: Node status, pod health, resource usage

2. **Node Metrics**
   - CPU usage per node
   - Memory usage per node
   - Disk I/O
   - Network traffic

3. **Prometheus Metrics**
   - Query performance
   - Scrape duration
   - Time series count

### Creating Custom Dashboards

As an anonymous viewer, you cannot save dashboards. To create custom dashboards:

1. Sign in as admin
2. Create/import dashboard
3. Save to default organization
4. Dashboard will be visible to anonymous users

## Health Checks

### Quick Health Check Script

```bash
#!/bin/bash
# VMStation Monitoring Health Check

echo "=== VMStation Monitoring Health Check ==="
echo ""

echo "1. Checking Grafana..."
if curl -sf http://192.168.4.63:30300 >/dev/null; then
  echo "   ✅ Grafana is accessible"
else
  echo "   ❌ Grafana is NOT accessible"
fi

echo "2. Checking Prometheus..."
if curl -sf http://192.168.4.63:30090/-/healthy >/dev/null; then
  echo "   ✅ Prometheus is healthy"
else
  echo "   ❌ Prometheus is NOT healthy"
fi

echo "3. Checking Node Exporter (masternode)..."
if curl -sf http://192.168.4.63:9100/metrics >/dev/null; then
  echo "   ✅ Node Exporter is running"
else
  echo "   ❌ Node Exporter is NOT running"
fi

echo "4. Checking Prometheus targets..."
UP_TARGETS=$(curl -sf http://192.168.4.63:30090/api/v1/targets 2>/dev/null | \
  grep -o '"health":"up"' | wc -l)
echo "   📊 Active targets: $UP_TARGETS"

echo ""
echo "=== Health Check Complete ==="
```

Save this script and run it to verify all monitoring endpoints are accessible.

## References

- [Grafana Anonymous Access Documentation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/#anonymous-authentication)
- [Prometheus Federation](https://prometheus.io/docs/prometheus/latest/federation/)
- [VMStation Deployment Specification](../DEPLOYMENT_SPECIFICATION.md)

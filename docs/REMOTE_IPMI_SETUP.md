# Remote IPMI Monitoring Setup Guide

This guide explains how to configure and deploy remote IPMI monitoring for enterprise servers in the VMStation cluster.

## Quick Overview

The VMStation monitoring stack now supports monitoring multiple enterprise servers via IPMI:
- **Local IPMI**: Direct hardware monitoring on RHEL 10 node (192.168.4.62)
- **Remote IPMI**: Network-based monitoring of external BMCs (e.g., 192.168.4.60)

## Prerequisites

1. **BMC Network Access**
   - Remote BMC must be accessible from the Kubernetes cluster
   - Network connectivity on IPMI port (default: 623/udp)
   - Firewall rules allowing IPMI traffic

2. **IPMI Credentials**
   - Valid username/password for BMC access
   - User must have at least "USER" privilege level

## Configuration Steps

### Step 1: Configure Credentials

Edit `ansible/inventory/group_vars/secrets.yml`:

```yaml
# IPMI credentials for remote BMC access
ipmi_username: "admin"
ipmi_password: "your_secure_password"
```

### Step 2: Encrypt Secrets

```bash
cd /path/to/VMStation
ansible-vault encrypt ansible/inventory/group_vars/secrets.yml
```

### Step 3: Deploy the Stack

Using the Ansible playbook:

```bash
ansible-playbook -i ansible/inventory.txt \
  ansible/playbooks/deploy-cluster.yaml \
  --ask-vault-pass
```

Or manually:

```bash
# Create namespace
kubectl create namespace monitoring

# Create credentials secret
kubectl create secret generic ipmi-credentials \
  --from-literal=username='admin' \
  --from-literal=password='your_password' \
  --namespace=monitoring

# Deploy IPMI exporters
kubectl apply -f manifests/monitoring/ipmi-exporter.yaml

# Deploy Prometheus
kubectl apply -f manifests/monitoring/prometheus.yaml
```

## Validation

### 1. Check Deployment Status

```bash
# Check all monitoring pods
kubectl get pods -n monitoring

# Expected output should include:
# - ipmi-exporter-xxxxx (local IPMI on RHEL node)
# - ipmi-exporter-remote-xxxxx (remote IPMI deployment)
# - prometheus-xxxxx
```

### 2. Verify IPMI Exporters

```bash
# Check local IPMI exporter
kubectl logs -n monitoring -l app=ipmi-exporter --tail=20

# Check remote IPMI exporter
kubectl logs -n monitoring -l app=ipmi-exporter-remote --tail=20
```

### 3. Test IPMI Metrics

```bash
# Port-forward to remote IPMI exporter
kubectl port-forward -n monitoring svc/ipmi-exporter-remote 9291:9291 &

# Fetch metrics (should show IPMI sensor data)
curl -s http://localhost:9291/metrics?target=192.168.4.60 | grep ipmi_temperature

# Kill port-forward
pkill -f "port-forward.*ipmi-exporter-remote"
```

### 4. Check Prometheus Targets

```bash
# Port-forward to Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &

# Open in browser: http://localhost:9090/targets
# Verify these targets are UP:
# - ipmi-exporter (192.168.4.62:9290)
# - ipmi-exporter-remote (192.168.4.60)
```

### 5. Query Metrics in Prometheus

Open Prometheus UI (http://localhost:9090/graph) and test these queries:

```promql
# All temperature sensors from all servers
ipmi_temperature_celsius

# Temperature from local IPMI (homelab node)
ipmi_temperature_celsius{node="homelab"}

# Temperature from remote IPMI (enterprise server)
ipmi_temperature_celsius{node="enterprise-server-60"}

# Fan speeds from remote server
ipmi_fan_speed_rpm{node="enterprise-server-60"}

# Power consumption from both servers
ipmi_dcmi_power_consumption_watts
```

## Architecture

### Local IPMI Monitoring (192.168.4.62)

```
┌─────────────────────────────────────┐
│  RHEL 10 Node (homelab)             │
│  192.168.4.62                       │
│                                     │
│  ┌──────────────────────────────┐  │
│  │  ipmi-exporter (DaemonSet)   │  │
│  │  - hostNetwork: true         │  │
│  │  - privileged: true          │  │
│  │  - Port: 9290                │  │
│  │  - Local BMC access via /dev │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
           ▲
           │ scrape
           │
    ┌──────┴───────┐
    │  Prometheus  │
    └──────────────┘
```

### Remote IPMI Monitoring (192.168.4.60)

```
┌──────────────────────────┐     ┌─────────────────────────┐
│  Kubernetes Cluster      │     │  Remote Server          │
│                          │     │  192.168.4.60           │
│  ┌────────────────────┐  │     │                         │
│  │  ipmi-exporter-    │  │     │  ┌──────────────────┐  │
│  │  remote            │  │◄────┼──┤  BMC / IPMI      │  │
│  │  (Deployment)      │  │IPMI │  │  Interface       │  │
│  │  - Port: 9291      │  │LAN  │  └──────────────────┘  │
│  │  - Credentials from│  │     │                         │
│  │    K8s Secret      │  │     └─────────────────────────┘
│  └────────────────────┘  │
│           ▲              │
│           │ scrape       │
│    ┌──────┴───────┐     │
│    │  Prometheus  │     │
│    └──────────────┘     │
└──────────────────────────┘
```

## Prometheus Scrape Configuration

The remote IPMI target uses a different scrape pattern than traditional exporters:

```yaml
- job_name: 'ipmi-exporter-remote'
  static_configs:
  - targets:
    - '192.168.4.60'  # Remote BMC address
    labels:
      node: 'enterprise-server-60'
  relabel_configs:
  # Pass BMC address as target parameter
  - source_labels: [__address__]
    target_label: __param_target
  # Use instance label from target
  - source_labels: [__param_target]
    target_label: instance
  # Redirect scrape to ipmi-exporter-remote service
  - target_label: __address__
    replacement: ipmi-exporter-remote.monitoring.svc.cluster.local:9291
```

**How it works:**
1. Prometheus receives target `192.168.4.60`
2. Relabel configs convert it to `?target=192.168.4.60` parameter
3. Actual scrape goes to `ipmi-exporter-remote.monitoring.svc:9291/metrics?target=192.168.4.60`
4. Remote exporter connects to 192.168.4.60 BMC and returns metrics
5. Metrics are labeled with `instance="192.168.4.60"`

## Security Considerations

### 1. Credential Storage

- ✅ **DO**: Store credentials in `secrets.yml` encrypted with ansible-vault
- ✅ **DO**: Use strong, unique passwords for each BMC
- ❌ **DON'T**: Hardcode credentials in manifests or ConfigMaps
- ❌ **DON'T**: Commit unencrypted secrets to version control

### 2. Network Security

```bash
# Recommended: Isolate BMC network with firewall rules
# Allow only Kubernetes nodes to access BMC ports

# Example iptables rule (on BMC network):
iptables -A INPUT -p udp --dport 623 -s 192.168.4.0/24 -j ACCEPT
iptables -A INPUT -p udp --dport 623 -j DROP
```

### 3. RBAC and Network Policies

The deployment includes minimal privileges:
- Remote exporter runs as non-root
- No elevated capabilities required
- Uses standard cluster networking

Consider adding NetworkPolicy:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ipmi-exporter-remote-policy
  namespace: monitoring
spec:
  podSelector:
    matchLabels:
      app: ipmi-exporter-remote
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: prometheus
    ports:
    - protocol: TCP
      port: 9291
  egress:
  - to:
    - podSelector: {}
    ports:
    - protocol: UDP
      port: 623  # IPMI port
```

## Troubleshooting

### Issue: Remote exporter can't connect to BMC

```bash
# Test network connectivity
ping 192.168.4.60

# Test IPMI from a node
ipmitool -I lanplus -H 192.168.4.60 -U admin -P password sensor list

# Check exporter logs
kubectl logs -n monitoring -l app=ipmi-exporter-remote
```

### Issue: Authentication failures

```bash
# Verify credentials in secret
kubectl get secret ipmi-credentials -n monitoring -o jsonpath='{.data.username}' | base64 -d
echo  # newline

# Re-create secret if needed
kubectl delete secret ipmi-credentials -n monitoring
kubectl create secret generic ipmi-credentials \
  --from-literal=username='correct_username' \
  --from-literal=password='correct_password' \
  --namespace=monitoring

# Restart exporter to pick up new credentials
kubectl rollout restart deployment/ipmi-exporter-remote -n monitoring
```

### Issue: Metrics not appearing in Prometheus

```bash
# Check Prometheus target status
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Browse to http://localhost:9090/targets
# Look for errors on ipmi-exporter-remote target

# Check service DNS resolution
kubectl exec -n monitoring deployment/prometheus -- \
  nslookup ipmi-exporter-remote.monitoring.svc.cluster.local

# Reload Prometheus config
kubectl exec -n monitoring deployment/prometheus -- \
  wget -qO- --post-data='' http://localhost:9090/-/reload
```

## Adding Additional Remote IPMI Targets

To monitor additional servers, add them to the Prometheus configuration:

1. Edit `manifests/monitoring/prometheus.yaml`

2. Add a new static_config under the `ipmi-exporter-remote` job:

```yaml
- job_name: 'ipmi-exporter-remote'
  static_configs:
  - targets:
    - '192.168.4.60'  # Existing server
    labels:
      node: 'enterprise-server-60'
  - targets:
    - '192.168.4.70'  # New server
    labels:
      node: 'enterprise-server-70'
  # ... rest of config
```

3. Apply the updated configuration:

```bash
kubectl apply -f manifests/monitoring/prometheus.yaml
kubectl rollout restart deployment/prometheus -n monitoring
```

## Monitoring Best Practices

1. **Set appropriate scrape intervals**
   - Hardware metrics don't change rapidly
   - 30-60 seconds is usually sufficient
   - Avoid scraping too frequently (can stress BMC)

2. **Configure alerts**
   - Temperature thresholds: 75°C warning, 85°C critical
   - Fan speed minimums: 1000 RPM warning
   - Power consumption limits: based on your hardware

3. **Regular maintenance**
   - Rotate IPMI credentials quarterly
   - Review and update BMC firmware
   - Monitor exporter resource usage
   - Test failover scenarios

4. **Dashboard organization**
   - Group metrics by server/node
   - Use consistent labeling
   - Create separate dashboards for different server types

## References

- [IPMI Exporter Documentation](https://github.com/prometheus-community/ipmi_exporter)
- [Prometheus Relabeling Guide](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#relabel_config)
- [IPMI Specification](https://www.intel.com/content/www/us/en/products/docs/servers/ipmi/ipmi-home.html)
- [VMStation IPMI Monitoring Guide](./IPMI_MONITORING_GUIDE.md)

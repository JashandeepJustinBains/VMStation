# IPMI Monitoring Setup for RHEL 10 Enterprise Server

## Overview

This guide explains how to set up and configure IPMI (Intelligent Platform Management Interface) monitoring on the RHEL 10 homelab node for enterprise-grade hardware health monitoring.

## Prerequisites

### Hardware Requirements

- Enterprise-grade server with BMC (Baseboard Management Controller)
- IPMI interface enabled in BIOS/UEFI
- Network connection to BMC (can be shared or dedicated)

### Software Requirements

- RHEL 10 operating system
- Kubernetes cluster access
- IPMI kernel modules loaded
- Root or sudo access for initial setup

## IPMI Setup on RHEL 10 Node

### Step 1: Load IPMI Kernel Modules

```bash
# Load required kernel modules
sudo modprobe ipmi_devintf
sudo modprobe ipmi_si
sudo modprobe ipmi_msghandler

# Verify modules are loaded
lsmod | grep ipmi

# Make modules load on boot
cat << 'EOF' | sudo tee /etc/modules-load.d/ipmi.conf
ipmi_devintf
ipmi_si
ipmi_msghandler
EOF
```

### Step 2: Install IPMI Tools

```bash
# Install ipmitool for testing
sudo dnf install -y ipmitool

# Verify IPMI access
sudo ipmitool sensor list

# Expected output: List of sensors with readings
# Example:
# CPU Temp         | 45.000     | degrees C  | ok    | na        | na        | na        | 80.000    | 85.000    | 90.000
# System Temp      | 35.000     | degrees C  | ok    | na        | na        | na        | 70.000    | 75.000    | 80.000
# Fan1             | 3200.000   | RPM        | ok    | na        | 300.000   | 500.000   | na        | na        | na
```

### Step 3: Configure IPMI Network (if needed)

If using dedicated BMC network:

```bash
# Configure BMC network using ipmitool
sudo ipmitool lan set 1 ipsrc static
sudo ipmitool lan set 1 ipaddr 192.168.100.62
sudo ipmitool lan set 1 netmask 255.255.255.0
sudo ipmitool lan set 1 defgw ipaddr 192.168.100.1

# Verify configuration
sudo ipmitool lan print 1
```

### Step 4: Test IPMI Access

```bash
# List all sensors
sudo ipmitool sensor list

# Get specific sensor readings
sudo ipmitool sensor get "CPU Temp"
sudo ipmitool sensor get "Fan1"

# Check BMC info
sudo ipmitool bmc info

# Test DCMI power reading
sudo ipmitool dcmi power reading
```

## Deploy IPMI Exporter on Kubernetes

### Step 1: Label the RHEL 10 Node

```bash
# Verify node has correct label
kubectl get node homelab -o jsonpath='{.metadata.labels}' | jq

# If not present, add the label
kubectl label node homelab vmstation.io/role=compute --overwrite
```

### Step 2: Deploy IPMI Exporter

```bash
# Deploy the IPMI exporter DaemonSet
kubectl apply -f manifests/monitoring/ipmi-exporter.yaml

# Verify deployment
kubectl get pods -n monitoring -l app=ipmi-exporter

# Check pod status
kubectl describe pod -n monitoring -l app=ipmi-exporter
```

### Step 3: Verify IPMI Metrics

```bash
# Port-forward to test locally
kubectl port-forward -n monitoring daemonset/ipmi-exporter 9290:9290 &

# Fetch metrics
curl http://localhost:9290/metrics | grep ipmi

# Kill port-forward
pkill -f "port-forward.*ipmi-exporter"

# Or test directly on node
curl http://192.168.4.62:9290/metrics | grep ipmi_temperature
```

## Available IPMI Metrics

### Temperature Metrics

```promql
# Current temperature of all sensors
ipmi_temperature_celsius

# Example query: Show all temperature sensors
ipmi_temperature_celsius{node="homelab"}

# Example query: CPU temperature
ipmi_temperature_celsius{sensor=~"CPU.*"}

# Example query: Motherboard temperature
ipmi_temperature_celsius{sensor=~"(MB|System).*"}
```

### Fan Speed Metrics

```promql
# Fan speeds in RPM
ipmi_fan_speed_rpm

# Example query: All fan speeds
ipmi_fan_speed_rpm{node="homelab"}

# Example query: Minimum fan speed
min(ipmi_fan_speed_rpm{node="homelab"})

# Example query: Fan speed below threshold
ipmi_fan_speed_rpm < 2000
```

### Power Consumption Metrics

```promql
# Current power consumption in watts
ipmi_dcmi_power_consumption_watts

# Example query: Current power draw
ipmi_dcmi_power_consumption_watts{node="homelab"}

# Example query: Power consumption over time
rate(ipmi_dcmi_power_consumption_watts[5m])

# Example query: Average power in last hour
avg_over_time(ipmi_dcmi_power_consumption_watts[1h])
```

### Voltage Metrics

```promql
# Voltage rail readings
ipmi_voltage_volts

# Example query: All voltage rails
ipmi_voltage_volts{node="homelab"}

# Example query: 12V rail
ipmi_voltage_volts{sensor=~".*12V.*"}

# Example query: Voltage out of range
abs(ipmi_voltage_volts - 12) > 0.6
```

### Sensor Status Metrics

```promql
# Sensor health status (0=bad, 1=good)
ipmi_up

# Example query: All sensor status
ipmi_up{node="homelab"}

# Example query: Failed sensors
ipmi_up{node="homelab"} == 0
```

## Prometheus Configuration

The IPMI exporter is automatically scraped by Prometheus with this configuration:

### Local IPMI Monitoring (homelab node)

```yaml
- job_name: 'ipmi-exporter'
  static_configs:
  - targets:
    - '192.168.4.62:9290'
    labels:
      node: 'homelab'
      role: 'compute'
      os: 'rhel10'
      hardware: 'enterprise-server'
  metrics_path: /metrics
  scrape_interval: 30s
  scrape_timeout: 20s
```

### Remote IPMI Monitoring (enterprise server at 192.168.4.60)

The Prometheus stack also supports remote IPMI monitoring for enterprise servers accessible via IPMI over LAN. This configuration monitors the BMC at 192.168.4.60:

```yaml
- job_name: 'ipmi-exporter-remote'
  static_configs:
  - targets:
    - '192.168.4.60'  # Remote enterprise server BMC address
    labels:
      node: 'enterprise-server-60'
      role: 'enterprise-compute'
      hardware: 'enterprise-server'
  metrics_path: /metrics
  scrape_interval: 30s
  scrape_timeout: 20s
  relabel_configs:
  # Redirect scrape to ipmi-exporter-remote service
  - source_labels: [__address__]
    target_label: __param_target
  - source_labels: [__param_target]
    target_label: instance
  - target_label: __address__
    replacement: ipmi-exporter-remote.monitoring.svc.cluster.local:9291
```

**Key Differences:**
- Remote IPMI uses a separate deployment (`ipmi-exporter-remote`) that connects to BMC over the network
- Authentication credentials are stored in Kubernetes secrets (created from `ansible/inventory/group_vars/secrets.yml`)
- The exporter runs on port 9291 (vs. 9290 for local IPMI)
- Uses relabel configs to redirect Prometheus scrapes to the remote IPMI exporter service

**Security Note:** Remote IPMI credentials are securely managed through:
1. Define `ipmi_username` and `ipmi_password` in `ansible/inventory/group_vars/secrets.yml`
2. Encrypt the secrets file using ansible-vault
3. The deployment process creates a Kubernetes secret `ipmi-credentials` in the monitoring namespace
4. The IPMI exporter pod reads credentials from the secret via environment variables

## Deployment Steps

### Prerequisites

1. **Configure IPMI Credentials**

   Edit `ansible/inventory/group_vars/secrets.yml` and add:
   ```yaml
   ipmi_username: "your_ipmi_username"
   ipmi_password: "your_ipmi_password"
   ```

2. **Encrypt Secrets File**

   ```bash
   ansible-vault encrypt ansible/inventory/group_vars/secrets.yml
   ```

### Deploy the Monitoring Stack

1. **Deploy using Ansible playbook**

   The deployment is integrated into the main cluster deployment playbook:
   ```bash
   cd /path/to/VMStation
   ansible-playbook -i ansible/inventory.txt ansible/playbooks/deploy-cluster.yaml --ask-vault-pass
   ```

   This will:
   - Create the `monitoring` namespace
   - Create the `ipmi-credentials` secret from your vaulted variables
   - Deploy the local IPMI exporter (DaemonSet on RHEL 10 node)
   - Deploy the remote IPMI exporter (Deployment for 192.168.4.60)
   - Deploy Prometheus with both IPMI scrape jobs
   - Deploy Grafana for visualization

2. **Or deploy manually**

   ```bash
   # Create namespace
   kubectl create namespace monitoring

   # Create IPMI credentials secret
   kubectl create secret generic ipmi-credentials \
     --from-literal=username='YOUR_IPMI_USERNAME' \
     --from-literal=password='YOUR_IPMI_PASSWORD' \
     --namespace=monitoring

   # Deploy IPMI exporters
   kubectl apply -f manifests/monitoring/ipmi-exporter.yaml

   # Deploy Prometheus
   kubectl apply -f manifests/monitoring/prometheus.yaml

   # Deploy Grafana
   kubectl apply -f manifests/monitoring/grafana.yaml
   ```

### Verify Deployment

1. **Check pod status**

   ```bash
   kubectl get pods -n monitoring
   ```

   Expected output:
   ```
   NAME                                    READY   STATUS    RESTARTS   AGE
   ipmi-exporter-xxxxx                     1/1     Running   0          5m
   ipmi-exporter-remote-xxxxxxxxxx-xxxxx   1/1     Running   0          5m
   prometheus-xxxxxxxxxx-xxxxx             1/1     Running   0          5m
   grafana-xxxxxxxxxx-xxxxx                1/1     Running   0          5m
   ```

2. **Check Prometheus targets**

   ```bash
   kubectl port-forward -n monitoring svc/prometheus 9090:9090
   ```

   Open http://localhost:9090/targets and verify:
   - `ipmi-exporter` target (192.168.4.62:9290) is UP
   - `ipmi-exporter-remote` target (192.168.4.60) is UP

3. **Test IPMI metrics**

   ```bash
   # For local IPMI (homelab node)
   curl http://192.168.4.62:9290/metrics | grep ipmi_temperature

   # For remote IPMI (via service)
   kubectl port-forward -n monitoring svc/ipmi-exporter-remote 9291:9291
   curl http://localhost:9291/metrics?target=192.168.4.60 | grep ipmi_temperature
   ```

4. **Query metrics in Prometheus**

   Open Prometheus UI and run these queries:
   ```promql
   # Temperature from local IPMI
   ipmi_temperature_celsius{node="homelab"}

   # Temperature from remote IPMI
   ipmi_temperature_celsius{node="enterprise-server-60"}

   # All IPMI sensors from both servers
   ipmi_temperature_celsius
   ```

## Grafana Dashboard

### Access the IPMI Dashboard

1. Open Grafana: `http://192.168.4.63:30300`
2. Navigate to "Dashboards" → "Browse"
3. Select "IPMI Hardware Monitoring - RHEL 10 Enterprise Server"

### Dashboard Panels

**Overview Panels:**
- Current Temperature Status (max temp across all sensors)
- BMC Status (online/offline indicator)
- Current Power Draw

**Detailed Panels:**
- Server Temperature Sensors (all temp sensors over time)
- Fan Speeds (all fans in RPM)
- Power Consumption (watts over time)
- Voltage Sensors (all voltage rails)
- Sensor Status Table (health of all sensors)

### Alert Thresholds

**Temperature:**
- Green: < 65°C
- Yellow: 65-75°C
- Orange: 75-85°C
- Red: > 85°C

**Fan Speed:**
- Red: < 1000 RPM (critical)
- Yellow: 1000-2000 RPM (warning)
- Green: > 2000 RPM (normal)

**Power:**
- Green: < 200W (normal)
- Yellow: 200-300W (high)
- Red: > 300W (critical)

## Alerting Rules

The following alert rules are pre-configured:

```yaml
# High temperature alert
- alert: IPMIHighTemperature
  expr: ipmi_temperature_celsius > 75
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High temperature on {{ $labels.node }}"
    description: "Temperature sensor {{ $labels.sensor }} on {{ $labels.node }} is above 75°C (current: {{ $value }}°C)"

# Low fan speed alert
- alert: IPMIFanSpeed
  expr: ipmi_fan_speed_rpm < 1000
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Low fan speed on {{ $labels.node }}"
    description: "Fan {{ $labels.sensor }} on {{ $labels.node }} is below 1000 RPM (current: {{ $value }} RPM)"
```

## Troubleshooting

### IPMI Exporter Pod Not Running

```bash
# Check pod status
kubectl get pods -n monitoring -l app=ipmi-exporter

# Check events
kubectl describe pod -n monitoring -l app=ipmi-exporter

# Common issues:
# 1. Node doesn't have correct label
kubectl label node homelab vmstation.io/role=compute --overwrite

# 2. IPMI modules not loaded on host
kubectl exec -n monitoring ipmi-exporter-xxx -- modprobe ipmi_devintf

# 3. Insufficient privileges
kubectl describe pod -n monitoring ipmi-exporter-xxx | grep -A 10 Security
# Should show: privileged: true, SYS_ADMIN, SYS_RAWIO
```

### No Metrics Available

```bash
# Check IPMI exporter logs
kubectl logs -n monitoring -l app=ipmi-exporter

# Test IPMI locally on the node
ssh homelab
sudo ipmitool sensor list

# Verify /dev/ipmi0 exists
ls -la /dev/ipmi*

# If missing, load modules
sudo modprobe ipmi_devintf
sudo modprobe ipmi_si
```

### Metrics Show Zero or N/A

```bash
# Some sensors may not be available on all hardware
# Check which sensors are actually present
sudo ipmitool sensor list | grep -v "na"

# Update dashboard queries to match your actual sensors
# Edit Grafana dashboard to use correct sensor names
```

### BMC Not Responding

```bash
# Check BMC network connectivity
ping <BMC_IP>

# Reset BMC (caution: may interrupt monitoring)
sudo ipmitool bmc reset cold

# Wait for BMC to restart (usually 1-2 minutes)
sleep 120

# Verify BMC is back online
sudo ipmitool bmc info
```

### High CPU Usage by IPMI Exporter

```bash
# Increase scrape interval in Prometheus config
# Edit manifests/monitoring/prometheus.yaml
# Change scrape_interval from 30s to 60s for ipmi-exporter

# Reduce timeout
# Change scrape_timeout from 20s to 10s

# Restart Prometheus
kubectl rollout restart deployment -n monitoring prometheus
```

## Security Considerations

### Production Recommendations

1. **BMC Network Isolation**
   - Use dedicated management network for BMC
   - Implement VLANs to separate BMC traffic
   - Use firewall rules to restrict BMC access

2. **IPMI Credentials**
   - Use strong, unique passwords for IPMI
   - Rotate credentials regularly
   - Store credentials in Kubernetes secrets

3. **Network Policies**
   ```yaml
   # Allow only Prometheus to scrape IPMI exporter
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: ipmi-exporter-policy
     namespace: monitoring
   spec:
     podSelector:
       matchLabels:
         app: ipmi-exporter
     ingress:
     - from:
       - podSelector:
           matchLabels:
             app: prometheus
       ports:
       - protocol: TCP
         port: 9290
   ```

4. **Audit Logging**
   - Enable IPMI command logging
   - Monitor BMC access logs
   - Alert on suspicious activity

## Maintenance

### Regular Tasks

**Daily:**
- Monitor temperature trends
- Check for fan failures
- Review power consumption

**Weekly:**
- Verify all sensors are reporting
- Check for BMC firmware updates
- Review alert history

**Monthly:**
- Test BMC connectivity
- Validate sensor calibration
- Update IPMI exporter if needed

### BMC Firmware Updates

```bash
# Check current BMC version
sudo ipmitool bmc info | grep "Firmware Revision"

# Download firmware from vendor
# Follow vendor-specific update procedure
# Usually: ipmitool exec <firmware_file>

# Verify update
sudo ipmitool bmc info
```

## Advanced Configuration

### Custom Sensor Thresholds

Edit the IPMI exporter configuration to set custom thresholds:

```yaml
# manifests/monitoring/ipmi-exporter.yaml
# In the ConfigMap section
data:
  ipmi.yml: |
    modules:
      default:
        collectors:
        - ipmi
        - dcmi
        - bmc
        - chassis
        timeout: 10s
        driver: "LAN_2_0"
        privilege: "user"
        # Custom sensor configuration
        sensors:
          CPU_Temp:
            warn_upper: 70
            crit_upper: 85
          System_Temp:
            warn_upper: 60
            crit_upper: 75
```

### Multiple BMC Monitoring

If you have multiple enterprise servers:

```yaml
# Add additional IPMI exporter instances
- job_name: 'ipmi-exporter-server2'
  static_configs:
  - targets:
    - 'server2.example.com:9290'
    labels:
      node: 'server2'
      datacenter: 'dc1'
```

### Integration with Other Tools

**1. Export to InfluxDB:**
```yaml
# Add remote write to Prometheus config
remote_write:
- url: "http://influxdb:8086/api/v1/prom/write?db=metrics"
  queue_config:
    capacity: 10000
```

**2. Alert to Slack:**
```yaml
# Configure Alertmanager
route:
  receiver: 'slack-ipmi'
  group_by: ['alertname', 'node']
  
receivers:
- name: 'slack-ipmi'
  slack_configs:
  - api_url: 'https://hooks.slack.com/services/XXX'
    channel: '#hardware-alerts'
```

### Remote IPMI Exporter Troubleshooting

**Pod not starting:**

```bash
# Check pod status
kubectl get pods -n monitoring -l app=ipmi-exporter-remote

# Check pod logs
kubectl logs -n monitoring -l app=ipmi-exporter-remote

# Check if secret exists
kubectl get secret ipmi-credentials -n monitoring

# View secret (without showing values)
kubectl describe secret ipmi-credentials -n monitoring
```

**Authentication failures:**

```bash
# Verify credentials are correct in secrets.yml
# Re-create the secret with correct credentials
kubectl delete secret ipmi-credentials -n monitoring
kubectl create secret generic ipmi-credentials \
  --from-literal=username='CORRECT_USERNAME' \
  --from-literal=password='CORRECT_PASSWORD' \
  --namespace=monitoring

# Restart the remote IPMI exporter
kubectl rollout restart deployment/ipmi-exporter-remote -n monitoring
```

**No metrics from 192.168.4.60:**

```bash
# Test network connectivity to BMC
ping 192.168.4.60

# Test IPMI access from a node
ipmitool -I lanplus -H 192.168.4.60 -U username -P password sensor list

# Check Prometheus target status
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets
# Look for ipmi-exporter-remote target status

# Check remote exporter logs
kubectl logs -n monitoring -l app=ipmi-exporter-remote --tail=50
```

**Metrics showing but not in Prometheus:**

```bash
# Check Prometheus configuration
kubectl get configmap prometheus-config -n monitoring -o yaml | grep -A 20 ipmi-exporter-remote

# Verify the service DNS is resolvable
kubectl exec -n monitoring deployment/prometheus -- nslookup ipmi-exporter-remote.monitoring.svc.cluster.local

# Reload Prometheus configuration
kubectl exec -n monitoring deployment/prometheus -- wget -qO- --post-data='' http://localhost:9090/-/reload
```

## Conclusion

IPMI monitoring provides critical visibility into enterprise server hardware health. With this setup:

- ✅ Real-time temperature monitoring
- ✅ Fan speed tracking with alerts
- ✅ Power consumption visibility
- ✅ Voltage rail monitoring
- ✅ BMC health status
- ✅ Pre-configured dashboard
- ✅ Automated alerting
- ✅ Remote IPMI support for multiple servers
- ✅ Secure credential management via Kubernetes secrets

Regular monitoring of these metrics helps prevent hardware failures and ensures optimal server operation.

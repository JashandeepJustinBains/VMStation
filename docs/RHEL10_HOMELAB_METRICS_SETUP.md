# RHEL10 Homelab Node Metrics Collection Configuration

## Overview

This guide explains how to configure the RHEL10 homelab node (192.168.4.62) to send metrics to the VMStation monitoring stack.

## Architecture

The homelab node runs RKE2 Kubernetes and should export metrics for:
- **Node Exporter**: System metrics (CPU, memory, disk, network)
- **RKE2 Components**: Kubernetes component metrics
- **IPMI Exporter**: Hardware sensor data (temperature, fans, power)
- **Syslog**: System logs forwarded to centralized syslog-ng

Prometheus on the Debian masternode scrapes these endpoints and stores metrics for visualization in Grafana.

---

## Prerequisites

- RHEL10 homelab node accessible at 192.168.4.62
- SSH access with root or sudo privileges
- Network connectivity between homelab and masternode
- Firewall rules allowing inbound connections on required ports

---

## 1. Node Exporter Installation

Node Exporter exposes system-level metrics on port 9100.

### Installation Steps

```bash
# SSH to homelab node
ssh root@192.168.4.62

# Create node_exporter user
useradd --no-create-home --shell /bin/false node_exporter

# Download Node Exporter (check for latest version)
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz

# Extract
tar xvf node_exporter-1.7.0.linux-amd64.tar.gz

# Install binary
cp node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Clean up
rm -rf /tmp/node_exporter-*
```

### Systemd Service Configuration

Create `/etc/systemd/system/node_exporter.service`:

```ini
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \
  --collector.filesystem.mount-points-exclude='^/(dev|proc|sys|var/lib/docker/.+|var/lib/kubelet/.+)($|/)' \
  --collector.netclass.ignored-devices='^(veth.*|[a-f0-9]{15})$' \
  --collector.netdev.device-exclude='^(veth.*|[a-f0-9]{15})$'

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Start and Enable Service

```bash
systemctl daemon-reload
systemctl start node_exporter
systemctl enable node_exporter
systemctl status node_exporter
```

### Verify Metrics

```bash
curl http://localhost:9100/metrics | head -20
```

Expected output: Prometheus-formatted metrics like `node_cpu_seconds_total`, `node_memory_MemTotal_bytes`, etc.

---

## 2. Firewall Configuration

Allow Prometheus to scrape metrics from the homelab node.

### For firewalld (RHEL default)

```bash
# Allow node-exporter
firewall-cmd --permanent --add-port=9100/tcp
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.4.63/32" port protocol="tcp" port="9100" accept'

# Allow IPMI exporter (if installed)
firewall-cmd --permanent --add-port=9290/tcp
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.4.63/32" port protocol="tcp" port="9290" accept'

# Reload firewall
firewall-cmd --reload

# Verify rules
firewall-cmd --list-all
```

### For iptables

```bash
iptables -A INPUT -p tcp -s 192.168.4.63 --dport 9100 -j ACCEPT
iptables -A INPUT -p tcp -s 192.168.4.63 --dport 9290 -j ACCEPT
iptables-save > /etc/sysconfig/iptables
```

### Test Connectivity from Masternode

From masternode (192.168.4.63):

```bash
curl http://192.168.4.62:9100/metrics | head -10
```

If this fails, check:
1. Firewall rules on homelab
2. Network connectivity: `ping 192.168.4.62`
3. Node exporter is running: `systemctl status node_exporter`

---

## 3. IPMI Exporter Installation (Hardware Monitoring)

IPMI Exporter exposes hardware sensor metrics (temperature, fans, power) on port 9290.

### Prerequisites

- Server with IPMI/BMC support
- IPMI tools installed
- BMC network access

### Install IPMI Tools

```bash
dnf install -y ipmitool freeipmi
```

### Test IPMI Access

```bash
# Local sensor readout
ipmitool sensor list

# If using remote BMC
ipmitool -I lanplus -H <bmc-ip> -U <user> -P <password> sensor list
```

### Install IPMI Exporter

```bash
# Create ipmi_exporter user
useradd --no-create-home --shell /bin/false ipmi_exporter

# Download IPMI Exporter
cd /tmp
wget https://github.com/prometheus-community/ipmi_exporter/releases/download/v1.6.1/ipmi_exporter-1.6.1.linux-amd64.tar.gz

# Extract
tar xvf ipmi_exporter-1.6.1.linux-amd64.tar.gz

# Install binary
cp ipmi_exporter-1.6.1.linux-amd64/ipmi_exporter /usr/local/bin/
chown ipmi_exporter:ipmi_exporter /usr/local/bin/ipmi_exporter

# Clean up
rm -rf /tmp/ipmi_exporter-*
```

### Configuration File

Create `/etc/ipmi_exporter.yml`:

```yaml
# IPMI Exporter Configuration
modules:
  default:
    user: ""  # Leave empty for local access
    pass: ""
    driver: "LAN_2_0"
    privilege: "user"
    timeout: 10000
    collectors:
    - bmc
    - ipmi
    - chassis
    - dcmi
    - sel
    exclude_sensor_ids: []
  
  # For remote BMC access (if needed)
  remote:
    user: "ADMIN"
    pass: "changeme"
    driver: "LAN_2_0"
    privilege: "admin"
```

### Systemd Service

Create `/etc/systemd/system/ipmi_exporter.service`:

```ini
[Unit]
Description=IPMI Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=ipmi_exporter
Group=ipmi_exporter
Type=simple
ExecStart=/usr/local/bin/ipmi_exporter \
  --config.file=/etc/ipmi_exporter.yml \
  --web.listen-address=:9290

# Grant CAP_SYS_RAWIO for local IPMI access
AmbientCapabilities=CAP_SYS_RAWIO
CapabilityBoundingSet=CAP_SYS_RAWIO

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Start Service

```bash
systemctl daemon-reload
systemctl start ipmi_exporter
systemctl enable ipmi_exporter
systemctl status ipmi_exporter
```

### Verify Metrics

```bash
curl http://localhost:9290/metrics | grep ipmi_temperature
```

---

## 4. RKE2 Metrics (Optional)

If running RKE2 on the homelab node, expose component metrics.

### RKE2 Component Metrics

RKE2 exposes metrics on various ports:
- **kube-apiserver**: 6443 (requires auth)
- **kubelet**: 10250
- **kube-controller-manager**: 10257
- **kube-scheduler**: 10259

### Prometheus Scrape Configuration

On the masternode, update Prometheus config to scrape RKE2:

```yaml
# Add to manifests/monitoring/prometheus.yaml
scrape_configs:
  # RKE2 Kubelet on homelab
  - job_name: 'rke2-kubelet'
    static_configs:
    - targets:
      - '192.168.4.62:10250'
      labels:
        node: 'homelab'
        cluster: 'rke2'
    scheme: https
    tls_config:
      insecure_skip_verify: true
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
```

---

## 5. Syslog Forwarding

Forward system logs from homelab to the centralized syslog-ng server.

### Install rsyslog

RHEL10 includes rsyslog by default:

```bash
systemctl status rsyslog
```

### Configure Log Forwarding

Edit `/etc/rsyslog.d/50-forward-to-vmstation.conf`:

```
# Forward all logs to VMStation syslog server
# TCP is recommended for reliability
*.* @@192.168.4.63:30515

# Alternative: UDP (less reliable but faster)
# *.* @192.168.4.63:30514

# TLS (RFC5424) - most secure
# *.* @@192.168.4.63:30601
```

### Restart rsyslog

```bash
systemctl restart rsyslog
systemctl status rsyslog
```

### Test Syslog Forwarding

```bash
logger -t vmstation-test "Test message from homelab node"
```

On masternode, check if log appears in Loki:
```bash
kubectl logs -n infrastructure syslog-server-0 | tail -20
```

Or query in Grafana → Loki Logs dashboard → filter for `{job="syslog"}`

---

## 6. Prometheus Configuration Update

Update Prometheus on masternode to scrape homelab metrics.

### Edit Prometheus ConfigMap

The homelab node is already configured in `manifests/monitoring/prometheus.yaml`:

```yaml
# Node Exporter - All nodes
- job_name: 'node-exporter'
  static_configs:
  - targets:
    - '192.168.4.62:9100'  # homelab (RHEL 10 worker)
    labels:
      node: 'homelab'
      role: 'worker'
      os: 'rhel10'
```

```yaml
# IPMI Exporter - Hardware monitoring
- job_name: 'ipmi-exporter'
  static_configs:
  - targets:
    - '192.168.4.62:9290'
    labels:
      node: 'homelab'
      server_type: 'rhel10-enterprise'
```

If not present, add these and apply:

```bash
kubectl apply -f manifests/monitoring/prometheus.yaml
kubectl delete pod prometheus-0 -n monitoring
```

---

## 7. Verification and Testing

### Check Prometheus Targets

1. Access Prometheus: `http://192.168.4.63:30090`
2. Go to Status → Targets
3. Verify homelab targets are **UP**:
   - `node-exporter` (192.168.4.62:9100)
   - `ipmi-exporter` (192.168.4.62:9290)

### Check Grafana Dashboards

1. Access Grafana: `http://192.168.4.63:30300`
2. Open dashboards:
   - **Node Metrics - Detailed System Monitoring**: Should show homelab node
   - **IPMI Hardware Monitoring**: Should show temperature, fans, power
   - **Loki Logs & Aggregation**: Should show homelab syslog entries
   - **Syslog Infrastructure Monitoring**: Should show messages from homelab

### Query Metrics in Prometheus

Test queries:
```promql
# Node exporter metrics
node_cpu_seconds_total{node="homelab"}

# IPMI metrics
ipmi_temperature_celsius{node="homelab"}

# System load
node_load5{node="homelab"}
```

### Query Logs in Loki

In Grafana → Explore → Loki:
```
# Homelab system logs
{job="syslog", hostname="homelab"}

# Last 5 minutes
{job="syslog", hostname="homelab"} [5m]
```

---

## Troubleshooting

### Node Exporter Not Reachable

1. **Check service status**:
   ```bash
   systemctl status node_exporter
   journalctl -u node_exporter -f
   ```

2. **Test local access**:
   ```bash
   curl http://localhost:9100/metrics
   ```

3. **Check firewall**:
   ```bash
   firewall-cmd --list-all
   ss -tlnp | grep 9100
   ```

4. **Test from masternode**:
   ```bash
   curl http://192.168.4.62:9100/metrics
   telnet 192.168.4.62 9100
   ```

### IPMI Exporter Issues

1. **Check IPMI access**:
   ```bash
   ipmitool sensor list
   ```

2. **Check service**:
   ```bash
   systemctl status ipmi_exporter
   journalctl -u ipmi_exporter -f
   ```

3. **Verify capabilities**:
   ```bash
   systemctl show ipmi_exporter | grep Cap
   ```

4. **Test metrics endpoint**:
   ```bash
   curl http://localhost:9290/metrics
   ```

### No Logs in Syslog Dashboard

1. **Check rsyslog**:
   ```bash
   systemctl status rsyslog
   journalctl -u rsyslog -f
   ```

2. **Verify syslog-ng pod**:
   ```bash
   kubectl get pods -n infrastructure
   kubectl logs -n infrastructure syslog-server-0
   ```

3. **Test connectivity**:
   ```bash
   telnet 192.168.4.63 30515
   logger -n 192.168.4.63 -P 30515 "Test from homelab"
   ```

4. **Check firewall on masternode**:
   ```bash
   kubectl get svc -n infrastructure syslog-server
   ```

---

## Security Hardening

### 1. Restrict Exporter Access

Only allow scraping from Prometheus (192.168.4.63):

```bash
firewall-cmd --remove-port=9100/tcp --permanent
firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.4.63/32" port protocol="tcp" port="9100" accept' --permanent
firewall-cmd --reload
```

### 2. Use TLS for Exporters

Configure node_exporter with TLS:

```bash
# Generate certificate
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
  -keyout /etc/node_exporter/node_exporter.key \
  -out /etc/node_exporter/node_exporter.crt \
  -subj "/CN=homelab.vmstation.local"

# Update systemd service
ExecStart=/usr/local/bin/node_exporter \
  --web.config.file=/etc/node_exporter/web-config.yml
```

Create `/etc/node_exporter/web-config.yml`:
```yaml
tls_server_config:
  cert_file: /etc/node_exporter/node_exporter.crt
  key_file: /etc/node_exporter/node_exporter.key
```

### 3. Secure Syslog

Use TLS for syslog forwarding (port 30601).

---

## Maintenance

### Update Exporters

```bash
# Stop service
systemctl stop node_exporter

# Download new version
cd /tmp
wget <new-version-url>
tar xvf node_exporter-*.tar.gz
cp node_exporter-*/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter

# Restart
systemctl start node_exporter
systemctl status node_exporter
```

### Monitor Exporter Health

Create alert in Prometheus for down exporters:

```yaml
- alert: ExporterDown
  expr: up{job="node-exporter", node="homelab"} == 0
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Node exporter down on homelab"
```

---

## Summary

After completing this guide, the RHEL10 homelab node will:
- ✅ Export system metrics via node_exporter (port 9100)
- ✅ Export hardware metrics via ipmi_exporter (port 9290)
- ✅ Forward system logs to centralized syslog-ng
- ✅ Be monitored in Grafana dashboards
- ✅ Have proper firewall rules for security

All metrics and logs are now centralized in the VMStation monitoring stack!

---

**Last Updated**: 2025-10-10  
**Tested On**: RHEL 10.0, RKE2 v1.28  
**Author**: VMStation Operations Team

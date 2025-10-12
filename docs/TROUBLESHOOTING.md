# VMStation Troubleshooting Guide

Quick diagnostic checks and solutions for VMStation clusters.

## Automated Validation

**Before manually troubleshooting**, run the automated validation suite:

```bash
# Run complete validation (recommended)
./tests/test-complete-validation.sh

# Or run individual validation tests
./tests/test-autosleep-wake-validation.sh      # Auto-sleep/wake configuration
./tests/test-monitoring-exporters-health.sh    # Monitoring stack health
./tests/test-loki-validation.sh                # Loki log aggregation
./tests/test-monitoring-access.sh              # Monitoring endpoints
```

## Diagnostic Scripts

VMStation includes diagnostic and remediation scripts:

```bash
# Diagnose monitoring stack issues
./scripts/diagnose-monitoring-stack.sh

# Remediate common monitoring problems
./scripts/remediate-monitoring-stack.sh

# Validate monitoring stack is working
./scripts/validate-monitoring-stack.sh
```

## Common Deployment Issues

### Worker Node Join Hangs

**Symptom**: Deployment hangs at "Wait for kubelet config to appear (join completion)"

**Causes**:
1. Missing kubeadm binary on master node
2. Network connectivity issues between worker and master
3. Join command failed silently

**Solution**:
```bash
# On master node, verify kubeadm is installed
which kubeadm

# If missing, install it
./scripts/install-k8s-binaries-manual.sh

# Check join token is valid
kubeadm token list

# Re-run deployment
./deploy.sh debian
```

### Loki CrashLoopBackOff

**Symptom**: Loki pod keeps restarting

**Causes**:
1. Incorrect schema configuration (period mismatch)
2. Wrong storage permissions
3. Config drift from manual edits

**Solution**:
```bash
# Check Loki logs
kubectl --kubeconfig=/etc/kubernetes/admin.conf logs -n monitoring -l app=loki

# Common error: "period of 168h is incompatible with boltdb-shipper"
# Fix: Redeploy with correct 24h period
./deploy.sh monitoring

# Verify storage permissions
ls -la /srv/monitoring_data/loki
sudo chown -R 10001:10001 /srv/monitoring_data/loki

# Prevent config drift
./tests/test-loki-config-drift.sh
```

### Monitoring Stack Validation

Use the monitoring stack validation script:

```bash
./scripts/validate-monitoring-stack.sh
```

This checks:
- All monitoring pods are running
- Services have endpoints
- Prometheus targets are healthy
- Grafana datasources are connected

## Cluster Health Checks

### 1. Check Cluster Nodes

**Debian Cluster**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide
```

**RKE2 Cluster**:
```bash
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes -o wide
```

**Expected**: All nodes `Ready`, correct Kubernetes version

**If not Ready**:
```bash
# Check kubelet
systemctl status kubelet
journalctl -xeu kubelet

# Verify CNI
ls /etc/cni/net.d/

# Check if node is cordoned
kubectl uncordon <node-name>
```

### 2. Check System Pods

**Debian Cluster**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -o wide
```

**Critical pods** must be Running:
- `kube-flannel-*` (DaemonSet)
- `kube-proxy-*` (DaemonSet)
- `coredns-*` (2 replicas)

**If CrashLoopBackOff**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf describe pod <pod-name> -n kube-system
kubectl --kubeconfig=/etc/kubernetes/admin.conf logs <pod-name> -n kube-system
```

### 3. Verify CNI Configuration

```bash
# Check CNI config on all Debian nodes
ssh root@192.168.4.63 "cat /etc/cni/net.d/10-flannel.conflist"
ssh root@192.168.4.61 "cat /etc/cni/net.d/10-flannel.conflist"

# Check CNI plugins installed
ls -la /opt/cni/bin/
```

**Expected**: Flannel config exists, plugins installed (bridge, loopback, etc.)

## Monitoring Stack Troubleshooting

### Prometheus Not Scraping Targets

**Check Prometheus targets**:
```bash
# Access Prometheus UI
# http://192.168.4.63:30090/targets

# Or use API
curl http://192.168.4.63:30090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

**Common issues**:
- Firewall blocking ports (9100, 9290)
- Node exporter not running
- Network policies blocking traffic

**Fix firewall** (RHEL10):
```bash
# On homelab node
sudo firewall-cmd --add-port=9100/tcp --permanent
sudo firewall-cmd --add-port=9290/tcp --permanent
sudo firewall-cmd --reload
```

**Verify node exporter**:
```bash
# Check if running
systemctl status node_exporter

# Test locally
curl http://localhost:9100/metrics

# Test from masternode
curl http://192.168.4.62:9100/metrics
```

### Grafana Datasource Connectivity

**Access Grafana**: http://192.168.4.63:30300

**Test datasources**:
1. Navigate to Configuration → Data Sources
2. Click on Prometheus → "Test" button
3. Click on Loki → "Test" button

**If Prometheus fails**:
```bash
# Check Prometheus service
kubectl --kubeconfig=/etc/kubernetes/admin.conf get svc -n monitoring prometheus

# Check endpoints
kubectl --kubeconfig=/etc/kubernetes/admin.conf get endpoints -n monitoring prometheus

# Test from Grafana pod
kubectl --kubeconfig=/etc/kubernetes/admin.conf exec -n monitoring deploy/grafana -- \
  curl http://prometheus.monitoring.svc.cluster.local:9090/-/healthy
```

**If Loki fails**:
```bash
# Check Loki service
kubectl --kubeconfig=/etc/kubernetes/admin.conf get svc -n monitoring loki

# Test Loki ready endpoint
kubectl --kubeconfig=/etc/kubernetes/admin.conf exec -n monitoring deploy/loki -- \
  wget -qO- http://localhost:3100/ready

# Should return: ready
```

### IPMI Exporter Down

**Expected behavior**: IPMI exporter requires hardware credentials

**If you don't have IPMI/iDRAC access**:
- This is expected and normal
- The scrape target will show as DOWN
- No action needed unless you want hardware monitoring

**To enable IPMI monitoring**:
```bash
# Install IPMI tools on homelab
ssh root@192.168.4.62
dnf install -y ipmitool freeipmi

# Download and setup ipmi_exporter
# Follow: docs/RHEL10_HOMELAB_METRICS_SETUP.md

# Configure firewall
firewall-cmd --add-port=9290/tcp --permanent
firewall-cmd --reload
```

## Wake-on-LAN Troubleshooting

### WoL Not Waking Node

**Check WoL enabled in BIOS/UEFI**:
- Must be enabled in BIOS
- Some systems call it "Wake on Magic Packet"

**Check network interface WoL settings**:
```bash
# On the node you want to wake
sudo ethtool <interface> | grep Wake-on
# Should show: Wake-on: g
```

**Enable WoL** if disabled:
```bash
sudo ethtool -s <interface> wol g
```

**Make persistent** (systemd):
```bash
# Create /etc/systemd/system/wol@.service
sudo nano /etc/systemd/system/wol@.service

# Enable for interface
sudo systemctl enable wol@eno1.service
```

**Test WoL from masternode**:
```bash
# Install wakeonlan
apt-get install -y wakeonlan

# Send magic packet
wakeonlan -i 192.168.4.255 b8:ac:6f:7e:6c:9d

# Monitor for wake (tcpdump)
sudo tcpdump -i eno1 "tcp port 22 and tcp[tcpflags] & tcp-syn != 0" -c 1
```

### Auto-Sleep Not Triggering

**Check cron job**:
```bash
# On masternode
crontab -l | grep vmstation

# Check sleep script exists
ls -la /usr/local/bin/vmstation-check-idle.sh

# Run manually to test
sudo /usr/local/bin/vmstation-check-idle.sh --dry-run
```

**Check activity detection**:
```bash
# View recent activity checks
sudo cat /var/log/vmstation/activity.log

# Verify Jellyfin API is reachable
curl http://192.168.4.61:8096/System/Info
```

### Wake Event Not Detecting

**Check systemd timer**:
```bash
# On masternode
systemctl list-timers | grep vmstation

# View timer status
systemctl status vmstation-event-wake.timer

# View service status
systemctl status vmstation-event-wake.service
```

**Check logs**:
```bash
# View wake event logs
journalctl -u vmstation-event-wake.service -f

# Check state file
cat /var/lib/vmstation/state
```

## Network Diagnostics

### Pod-to-Pod Communication

**Test from one pod to another**:
```bash
# Get pod IPs
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring -o wide

# Exec into a pod
kubectl --kubeconfig=/etc/kubernetes/admin.conf exec -it -n monitoring deploy/grafana -- sh

# Ping another pod (if ping available)
ping <other-pod-ip>

# Or use wget/curl
wget -qO- http://<other-pod-ip>:port
```

### DNS Resolution

**Test DNS from pod**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf exec -it -n monitoring deploy/grafana -- sh

# Test service DNS
nslookup prometheus.monitoring.svc.cluster.local

# Test external DNS
nslookup google.com
```

**If DNS fails**:
```bash
# Check CoreDNS pods
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system -l k8s-app=kube-dns

# Check CoreDNS logs
kubectl --kubeconfig=/etc/kubernetes/admin.conf logs -n kube-system -l k8s-app=kube-dns
```

### Service Connectivity

**Check service endpoints**:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get svc -n monitoring
kubectl --kubeconfig=/etc/kubernetes/admin.conf get endpoints -n monitoring
```

**Expected**: Each service should have endpoints matching pod IPs

**If no endpoints**:
- Check pod selector matches deployment labels
- Verify pods are Running and Ready
- Check pod ports match service targetPort

## Time Synchronization

**Critical for Kubernetes**: All nodes must have synchronized time

**Check time on all nodes**:
```bash
# masternode
date

# storagenodet3500
ssh root@192.168.4.61 date

# homelab
ssh jashandeepjustinbains@192.168.4.62 date
```

**Check chrony status**:
```bash
# On each node
chronyc tracking
chronyc sources
```

**If time drift > 1 second**:
```bash
# Force time sync
sudo chronyc makestep

# Restart chronyd
sudo systemctl restart chronyd
```

**Run validation**:
```bash
./tests/validate-time-sync.sh
```

## Log Collection and Analysis

### Collect Deployment Logs

```bash
# View recent deployment logs
ls -lh ansible/artifacts/*.log

# View specific deployment log
less ansible/artifacts/deploy-debian.log
less ansible/artifacts/install-rke2-homelab.log
```

### Collect Wake Logs

```bash
# Collect all wake-related logs
./scripts/vmstation-collect-wake-logs.sh

# Outputs to: /tmp/vmstation-wake-logs-<timestamp>.tar.gz
```

### Check Loki Logs

```bash
# Check if logs are being ingested
# Access Grafana: http://192.168.4.63:30300
# Go to Explore → Select Loki
# Query: {namespace="monitoring"}
```

## SELinux Troubleshooting (RHEL10)

**Check SELinux mode**:
```bash
getenforce
```

**If you suspect SELinux is blocking**:
```bash
# Check audit log
sudo ausearch -m avc -ts recent

# Temporarily set to permissive
sudo setenforce 0

# If that fixes it, generate policy or keep permissive
```

**Make permissive persistent**:
```bash
sudo nano /etc/selinux/config
# Set: SELINUX=permissive

# Or use preflight role
ansible-playbook -i ansible/inventory/hosts.yml \
  -e 'selinux_mode=permissive' \
  ansible/playbooks/run-preflight-rhel10.yml
```

## Firewall Troubleshooting

### Check Firewall Status (RHEL10)

```bash
sudo firewall-cmd --list-all
```

**Required ports**:
- 6443/tcp (Kubernetes API)
- 10250/tcp (Kubelet)
- 30000-32767/tcp (NodePort range)
- 9100/tcp (Node Exporter)
- 9290/tcp (IPMI Exporter)

**Open ports**:
```bash
sudo firewall-cmd --add-port=9100/tcp --permanent
sudo firewall-cmd --reload
```

**Or use preflight role** (opens all required ports):
```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/run-preflight-rhel10.yml
```

## Reset and Recovery

### Full Cluster Reset

**⚠️ Warning**: This will delete all cluster data and configurations

```bash
# Reset both clusters
./deploy.sh reset --yes

# Fresh deployment
./deploy.sh setup
./deploy.sh debian
./deploy.sh monitoring
./deploy.sh infrastructure
./deploy.sh rke2  # Optional
```

### Reset Single Node

**Debian node**:
```bash
# On the node
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/kubelet
sudo systemctl restart containerd
```

**RKE2 node**:
```bash
# On homelab
sudo systemctl stop rke2-server
sudo /usr/local/bin/rke2-uninstall.sh
```

## Getting Help

### Logs to Collect

When reporting issues:
1. Deployment logs: `ansible/artifacts/*.log`
2. Cluster info: `kubectl cluster-info dump`
3. Pod logs: `kubectl logs -n <namespace> <pod-name>`
4. Node status: `kubectl get nodes -o wide`
5. System logs: `journalctl -u kubelet -n 100`

### Diagnostic Commands

Run these for comprehensive diagnostics:
```bash
# Complete validation
./tests/test-complete-validation.sh > /tmp/validation.log 2>&1

# Monitoring diagnostics
./scripts/diagnose-monitoring-stack.sh > /tmp/monitoring-diag.log 2>&1

# Sleep/wake diagnostics
./tests/test-autosleep-wake-validation.sh > /tmp/sleep-wake.log 2>&1
```

## References

- [Architecture Documentation](ARCHITECTURE.md)
- [Deployment Runbook](DEPLOYMENT_RUNBOOK.md)
- [Validation Test Guide](VALIDATION_TEST_GUIDE.md)
- [Monitoring Stack Fixes](MONITORING_STACK_FIXES_OCT2025.md)

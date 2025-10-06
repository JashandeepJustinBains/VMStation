# RKE2 Deployment - Complete Runbook

This runbook provides step-by-step instructions for deploying RKE2 on the RHEL 10 homelab node and configuring Prometheus federation.

## Quick Start (TL;DR)

```bash
# 1. Cleanup prior installation
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cleanup-homelab.yml

# 2. Install RKE2
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml

# 3. Verify
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes

# 4. Configure Prometheus federation (see Federation Setup below)
```

**Estimated time**: 20-30 minutes

## Prerequisites Checklist

Before starting, ensure:

- [ ] SSH access to homelab node (192.168.4.62)
- [ ] Ansible installed on masternode (192.168.4.63)
- [ ] Homelab has minimum 4GB RAM, 20GB free disk
- [ ] Network connectivity between masternode and homelab
- [ ] Repository cloned to `/srv/monitoring_data/VMStation` on masternode

**Verify prerequisites:**

```bash
# Test SSH access
ssh jashandeepjustinbains@192.168.4.62 'hostname && free -h && df -h /'

# Test Ansible connectivity
ansible homelab -i ansible/inventory/hosts.yml -m ping

# Verify repository location
pwd  # Should be /srv/monitoring_data/VMStation
```

## Part 1: Cleanup Prior Installation

**Duration**: 5-10 minutes

### Option A: Ansible Playbook (Recommended)

```bash
cd /srv/monitoring_data/VMStation

# Run cleanup playbook
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cleanup-homelab.yml
```

**What it does:**
- Stops kubelet and containerd services
- Removes Kubernetes binaries
- Cleans CNI plugins and configurations
- Removes all Kubernetes data directories
- Cleans iptables/nftables rules
- Removes NetworkManager Kubernetes config

**Expected output:**
```
PLAY RECAP ***************************************************
homelab                    : ok=XX   changed=YY   failed=0
```

### Option B: Manual Cleanup

```bash
# Run cleanup script on homelab
ssh jashandeepjustinbains@192.168.4.62 'sudo bash /srv/monitoring_data/VMStation/scripts/cleanup-homelab-k8s-artifacts.sh'

# Follow prompts and confirm cleanup
```

### Verification

```bash
# Verify no Kubernetes processes remain
ssh jashandeepjustinbains@192.168.4.62 'ps aux | grep -E "kube|containerd" | grep -v grep'
# Should return no results

# Verify binaries removed
ssh jashandeepjustinbains@192.168.4.62 'which kubelet'
# Should return: kubelet not found
```

## Part 2: Install RKE2

**Duration**: 10-15 minutes

### Step 1: Review Configuration (Optional)

Edit configuration if you want to customize:

```bash
# View default configuration
cat ansible/roles/rke2/defaults/main.yml

# Customize if needed (optional)
vim ansible/roles/rke2/defaults/main.yml
```

**Key variables:**
- `rke2_version: "v1.29.10+rke2r1"` - RKE2 version
- `rke2_cluster_cidr: "10.42.0.0/16"` - Pod network
- `rke2_service_cidr: "10.43.0.0/16"` - Service network
- `rke2_cni: "canal"` - CNI plugin

### Step 2: Run Installation Playbook

```bash
cd /srv/monitoring_data/VMStation

# Run installation
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml

# With verbose output (for troubleshooting)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml -vv
```

**What it does:**
1. Runs pre-flight checks
2. Prepares system (kernel modules, sysctl, etc.)
3. Downloads and installs RKE2
4. Configures RKE2 server
5. Starts rke2-server service
6. Waits for cluster to be ready
7. Deploys monitoring components (node-exporter, Prometheus)
8. Fetches kubeconfig to `ansible/artifacts/`
9. Runs verification tests

### Step 3: Monitor Installation (Optional)

In another terminal, watch RKE2 service logs:

```bash
ssh jashandeepjustinbains@192.168.4.62 'sudo journalctl -u rke2-server -f'
```

Look for:
- "Starting RKE2"
- "Wrote kubeconfig"
- "Node homelab is ready"

### Step 4: Verify Installation

```bash
# Check artifacts created
ls -lh ansible/artifacts/
# Should see: homelab-rke2-kubeconfig.yaml and install-rke2-homelab.log

# Set kubeconfig
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml

# Check node status
kubectl get nodes -o wide

# Expected output:
# NAME      STATUS   ROLES                       AGE   VERSION
# homelab   Ready    control-plane,etcd,master   5m    v1.29.10+rke2r1

# Check all pods
kubectl get pods -A

# All pods should be Running or Completed
# Key namespaces: kube-system, kube-node-lease, kube-public, monitoring-rke2

# Check monitoring pods specifically
kubectl get pods -n monitoring-rke2

# Expected:
# NAME                             READY   STATUS    RESTARTS   AGE
# node-exporter-xxxxx              1/1     Running   0          5m
# prometheus-rke2-xxxxxxxxxx-xxxxx 1/1     Running   0          5m
```

## Part 3: Verify Monitoring Endpoints

**Duration**: 2-3 minutes

```bash
# From masternode, test node-exporter
curl -s http://192.168.4.62:9100/metrics | head -20
# Should return Prometheus metrics

# Test Prometheus API
curl -s http://192.168.4.62:30090/api/v1/status/config | jq .status
# Should return: "success"

# Test federation endpoint
curl -s 'http://192.168.4.62:30090/federate?match[]={job="kubernetes-nodes"}' | head -20
# Should return federated metrics in Prometheus format
```

**All endpoints should return HTTP 200 with valid data.**

## Part 4: Configure Prometheus Federation

**Duration**: 5-10 minutes

### Step 1: Backup Current Prometheus Config

```bash
cd /srv/monitoring_data/VMStation

# Backup current configuration
cp manifests/monitoring/prometheus.yaml manifests/monitoring/prometheus.yaml.backup
```

### Step 2: Update Prometheus ConfigMap

Edit `manifests/monitoring/prometheus.yaml` and add the following to the `scrape_configs` section:

```bash
# Open the file
vim manifests/monitoring/prometheus.yaml
```

Add this configuration at the end of the `scrape_configs` array (after the last job):

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
          # Federate monitoring namespace metrics
          - '{__name__=~".+",namespace="monitoring-rke2"}'
      static_configs:
        - targets:
            - '192.168.4.62:30090'
          labels:
            cluster: 'rke2-homelab'
            environment: 'homelab'
            source: 'federation'
      relabel_configs:
        # Preserve original cluster label
        - source_labels: [cluster]
          target_label: source_cluster
          action: replace
        # Ensure cluster label is set
        - target_label: cluster
          replacement: 'rke2-homelab'
          action: replace
      scrape_interval: 30s
      scrape_timeout: 25s
```

**Important**: Ensure proper YAML indentation. The job should be at the same level as other jobs in `scrape_configs`.

### Step 3: Apply Updated Configuration

```bash
# Unset RKE2 kubeconfig to use Debian cluster
unset KUBECONFIG

# Verify you're targeting the Debian cluster
kubectl get nodes
# Should show: masternode and storagenodet3500 (NOT homelab)

# Apply updated Prometheus configuration
kubectl apply -f manifests/monitoring/prometheus.yaml

# Reload Prometheus configuration
kubectl exec -n monitoring deployment/prometheus -- curl -X POST http://localhost:9090/-/reload

# Or restart Prometheus pod
kubectl rollout restart -n monitoring deployment/prometheus

# Wait for Prometheus to be ready
kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=120s
```

### Step 4: Verify Federation is Working

```bash
# Option 1: Via port-forward
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
sleep 5

# Check targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="rke2-federation")'

# Should show target with state="up"

# Kill port-forward
pkill -f "port-forward.*prometheus"

# Option 2: Via NodePort (if accessible)
curl -s 'http://192.168.4.63:30090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job=="rke2-federation")'

# Query federated metrics
curl -s 'http://192.168.4.63:30090/api/v1/query?query=up{cluster="rke2-homelab"}' | jq .

# Expected: Should return metrics with cluster="rke2-homelab" label
```

### Step 5: Verify in Prometheus UI

```bash
# Access Prometheus UI at http://192.168.4.63:30090

# Navigate to Status > Targets
# Look for "rke2-federation" - should show State: UP

# Run test query in Expression Browser:
up{cluster="rke2-homelab"}

# Should return:
# up{cluster="rke2-homelab", instance="192.168.4.62:30090", job="rke2-federation"} = 1
```

## Part 5: Verification Checklist

Complete this checklist to confirm successful deployment:

### RKE2 Cluster Health

```bash
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml

# [ ] Node is Ready
kubectl get nodes
# Expected: homelab Ready

# [ ] All pods Running
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
# Expected: No results (empty)

# [ ] Monitoring pods Running
kubectl get pods -n monitoring-rke2
# Expected: node-exporter and prometheus-rke2 both Running

# [ ] DNS resolution works
kubectl run -it --rm test-dns --image=busybox --restart=Never -- nslookup kubernetes.default
# Expected: Resolves successfully

# [ ] Cluster info accessible
kubectl cluster-info
# Expected: Shows Kubernetes control plane URL
```

### Monitoring Endpoints

```bash
# [ ] Node exporter accessible
curl -s http://192.168.4.62:9100/metrics | grep -i node_cpu | head -5
# Expected: CPU metrics returned

# [ ] Prometheus accessible
curl -s http://192.168.4.62:30090/api/v1/status/config | jq .status
# Expected: "success"

# [ ] Federation endpoint working
curl -s 'http://192.168.4.62:30090/federate?match[]={job="prometheus"}' | head -10
# Expected: Prometheus metrics in text format
```

### Central Prometheus Federation

```bash
unset KUBECONFIG

# [ ] Federation target is UP
curl -s 'http://192.168.4.63:30090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job=="rke2-federation") | .health'
# Expected: "up"

# [ ] Can query RKE2 metrics
curl -s 'http://192.168.4.63:30090/api/v1/query?query=up{cluster="rke2-homelab"}' | jq '.data.result[0].value[1]'
# Expected: "1"

# [ ] Can query node metrics
curl -s 'http://192.168.4.63:30090/api/v1/query?query=node_memory_MemTotal_bytes{cluster="rke2-homelab"}' | jq .data.result
# Expected: Returns memory metrics
```

### Debian Cluster Unaffected

```bash
# [ ] Debian nodes unchanged
kubectl get nodes
# Expected: Only masternode and storagenodet3500 (homelab NOT listed)

# [ ] Debian pods still running
kubectl get pods -A | grep -v Running | grep -v Completed | wc -l
# Expected: 1 (only header line)
```

## Part 6: Post-Deployment Configuration

### Secure Kubeconfig

```bash
# Set restrictive permissions
chmod 600 /srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml

# Optional: Encrypt with ansible-vault
ansible-vault encrypt /srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml

# To use encrypted kubeconfig later:
ansible-vault view /srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml > /tmp/kubeconfig
export KUBECONFIG=/tmp/kubeconfig
kubectl get nodes
rm /tmp/kubeconfig
```

### Create kubectl Aliases

Add to `~/.bashrc` or `~/.bash_aliases`:

```bash
# Alias for RKE2 cluster
alias kubectl-rke2='kubectl --kubeconfig=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml'

# Alias for Debian cluster (if not default)
alias kubectl-debian='kubectl --kubeconfig=/etc/kubernetes/admin.conf'

# Source the file
source ~/.bashrc

# Test
kubectl-rke2 get nodes
kubectl-debian get nodes
```

### Deploy Sample Application (Optional)

```bash
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml

# Create test namespace
kubectl create namespace test-app

# Deploy nginx
kubectl create deployment nginx --image=nginx --namespace=test-app
kubectl expose deployment nginx --port=80 --type=NodePort --namespace=test-app

# Get NodePort
kubectl get svc -n test-app
# Access at http://192.168.4.62:<NodePort>

# Clean up when done
kubectl delete namespace test-app
```

## Troubleshooting Guide

### Issue: RKE2 service won't start

**Symptoms:**
- `systemctl status rke2-server` shows failed
- Installation playbook fails at service start

**Diagnosis:**
```bash
ssh jashandeepjustinbains@192.168.4.62 'sudo journalctl -u rke2-server -n 100 --no-pager'
```

**Common causes:**
1. Port 6443 already in use
   - Check: `sudo ss -tlnp | grep 6443`
   - Fix: Stop conflicting service
   
2. SELinux denials
   - Check: `sudo ausearch -m avc -ts recent`
   - Fix: Set SELinux to permissive: `sudo setenforce 0`
   
3. Configuration errors
   - Check: `sudo cat /etc/rancher/rke2/config.yaml`
   - Fix: Verify YAML syntax

### Issue: Pods stuck in Pending or CrashLoopBackOff

**Diagnosis:**
```bash
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get pods -A | grep -E 'Pending|CrashLoopBackOff'
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

**Common causes:**
1. Insufficient resources
   - Check: `kubectl top nodes` or `ssh 192.168.4.62 'free -h && df -h'`
   
2. Image pull errors
   - Check pod events: `kubectl describe pod <pod-name> -n <namespace>`
   - Fix: Ensure internet connectivity

3. CNI not ready
   - Check canal pods: `kubectl get pods -n kube-system -l app=canal`

### Issue: Federation not working

**Diagnosis:**
```bash
# Test federation endpoint directly
curl -v http://192.168.4.62:30090/federate

# Check central Prometheus logs
kubectl logs -n monitoring -l app=prometheus --tail=100 | grep rke2

# Check target status
curl -s 'http://192.168.4.63:30090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job=="rke2-federation")'
```

**Common causes:**
1. Endpoint not accessible
   - Check: `curl http://192.168.4.62:30090/federate`
   - Fix: Verify Prometheus pod running in RKE2
   
2. Configuration error
   - Check: Verify YAML indentation in prometheus.yaml
   - Fix: Re-apply corrected configuration

3. Firewall blocking
   - Check: `ssh 192.168.4.62 'sudo firewall-cmd --list-ports'`
   - Fix: Open port 30090

### Issue: Node not Ready

**Diagnosis:**
```bash
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl describe node homelab
```

**Look for:**
- DiskPressure: Check disk space
- MemoryPressure: Check memory usage
- NetworkUnavailable: Check CNI pods

### Getting More Help

1. **Check installation logs:**
   ```bash
   cat /srv/monitoring_data/VMStation/ansible/artifacts/install-rke2-homelab.log
   ```

2. **Review documentation:**
   - [RKE2 Deployment Guide](../docs/RKE2_DEPLOYMENT_GUIDE.md)
   - [Prometheus Federation Guide](../docs/RKE2_PROMETHEUS_FEDERATION.md)
   - [Role README](../ansible/roles/rke2/README.md)

3. **Check RKE2 community:**
   - [RKE2 Documentation](https://docs.rke2.io/)
   - [RKE2 GitHub Issues](https://github.com/rancher/rke2/issues)

## Rollback / Uninstall

If you need to remove RKE2 and start over:

### Full Uninstall

```bash
cd /srv/monitoring_data/VMStation

# Run uninstall playbook
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/uninstall-rke2-homelab.yml

# Follow prompts to confirm uninstallation
```

**What it does:**
- Stops rke2-server service
- Runs RKE2 uninstall script
- Removes all RKE2 binaries and data
- Cleans up configuration files
- Backs up kubeconfig to `.backup` file

### Verify Removal

```bash
ssh jashandeepjustinbains@192.168.4.62 'which rke2'
# Should return: rke2 not found

ssh jashandeepjustinbains@192.168.4.62 'sudo systemctl status rke2-server'
# Should return: Unit rke2-server.service could not be found
```

### Optional: Reboot for Clean State

```bash
ansible homelab -i ansible/inventory/hosts.yml -m reboot -b
```

### Remove Federation from Central Prometheus

```bash
# Edit Prometheus config
vim manifests/monitoring/prometheus.yaml

# Remove or comment out the rke2-federation job

# Apply changes
kubectl apply -f manifests/monitoring/prometheus.yaml
kubectl rollout restart -n monitoring deployment/prometheus
```

## Maintenance Tasks

### Update RKE2 Version

```bash
# Update version in role defaults
vim ansible/roles/rke2/defaults/main.yml
# Change: rke2_version: "v1.29.11+rke2r1"

# Re-run installation (idempotent)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml
```

### Backup RKE2 Cluster

```bash
# Backup kubeconfig
cp /srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml ~/backups/rke2-kubeconfig-$(date +%Y%m%d).yaml

# Backup RKE2 data (on homelab)
ssh jashandeepjustinbains@192.168.4.62 'sudo tar -czf /tmp/rke2-backup-$(date +%Y%m%d).tar.gz /etc/rancher/rke2 /var/lib/rancher/rke2'
scp jashandeepjustinbains@192.168.4.62:/tmp/rke2-backup-*.tar.gz ~/backups/
```

### View Logs

```bash
# RKE2 service logs
ssh jashandeepjustinbains@192.168.4.62 'sudo journalctl -u rke2-server -f'

# Pod logs
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl logs -n <namespace> <pod-name> -f

# Installation log
cat /srv/monitoring_data/VMStation/ansible/artifacts/install-rke2-homelab.log
```

## Summary

### What You've Deployed

1. **RKE2 Single-Node Cluster** on homelab (192.168.4.62)
   - Kubernetes v1.29.x
   - Canal CNI
   - Monitoring namespace with node-exporter and Prometheus

2. **Prometheus Federation** from central Prometheus (192.168.4.63)
   - Unified metrics view across both clusters
   - Cluster-level labels for filtering

3. **Artifacts Collected**
   - Kubeconfig: `ansible/artifacts/homelab-rke2-kubeconfig.yaml`
   - Install log: `ansible/artifacts/install-rke2-homelab.log`

### Key Endpoints

- **RKE2 Prometheus**: http://192.168.4.62:30090
- **RKE2 Node Exporter**: http://192.168.4.62:9100/metrics
- **RKE2 Federation**: http://192.168.4.62:30090/federate
- **Central Prometheus**: http://192.168.4.63:30090
- **Grafana**: http://192.168.4.63:30300

### Next Steps

1. **Deploy workloads** to RKE2 cluster as needed
2. **Configure Grafana dashboards** to visualize federated metrics
3. **Set up alerts** in central Prometheus for RKE2 cluster
4. **Document** any custom configurations or applications

---

**Deployment completed!** 🎉

For questions or issues, refer to:
- [RKE2 Deployment Guide](../docs/RKE2_DEPLOYMENT_GUIDE.md)
- [Prometheus Federation Guide](../docs/RKE2_PROMETHEUS_FEDERATION.md)
- [Troubleshooting](#troubleshooting-guide)

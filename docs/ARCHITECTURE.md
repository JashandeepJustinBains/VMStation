# VMStation Architecture

## Overview

VMStation is a homelab Kubernetes environment using a **two-cluster architecture** that separates concerns and avoids OS mixing issues:

1. **Debian Cluster (kubeadm)**: Production workloads, storage, monitoring control plane
2. **RKE2 Cluster (RHEL 10)**: Compute, testing, monitoring federation
3. **Kubespray Option (New)**: Alternative deployment path for RHEL10 nodes

## Cluster Topology

### Debian Cluster (kubeadm)

**Nodes**:
- **masternode** (192.168.4.63): Control plane, always-on, monitoring hub
- **storagenodet3500** (192.168.4.61): Worker, Jellyfin host, media storage

**Components**:
- Kubernetes v1.29.15
- Flannel CNI (v0.27.4) with nftables support
- containerd runtime
- kube-proxy, CoreDNS

**Workloads**:
- Jellyfin (media streaming) - pinned to storage node
- Prometheus + Grafana (monitoring stack)
- Loki + Promtail (log aggregation)
- Node exporter, kube-state-metrics
- Blackbox exporter, IPMI exporter

### RKE2 Cluster (RHEL 10)

**Nodes**:
- **homelab** (192.168.4.62): Single-node cluster

**Components**:
- RKE2 v1.29.x
- Canal CNI (Flannel + Calico)
- Built-in containerd

**Workloads**:
- Node exporter (port 9100)
- Prometheus (port 30090) - federates from Debian cluster
- Future: VM testing, enterprise workloads

### Kubespray Deployment Path (New)

An alternative to RKE2 for deploying Kubernetes on RHEL10 nodes:

**Benefits**:
- Standard upstream Kubernetes (like kubeadm)
- Flexible CNI options
- Production-grade deployment automation
- Multi-node cluster support

**Usage**:
```bash
# Stage kubespray
./scripts/run-kubespray.sh

# Run preflight checks on RHEL10 node
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/run-preflight-rhel10.yml

# Deploy cluster (follow kubespray instructions)
```

## Why Two Clusters?

### Problems with Mixed Cluster (Old Approach)
- RHEL 10 uses nftables, Debian uses iptables → firewall conflicts
- SELinux on RHEL blocked CNI init containers
- kube-proxy CrashLoopBackOff on RHEL due to missing iptables chains
- Complex network-fix role required for RHEL
- Fragile, hard to debug

### Benefits of Separation (Current Approach)
- ✅ Clean OS-specific configurations
- ✅ RKE2/Kubespray handle RHEL nftables/SELinux natively
- ✅ Debian kubeadm cluster is simple and robust
- ✅ Independent upgrade/maintenance cycles
- ✅ Monitoring federation still works

## Network Architecture

### Debian Cluster Networks
- **Pod CIDR**: 10.244.0.0/16 (Flannel)
- **Service CIDR**: 10.96.0.0/12
- **Control Plane**: 192.168.4.63:6443
- **CNI**: Flannel VXLAN with nftables mode enabled

### RKE2 Cluster Networks
- **Pod CIDR**: 10.42.0.0/16 (RKE2 default)
- **Service CIDR**: 10.43.0.0/16 (RKE2 default)
- **API Server**: 192.168.4.62:6443
- **CNI**: Canal (Flannel + Calico)

### Monitoring Federation

```
Debian Cluster Prometheus (masternode)
    ↓ scrapes/federates
RKE2 Cluster Prometheus (homelab:30090)
    ↓ provides
Federation endpoint for central metrics
```

Central Prometheus on masternode federates metrics from RKE2, providing unified monitoring.

## Data Flow Patterns

### Jellyfin Media Streaming
```
Client → storagenodet3500:NodePort → Jellyfin Pod → /srv/media (local storage)
```

### Monitoring Metrics
```
kubelet (all nodes) → node-exporter → Prometheus → Grafana dashboards
```

### Logging (Loki)
```
Pods → promtail DaemonSet → Loki → Grafana log viewer
homelab logs → promtail → masternode Loki (external labels: cluster=rke2-homelab)
```

### DNS Resolution
```
Pod → CoreDNS (cluster DNS) → External DNS (if needed)
masternode → dnsmasq (for WoL and local DNS)
```

## Deployment Architecture

### Debian Cluster Deployment (deploy.sh debian)

**Phases**:
1. Install binaries (kubeadm, kubelet, kubectl)
2. System prep (sysctl, swap, modules)
3. CNI plugins
4. Control plane init (kubeadm)
5. Worker join
6. Deploy Flannel CNI
7. Wait for nodes Ready
8. Deploy apps (Prometheus, Grafana, Loki, Jellyfin)

**Idempotency**: All phases are idempotent and safe to re-run

### RKE2 Cluster Deployment (deploy.sh rke2)

**Phases**:
1. System prep (RHEL-specific)
2. RKE2 install
3. Configure RKE2 server
4. Start service
5. Deploy monitoring (node-exporter, Prometheus)
6. Collect artifacts (kubeconfig, logs)

**Idempotency**: Safe to re-run, skips if already installed

### Kubespray Deployment (New Path)

**Phases**:
1. Run preflight checks (ansible/roles/preflight-rhel10)
   - Install Python packages
   - Configure chrony (time sync)
   - Setup sudoers
   - Open firewall ports
   - Configure SELinux
   - Load kernel modules
   - Apply sysctl settings
2. Stage Kubespray (scripts/run-kubespray.sh)
3. Customize inventory
4. Deploy cluster with Kubespray

## Wake-on-LAN Architecture

### Design

VMStation implements power management through Wake-on-LAN (WoL) for energy savings during idle periods.

**Components**:
- Auto-sleep monitoring cron job (masternode)
- WoL magic packet sender (masternode)
- Event-driven wake scripts (systemd timers)
- State tracking for suspend/wake cycles

### Monitoring and Sleep Detection

**Location**: masternode (always-on)

**Checks** (hourly cron):
- Jellyfin activity (API checks)
- CPU usage across cluster
- Active user sessions
- Pod activity levels

**Triggers**:
- If idle for 2+ hours → initiate sleep sequence

### Sleep Process

1. **Cordon** all worker nodes (mark unschedulable)
2. **Drain** workloads (except DaemonSets)
3. **Scale down** non-essential deployments
4. **Record state** to `/var/lib/vmstation/state`
5. **Suspend nodes** (systemctl suspend)

### Wake Process

1. **masternode** detects wake trigger (timer, API call, manual)
2. **Send WoL packets** to worker node MAC addresses
3. **Monitor wake** via tcpdump (TCP SYN on port 22)
4. **Uncordon nodes** when kubelet ready
5. **Restore workloads** (auto-restart or manual)
6. **Record wake time** and metrics

**WoL Configuration**:
- masternode: `00:e0:4c:68:cb:bf`
- storagenodet3500: `b8:ac:6f:7e:6c:9d`
- homelab: `d0:94:66:30:d6:63`

### State Tracking

**File**: `/var/lib/vmstation/state`

**Format**:
```
suspended:1697123456
awake:1697127056
last_activity:1697123400
```

**Scripts**:
- `scripts/vmstation-event-wake.sh` - Wake handler with tcpdump monitoring
- `ansible/playbooks/setup-autosleep.yaml` - Auto-sleep configuration
- `scripts/vmstation-collect-wake-logs.sh` - Diagnostics collection

## DNS and Network Services

### dnsmasq (masternode)

**Purpose**: 
- Local DNS for cluster nodes
- DHCP (optional)
- WoL MAC-to-IP mapping

**Configuration**:
- Serves 192.168.4.0/24 subnet
- Static entries for masternode, storagenodet3500, homelab

### CoreDNS (Kubernetes)

**Purpose**: Cluster DNS for pod name resolution

**Configuration**:
- Forward external queries to host DNS
- Service discovery for Kubernetes services
- Custom DNS entries via ConfigMap

## Monitoring Architecture

### Prometheus (Metrics)

**Location**: masternode (monitoring namespace)

**Scrape Targets**:
- Node exporters (all nodes)
- Kube-state-metrics (Kubernetes objects)
- Blackbox exporter (HTTP/DNS probes)
- IPMI exporter (hardware metrics)
- RKE2 Prometheus (federation)

**Storage**: `/srv/monitoring_data/prometheus` (PersistentVolume)

**Access**: http://192.168.4.63:30090

### Grafana (Dashboards)

**Location**: masternode (monitoring namespace)

**Datasources**:
- Prometheus (metrics)
- Loki (logs)

**Dashboards**:
- Node metrics and resource usage
- Kubernetes cluster overview
- Loki logs and aggregation
- Syslog infrastructure monitoring
- CoreDNS performance
- IPMI hardware monitoring

**Storage**: `/srv/monitoring_data/grafana` (PersistentVolume)

**Access**: http://192.168.4.63:30300

### Loki (Logs)

**Location**: masternode (monitoring namespace)

**Log Sources**:
- Kubernetes pods (via promtail DaemonSet)
- System logs (via promtail)
- RKE2 cluster logs (external labels: cluster=rke2-homelab)

**Storage**: `/srv/monitoring_data/loki` (PersistentVolume, UID 10001)

**Access**: http://192.168.4.63:31100

**Configuration**:
- Schema: boltdb-shipper with 24h period
- Retention: 168h (7 days)
- Chunk size: 1048576 bytes

## Security Considerations

### Authentication
- **Debian nodes**: Root SSH with key-based auth
- **RHEL node**: Non-root user + sudo with vault-encrypted password
- **Kubeconfig**: Secured with file permissions (600)
- **Ansible vault**: Secrets encrypted at rest

### Network Security
- No external ingress (NodePort only for now)
- Future: TLS with cert-manager, ingress controller
- Firewall rules on RHEL10 (preflight-rhel10 role)

### SELinux (RHEL10)
- Default: permissive mode (configurable)
- Allows Kubernetes without complex policies
- Can be switched to enforcing with custom policies

### Secrets Management
- Ansible Vault for sudo passwords
- Kubernetes Secrets for app credentials
- Future: External secrets operator (Vault, sealed-secrets)

## Scalability

### Adding Nodes

**Debian worker**:
```bash
# Add to storage_nodes in ansible/inventory/hosts.yml
# Run deployment
./deploy.sh debian
```

**RKE2 agent**:
```bash
# Modify RKE2 config to add agent
# Join to homelab server
```

**Kubespray cluster**:
```bash
# Add node to kubespray inventory
# Run scale.yml playbook
```

### Removing Nodes

```bash
# Drain node
kubectl drain <node> --delete-emptydir-data --ignore-daemonsets

# Remove from inventory
# Run reset on that node
./deploy.sh reset
```

## Storage Architecture

### Persistent Volumes

**Monitoring Data** (`/srv/monitoring_data/`):
- `prometheus/` - Time-series database
- `grafana/` - Dashboards and settings
- `loki/` - Log chunks and indices

**Media Storage** (`/srv/media/`):
- Movies, TV shows, music
- Mounted into Jellyfin pod

**Configuration**:
- Local hostPath volumes
- Pinned to specific nodes via nodeSelector
- UID/GID ownership requirements (Loki: 10001)

### Backup Strategy

**Monitoring Data**:
- Prometheus: TSDB snapshots
- Grafana: Dashboard exports (JSON)
- Loki: Chunk backup (optional)

**Media**:
- External backup to NAS or cloud storage

## Infrastructure Services

### NTP/Chrony

**Purpose**: Cluster-wide time synchronization

**Deployment**: DaemonSet on all nodes

**Importance**: Kubernetes requires synchronized time for:
- Certificate validation
- Log correlation
- Distributed consensus (etcd)

### Syslog Server

**Purpose**: Centralized logging from non-Kubernetes devices

**Use Cases**:
- Router logs
- Switch logs
- IoT device logs

**Integration**: Grafana dashboard for syslog analysis

### Kerberos/FreeIPA (Future)

**Purpose**: SSO for home network

**Use Cases**:
- Samba/NFS authentication
- Wi-Fi 802.1X (RADIUS)
- Service principal management

**Deployment**: StatefulSet on masternode with persistent storage

## Future Enhancements

- [ ] Add nginx-ingress or Traefik for external HTTPS access
- [ ] Implement cert-manager for TLS certificate management
- [ ] Add more compute nodes to RKE2 cluster
- [ ] Automated VM provisioning on homelab (KubeVirt or Proxmox)
- [ ] GitOps with ArgoCD or Flux
- [ ] External secrets operator integration
- [ ] High availability for monitoring stack
- [ ] Automated backup and disaster recovery
- [ ] Network policies for pod-to-pod security
- [ ] Service mesh (Istio or Linkerd) for advanced traffic management

## References

- [Deployment Runbook](DEPLOYMENT_RUNBOOK.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [Monitoring Configuration](HOMELAB_MONITORING_INTEGRATION.md)
- [Sleep/Wake Implementation](../SLEEP_WAKE_IMPLEMENTATION_SUMMARY.md)
- [Kubespray Documentation](https://kubespray.io/)

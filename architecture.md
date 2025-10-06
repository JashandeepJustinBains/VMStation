# Architecture

## Overview

VMStation uses a **two-cluster architecture** to separate concerns and avoid OS mixing issues:

1. **Debian Cluster (kubeadm)**: Production workloads, storage, monitoring
2. **RKE2 Cluster (RHEL 10)**: Compute, testing, monitoring federation

## Cluster Details

### Debian Cluster (kubeadm)

**Nodes**:
- **masternode** (192.168.4.63): Control plane, always-on
- **storagenodet3500** (192.168.4.61): Worker, Jellyfin host

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

## Why Two Clusters?

### Problems with Mixed Cluster (Old Approach)
- RHEL 10 uses nftables, Debian uses iptables → firewall conflicts
- SELinux on RHEL blocked CNI init containers
- kube-proxy CrashLoopBackOff on RHEL due to missing iptables chains
- Complex network-fix role required for RHEL
- Fragile, hard to debug

### Benefits of Separation (Current Approach)
- ✅ Clean OS-specific configurations
- ✅ RKE2 handles RHEL nftables/SELinux natively
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
    ↓ scrapes
RKE2 Cluster Prometheus (homelab:30090)
    ↓ provides
Federation endpoint for central metrics
```

Central Prometheus on masternode federates metrics from RKE2, providing unified monitoring.

## Data Flow

### Jellyfin Media Streaming
```
Client → storagenodet3500:NodePort → Jellyfin Pod → /srv/media (local storage)
```

### Monitoring Metrics
```
kubelet (all nodes) → node-exporter → Prometheus → Grafana dashboards
```

### Logging
```
Pods → promtail DaemonSet → Loki → Grafana log viewer
```

## Deployment Phases

### Debian Cluster (deploy.sh debian)
1. Install binaries (kubeadm, kubelet, kubectl)
2. System prep (sysctl, swap, modules)
3. CNI plugins
4. Control plane init (kubeadm)
5. Worker join
6. Deploy Flannel CNI
7. Wait for nodes Ready
8. Deploy apps (Prometheus, Grafana, Loki, Jellyfin)

### RKE2 Cluster (deploy.sh rke2)
1. System prep (RHEL-specific)
2. RKE2 install
3. Configure RKE2 server
4. Start service
5. Deploy monitoring (node-exporter, Prometheus)
6. Collect artifacts (kubeconfig, logs)

## Auto-Sleep Architecture

### Monitoring
- Cron job runs hourly on masternode
- Checks Jellyfin activity, CPU usage, user sessions
- If idle for 2+ hours → triggers sleep

### Sleep Process
1. Cordon all worker nodes
2. Drain workloads (except critical)
3. Scale down non-essential pods
4. Send Wake-on-LAN magic packet prep
5. Node shutdown (manual or automated)

### Wake Process
- masternode sends WoL magic packets to worker MACs
- Workers boot and rejoin cluster
- Pods auto-restart on schedule

## Security Considerations

### Authentication
- **Debian nodes**: Root SSH with key-based auth
- **RHEL node**: Non-root user + sudo with vault-encrypted password
- **Kubeconfig**: Secured with file permissions (600)

### Network
- No external ingress (NodePort only)
- Future: TLS with cert-manager, ingress controller

### Secrets Management
- Ansible Vault for sudo passwords
- Kubernetes Secrets for app credentials
- Future: External secrets operator

## Scalability

### Adding Nodes
- **Debian worker**: Add to `storage_nodes` in inventory, run `./deploy.sh debian`
- **RKE2 agent**: Modify RKE2 config, join to homelab server

### Removing Nodes
- Drain node: `kubectl drain <node> --delete-emptydir-data --ignore-daemonsets`
- Remove from inventory
- Run `./deploy.sh reset` on that node

## Future Enhancements

- Add more compute nodes to RKE2 cluster
- Implement automated VM provisioning on homelab
- Add nginx-ingress or Traefik for external access
- Rotate TLS certificates with cert-manager
- Implement GitOps with ArgoCD or Flux

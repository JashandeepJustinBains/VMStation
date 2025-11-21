# VMStation Homelab - Network Topology Documentation
## For Portfolio Website Integration

This document provides structured information about the VMStation Kubernetes homelab infrastructure in a format suitable for visualization in a GNS3-style network topology diagram.

---

## Repository Information

**Repository Name:** VMStation  
**GitHub URL:** https://github.com/JashandeepJustinBains/VMStation  
**Description:** A production-ready Kubernetes homelab environment with automated deployment, monitoring, and power management  
**Primary Tech Stack:** Kubernetes, Ansible, Prometheus, Grafana, Kubespray  

---

## Network Topology Nodes

### Node 1: masternode (Control Plane)
**Type:** hypervisor  
**IP Address:** 192.168.4.63  
**Role:** Kubernetes Control Plane & Monitoring Hub  
**Status:** Always-On (24/7)

**Specifications:**
- **CPU:** 4 cores
- **RAM:** 8 GB
- **Storage:** 100 GB
- **OS:** Debian 12 (Bookworm)
- **Container Runtime:** containerd

**Services Running:**
- Kubernetes API Server (port 6443)
- etcd (distributed key-value store)
- Prometheus (metrics collection) - :30090
- Grafana (dashboards & visualization) - :30300
- Loki (log aggregation) - :31100
- CoreDNS
- Kube-scheduler
- Kube-controller-manager

**Key Features:**
- Primary control plane for entire cluster
- Centralized monitoring and observability hub
- Always-on for 24/7 cluster availability
- Serves as NTP/Chrony time sync server
- Hosts syslog centralized logging

---

### Node 2: storagenodet3500 (Storage & Media Worker)
**Type:** storage  
**IP Address:** 192.168.4.61  
**Role:** Storage Worker Node  
**Status:** Auto-Sleep Enabled

**Specifications:**
- **CPU:** 4 cores
- **RAM:** 8 GB
- **Storage:** 500+ GB (media storage optimized)
- **OS:** Debian 12 (Bookworm)
- **Container Runtime:** containerd
- **MAC Address:** b8:ac:6f:7e:6c:9d (for WoL)

**Services Running:**
- Jellyfin (media streaming server)
- Storage workloads
- Node Exporter (system metrics)
- Promtail (log shipping to Loki)

**Key Features:**
- Optimized for storage-intensive workloads
- Auto-sleep after 2+ hours of inactivity
- Wake-on-LAN capable for power efficiency
- Media storage and streaming capabilities
- Automatically joins cluster on wake

**Power Management:**
- Monitors Jellyfin activity
- Checks CPU usage patterns
- Graceful pod eviction before sleep
- WoL magic packet triggers: 192.168.4.255

---

### Node 3: homelab (RHEL10 Compute Worker)
**Type:** application  
**IP Address:** 192.168.4.62  
**Role:** General Compute Worker  
**Status:** Auto-Sleep Enabled

**Specifications:**
- **CPU:** 4 cores
- **RAM:** 8 GB
- **Storage:** 100 GB
- **OS:** RHEL 10 (Red Hat Enterprise Linux)
- **Container Runtime:** containerd
- **MAC Address:** d0:94:66:30:d6:63 (for WoL)

**Services Running:**
- General compute workloads
- Node Exporter (system metrics)
- Promtail (log shipping to Loki)

**Key Features:**
- Multi-distro support (RHEL alongside Debian)
- Auto-sleep capability for power efficiency
- Wake-on-LAN enabled
- Supports both Kubespray and RKE2 deployment methods
- Enterprise Linux compatibility testing

**Deployment Options:**
- Kubespray: Production-grade Kubernetes deployment
- RKE2: Rancher Kubernetes Engine alternative

---

## Network Connections

### Connection Matrix

| From Node | To Node | Connection Type | Protocol/Service | Port(s) |
|-----------|---------|-----------------|------------------|---------|
| masternode | storagenodet3500 | Kubernetes API | HTTPS | 6443 |
| masternode | homelab | Kubernetes API | HTTPS | 6443 |
| storagenodet3500 | masternode | kubelet | HTTPS | 10250 |
| homelab | masternode | kubelet | HTTPS | 10250 |
| masternode | storagenodet3500 | Flannel (CNI) | VXLAN | 8472 |
| masternode | homelab | Flannel (CNI) | VXLAN | 8472 |
| masternode | storagenodet3500 | Prometheus Scrape | HTTP | 9100 |
| masternode | homelab | Prometheus Scrape | HTTP | 9100 |
| storagenodet3500 | masternode | Loki Push | HTTP | 31100 |
| homelab | masternode | Loki Push | HTTP | 31100 |
| masternode | storagenodet3500 | Wake-on-LAN | UDP | 9 |
| masternode | homelab | Wake-on-LAN | UDP | 9 |

### Connection Topology for Visualization

```
Edge 1: masternode ↔ storagenodet3500
Label: "Kubernetes Control / CNI Network"
Type: Bidirectional
Color: Blue (primary cluster connection)

Edge 2: masternode ↔ homelab
Label: "Kubernetes Control / CNI Network"
Type: Bidirectional
Color: Blue (primary cluster connection)

Edge 3: masternode → storagenodet3500
Label: "Monitoring & Metrics"
Type: Unidirectional
Color: Green (monitoring data flow)

Edge 4: masternode → homelab
Label: "Monitoring & Metrics"
Type: Unidirectional
Color: Green (monitoring data flow)

Edge 5: storagenodet3500 → masternode
Label: "Log Aggregation"
Type: Unidirectional
Color: Orange (log data flow)

Edge 6: homelab → masternode
Label: "Log Aggregation"
Type: Unidirectional
Color: Orange (log data flow)

Edge 7: masternode ⇢ storagenodet3500
Label: "Wake-on-LAN"
Type: Special (dashed line)
Color: Purple (power management)

Edge 8: masternode ⇢ homelab
Label: "Wake-on-LAN"
Type: Special (dashed line)
Color: Purple (power management)
```

---

## Technology Stack

### Core Infrastructure
- **Kubernetes:** v1.29.15 (container orchestration)
- **Deployment Method:** Kubespray (production-grade automation)
- **Legacy Deployment:** kubeadm (Debian nodes)
- **Alternative Deployment:** RKE2 (RHEL10 node)
- **CNI Plugin:** Flannel v0.27.4 (networking)
- **Container Runtime:** containerd

### Automation & Configuration
- **Configuration Management:** Ansible 2.9+
- **Inventory Management:** YAML-based inventory
- **Infrastructure as Code:** Ansible playbooks and roles
- **Deployment Script:** Modular bash deployment wrapper

### Monitoring & Observability
- **Metrics Collection:** Prometheus
- **Visualization:** Grafana with custom dashboards
- **Log Aggregation:** Loki + Promtail
- **System Metrics:** Node Exporter (all nodes)
- **Kubernetes Metrics:** Kube-state-metrics
- **HTTP/DNS Probes:** Blackbox Exporter
- **Hardware Monitoring:** IPMI Exporter (optional)

### Infrastructure Services
- **Time Sync:** NTP/Chrony DaemonSet
- **Centralized Logging:** Syslog Server
- **Identity Management:** FreeIPA/Kerberos (optional)

### Power Management
- **Auto-Sleep:** Automated idle detection and suspend
- **Wake-on-LAN:** Remote wake capability via magic packets
- **Energy Efficiency:** Automatic power management for worker nodes

---

## Key Features

### 🚀 Automated Deployment
- **Single-command deployment:** `./deploy.sh kubespray` deploys entire stack
- **Idempotent playbooks:** Safe to run multiple times
- **Pre-flight checks:** Validates requirements before deployment
- **Multi-cluster support:** Debian (kubeadm) + RHEL10 (Kubespray/RKE2)
- **Modular architecture:** Deploy components independently

### 📊 Complete Monitoring Stack
- **Full observability:** Metrics, logs, and traces
- **Custom dashboards:** Pre-configured Grafana dashboards
- **Real-time alerting:** Prometheus alert rules
- **Multi-cluster monitoring:** Aggregates data from all nodes
- **Historical data:** Persistent storage for metrics and logs

### ⚡ Smart Power Management
- **Intelligent auto-sleep:** Monitors activity patterns
- **Activity detection:** Tracks Jellyfin usage and CPU patterns
- **Graceful shutdown:** Cordons, drains, then suspends nodes
- **Fast wake:** WoL + automatic cluster rejoin
- **Energy savings:** Reduces power consumption during idle periods

### 🔧 Production-Ready Features
- **High availability aware:** Control plane always-on design
- **Data persistence:** Persistent volumes for monitoring data
- **Backup ready:** Documented backup/restore procedures
- **Enterprise OS support:** RHEL 10 compatibility
- **Security:** SELinux, firewall configuration, RBAC

---

## Deployment Methods

### Method 1: Kubespray (Recommended)
**Description:** Production-grade Kubernetes deployment  
**Target:** All nodes (unified cluster)  
**Command:** `./deploy.sh kubespray`

**Features:**
- Standard upstream Kubernetes
- Flexible CNI options (Calico, Flannel, Weave, Cilium)
- Multi-node cluster support
- Active community support
- Enterprise-ready

### Method 2: kubeadm (Legacy)
**Description:** Traditional Kubernetes deployment  
**Target:** Debian nodes only  
**Command:** `./deploy.sh debian`

**Features:**
- Lightweight deployment
- Debian-optimized
- Simple control plane initialization
- Manual worker join process

### Method 3: RKE2 (Alternative)
**Description:** Rancher Kubernetes Engine 2  
**Target:** RHEL10 node (homelab)  
**Command:** `./deploy.sh rke2`

**Features:**
- "Batteries included" distribution
- Built-in Canal CNI (Flannel + Calico)
- RHEL/CentOS optimized
- Simple binary installation
- Embedded containerd

---

## Access Information

### Management Endpoints

| Service | URL | Purpose | Default Credentials |
|---------|-----|---------|---------------------|
| Grafana | http://192.168.4.63:30300 | Dashboards & Visualization | admin/admin |
| Prometheus | http://192.168.4.63:30090 | Metrics & Query Interface | None required |
| Loki | http://192.168.4.63:31100 | Log Query API | None required |
| Kubernetes API | https://192.168.4.63:6443 | Cluster Management | Certificate-based |

### SSH Access

| Node | SSH Command | User | Key |
|------|-------------|------|-----|
| masternode | `ssh root@192.168.4.63` | root | Local connection |
| storagenodet3500 | `ssh root@192.168.4.61` | root | ~/.ssh/id_k3s |
| homelab | `ssh jashandeepjustinbains@192.168.4.62` | jashandeepjustinbains | ~/.ssh/id_k3s |

---

## Project Statistics

### Repository Structure
- **Ansible Playbooks:** 17 automated deployment playbooks (4,256 total lines)
- **Ansible Roles:** Custom preflight-rhel10 role
- **Scripts:** 10+ management and validation scripts
- **Tests:** Comprehensive validation test suite (8+ scripts)
- **Manifests:** 33 Kubernetes manifests for services
- **Documentation:** 11 detailed markdown documents

### Deployment Capabilities
- **Full Stack Deployment:** ~25-30 minutes
- **Monitoring Stack Only:** ~5-10 minutes
- **Infrastructure Services:** ~3-5 minutes
- **Auto-Sleep Setup:** ~1-2 minutes

### Testing & Validation
- **Automated Tests:** 8+ validation scripts
- **Idempotency Testing:** 3-cycle deployment validation
- **Sleep/Wake Testing:** Full power management validation
- **Monitoring Validation:** Health checks for all exporters

---

## Use Cases

### Development & Testing
- Multi-distribution testing (Debian + RHEL)
- Container orchestration development
- Kubernetes feature testing
- CI/CD pipeline testing

### Media & Storage
- Jellyfin media streaming
- Network-attached storage
- Automated backup solutions
- Data persistence testing

### Learning & Experimentation
- Production Kubernetes patterns
- Monitoring best practices
- Infrastructure automation
- Power management strategies

### Production Simulation
- Multi-node cluster operations
- High-availability patterns
- Disaster recovery testing
- Performance optimization

---

## Notable Achievements

### Technical Accomplishments
- ✅ **Multi-distribution cluster:** Seamless Debian + RHEL integration
- ✅ **Complete observability:** Full monitoring stack with Prometheus/Grafana/Loki
- ✅ **Intelligent power management:** Automated sleep/wake with activity detection
- ✅ **Idempotent automation:** All playbooks safe to run repeatedly
- ✅ **Production-grade deployment:** Kubespray integration for enterprise quality

### Operational Excellence
- ✅ **Zero-downtime monitoring:** Always-on control plane design
- ✅ **Automated validation:** Comprehensive test suite
- ✅ **Detailed documentation:** 10+ docs covering all aspects
- ✅ **Modular architecture:** Independent component deployment
- ✅ **Energy efficient:** Smart power management reduces costs

### Innovation
- ✅ **Hybrid deployment:** Multiple Kubernetes distributions in one environment
- ✅ **Activity-aware automation:** Jellyfin integration for smart sleep decisions
- ✅ **Wake-on-LAN integration:** Seamless cluster recovery from sleep
- ✅ **Centralized management:** Single pane of glass for all cluster operations

---

## Quick Start Commands

```bash
# Deploy full stack with Kubespray (RECOMMENDED)
./deploy.sh reset
./deploy.sh setup
./deploy.sh kubespray  # Deploys cluster + monitoring + infrastructure

# Validate deployment
./scripts/validate-monitoring-stack.sh
./tests/test-complete-validation.sh

# Legacy Debian-only deployment
./deploy.sh reset
./deploy.sh setup
./deploy.sh debian
./deploy.sh monitoring
./deploy.sh infrastructure

# Access services
# Grafana: http://192.168.4.63:30300
# Prometheus: http://192.168.4.63:30090
```

---

## Color Coding for Visualization

For optimal visual representation in the GNS3-style network topology:

### Node Colors
- **masternode (Control Plane):** `#2563eb` (Blue) - Always-on, critical infrastructure
- **storagenodet3500 (Storage):** `#16a34a` (Green) - Storage and media workloads
- **homelab (Compute):** `#ea580c` (Orange) - General compute, RHEL testing

### Connection Colors
- **Kubernetes Control Plane:** `#2563eb` (Blue) - Primary cluster connections
- **Monitoring Data Flow:** `#16a34a` (Green) - Metrics scraping paths
- **Log Aggregation:** `#ea580c` (Orange) - Log shipping to Loki
- **Wake-on-LAN:** `#9333ea` (Purple) - Power management, dashed lines

### Status Indicators
- **Always-On:** Solid border
- **Auto-Sleep Enabled:** Dashed border
- **Active/Awake:** Green indicator
- **Sleeping:** Gray indicator

---

## Repository Links

- **Main Repository:** https://github.com/JashandeepJustinBains/VMStation
- **Documentation:** See `/docs` directory in repository
- **Quick Start:** See `QUICK_START.md`
- **Architecture Guide:** See `docs/ARCHITECTURE.md`
- **Usage Guide:** See `docs/USAGE.md`
- **Troubleshooting:** See `docs/TROUBLESHOOTING.md`

---

## Integration Instructions for Portfolio Website

### Node Definition Format (for NetworkTopology.astro)

```javascript
const nodes = [
  {
    id: 1,
    label: 'masternode',
    group: 'hypervisor',
    title: 'Kubernetes Control Plane & Monitoring Hub',
    specs: {
      cpu: '4 cores',
      ram: '8 GB',
      storage: '100 GB',
      os: 'Debian 12',
      role: 'Control plane, always-on',
      status: 'Always Active',
      services: 'K8s API, Prometheus, Grafana, Loki, etcd'
    },
    ip: '192.168.4.63'
  },
  {
    id: 2,
    label: 'storagenodet3500',
    group: 'storage',
    title: 'Storage & Media Worker Node',
    specs: {
      cpu: '4 cores',
      ram: '8 GB',
      storage: '500+ GB',
      os: 'Debian 12',
      role: 'Worker node, storage, auto-sleep enabled',
      status: 'Auto-Sleep Enabled',
      services: 'Jellyfin, Storage workloads, Node Exporter'
    },
    ip: '192.168.4.61',
    mac: 'b8:ac:6f:7e:6c:9d'
  },
  {
    id: 3,
    label: 'homelab',
    group: 'application',
    title: 'RHEL10 Compute Worker',
    specs: {
      cpu: '4 cores',
      ram: '8 GB',
      storage: '100 GB',
      os: 'RHEL 10',
      role: 'Worker node, compute, auto-sleep enabled',
      status: 'Auto-Sleep Enabled',
      services: 'General compute workloads, Node Exporter'
    },
    ip: '192.168.4.62',
    mac: 'd0:94:66:30:d6:63'
  }
];
```

### Edge Definition Format (for NetworkTopology.astro)

```javascript
const edges = [
  { from: 1, to: 2, label: 'K8s Control / CNI', color: { color: '#2563eb' } },
  { from: 1, to: 3, label: 'K8s Control / CNI', color: { color: '#2563eb' } },
  { from: 1, to: 2, label: 'Prometheus Scrape', color: { color: '#16a34a' }, dashes: true },
  { from: 1, to: 3, label: 'Prometheus Scrape', color: { color: '#16a34a' }, dashes: true },
  { from: 2, to: 1, label: 'Log Push (Loki)', color: { color: '#ea580c' }, dashes: true },
  { from: 3, to: 1, label: 'Log Push (Loki)', color: { color: '#ea580c' }, dashes: true },
  { from: 1, to: 2, label: 'Wake-on-LAN', color: { color: '#9333ea' }, dashes: [10, 5] },
  { from: 1, to: 3, label: 'Wake-on-LAN', color: { color: '#9333ea' }, dashes: [10, 5] }
];
```

### Recommended Features to Highlight

1. **Tech Stack Badge:** Kubernetes, Ansible, Prometheus, Grafana, Loki
2. **Key Stats:** 3 nodes, 15+ playbooks, 20+ manifests, 8+ tests
3. **Special Features:** Auto-sleep, Wake-on-LAN, Multi-distro support
4. **Deployment Time:** ~25-30 minutes for full stack
5. **Monitoring Access:** Links to Grafana dashboard (if public)

---

*Document generated for integration with personal portfolio website*  
*Last Updated: November 2024*  
*VMStation - A Production-Ready Homelab Kubernetes Environment*

# VMStation Monitoring Architecture - Version 2.0

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         VMStation Cluster                            │
│                                                                       │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                   Control Plane Node (masternode)              │  │
│  │                                                                 │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │  │
│  │  │  Prometheus  │  │   Grafana    │  │     Loki     │        │  │
│  │  │    :9090     │  │    :3000     │  │    :3100     │        │  │
│  │  └──────┬───────┘  └──────┬───────┘  └──────▲───────┘        │  │
│  │         │                  │                  │                 │  │
│  │         │  ┌───────────────┘                  │                 │  │
│  │         │  │                                   │                 │  │
│  │  ┌──────▼──▼───────┐  ┌──────────────┐  ┌───┴──────────┐     │  │
│  │  │ Blackbox Exporter│  │Kube State    │  │   Promtail   │     │  │
│  │  │     :9115       │  │  Metrics     │  │  (DaemonSet) │     │  │
│  │  └──────────────────┘  └──────────────┘  └──────────────┘     │  │
│  │                                                                 │  │
│  │  ┌──────────────┐  ┌──────────────┐                           │  │
│  │  │Syslog Server │  │Syslog Exporter│                          │  │
│  │  │   :514 UDP   │  │    :9104     │  (New in v2.0)           │  │
│  │  │   :514 TCP   │  │              │                           │  │
│  │  └──────▲───────┘  └──────────────┘                           │  │
│  │         │                                                       │  │
│  └─────────┼───────────────────────────────────────────────────┘  │
│            │                                                         │
│  ┌─────────┼─────────────────────────────────────────────────────┐ │
│  │         │        Worker Nodes (DaemonSets on all nodes)       │ │
│  │         │                                                       │ │
│  │  ┌──────▼───────┐  ┌──────────────┐  ┌──────────────┐        │ │
│  │  │Syslog Server │  │ Node Exporter│  │   Promtail   │        │ │
│  │  │  (collector) │  │    :9100     │  │              │        │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │ │
│  │                                                                 │ │
│  │  ┌──────────────┐  ┌──────────────┐                           │ │
│  │  │IPMI Exporter │  │Syslog Exporter│                          │ │
│  │  │  (DaemonSet) │  │              │                           │ │
│  │  └──────────────┘  └──────────────┘                           │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                    External Systems                                  │
│                                                                       │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  RKE2 Cluster (homelab - 192.168.4.62)                        │  │
│  │                                                                 │  │
│  │  ┌──────────────┐                                              │  │
│  │  │  Prometheus  │  ──────────────┐                            │  │
│  │  │    :30090    │                 │ Federation                 │  │
│  │  └──────────────┘                 │                            │  │
│  └────────────────────────────────────┼──────────────────────────┘  │
│                                        │                              │
│  ┌────────────────────────────────────▼──────────────────────────┐  │
│  │  Network Devices (Routers, Switches, Firewalls)              │  │
│  │                                                                 │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐           │  │
│  │  │   Router    │  │   Switch    │  │  Firewall   │           │  │
│  │  │             │  │             │  │             │           │  │
│  │  │  Syslog ────┼──┼─────────────┼──┼────────────►│           │  │
│  │  │  :514 UDP   │  │  :514 UDP   │  │  :514 UDP   │           │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘           │  │
│  └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

                           │
                           │ All metrics flow to Prometheus
                           │ All logs flow to Loki
                           ▼

┌─────────────────────────────────────────────────────────────────────┐
│                    Grafana Dashboards                                │
│                                                                       │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  Cluster Health & Performance                                  │  │
│  │  • Kubernetes Cluster Dashboard                                │  │
│  │  • Node Dashboard                                               │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  Metrics & Monitoring                                           │  │
│  │  • Prometheus Metrics & Health                                  │  │
│  │  • IPMI Hardware Monitoring                                     │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  Logs & Aggregation                                             │  │
│  │  • Loki Logs & Aggregation                                      │  │
│  │  • Syslog Analysis & Monitoring         (New in v2.0)          │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                       │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │  Network & Security                                             │  │
│  │  • Network Monitoring - Blackbox Exporter  (New in v2.0)       │  │
│  │  • Network Security & Analysis             (New in v2.0)       │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Metrics Collection
```
Node Exporter (each node) ──┐
IPMI Exporter (each node) ──┤
Kube State Metrics ──────────┼──► Prometheus ──► Grafana
Blackbox Exporter ───────────┤
Syslog Exporter (each node) ─┤
RKE2 Prometheus (federated) ─┘
```

### Log Collection
```
Application Pods ────────┐
System Logs ─────────────┼──► Promtail ──► Loki ──► Grafana
Syslog (network devices) ┤                              │
Syslog Server ───────────┘                              │
                                                         └──► Syslog Dashboard
```

### Network Monitoring
```
External Services (1.1.1.1, 8.8.8.8) ──┐
Internal Services (Prometheus, etc.) ──┼──► Blackbox Exporter ──► Prometheus ──► Grafana
Custom Targets ────────────────────────┘                                             │
                                                                                       └──► Blackbox Dashboard
```

## Key Components

### Core Monitoring (v1.0)
- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation
- **Node Exporter**: System metrics (CPU, memory, disk, network)
- **Kube State Metrics**: Kubernetes object state
- **IPMI Exporter**: Hardware monitoring
- **Promtail**: Log shipper

### New in v2.0
- **Syslog Server**: Centralized log collection from network devices
- **Syslog Exporter**: Prometheus metrics from syslog
- **Blackbox Exporter Dashboard**: Network probe visualization
- **Network Security Dashboard**: Traffic and security analysis
- **Syslog Analysis Dashboard**: Log analysis and security events
- **Enhanced Diagnostics**: Detailed Ansible task output

### External Integration
- **RKE2 Federation**: Metrics from homelab RKE2 cluster
- **Network Device Syslog**: Logs from routers, switches, firewalls

## Access Points

| Service | Port | Protocol | Access |
|---------|------|----------|--------|
| Grafana | 30300 | HTTP | NodePort |
| Prometheus | 30090 | HTTP | NodePort |
| Loki | 31100 | HTTP | NodePort |
| Blackbox Exporter | 9115 | HTTP | ClusterIP |
| Node Exporter | 9100 | HTTP | HostPort |
| Syslog Server | 514 | UDP/TCP | HostNetwork |
| Syslog Exporter | 9104 | HTTP | ClusterIP |

## Dashboard Organization

```
Grafana Dashboards
├── Cluster Health & Performance
│   ├── Kubernetes Cluster Dashboard
│   └── Node Dashboard
├── Metrics & Monitoring
│   ├── Prometheus Metrics & Health
│   └── IPMI Hardware Monitoring
├── Logs & Aggregation
│   ├── Loki Logs & Aggregation
│   └── Syslog Analysis & Monitoring ⭐ NEW
└── Network & Security
    ├── Network Monitoring - Blackbox Exporter ⭐ NEW
    └── Network Security & Analysis ⭐ NEW
```

## Deployment Flow

```
1. Ansible Playbook Start
   │
2. Deploy Monitoring Namespace
   │
3. Deploy Persistent Volumes
   │
4. Deploy Core Components
   ├── Prometheus
   ├── Grafana
   ├── Loki
   └── Syslog Server ⭐ NEW
   │
5. Deploy Exporters
   ├── Node Exporter (DaemonSet)
   ├── IPMI Exporter (DaemonSet)
   ├── Kube State Metrics
   ├── Blackbox Exporter
   ├── Syslog Exporter (DaemonSet) ⭐ NEW
   └── Promtail (DaemonSet)
   │
6. Wait for Readiness (Enhanced Diagnostics ⭐ NEW)
   ├── Wait for Prometheus (with retries)
   ├── Wait for Grafana (with retries)
   ├── Wait for Loki (with retries)
   └── Wait for Blackbox Exporter ⭐ ENHANCED
       ├── Pre-flight checks
       ├── Pod status display
       ├── Event history
       ├── Readiness testing
       └── Detailed error output
   │
7. Display Status
   │
8. Deploy Applications
   └── Wait for Jellyfin ⭐ ENHANCED
       ├── Pod verification
       ├── Status tracking
       ├── Event display
       └── Node information
```

## Security Model

```
┌─────────────────────────────────────────────────────────────┐
│                    Security Layers                           │
│                                                               │
│  Network Layer                                               │
│  ├── Firewall monitoring via syslog                         │
│  ├── Network probe monitoring via blackbox exporter         │
│  └── SSL certificate expiry tracking                        │
│                                                               │
│  Application Layer                                           │
│  ├── Authentication event tracking                          │
│  ├── Failed login detection                                 │
│  └── Security event correlation                             │
│                                                               │
│  System Layer                                                │
│  ├── System log aggregation                                 │
│  ├── Error pattern detection                                │
│  └── Performance monitoring                                 │
│                                                               │
│  Kubernetes Layer                                            │
│  ├── Pod security monitoring                                │
│  ├── Resource usage tracking                                │
│  └── Cluster health monitoring                              │
└─────────────────────────────────────────────────────────────┘
```

## Troubleshooting Workflow

```
Issue Detected
    │
    ├─► Deployment Failure?
    │   ├─► Check Ansible output ⭐ Enhanced diagnostics
    │   ├─► Review pod events (shown automatically)
    │   ├─► Check pod logs (displayed in output)
    │   └─► Apply remediation (documented in guide)
    │
    ├─► Loki 502 Error?
    │   ├─► Check Loki pod status
    │   ├─► Test readiness endpoint
    │   ├─► Restart if needed
    │   └─► Use syslog as alternative
    │
    ├─► No Metrics?
    │   ├─► Check Prometheus targets
    │   ├─► Verify service endpoints
    │   └─► Check network connectivity
    │
    └─► No Logs?
        ├─► Check Promtail status
        ├─► Verify Loki connectivity
        └─► Test syslog ingestion
```

## Performance Considerations

| Component | CPU (per node) | Memory (per node) | Storage |
|-----------|----------------|-------------------|---------|
| Prometheus | 200m | 512Mi | 10Gi (PV) |
| Grafana | 100m | 256Mi | 2Gi (PV) |
| Loki | 100m | 256Mi | 10Gi (PV) |
| Node Exporter | 50m | 64Mi | - |
| Promtail | 50m | 64Mi | - |
| Syslog Server | 50m | 64Mi | Variable (host) |
| Syslog Exporter | 25m | 32Mi | - |
| Blackbox Exporter | 50m | 64Mi | - |

**Total per control-plane node**: ~575m CPU, ~1.25Gi Memory
**Total per worker node**: ~175m CPU, ~224Mi Memory

## Version History

### v2.0 (Current) - Comprehensive Monitoring
- ✅ Enhanced diagnostic output for troubleshooting
- ✅ Syslog server integration
- ✅ 3 new professional Grafana dashboards
- ✅ Improved dashboard organization
- ✅ RKE2 federation documented
- ✅ Automated verification script
- ✅ Comprehensive documentation

### v1.0 - Basic Monitoring Stack
- Prometheus, Grafana, Loki
- Node, IPMI, Kube State Metrics exporters
- Basic cluster and node dashboards
- Minimal diagnostics

---

**Legend:**
⭐ NEW - New feature in v2.0
✅ - Implemented and tested
📊 - Dashboard/Visualization
🔐 - Security feature

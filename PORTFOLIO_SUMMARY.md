# VMStation - Portfolio Website Integration Guide

This repository contains a production-ready Kubernetes homelab environment perfect for showcasing infrastructure and DevOps skills.

## Quick Reference for Portfolio Display

### Elevator Pitch
A sophisticated 3-node Kubernetes homelab with automated deployment, comprehensive monitoring, and intelligent power management. Features multi-distribution support (Debian + RHEL), complete observability stack (Prometheus/Grafana/Loki), and automated sleep/wake functionality for energy efficiency.

### Key Highlights
- **🚀 Production-Grade:** Kubespray deployment automation
- **📊 Full Observability:** Prometheus, Grafana, Loki monitoring stack
- **⚡ Smart Power Management:** Automated sleep/wake with Wake-on-LAN
- **🔧 Multi-Distribution:** Seamless Debian + RHEL integration
- **📦 Modular Design:** Independent deployment of components

### Architecture at a Glance
```
┌──────────────────────────────────────────────────────────┐
│  masternode (192.168.4.63) - Control Plane - Always On  │
│  ├─ Kubernetes API Server                               │
│  ├─ Prometheus (Metrics)                                │
│  ├─ Grafana (Dashboards)                                │
│  └─ Loki (Logs)                                         │
├──────────────────────────────────────────────────────────┤
│  storagenodet3500 (192.168.4.61) - Storage - Auto-Sleep │
│  ├─ Jellyfin Media Server                               │
│  ├─ Storage Workloads                                   │
│  └─ Wake-on-LAN Enabled                                 │
├──────────────────────────────────────────────────────────┤
│  homelab (192.168.4.62) - Compute - Auto-Sleep          │
│  ├─ RHEL 10 Worker Node                                 │
│  ├─ General Compute                                     │
│  └─ Wake-on-LAN Enabled                                 │
└──────────────────────────────────────────────────────────┘
```

### Tech Stack Summary
- **Orchestration:** Kubernetes v1.29, Kubespray, kubeadm, RKE2
- **Automation:** Ansible 2.9+ with 15+ playbooks
- **Monitoring:** Prometheus, Grafana, Loki, Node Exporter
- **Infrastructure:** NTP/Chrony, Syslog, FreeIPA/Kerberos
- **Networking:** Flannel CNI, containerd runtime
- **OS:** Debian 12, RHEL 10

### Statistics
- **Deployment Time:** 25-30 minutes (full stack)
- **Lines of Automation:** 4,256 lines of Ansible code (17 playbooks + roles)
- **Manifests:** 33 Kubernetes manifests
- **Test Coverage:** 8+ validation scripts
- **Documentation:** 11 detailed guides

### Demo Links
- **Repository:** https://github.com/JashandeepJustinBains/VMStation
- **Grafana:** http://192.168.4.63:30300 (if publicly accessible)
- **Prometheus:** http://192.168.4.63:30090 (if publicly accessible)

## Files for Portfolio Integration

### Primary Documentation
1. **PORTFOLIO_NETWORK_TOPOLOGY.md** - Complete structured data for GNS3-style visualization
   - Node specifications with full details
   - Connection matrix and topology
   - Color coding guidelines
   - Ready-to-use code snippets for Vis.js integration

### Quick Start Command
```bash
# Single command deployment
./deploy.sh kubespray
```

### Visual Appeal
- **Color Scheme:**
  - Control Plane: Blue (#2563eb)
  - Storage: Green (#16a34a)
  - Compute: Orange (#ea580c)
  - Power Management: Purple (#9333ea)

## How to Use This for Portfolio

### For Network Topology Component
1. Use `PORTFOLIO_NETWORK_TOPOLOGY.md` as source
2. Copy node definitions to `NetworkTopology.astro`
3. Copy edge definitions for connections
4. Apply suggested color scheme

### For Repository Card
**Title:** VMStation - Kubernetes Homelab  
**Description:** Production-ready 3-node Kubernetes cluster with automated deployment, comprehensive monitoring (Prometheus/Grafana/Loki), and intelligent power management. Features multi-distro support and complete observability.

**Tags:**
- Kubernetes
- Ansible
- Prometheus
- Grafana
- DevOps
- Homelab
- Infrastructure-as-Code
- Monitoring

**Stats to Display:**
- ⭐ Stars: [GitHub will show]
- 🍴 Forks: [GitHub will show]
- 📝 17 Ansible Playbooks (4,256 lines)
- 🧪 8+ Test Scripts
- 📊 3 Node Cluster
- ⚡ Auto-Sleep Enabled

### Key Selling Points for Recruiters

1. **Enterprise Skills:**
   - Kubernetes deployment and management
   - Infrastructure automation with Ansible
   - Monitoring and observability best practices
   - Multi-distribution Linux administration

2. **DevOps Practices:**
   - Infrastructure as Code (IaC)
   - Automated testing and validation
   - CI/CD ready architecture
   - Documentation-first approach

3. **Innovation:**
   - Intelligent power management
   - Multi-cluster orchestration
   - Activity-aware automation
   - Cost optimization through auto-sleep

4. **Production Mindset:**
   - Idempotent automation
   - Comprehensive monitoring
   - Detailed documentation
   - Disaster recovery capable

## Sample Portfolio Description

```markdown
### VMStation: Enterprise-Grade Kubernetes Homelab

A sophisticated 3-node Kubernetes homelab demonstrating production-ready 
infrastructure patterns and DevOps best practices.

**Key Features:**
- Automated deployment using Kubespray and Ansible
- Complete observability with Prometheus, Grafana, and Loki
- Intelligent power management with Wake-on-LAN
- Multi-distribution support (Debian 12 + RHEL 10)
- 25-30 minute full-stack deployment

**Technical Achievements:**
- 15+ automated Ansible playbooks
- 20+ Kubernetes manifests
- Comprehensive test suite with 8+ validation scripts
- Zero-downtime monitoring architecture
- Energy-efficient auto-sleep functionality

**Skills Demonstrated:**
Kubernetes | Ansible | Prometheus | Grafana | Loki | Linux Administration | 
Infrastructure as Code | Monitoring & Observability | DevOps Automation
```

## Network Topology Visualization Guide

### Recommended Layout
```
         [masternode]
         (Control Plane)
         /           \
        /             \
       /               \
[storagenodet3500]  [homelab]
(Storage Worker)    (RHEL Compute)
```

### Interactive Features to Enable
- ✅ Click nodes to view detailed specs
- ✅ Hover to show services running
- ✅ Color-coded by node type
- ✅ Connection labels for data flow
- ✅ Status indicators (always-on vs auto-sleep)
- ✅ Link to GitHub repository

### Mobile Optimization
- Touch-friendly node selection
- Responsive layout for small screens
- Collapsible detail panels
- Pinch-to-zoom support

## LinkedIn Sharing Tips

When sharing this project on LinkedIn:

**Headline:**
"Built a Production-Ready Kubernetes Homelab with Automated Deployment & Monitoring"

**Description Template:**
```
Excited to share my latest homelab project: VMStation - a 3-node Kubernetes 
cluster with enterprise-grade features! 🚀

✅ Automated deployment with Ansible & Kubespray
✅ Complete monitoring stack (Prometheus/Grafana/Loki)
✅ Intelligent power management with Wake-on-LAN
✅ Multi-distribution support (Debian + RHEL)
✅ 25-minute full-stack deployment

This project demonstrates production Kubernetes patterns, infrastructure 
automation, and DevOps best practices - all skills I'm bringing to my 
next role!

Check it out: [your portfolio URL]

#Kubernetes #DevOps #Homelab #InfrastructureAsCode #Monitoring
```

## Questions to Answer in Interviews

When discussing this project in interviews, be prepared to answer:

1. **Architecture:** "Why did you choose this 3-node design?"
2. **Technology:** "Why Kubespray over other deployment methods?"
3. **Monitoring:** "How does your observability stack help with debugging?"
4. **Automation:** "What challenges did you face making deployments idempotent?"
5. **Innovation:** "Tell me about the auto-sleep feature - how does it work?"
6. **Scale:** "How would you scale this to 10 nodes? 100 nodes?"
7. **Disaster Recovery:** "Walk me through your backup and recovery process"
8. **Security:** "What security measures did you implement?"

## Additional Resources in Repository

- **README.md** - Main project overview
- **QUICK_START.md** - Fast deployment guide
- **docs/ARCHITECTURE.md** - Detailed architecture documentation
- **docs/USAGE.md** - Comprehensive usage guide
- **docs/TROUBLESHOOTING.md** - Common issues and solutions
- **TODO.md** - Future enhancements and roadmap

---

**Last Updated:** November 2024  
**Status:** Production Ready ✅  
**License:** MIT  
**Author:** Jashandeep Justin Bains

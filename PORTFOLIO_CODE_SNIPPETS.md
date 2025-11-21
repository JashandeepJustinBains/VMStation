# Portfolio Website Code Snippets for VMStation

Ready-to-use code snippets for integrating VMStation into the NetworkTopology.astro component.

## 1. Node Definitions (JavaScript)

Copy and paste this directly into your NetworkTopology.astro file:

```javascript
// VMStation Homelab Network Topology Nodes
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
      role: 'Control plane, always-on (24/7)',
      status: '🟢 Always Active',
      services: 'K8s API, Prometheus, Grafana, Loki, etcd, CoreDNS',
      ip: '192.168.4.63',
      highlights: 'Primary control plane • Monitoring hub • Time sync server'
    }
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
      role: 'Worker node, storage, media streaming',
      status: '🟡 Auto-Sleep Enabled',
      services: 'Jellyfin, Storage workloads, Node Exporter, Promtail',
      ip: '192.168.4.61',
      mac: 'b8:ac:6f:7e:6c:9d',
      highlights: 'Media streaming • Auto-sleep after 2hrs idle • WoL capable'
    }
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
      role: 'Worker node, general compute',
      status: '🟡 Auto-Sleep Enabled',
      services: 'General compute workloads, Node Exporter, Promtail',
      ip: '192.168.4.62',
      mac: 'd0:94:66:30:d6:63',
      highlights: 'Multi-distro support • Enterprise Linux • WoL capable'
    }
  }
];
```

## 2. Edge Definitions (JavaScript)

Copy and paste this directly into your NetworkTopology.astro file:

```javascript
// VMStation Homelab Network Connections
const edges = [
  // Kubernetes Control Plane connections
  {
    from: 1,
    to: 2,
    label: 'K8s Control / CNI',
    color: { color: '#2563eb' },
    width: 2,
    arrows: 'to;from'
  },
  {
    from: 1,
    to: 3,
    label: 'K8s Control / CNI',
    color: { color: '#2563eb' },
    width: 2,
    arrows: 'to;from'
  },
  
  // Monitoring data flow
  {
    from: 1,
    to: 2,
    label: 'Prometheus Scrape',
    color: { color: '#16a34a' },
    width: 1.5,
    dashes: true,
    arrows: 'to'
  },
  {
    from: 1,
    to: 3,
    label: 'Prometheus Scrape',
    color: { color: '#16a34a' },
    width: 1.5,
    dashes: true,
    arrows: 'to'
  },
  
  // Log aggregation
  {
    from: 2,
    to: 1,
    label: 'Log Push (Loki)',
    color: { color: '#ea580c' },
    width: 1.5,
    dashes: true,
    arrows: 'to'
  },
  {
    from: 3,
    to: 1,
    label: 'Log Push (Loki)',
    color: { color: '#ea580c' },
    width: 1.5,
    dashes: true,
    arrows: 'to'
  },
  
  // Wake-on-LAN power management
  {
    from: 1,
    to: 2,
    label: 'Wake-on-LAN',
    color: { color: '#9333ea' },
    width: 1,
    dashes: [10, 5],
    arrows: 'to'
  },
  {
    from: 1,
    to: 3,
    label: 'Wake-on-LAN',
    color: { color: '#9333ea' },
    width: 1,
    dashes: [10, 5],
    arrows: 'to'
  }
];
```

## 3. Vis.js Options Configuration

Enhanced options for better visualization:

```javascript
const options = {
  nodes: {
    shape: 'box',
    margin: 10,
    widthConstraint: {
      minimum: 120,
      maximum: 200
    },
    font: {
      size: 14,
      face: 'Inter, system-ui, sans-serif',
      bold: {
        size: 16
      }
    }
  },
  edges: {
    smooth: {
      type: 'cubicBezier',
      forceDirection: 'none',
      roundness: 0.4
    },
    font: {
      size: 11,
      align: 'middle',
      background: 'rgba(255, 255, 255, 0.9)',
      strokeWidth: 2,
      strokeColor: '#ffffff'
    }
  },
  groups: {
    hypervisor: {
      color: {
        background: '#dbeafe',
        border: '#2563eb',
        highlight: {
          background: '#bfdbfe',
          border: '#1d4ed8'
        }
      },
      borderWidth: 3
    },
    storage: {
      color: {
        background: '#dcfce7',
        border: '#16a34a',
        highlight: {
          background: '#bbf7d0',
          border: '#15803d'
        }
      },
      borderWidth: 3
    },
    application: {
      color: {
        background: '#fed7aa',
        border: '#ea580c',
        highlight: {
          background: '#fdba74',
          border: '#c2410c'
        }
      },
      borderWidth: 3
    }
  },
  physics: {
    enabled: true,
    hierarchicalRepulsion: {
      centralGravity: 0.3,
      springLength: 200,
      springConstant: 0.01,
      nodeDistance: 180,
      damping: 0.09
    },
    solver: 'hierarchicalRepulsion'
  },
  interaction: {
    hover: true,
    tooltipDelay: 100,
    navigationButtons: true,
    keyboard: true
  },
  layout: {
    hierarchical: {
      enabled: true,
      direction: 'UD',
      sortMethod: 'directed',
      levelSeparation: 150,
      nodeSpacing: 200
    }
  }
};
```

## 4. Repository Link Button

Add this button near your network topology:

```html
<a 
  href="https://github.com/JashandeepJustinBains/VMStation" 
  target="_blank"
  rel="noopener noreferrer"
  class="repo-link-button"
>
  <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
    <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z"/>
  </svg>
  View on GitHub
</a>

<style>
.repo-link-button {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.75rem 1.5rem;
  background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%);
  color: white;
  text-decoration: none;
  border-radius: 0.5rem;
  font-weight: 600;
  transition: all 0.3s ease;
  box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
}

.repo-link-button:hover {
  transform: translateY(-2px);
  box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.2);
}
</style>
```

## 5. Stats Badge Component

Display key statistics about the homelab:

```html
<div class="homelab-stats">
  <div class="stat-card">
    <div class="stat-value">3</div>
    <div class="stat-label">Nodes</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">17</div>
    <div class="stat-label">Playbooks</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">33</div>
    <div class="stat-label">Manifests</div>
  </div>
  <div class="stat-card">
    <div class="stat-value">~30min</div>
    <div class="stat-label">Deploy Time</div>
  </div>
</div>

<style>
.homelab-stats {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
  gap: 1rem;
  margin: 2rem 0;
}

.stat-card {
  background: linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%);
  padding: 1.5rem 1rem;
  border-radius: 0.75rem;
  text-align: center;
  border: 2px solid #cbd5e1;
  transition: all 0.3s ease;
}

.stat-card:hover {
  transform: translateY(-4px);
  box-shadow: 0 10px 20px -5px rgba(0, 0, 0, 0.15);
  border-color: #2563eb;
}

.stat-value {
  font-size: 2rem;
  font-weight: 700;
  color: #2563eb;
  line-height: 1;
  margin-bottom: 0.5rem;
}

.stat-label {
  font-size: 0.875rem;
  color: #64748b;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
</style>
```

## 6. Technology Stack Badges

Display technologies used:

```html
<div class="tech-stack">
  <span class="tech-badge tech-kubernetes">Kubernetes</span>
  <span class="tech-badge tech-ansible">Ansible</span>
  <span class="tech-badge tech-prometheus">Prometheus</span>
  <span class="tech-badge tech-grafana">Grafana</span>
  <span class="tech-badge tech-loki">Loki</span>
  <span class="tech-badge tech-debian">Debian</span>
  <span class="tech-badge tech-rhel">RHEL</span>
  <span class="tech-badge tech-containerd">containerd</span>
</div>

<style>
.tech-stack {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin: 1.5rem 0;
}

.tech-badge {
  display: inline-block;
  padding: 0.5rem 1rem;
  border-radius: 9999px;
  font-size: 0.875rem;
  font-weight: 600;
  color: white;
  transition: all 0.2s ease;
}

.tech-badge:hover {
  transform: scale(1.05);
  box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2);
}

.tech-kubernetes { background: linear-gradient(135deg, #326ce5 0%, #2563eb 100%); }
.tech-ansible { background: linear-gradient(135deg, #ee0000 0%, #c41e3a 100%); }
.tech-prometheus { background: linear-gradient(135deg, #e6522c 0%, #ea580c 100%); }
.tech-grafana { background: linear-gradient(135deg, #f46800 0%, #ea580c 100%); }
.tech-loki { background: linear-gradient(135deg, #f46800 0%, #d97706 100%); }
.tech-debian { background: linear-gradient(135deg, #d70a53 0%, #be185d 100%); }
.tech-rhel { background: linear-gradient(135deg, #ee0000 0%, #991b1b 100%); }
.tech-containerd { background: linear-gradient(135deg, #575757 0%, #374151 100%); }
</style>
```

## 7. Feature Highlights Section

```html
<div class="feature-highlights">
  <div class="feature-card">
    <div class="feature-icon">🚀</div>
    <h3>Automated Deployment</h3>
    <p>Single-command deployment with Kubespray. Idempotent playbooks ensure safe re-runs.</p>
  </div>
  
  <div class="feature-card">
    <div class="feature-icon">📊</div>
    <h3>Complete Monitoring</h3>
    <p>Full observability stack with Prometheus, Grafana, and Loki. Custom dashboards included.</p>
  </div>
  
  <div class="feature-card">
    <div class="feature-icon">⚡</div>
    <h3>Smart Power Management</h3>
    <p>Automated sleep/wake with Wake-on-LAN. Monitors activity patterns for energy efficiency.</p>
  </div>
  
  <div class="feature-card">
    <div class="feature-icon">🔧</div>
    <h3>Multi-Distribution</h3>
    <p>Seamless Debian + RHEL integration. Enterprise Linux compatibility tested.</p>
  </div>
</div>

<style>
.feature-highlights {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
  gap: 1.5rem;
  margin: 2rem 0;
}

.feature-card {
  background: white;
  padding: 1.5rem;
  border-radius: 0.75rem;
  border: 2px solid #e2e8f0;
  transition: all 0.3s ease;
}

.feature-card:hover {
  border-color: #2563eb;
  transform: translateY(-4px);
  box-shadow: 0 10px 20px -5px rgba(37, 99, 235, 0.2);
}

.feature-icon {
  font-size: 2.5rem;
  margin-bottom: 1rem;
}

.feature-card h3 {
  font-size: 1.25rem;
  font-weight: 700;
  color: #1e293b;
  margin-bottom: 0.5rem;
}

.feature-card p {
  font-size: 0.875rem;
  color: #64748b;
  line-height: 1.6;
}
</style>
```

## 8. Access Endpoints Table

```html
<div class="endpoints-section">
  <h3>Management Endpoints</h3>
  <table class="endpoints-table">
    <thead>
      <tr>
        <th>Service</th>
        <th>URL</th>
        <th>Purpose</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td><strong>Grafana</strong></td>
        <td><code>:30300</code></td>
        <td>Dashboards & Visualization</td>
        <td><span class="status-badge status-active">Active</span></td>
      </tr>
      <tr>
        <td><strong>Prometheus</strong></td>
        <td><code>:30090</code></td>
        <td>Metrics Collection</td>
        <td><span class="status-badge status-active">Active</span></td>
      </tr>
      <tr>
        <td><strong>Loki</strong></td>
        <td><code>:31100</code></td>
        <td>Log Aggregation</td>
        <td><span class="status-badge status-active">Active</span></td>
      </tr>
      <tr>
        <td><strong>Kubernetes API</strong></td>
        <td><code>:6443</code></td>
        <td>Cluster Management</td>
        <td><span class="status-badge status-active">Active</span></td>
      </tr>
    </tbody>
  </table>
</div>

<style>
.endpoints-section {
  margin: 2rem 0;
}

.endpoints-section h3 {
  font-size: 1.5rem;
  font-weight: 700;
  color: #1e293b;
  margin-bottom: 1rem;
}

.endpoints-table {
  width: 100%;
  border-collapse: collapse;
  background: white;
  border-radius: 0.5rem;
  overflow: hidden;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
}

.endpoints-table th {
  background: #f8fafc;
  padding: 1rem;
  text-align: left;
  font-weight: 600;
  color: #475569;
  border-bottom: 2px solid #e2e8f0;
}

.endpoints-table td {
  padding: 1rem;
  border-bottom: 1px solid #f1f5f9;
}

.endpoints-table tr:last-child td {
  border-bottom: none;
}

.endpoints-table code {
  background: #f1f5f9;
  padding: 0.25rem 0.5rem;
  border-radius: 0.25rem;
  font-family: 'JetBrains Mono', monospace;
  font-size: 0.875rem;
  color: #2563eb;
}

.status-badge {
  display: inline-block;
  padding: 0.25rem 0.75rem;
  border-radius: 9999px;
  font-size: 0.75rem;
  font-weight: 600;
}

.status-active {
  background: #dcfce7;
  color: #15803d;
}
</style>
```

## 9. Complete Integration Example

Here's a complete example combining all elements:

```astro
---
// src/components/VMStationTopology.astro
import 'vis-network/styles/vis-network.css';
---

<section class="vmstation-section">
  <div class="container">
    <h2 class="section-title">VMStation Homelab Infrastructure</h2>
    <p class="section-description">
      A production-ready 3-node Kubernetes cluster with automated deployment, 
      comprehensive monitoring, and intelligent power management.
    </p>

    <!-- Stats -->
    <div class="homelab-stats">
      <!-- Stats badges from snippet #5 -->
    </div>

    <!-- Tech Stack -->
    <div class="tech-stack">
      <!-- Tech badges from snippet #6 -->
    </div>

    <!-- Network Topology -->
    <div id="vmstation-network" class="network-container"></div>

    <!-- GitHub Link -->
    <div class="center-button">
      <!-- Button from snippet #4 -->
    </div>

    <!-- Feature Highlights -->
    <div class="feature-highlights">
      <!-- Features from snippet #7 -->
    </div>

    <!-- Endpoints -->
    <div class="endpoints-section">
      <!-- Table from snippet #8 -->
    </div>
  </div>
</section>

<script>
  import { Network } from 'vis-network/standalone';

  // Use nodes from snippet #1
  const nodes = [ /* ... */ ];
  
  // Use edges from snippet #2
  const edges = [ /* ... */ ];
  
  // Use options from snippet #3
  const options = { /* ... */ };

  const container = document.getElementById('vmstation-network');
  const data = { nodes, edges };
  const network = new Network(container, data, options);

  // Click handler to show node details
  network.on('selectNode', (params) => {
    const nodeId = params.nodes[0];
    const node = nodes.find(n => n.id === nodeId);
    if (node && node.specs) {
      // Display specs in a modal or side panel
      console.log('Node specs:', node.specs);
    }
  });
</script>

<style>
.vmstation-section {
  padding: 4rem 2rem;
  background: linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%);
}

.container {
  max-width: 1200px;
  margin: 0 auto;
}

.section-title {
  font-size: 2.5rem;
  font-weight: 700;
  color: #1e293b;
  text-align: center;
  margin-bottom: 1rem;
}

.section-description {
  font-size: 1.125rem;
  color: #64748b;
  text-align: center;
  max-width: 800px;
  margin: 0 auto 2rem;
  line-height: 1.6;
}

.network-container {
  width: 100%;
  height: 600px;
  background: white;
  border-radius: 1rem;
  box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.1);
  margin: 2rem 0;
  border: 2px solid #e2e8f0;
}

.center-button {
  display: flex;
  justify-content: center;
  margin: 2rem 0;
}

/* Include other styles from snippets */
</style>
```

## 10. JSON Data Import (Alternative Approach)

If you prefer to fetch data from JSON:

```javascript
// Fetch from portfolio-data.json (adjust path as needed)
fetch('./portfolio-data.json')  // Or '/data/portfolio-data.json' if in public folder
  .then(response => response.json())
  .then(data => {
    const nodes = data.network_topology.nodes.map(node => ({
      id: node.id,
      label: node.label,
      group: node.group,
      title: node.title,
      specs: {
        ...node.specs,
        services: node.services.map(s => s.name).join(', ')
      }
    }));

    const edges = data.network_topology.edges;

    // Initialize network with this data
    const network = new Network(container, { nodes, edges }, options);
  });
```

---

## Quick Copy Checklist

- [ ] Copy nodes array (snippet #1)
- [ ] Copy edges array (snippet #2)
- [ ] Copy visualization options (snippet #3)
- [ ] Add GitHub link button (snippet #4)
- [ ] Add stats badges (snippet #5)
- [ ] Add tech stack badges (snippet #6)
- [ ] Add feature highlights (snippet #7)
- [ ] Add endpoints table (snippet #8)
- [ ] Update colors to match your theme
- [ ] Test on mobile devices

## Color Palette Reference

```css
/* VMStation Brand Colors */
--color-control-plane: #2563eb;  /* Blue - Control plane */
--color-storage: #16a34a;        /* Green - Storage */
--color-compute: #ea580c;        /* Orange - Compute */
--color-power: #9333ea;          /* Purple - Power management */

/* Supporting Colors */
--color-bg-light: #f8fafc;
--color-bg-medium: #e2e8f0;
--color-border: #cbd5e1;
--color-text-primary: #1e293b;
--color-text-secondary: #64748b;
```

---

**Ready to integrate!** All snippets are production-ready and mobile-responsive.

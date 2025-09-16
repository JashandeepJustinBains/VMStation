import { RepositoryData, ClusterTopology, ClusterNode, ClusterEdge } from '@/types';

export async function loadRepositoryData(): Promise<RepositoryData> {
  try {
    const response = await fetch('/data/repo_index.json');
    if (!response.ok) {
      throw new Error('Failed to load repository data');
    }
    return await response.json();
  } catch (error) {
    console.error('Error loading repository data:', error);
    throw error;
  }
}

export function getFileIcon(type: string): string {
  switch (type) {
    case 'script': return '⚙️';
    case 'doc': return '📄';
    case 'config': return '⚙️';
    case 'todo': return '📝';
    case 'template': return '📋';
    default: return '📁';
  }
}

export function getFileTypeColor(type: string): string {
  switch (type) {
    case 'script': return 'border-green-400 bg-green-50';
    case 'doc': return 'border-blue-400 bg-blue-50';
    case 'config': return 'border-orange-400 bg-orange-50';
    case 'todo': return 'border-purple-400 bg-purple-50';
    case 'template': return 'border-pink-400 bg-pink-50';
    default: return 'border-gray-400 bg-gray-50';
  }
}

export function formatFileSize(bytes: number): string {
  const sizes = ['B', 'KB', 'MB', 'GB'];
  if (bytes === 0) return '0 B';
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return Math.round(bytes / Math.pow(1024, i) * 100) / 100 + ' ' + sizes[i];
}

export function generateClusterTopology(): ClusterTopology {
  const nodes: ClusterNode[] = [
    {
      id: 'control-plane',
      name: 'Control Plane',
      type: 'control-plane',
      status: 'healthy',
      ip: '192.168.4.63',
      description: 'MiniPC - Kubernetes Master Node',
      metadata: {
        hostname: 'masternode',
        role: 'control-plane',
        components: ['kube-apiserver', 'kube-controller-manager', 'kube-scheduler', 'etcd']
      }
    },
    {
      id: 'worker-t3500',
      name: 'T3500 Worker',
      type: 'worker',
      status: 'healthy',
      ip: '192.168.4.61',
      description: 'T3500 - Storage & Compute Worker',
      metadata: {
        hostname: 'storagenodet3500',
        role: 'worker',
        specialization: 'storage'
      }
    },
    {
      id: 'worker-r430',
      name: 'R430 Worker',
      type: 'worker',
      status: 'healthy',
      ip: '192.168.4.62',
      description: 'R430 - Compute Worker Node',
      metadata: {
        hostname: 'homelab',
        role: 'worker',
        specialization: 'compute'
      }
    },
    {
      id: 'kube-proxy',
      name: 'kube-proxy',
      type: 'cni',
      status: 'healthy',
      description: 'Kubernetes network proxy component',
      metadata: {
        component: 'kube-proxy',
        namespace: 'kube-system'
      }
    },
    {
      id: 'flannel',
      name: 'Flannel CNI',
      type: 'cni',
      status: 'healthy',
      description: 'Container Network Interface',
      metadata: {
        component: 'flannel',
        namespace: 'kube-flannel'
      }
    },
    {
      id: 'coredns',
      name: 'CoreDNS',
      type: 'dns',
      status: 'healthy',
      description: 'Cluster DNS service',
      metadata: {
        component: 'coredns',
        namespace: 'kube-system',
        clusterIP: '10.96.0.10'
      }
    },
    {
      id: 'jellyfin',
      name: 'Jellyfin',
      type: 'service',
      status: 'healthy',
      description: 'Media server application',
      metadata: {
        namespace: 'jellyfin',
        nodePort: 30096
      }
    },
    {
      id: 'prometheus',
      name: 'Prometheus',
      type: 'service',
      status: 'healthy',
      description: 'Monitoring and alerting',
      metadata: {
        namespace: 'monitoring',
        component: 'prometheus'
      }
    },
    {
      id: 'grafana',
      name: 'Grafana',
      type: 'service',
      status: 'healthy',
      description: 'Metrics visualization',
      metadata: {
        namespace: 'monitoring',
        component: 'grafana'
      }
    }
  ];

  const edges: ClusterEdge[] = [
    {
      from: 'control-plane',
      to: 'worker-t3500',
      type: 'network',
      status: 'active',
      protocol: 'TCP',
      port: 6443
    },
    {
      from: 'control-plane',
      to: 'worker-r430',
      type: 'network',
      status: 'active',
      protocol: 'TCP',
      port: 6443
    },
    {
      from: 'kube-proxy',
      to: 'control-plane',
      type: 'communication',
      status: 'active'
    },
    {
      from: 'kube-proxy',
      to: 'worker-t3500',
      type: 'communication',
      status: 'active'
    },
    {
      from: 'kube-proxy',
      to: 'worker-r430',
      type: 'communication',
      status: 'active'
    },
    {
      from: 'flannel',
      to: 'control-plane',
      type: 'network',
      status: 'active'
    },
    {
      from: 'flannel',
      to: 'worker-t3500',
      type: 'network',
      status: 'active'
    },
    {
      from: 'flannel',
      to: 'worker-r430',
      type: 'network',
      status: 'active'
    },
    {
      from: 'coredns',
      to: 'control-plane',
      type: 'dependency',
      status: 'active'
    },
    {
      from: 'jellyfin',
      to: 'worker-t3500',
      type: 'dependency',
      status: 'active'
    },
    {
      from: 'prometheus',
      to: 'control-plane',
      type: 'dependency',
      status: 'active'
    },
    {
      from: 'grafana',
      to: 'prometheus',
      type: 'dependency',
      status: 'active'
    }
  ];

  return { nodes, edges };
}
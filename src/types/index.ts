export interface RepositoryNode {
  id: string;
  path: string;
  type: 'script' | 'doc' | 'config' | 'todo' | 'template';
  title: string;
  summary: string;
  sizeBytes: number;
  tags: string[];
  lastModified: string;
  lines: number;
}

export interface RepositoryEdge {
  from: string;
  to: string;
  relation: 'calls' | 'references' | 'mentions';
  context: string;
}

export interface RepositoryData {
  nodes: RepositoryNode[];
  edges: RepositoryEdge[];
  metadata: {
    totalFiles: number;
    extractedAt: string;
    repoPath: string;
    stats: {
      byType: Record<string, number>;
      totalSize: number;
      averageSize: number;
    };
  };
}

export interface ClusterNode {
  id: string;
  name: string;
  type: 'control-plane' | 'worker' | 'pod' | 'service' | 'cni' | 'dns';
  status: 'healthy' | 'warning' | 'error' | 'unknown';
  ip?: string;
  description: string;
  metadata: Record<string, any>;
}

export interface ClusterEdge {
  from: string;
  to: string;
  type: 'network' | 'dependency' | 'communication';
  status: 'active' | 'inactive' | 'error';
  protocol?: string;
  port?: number;
}

export interface ClusterTopology {
  nodes: ClusterNode[];
  edges: ClusterEdge[];
}

export interface CardPosition {
  id: string;
  x: number;
  y: number;
  vx?: number;
  vy?: number;
  anchored?: boolean;
  selected?: boolean;
}
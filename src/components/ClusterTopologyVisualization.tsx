'use client';

import { useEffect, useRef, useState } from 'react';
import { motion } from 'framer-motion';
import * as d3 from 'd3';

interface ClusterNode {
  id: string;
  type: 'control-plane' | 'worker' | 'pod' | 'service' | 'network';
  name: string;
  status: 'healthy' | 'warning' | 'critical' | 'unknown';
  ip?: string;
  description: string;
  x?: number;
  y?: number;
  fx?: number | null;
  fy?: number | null;
}

interface ClusterLink {
  source: string;
  target: string;
  type: 'network' | 'service' | 'storage' | 'control';
  status: 'active' | 'inactive';
  bandwidth?: string;
}

interface ClusterTopologyProps {
  animationSpeed: number;
  showTooltips: boolean;
}

export default function ClusterTopologyVisualization({ 
  animationSpeed, 
  showTooltips 
}: ClusterTopologyProps) {
  const svgRef = useRef<SVGSVGElement>(null);
  const [selectedNode, setSelectedNode] = useState<ClusterNode | null>(null);
  const [tooltip, setTooltip] = useState<{ x: number; y: number; content: string } | null>(null);

  // Sample cluster data based on VMStation configuration
  const nodes: ClusterNode[] = [
    // Control Plane
    {
      id: 'masternode',
      type: 'control-plane',
      name: 'masternode',
      status: 'healthy',
      ip: '192.168.4.63',
      description: 'Kubernetes control plane - API server, etcd, scheduler'
    },
    
    // Worker Nodes
    {
      id: 'storagenode',
      type: 'worker',
      name: 'storagenodet3500',
      status: 'healthy',
      ip: '192.168.4.61',
      description: 'Storage node running Jellyfin media server'
    },
    {
      id: 'homelab',
      type: 'worker',
      name: 'homelab',
      status: 'healthy',
      ip: '192.168.4.62',
      description: 'Compute node for general workloads (RHEL 10)'
    },
    
    // Network Components
    {
      id: 'flannel',
      type: 'network',
      name: 'Flannel CNI',
      status: 'healthy',
      description: 'Container network interface providing pod networking'
    },
    {
      id: 'coredns',
      type: 'service',
      name: 'CoreDNS',
      status: 'healthy',
      description: 'Cluster DNS service for service discovery'
    },
    {
      id: 'kube-proxy',
      type: 'network',
      name: 'kube-proxy',
      status: 'healthy',
      description: 'Network proxy running on each node'
    },
    
    // Pods/Services
    {
      id: 'jellyfin-pod',
      type: 'pod',
      name: 'Jellyfin',
      status: 'healthy',
      description: 'Media streaming server pod'
    },
    {
      id: 'prometheus',
      type: 'pod',
      name: 'Prometheus',
      status: 'healthy',
      description: 'Monitoring and alerting system'
    },
    {
      id: 'grafana',
      type: 'pod',
      name: 'Grafana',
      status: 'healthy',
      description: 'Monitoring dashboard and visualization'
    },
    {
      id: 'loki',
      type: 'pod',
      name: 'Loki',
      status: 'warning',
      description: 'Log aggregation system'
    }
  ];

  const links: ClusterLink[] = [
    // Control plane connections
    { source: 'masternode', target: 'storagenode', type: 'control', status: 'active' },
    { source: 'masternode', target: 'homelab', type: 'control', status: 'active' },
    
    // CNI connections
    { source: 'flannel', target: 'masternode', type: 'network', status: 'active' },
    { source: 'flannel', target: 'storagenode', type: 'network', status: 'active' },
    { source: 'flannel', target: 'homelab', type: 'network', status: 'active' },
    
    // Service connections
    { source: 'coredns', target: 'masternode', type: 'service', status: 'active' },
    { source: 'kube-proxy', target: 'masternode', type: 'network', status: 'active' },
    { source: 'kube-proxy', target: 'storagenode', type: 'network', status: 'active' },
    { source: 'kube-proxy', target: 'homelab', type: 'network', status: 'active' },
    
    // Pod scheduling
    { source: 'jellyfin-pod', target: 'storagenode', type: 'service', status: 'active' },
    { source: 'prometheus', target: 'masternode', type: 'service', status: 'active' },
    { source: 'grafana', target: 'masternode', type: 'service', status: 'active' },
    { source: 'loki', target: 'masternode', type: 'service', status: 'active' },
    
    // Pod networking
    { source: 'jellyfin-pod', target: 'flannel', type: 'network', status: 'active' },
    { source: 'prometheus', target: 'flannel', type: 'network', status: 'active' },
    { source: 'grafana', target: 'flannel', type: 'network', status: 'active' },
    { source: 'loki', target: 'flannel', type: 'network', status: 'active' }
  ];

  useEffect(() => {
    if (!svgRef.current) return;

    const svg = d3.select(svgRef.current);
    const width = 800;
    const height = 600;

    // Clear previous content
    svg.selectAll('*').remove();

    // Create main group
    const g = svg.append('g');

    // Define node colors based on type and status
    const getNodeColor = (node: ClusterNode) => {
      const statusColors = {
        healthy: '#10B981',
        warning: '#F59E0B', 
        critical: '#EF4444',
        unknown: '#6B7280'
      };
      return statusColors[node.status];
    };

    const getNodeSize = (node: ClusterNode) => {
      switch (node.type) {
        case 'control-plane': return 25;
        case 'worker': return 20;
        case 'service': return 15;
        case 'network': return 15;
        case 'pod': return 12;
        default: return 10;
      }
    };

    // Create force simulation
    const simulation = d3.forceSimulation(nodes)
      .force('link', d3.forceLink(links).id((d: any) => d.id).distance(100))
      .force('charge', d3.forceManyBody().strength(-300))
      .force('center', d3.forceCenter(width / 2, height / 2))
      .force('collision', d3.forceCollide().radius(d => getNodeSize(d as ClusterNode) + 5));

    // Create links
    const link = g.append('g')
      .selectAll('line')
      .data(links)
      .enter()
      .append('line')
      .attr('class', 'cluster-link')
      .attr('stroke', d => {
        switch (d.type) {
          case 'control': return '#8B5CF6';
          case 'network': return '#3B82F6';
          case 'service': return '#10B981';
          case 'storage': return '#F59E0B';
          default: return '#6B7280';
        }
      })
      .attr('stroke-width', 2)
      .attr('opacity', 0.6);

    // Create nodes
    const node = g.append('g')
      .selectAll('circle')
      .data(nodes)
      .enter()
      .append('circle')
      .attr('class', 'cluster-node')
      .attr('r', d => getNodeSize(d))
      .attr('fill', d => getNodeColor(d))
      .attr('stroke', '#fff')
      .attr('stroke-width', 2)
      .style('cursor', 'pointer')
      .call(d3.drag<SVGCircleElement, ClusterNode>()
        .on('start', dragstarted)
        .on('drag', dragged)
        .on('end', dragended));

    // Create node labels
    const labels = g.append('g')
      .selectAll('text')
      .data(nodes)
      .enter()
      .append('text')
      .text(d => d.name)
      .attr('font-size', '12px')
      .attr('fill', '#fff')
      .attr('text-anchor', 'middle')
      .attr('dy', -30)
      .style('pointer-events', 'none');

    // Add click handlers
    node.on('click', (event, d) => {
      setSelectedNode(d);
    });

    // Add hover handlers for tooltips
    if (showTooltips) {
      node.on('mouseover', (event, d) => {
        const [x, y] = d3.pointer(event, document.body);
        setTooltip({
          x,
          y,
          content: `${d.name}: ${d.description}`
        });
      }).on('mouseout', () => {
        setTooltip(null);
      });
    }

    // Update positions on simulation tick
    simulation.on('tick', () => {
      link
        .attr('x1', (d: any) => d.source.x)
        .attr('y1', (d: any) => d.source.y)
        .attr('x2', (d: any) => d.target.x)
        .attr('y2', (d: any) => d.target.y);

      node
        .attr('cx', d => d.x!)
        .attr('cy', d => d.y!);

      labels
        .attr('x', d => d.x!)
        .attr('y', d => d.y!);
    });

    // Drag functions
    function dragstarted(event: d3.D3DragEvent<SVGCircleElement, ClusterNode, ClusterNode>) {
      if (!event.active) simulation.alphaTarget(0.3).restart();
      event.subject.fx = event.subject.x;
      event.subject.fy = event.subject.y;
    }

    function dragged(event: d3.D3DragEvent<SVGCircleElement, ClusterNode, ClusterNode>) {
      event.subject.fx = event.x;
      event.subject.fy = event.y;
    }

    function dragended(event: d3.D3DragEvent<SVGCircleElement, ClusterNode, ClusterNode>) {
      if (!event.active) simulation.alphaTarget(0);
      event.subject.fx = null;
      event.subject.fy = null;
    }

    // Animate links with barber pole effect
    const animateLinks = () => {
      link.style('stroke-dasharray', '5,5')
          .style('stroke-dashoffset', 0)
          .transition()
          .duration(2000 / animationSpeed)
          .ease(d3.easeLinear)
          .style('stroke-dashoffset', -10)
          .on('end', animateLinks);
    };

    if (animationSpeed > 0) {
      animateLinks();
    }

    return () => {
      simulation.stop();
    };
  }, [animationSpeed, showTooltips, nodes, links]);

  return (
    <div className="relative w-full h-full flex items-center justify-center">
      <div className="glass-card p-4 max-w-4xl w-full">
        <svg
          ref={svgRef}
          width="800"
          height="600"
          className="w-full h-auto"
          viewBox="0 0 800 600"
        >
        </svg>
        
        {/* Tooltip */}
        {tooltip && (
          <motion.div
            className="fixed z-50 bg-black/80 text-white p-2 rounded-md text-sm pointer-events-none"
            style={{
              left: tooltip.x + 10,
              top: tooltip.y - 30
            }}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            {tooltip.content}
          </motion.div>
        )}
        
        {/* Selected Node Details */}
        {selectedNode && (
          <motion.div
            className="absolute top-4 right-4 glass-card p-4 max-w-xs"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: 20 }}
          >
            <div className="flex items-center justify-between mb-2">
              <h3 className="font-semibold text-white">{selectedNode.name}</h3>
              <button
                onClick={() => setSelectedNode(null)}
                className="text-gray-400 hover:text-white"
              >
                ✕
              </button>
            </div>
            <div className="text-sm text-gray-300 space-y-1">
              <div>Type: <span className="text-white">{selectedNode.type}</span></div>
              {selectedNode.ip && (
                <div>IP: <span className="text-white">{selectedNode.ip}</span></div>
              )}
              <div>Status: 
                <span className={`ml-1 px-2 py-1 rounded-full text-xs ${
                  selectedNode.status === 'healthy' ? 'bg-green-500/20 text-green-300' :
                  selectedNode.status === 'warning' ? 'bg-yellow-500/20 text-yellow-300' :
                  selectedNode.status === 'critical' ? 'bg-red-500/20 text-red-300' :
                  'bg-gray-500/20 text-gray-300'
                }`}>
                  {selectedNode.status}
                </span>
              </div>
              <div className="pt-2 border-t border-white/20">
                <p className="text-gray-400">{selectedNode.description}</p>
              </div>
            </div>
          </motion.div>
        )}
      </div>
    </div>
  );
}
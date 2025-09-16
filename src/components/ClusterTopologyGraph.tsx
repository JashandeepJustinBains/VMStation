'use client';

import { useState, useRef, useEffect } from 'react';
import { motion } from 'framer-motion';
import { ClusterTopology, ClusterNode, ClusterEdge } from '@/types';

interface ClusterTopologyGraphProps {
  topology: ClusterTopology;
  animationSpeed: number;
}

export default function ClusterTopologyGraph({ topology, animationSpeed }: ClusterTopologyGraphProps) {
  const svgRef = useRef<SVGSVGElement>(null);
  const [dimensions, setDimensions] = useState({ width: 800, height: 600 });
  const [selectedNode, setSelectedNode] = useState<ClusterNode | null>(null);
  const [hoveredNode, setHoveredNode] = useState<ClusterNode | null>(null);

  // Update dimensions
  useEffect(() => {
    const updateDimensions = () => {
      if (svgRef.current) {
        const rect = svgRef.current.getBoundingClientRect();
        setDimensions({ width: rect.width, height: rect.height });
      }
    };

    updateDimensions();
    window.addEventListener('resize', updateDimensions);
    return () => window.removeEventListener('resize', updateDimensions);
  }, []);

  // Calculate node positions (simple force-directed layout)
  const nodePositions = topology.nodes.reduce((acc, node, index) => {
    const centerX = dimensions.width / 2;
    const centerY = dimensions.height / 2;
    const radius = Math.min(dimensions.width, dimensions.height) * 0.3;
    
    let x, y;
    
    // Position nodes based on type
    switch (node.type) {
      case 'control-plane':
        x = centerX;
        y = centerY - radius;
        break;
      case 'worker':
        const workerIndex = topology.nodes.filter(n => n.type === 'worker').indexOf(node);
        const workerAngle = (workerIndex * 120 - 60) * Math.PI / 180;
        x = centerX + Math.cos(workerAngle) * radius;
        y = centerY + Math.sin(workerAngle) * radius;
        break;
      case 'cni':
      case 'dns':
        const systemIndex = topology.nodes.filter(n => n.type === 'cni' || n.type === 'dns').indexOf(node);
        const systemAngle = (systemIndex * 90 - 45) * Math.PI / 180;
        x = centerX + Math.cos(systemAngle) * (radius * 0.6);
        y = centerY + Math.sin(systemAngle) * (radius * 0.6);
        break;
      case 'service':
        const serviceIndex = topology.nodes.filter(n => n.type === 'service').indexOf(node);
        const serviceAngle = (serviceIndex * 60 + 30) * Math.PI / 180;
        x = centerX + Math.cos(serviceAngle) * (radius * 1.2);
        y = centerY + Math.sin(serviceAngle) * (radius * 1.2);
        break;
      default:
        x = centerX + (Math.random() - 0.5) * radius;
        y = centerY + (Math.random() - 0.5) * radius;
    }
    
    acc[node.id] = { x, y };
    return acc;
  }, {} as Record<string, { x: number; y: number }>);

  // Get node color based on type and status
  const getNodeColor = (node: ClusterNode) => {
    const baseColors: Record<string, string> = {
      'control-plane': '#8b5cf6',
      'worker': '#06b6d4',
      'pod': '#8b5cf6',
      'service': '#f59e0b',
      'cni': '#10b981',
      'dns': '#10b981'
    };

    const statusOverlay: Record<string, string> = {
      'healthy': '',
      'warning': 'brightness(1.2) saturate(1.3)',
      'error': 'hue-rotate(0deg) saturate(1.5)',
      'unknown': 'grayscale(0.5)'
    };

    return {
      color: baseColors[node.type] || '#6b7280',
      filter: statusOverlay[node.status] || ''
    };
  };

  // Get edge style
  const getEdgeStyle = (edge: ClusterEdge) => {
    const styles = {
      network: {
        stroke: '#06b6d4',
        strokeWidth: 3,
        strokeDasharray: edge.status === 'active' ? '0' : '5,5'
      },
      communication: {
        stroke: '#10b981',
        strokeWidth: 2,
        strokeDasharray: '3,3'
      },
      dependency: {
        stroke: '#f59e0b',
        strokeWidth: 2,
        strokeDasharray: '1,2'
      }
    };

    return styles[edge.type] || styles.network;
  };

  return (
    <div className="w-full h-screen relative overflow-hidden">
      <svg
        ref={svgRef}
        className="w-full h-full"
        viewBox={`0 0 ${dimensions.width} ${dimensions.height}`}
      >
        <defs>
          {/* Barber pole pattern for active connections */}
          <pattern
            id="barberPole"
            patternUnits="userSpaceOnUse"
            width="20"
            height="20"
            patternTransform="rotate(45)"
          >
            <rect width="10" height="20" fill="#06b6d4" opacity="0.8" />
            <rect x="10" width="10" height="20" fill="#0891b2" opacity="0.8" />
            <animateTransform
              attributeName="patternTransform"
              type="translate"
              values="0,0;20,0;0,0"
              dur={`${2 / animationSpeed}s`}
              repeatCount="indefinite"
            />
          </pattern>

          {/* Glow filters for nodes */}
          <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation="3" result="coloredBlur"/>
            <feMerge> 
              <feMergeNode in="coloredBlur"/>
              <feMergeNode in="SourceGraphic"/>
            </feMerge>
          </filter>
        </defs>

        {/* Edges */}
        {topology.edges.map((edge, index) => {
          const fromPos = nodePositions[edge.from];
          const toPos = nodePositions[edge.to];
          if (!fromPos || !toPos) return null;

          const style = getEdgeStyle(edge);
          const isActive = edge.status === 'active';

          return (
            <g key={`edge-${index}`}>
              {/* Background line */}
              <motion.line
                initial={{ pathLength: 0, opacity: 0 }}
                animate={{ pathLength: 1, opacity: 0.3 }}
                transition={{ duration: 0.5, delay: index * 0.1 }}
                x1={fromPos.x}
                y1={fromPos.y}
                x2={toPos.x}
                y2={toPos.y}
                stroke={style.stroke}
                strokeWidth={style.strokeWidth + 2}
                opacity={0.2}
              />

              {/* Main line */}
              <motion.line
                initial={{ pathLength: 0, opacity: 0 }}
                animate={{ pathLength: 1, opacity: 1 }}
                transition={{ duration: 0.5, delay: index * 0.1 }}
                x1={fromPos.x}
                y1={fromPos.y}
                x2={toPos.x}
                y2={toPos.y}
                stroke={isActive && edge.type === 'network' ? 'url(#barberPole)' : style.stroke}
                strokeWidth={style.strokeWidth}
                strokeDasharray={style.strokeDasharray}
                className={isActive ? 'barber-pole-link' : ''}
              />

              {/* Edge label */}
              <motion.text
                initial={{ opacity: 0 }}
                animate={{ opacity: hoveredNode ? 0.8 : 0.5 }}
                transition={{ duration: 0.3 }}
                x={(fromPos.x + toPos.x) / 2}
                y={(fromPos.y + toPos.y) / 2}
                textAnchor="middle"
                className="text-xs fill-gray-600 font-medium"
                style={{ fontSize: '10px' }}
              >
                {edge.protocol && edge.port ? `${edge.protocol}:${edge.port}` : edge.type}
              </motion.text>
            </g>
          );
        })}

        {/* Nodes */}
        {topology.nodes.map((node, index) => {
          const position = nodePositions[node.id];
          if (!position) return null;

          const nodeStyle = getNodeColor(node);
          const isSelected = selectedNode?.id === node.id;
          const isHovered = hoveredNode?.id === node.id;

          return (
            <g 
              key={node.id}
              style={{ cursor: 'pointer' }}
              onClick={() => setSelectedNode(isSelected ? null : node)}
              onMouseEnter={() => setHoveredNode(node)}
              onMouseLeave={() => setHoveredNode(null)}
            >
              {/* Node glow effect */}
              {(isSelected || isHovered) && (
                <motion.circle
                  initial={{ r: 0, opacity: 0 }}
                  animate={{ r: 25, opacity: 0.3 }}
                  exit={{ r: 0, opacity: 0 }}
                  cx={position.x}
                  cy={position.y}
                  fill={nodeStyle.color}
                  filter="url(#glow)"
                />
              )}

              {/* Main node */}
              <motion.circle
                initial={{ scale: 0, opacity: 0 }}
                animate={{ 
                  scale: isSelected ? 1.3 : isHovered ? 1.1 : 1,
                  opacity: 1 
                }}
                transition={{ duration: 0.3, delay: index * 0.1 }}
                cx={position.x}
                cy={position.y}
                r={node.type === 'control-plane' ? 20 : 15}
                fill={nodeStyle.color}
                stroke="white"
                strokeWidth="3"
                style={{ filter: nodeStyle.filter }}
              />

              {/* Status indicator */}
              <circle
                cx={position.x + 12}
                cy={position.y - 12}
                r="4"
                fill={
                  node.status === 'healthy' ? '#22c55e' :
                  node.status === 'warning' ? '#f59e0b' :
                  node.status === 'error' ? '#ef4444' : '#6b7280'
                }
                stroke="white"
                strokeWidth="1"
              />

              {/* Node label */}
              <motion.text
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ duration: 0.3, delay: 0.5 + index * 0.1 }}
                x={position.x}
                y={position.y + 35}
                textAnchor="middle"
                className="text-sm font-medium fill-gray-900"
              >
                {node.name}
              </motion.text>

              {/* IP address for physical nodes */}
              {node.ip && (
                <motion.text
                  initial={{ opacity: 0 }}
                  animate={{ opacity: isHovered ? 1 : 0.7 }}
                  x={position.x}
                  y={position.y + 50}
                  textAnchor="middle"
                  className="text-xs fill-gray-600"
                >
                  {node.ip}
                </motion.text>
              )}
            </g>
          );
        })}
      </svg>

      {/* Node Details Panel */}
      {selectedNode && (
        <motion.div
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: 20 }}
          className="absolute top-4 right-4 bg-white rounded-lg shadow-lg p-4 max-w-sm"
        >
          <div className="flex items-center space-x-3 mb-3">
            <div
              className="w-4 h-4 rounded-full"
              style={{ backgroundColor: getNodeColor(selectedNode).color }}
            />
            <h3 className="font-semibold text-gray-900">{selectedNode.name}</h3>
          </div>
          
          <div className="space-y-2 text-sm">
            <div><span className="font-medium">Type:</span> {selectedNode.type}</div>
            <div><span className="font-medium">Status:</span> 
              <span className={`ml-1 px-2 py-1 rounded-full text-xs ${
                selectedNode.status === 'healthy' ? 'bg-green-100 text-green-800' :
                selectedNode.status === 'warning' ? 'bg-yellow-100 text-yellow-800' :
                selectedNode.status === 'error' ? 'bg-red-100 text-red-800' :
                'bg-gray-100 text-gray-800'
              }`}>
                {selectedNode.status}
              </span>
            </div>
            {selectedNode.ip && (
              <div><span className="font-medium">IP:</span> {selectedNode.ip}</div>
            )}
            <div><span className="font-medium">Description:</span> {selectedNode.description}</div>
            
            {/* Metadata */}
            {Object.keys(selectedNode.metadata).length > 0 && (
              <div className="mt-3 pt-3 border-t border-gray-200">
                <span className="font-medium text-gray-700">Metadata:</span>
                <div className="mt-1 space-y-1">
                  {Object.entries(selectedNode.metadata).map(([key, value]) => (
                    <div key={key} className="text-xs text-gray-600">
                      <span className="font-medium">{key}:</span> {Array.isArray(value) ? value.join(', ') : String(value)}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </motion.div>
      )}
    </div>
  );
}
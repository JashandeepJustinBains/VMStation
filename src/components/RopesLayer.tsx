'use client';

import { motion } from 'framer-motion';

interface Node {
  id: string;
  path: string;
  type: string;
  title: string;
  summary: string;
  tags: string[];
}

interface Edge {
  from: string;
  to: string;
  relation: string;
}

interface CardPosition {
  x: number;
  y: number;
}

interface RopesLayerProps {
  edges: Edge[];
  positions: Map<string, CardPosition>;
  nodes: Node[];
}

export default function RopesLayer({ edges, positions, nodes }: RopesLayerProps) {
  if (!edges.length) return null;

  const getNodePosition = (nodeId: string) => {
    return positions.get(nodeId) || { x: 0, y: 0 };
  };

  return (
    <svg
      className="absolute inset-0 w-full h-full pointer-events-none"
      style={{ zIndex: 5 }}
    >
      <defs>
        {/* Gradient for rope animation */}
        <linearGradient id="ropeGradient" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stopColor="rgba(59, 130, 246, 0.3)" />
          <stop offset="50%" stopColor="rgba(59, 130, 246, 0.8)" />
          <stop offset="100%" stopColor="rgba(59, 130, 246, 0.3)" />
        </linearGradient>
        
        {/* Animated gradient */}
        <linearGradient id="animatedRope" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stopColor="rgba(59, 130, 246, 0.2)">
            <animate attributeName="stop-color" 
              values="rgba(59, 130, 246, 0.2);rgba(59, 130, 246, 0.8);rgba(59, 130, 246, 0.2)" 
              dur="3s" 
              repeatCount="indefinite" />
          </stop>
          <stop offset="50%" stopColor="rgba(59, 130, 246, 0.8)">
            <animate attributeName="stop-color" 
              values="rgba(59, 130, 246, 0.8);rgba(59, 130, 246, 0.2);rgba(59, 130, 246, 0.8)" 
              dur="3s" 
              repeatCount="indefinite" />
          </stop>
          <stop offset="100%" stopColor="rgba(59, 130, 246, 0.2)">
            <animate attributeName="stop-color" 
              values="rgba(59, 130, 246, 0.2);rgba(59, 130, 246, 0.8);rgba(59, 130, 246, 0.2)" 
              dur="3s" 
              repeatCount="indefinite" />
          </stop>
        </linearGradient>

        {/* Filter for glow effect */}
        <filter id="glow">
          <feGaussianBlur stdDeviation="3" result="coloredBlur"/>
          <feMerge> 
            <feMergeNode in="coloredBlur"/>
            <feMergeNode in="SourceGraphic"/>
          </feMerge>
        </filter>
      </defs>

      {edges.map((edge, index) => {
        const fromPos = getNodePosition(edge.from);
        const toPos = getNodePosition(edge.to);
        
        if (!fromPos || !toPos) return null;

        // Calculate control points for curved line
        const dx = toPos.x - fromPos.x;
        const dy = toPos.y - fromPos.y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        
        // Curve intensity based on distance
        const curvature = Math.min(distance * 0.3, 100);
        
        // Control point perpendicular to the line
        const midX = (fromPos.x + toPos.x) / 2;
        const midY = (fromPos.y + toPos.y) / 2;
        
        // Perpendicular vector
        const perpX = -dy / distance * curvature;
        const perpY = dx / distance * curvature;
        
        const controlX = midX + perpX;
        const controlY = midY + perpY;

        const pathData = `M ${fromPos.x} ${fromPos.y} Q ${controlX} ${controlY} ${toPos.x} ${toPos.y}`;

        return (
          <motion.g
            key={`${edge.from}-${edge.to}-${index}`}
            initial={{ opacity: 0, pathLength: 0 }}
            animate={{ opacity: 1, pathLength: 1 }}
            exit={{ opacity: 0, pathLength: 0 }}
            transition={{ duration: 0.5, delay: index * 0.1 }}
          >
            {/* Base path */}
            <motion.path
              d={pathData}
              stroke="rgba(59, 130, 246, 0.3)"
              strokeWidth="2"
              fill="none"
              strokeLinecap="round"
            />
            
            {/* Animated highlight */}
            <motion.path
              d={pathData}
              stroke="url(#animatedRope)"
              strokeWidth="3"
              fill="none"
              strokeLinecap="round"
              filter="url(#glow)"
              animate={{
                strokeDasharray: [0, distance * 2],
                strokeDashoffset: [0, -distance * 2]
              }}
              transition={{
                duration: 2,
                repeat: Infinity,
                ease: "linear"
              }}
            />
            
            {/* Relation label */}
            {distance > 100 && (
              <text
                x={controlX}
                y={controlY - 10}
                fill="rgba(255, 255, 255, 0.6)"
                fontSize="10"
                textAnchor="middle"
                className="pointer-events-none select-none"
              >
                {edge.relation}
              </text>
            )}
          </motion.g>
        );
      })}
    </svg>
  );
}
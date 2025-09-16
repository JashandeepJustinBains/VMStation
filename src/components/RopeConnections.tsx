'use client';

import { useMemo } from 'react';
import { motion } from 'framer-motion';
import { RepositoryEdge, CardPosition } from '@/types';

interface RopeConnectionsProps {
  edges: RepositoryEdge[];
  positions: Map<string, CardPosition>;
  selectedCard: string | null;
  anchoredCards: Set<string>;
}

export default function RopeConnections({
  edges,
  positions,
  selectedCard,
  anchoredCards
}: RopeConnectionsProps) {
  // Filter and prepare visible connections
  const visibleConnections = useMemo(() => {
    if (!selectedCard) return [];

    return edges.filter(edge => {
      // Show connections to/from selected card
      return edge.from === selectedCard || edge.to === selectedCard;
    }).map(edge => {
      const fromPos = positions.get(edge.from);
      const toPos = positions.get(edge.to);
      
      if (!fromPos || !toPos) return null;

      // Calculate control points for smooth curved rope
      const dx = toPos.x - fromPos.x;
      const dy = toPos.y - fromPos.y;
      const distance = Math.sqrt(dx * dx + dy * dy);
      
      // Create gentle curve
      const curvature = Math.min(distance * 0.3, 100);
      const midX = (fromPos.x + toPos.x) / 2;
      const midY = (fromPos.y + toPos.y) / 2;
      
      // Perpendicular offset for curve
      const perpX = -dy / distance * curvature;
      const perpY = dx / distance * curvature;
      
      const controlX = midX + perpX;
      const controlY = midY + perpY;

      return {
        ...edge,
        fromPos,
        toPos,
        controlX,
        controlY,
        distance,
        isFromSelected: edge.from === selectedCard,
        isToSelected: edge.to === selectedCard,
        isFromAnchored: anchoredCards.has(edge.from),
        isToAnchored: anchoredCards.has(edge.to)
      };
    }).filter(Boolean);
  }, [edges, positions, selectedCard, anchoredCards]);

  if (visibleConnections.length === 0) return null;

  return (
    <svg 
      className="absolute inset-0 w-full h-full pointer-events-none z-20"
      style={{ zIndex: 20 }}
    >
      <defs>
        {/* Rope flow gradient */}
        <linearGradient id="ropeGradient" x1="0%" y1="0%" x2="100%" y2="0%">
          <stop offset="0%" stopColor="rgba(6, 182, 212, 0.1)" />
          <stop offset="50%" stopColor="rgba(6, 182, 212, 0.8)" />
          <stop offset="100%" stopColor="rgba(6, 182, 212, 0.1)" />
          <animateTransform
            attributeName="gradientTransform"
            type="translate"
            values="-100;100;-100"
            dur="3s"
            repeatCount="indefinite"
          />
        </linearGradient>

        {/* Connection type patterns */}
        <pattern id="callsPattern" patternUnits="userSpaceOnUse" width="10" height="10">
          <circle cx="5" cy="5" r="1" fill="rgba(34, 197, 94, 0.6)" />
        </pattern>
        
        <pattern id="referencesPattern" patternUnits="userSpaceOnUse" width="8" height="8">
          <rect x="0" y="0" width="4" height="8" fill="rgba(59, 130, 246, 0.6)" />
        </pattern>
        
        <pattern id="mentionsPattern" patternUnits="userSpaceOnUse" width="6" height="6">
          <circle cx="3" cy="3" r="0.5" fill="rgba(156, 163, 175, 0.6)" />
        </pattern>
      </defs>

      {visibleConnections.map((connection, index) => {
        if (!connection) return null;

        // Choose stroke pattern based on relation type
        let strokeColor = '#06b6d4';
        let strokePattern = '';
        let strokeWidth = 2;

        switch (connection.relation) {
          case 'calls':
            strokeColor = '#22c55e';
            strokeWidth = 3;
            break;
          case 'references':
            strokeColor = '#3b82f6';
            strokeWidth = 2;
            break;
          case 'mentions':
            strokeColor = '#9ca3af';
            strokeWidth = 1;
            break;
        }

        // Enhanced visibility for anchored connections
        if (connection.isFromAnchored || connection.isToAnchored) {
          strokeWidth += 1;
        }

        // Create smooth curve path
        const pathData = `M ${connection.fromPos.x} ${connection.fromPos.y} Q ${connection.controlX} ${connection.controlY} ${connection.toPos.x} ${connection.toPos.y}`;

        return (
          <g key={`${connection.from}-${connection.to}-${index}`}>
            {/* Background rope */}
            <motion.path
              initial={{ pathLength: 0, opacity: 0 }}
              animate={{ pathLength: 1, opacity: 0.3 }}
              transition={{ duration: 0.5, delay: index * 0.1 }}
              d={pathData}
              stroke={strokeColor}
              strokeWidth={strokeWidth + 2}
              fill="none"
              strokeLinecap="round"
              opacity={0.2}
            />

            {/* Main rope */}
            <motion.path
              initial={{ pathLength: 0, opacity: 0 }}
              animate={{ pathLength: 1, opacity: 1 }}
              transition={{ duration: 0.5, delay: index * 0.1 }}
              d={pathData}
              stroke={strokeColor}
              strokeWidth={strokeWidth}
              fill="none"
              strokeLinecap="round"
              strokeDasharray="5,5"
              className="rope-connection"
            />

            {/* Flowing highlight */}
            <motion.path
              initial={{ pathLength: 0, opacity: 0 }}
              animate={{ pathLength: 1, opacity: 0.8 }}
              transition={{ duration: 0.5, delay: index * 0.1 }}
              d={pathData}
              stroke="url(#ropeGradient)"
              strokeWidth={strokeWidth - 1}
              fill="none"
              strokeLinecap="round"
            />

            {/* Connection type indicator */}
            <motion.circle
              initial={{ scale: 0, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              transition={{ duration: 0.3, delay: 0.5 + index * 0.1 }}
              cx={connection.controlX}
              cy={connection.controlY}
              r="4"
              fill={strokeColor}
              stroke="white"
              strokeWidth="1"
            />

            {/* Relation type text */}
            <motion.text
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ duration: 0.3, delay: 0.7 + index * 0.1 }}
              x={connection.controlX}
              y={connection.controlY - 10}
              textAnchor="middle"
              className="text-xs fill-gray-600 font-medium"
              style={{ fontSize: '10px' }}
            >
              {connection.relation}
            </motion.text>
          </g>
        );
      })}
    </svg>
  );
}
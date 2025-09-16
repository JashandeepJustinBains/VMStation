'use client';

import { useState, useEffect, useRef, useMemo } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import FloatingCard from './FloatingCard';
import RopesLayer from './RopesLayer';
import SearchFilter from './SearchFilter';
import DetailDrawer from './DetailDrawer';

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

interface FloatingLakeProps {
  nodes: Node[];
  edges: Edge[];
}

interface CardPosition {
  x: number;
  y: number;
  vx: number;
  vy: number;
  targetX?: number;
  targetY?: number;
  scale: number;
  isAnchored?: boolean;
}

export default function FloatingLake({ nodes, edges }: FloatingLakeProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const animationRef = useRef<number>();
  
  const [positions, setPositions] = useState<Map<string, CardPosition>>(new Map());
  const [selectedNode, setSelectedNode] = useState<string | null>(null);
  const [anchoredNode, setAnchoredNode] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedType, setSelectedType] = useState<string>('all');
  const [hoveredNode, setHoveredNode] = useState<string | null>(null);
  const [reducedMotion, setReducedMotion] = useState(false);

  // Filter nodes based on search and type
  const filteredNodes = useMemo(() => {
    return nodes.filter(node => {
      const matchesSearch = searchTerm === '' || 
        node.title.toLowerCase().includes(searchTerm.toLowerCase()) ||
        node.tags.some(tag => tag.toLowerCase().includes(searchTerm.toLowerCase())) ||
        node.summary.toLowerCase().includes(searchTerm.toLowerCase());
      
      const matchesType = selectedType === 'all' || node.type === selectedType;
      
      return matchesSearch && matchesType;
    });
  }, [nodes, searchTerm, selectedType]);

  // Get connections for a node
  const getConnections = useMemo(() => {
    const connectionMap = new Map<string, string[]>();
    
    edges.forEach(edge => {
      if (!connectionMap.has(edge.from)) {
        connectionMap.set(edge.from, []);
      }
      if (!connectionMap.has(edge.to)) {
        connectionMap.set(edge.to, []);
      }
      
      connectionMap.get(edge.from)?.push(edge.to);
      connectionMap.get(edge.to)?.push(edge.from);
    });
    
    return connectionMap;
  }, [edges]);

  // Initialize positions
  useEffect(() => {
    if (!containerRef.current) return;
    
    const container = containerRef.current;
    const rect = container.getBoundingClientRect();
    const newPositions = new Map<string, CardPosition>();
    
    filteredNodes.forEach((node, index) => {
      // Distribute cards in a rough grid with some randomness
      const cols = Math.ceil(Math.sqrt(filteredNodes.length));
      const col = index % cols;
      const row = Math.floor(index / cols);
      
      const cellWidth = rect.width / cols;
      const cellHeight = rect.height / Math.ceil(filteredNodes.length / cols);
      
      const baseX = col * cellWidth + cellWidth / 2;
      const baseY = row * cellHeight + cellHeight / 2;
      
      // Add some randomness
      const randomX = (Math.random() - 0.5) * cellWidth * 0.3;
      const randomY = (Math.random() - 0.5) * cellHeight * 0.3;
      
      newPositions.set(node.id, {
        x: Math.max(100, Math.min(rect.width - 100, baseX + randomX)),
        y: Math.max(100, Math.min(rect.height - 100, baseY + randomY)),
        vx: (Math.random() - 0.5) * 0.5,
        vy: (Math.random() - 0.5) * 0.5,
        scale: 1
      });
    });
    
    setPositions(newPositions);
  }, [filteredNodes]);

  // Check for reduced motion preference
  useEffect(() => {
    const mediaQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
    setReducedMotion(mediaQuery.matches);
    
    const handleChange = (e: MediaQueryListEvent) => {
      setReducedMotion(e.matches);
    };
    
    mediaQuery.addEventListener('change', handleChange);
    return () => mediaQuery.removeEventListener('change', handleChange);
  }, []);

  // Physics animation loop
  useEffect(() => {
    if (reducedMotion) return;
    
    const animate = () => {
      setPositions(prev => {
        const newPositions = new Map(prev);
        const container = containerRef.current;
        if (!container) return prev;
        
        const rect = container.getBoundingClientRect();
        const damping = 0.98;
        const attraction = 0.02;
        const repulsion = 30;
        
        newPositions.forEach((pos, nodeId) => {
          if (pos.isAnchored) return;
          
          let fx = 0;
          let fy = 0;
          
          // Attraction to target if selected
          if (selectedNode && nodeId !== selectedNode) {
            const connections = getConnections.get(selectedNode) || [];
            if (connections.includes(nodeId)) {
              const selectedPos = newPositions.get(selectedNode);
              if (selectedPos) {
                const dx = selectedPos.x - pos.x;
                const dy = selectedPos.y - pos.y;
                const dist = Math.sqrt(dx * dx + dy * dy);
                
                if (dist > 150) {
                  fx += (dx / dist) * attraction * 5;
                  fy += (dy / dist) * attraction * 5;
                }
              }
            } else if (nodeId !== selectedNode) {
              // Push unrelated nodes away gently
              const selectedPos = newPositions.get(selectedNode);
              if (selectedPos) {
                const dx = pos.x - selectedPos.x;
                const dy = pos.y - selectedPos.y;
                const dist = Math.sqrt(dx * dx + dy * dy);
                
                if (dist < 300) {
                  fx += (dx / dist) * attraction * 0.5;
                  fy += (dy / dist) * attraction * 0.5;
                }
              }
            }
          }
          
          // Repulsion between cards
          newPositions.forEach((otherPos, otherId) => {
            if (nodeId === otherId) return;
            
            const dx = pos.x - otherPos.x;
            const dy = pos.y - otherPos.y;
            const dist = Math.sqrt(dx * dx + dy * dy);
            
            if (dist < repulsion && dist > 0) {
              const force = (repulsion - dist) / repulsion;
              fx += (dx / dist) * force * 0.5;
              fy += (dy / dist) * force * 0.5;
            }
          });
          
          // Boundary forces
          const margin = 80;
          if (pos.x < margin) fx += (margin - pos.x) * 0.01;
          if (pos.x > rect.width - margin) fx -= (pos.x - (rect.width - margin)) * 0.01;
          if (pos.y < margin) fy += (margin - pos.y) * 0.01;
          if (pos.y > rect.height - margin) fy -= (pos.y - (rect.height - margin)) * 0.01;
          
          // Update velocity and position
          const newVx = (pos.vx + fx) * damping;
          const newVy = (pos.vy + fy) * damping;
          
          newPositions.set(nodeId, {
            ...pos,
            x: Math.max(40, Math.min(rect.width - 40, pos.x + newVx)),
            y: Math.max(40, Math.min(rect.height - 40, pos.y + newVy)),
            vx: newVx,
            vy: newVy
          });
        });
        
        return newPositions;
      });
      
      animationRef.current = requestAnimationFrame(animate);
    };
    
    animationRef.current = requestAnimationFrame(animate);
    
    return () => {
      if (animationRef.current) {
        cancelAnimationFrame(animationRef.current);
      }
    };
  }, [selectedNode, getConnections, reducedMotion]);

  const handleCardClick = (nodeId: string) => {
    if (selectedNode === nodeId) {
      // Already selected - deselect
      setSelectedNode(null);
    } else if (selectedNode && getConnections.get(selectedNode)?.includes(nodeId)) {
      // Clicking a connected node - anchor it
      setAnchoredNode(nodeId);
      setPositions(prev => {
        const newPositions = new Map(prev);
        const pos = newPositions.get(nodeId);
        if (pos) {
          newPositions.set(nodeId, {
            ...pos,
            isAnchored: true,
            x: window.innerWidth - 450, // Position for detail drawer
            y: 200
          });
        }
        return newPositions;
      });
    } else {
      // Select new node
      setSelectedNode(nodeId);
      setAnchoredNode(null);
    }
  };

  const handleCloseAnchor = () => {
    if (anchoredNode) {
      setPositions(prev => {
        const newPositions = new Map(prev);
        const pos = newPositions.get(anchoredNode);
        if (pos) {
          newPositions.set(anchoredNode, {
            ...pos,
            isAnchored: false
          });
        }
        return newPositions;
      });
      setAnchoredNode(null);
    }
  };

  const getVisibleEdges = () => {
    if (!selectedNode) return [];
    
    const connections = getConnections.get(selectedNode) || [];
    return edges.filter(edge => 
      (edge.from === selectedNode && connections.includes(edge.to)) ||
      (edge.to === selectedNode && connections.includes(edge.from))
    );
  };

  const anchoredNodeData = anchoredNode ? nodes.find(n => n.id === anchoredNode) : null;

  return (
    <div className="relative w-full h-screen overflow-hidden">
      {/* Search and Filter */}
      <div className="absolute top-20 left-4 z-40">
        <SearchFilter
          searchTerm={searchTerm}
          onSearchChange={setSearchTerm}
          selectedType={selectedType}
          onTypeChange={setSelectedType}
          nodeTypes={[...new Set(nodes.map(n => n.type))]}
        />
      </div>

      {/* Main Canvas */}
      <div 
        ref={containerRef}
        className="w-full h-full relative"
        style={{ cursor: selectedNode ? 'pointer' : 'default' }}
      >
        {/* Ropes Layer */}
        <RopesLayer
          edges={getVisibleEdges()}
          positions={positions}
          nodes={nodes}
        />

        {/* Floating Cards */}
        <AnimatePresence>
          {filteredNodes.map(node => {
            const position = positions.get(node.id);
            if (!position) return null;

            const isSelected = selectedNode === node.id;
            const isConnected = selectedNode ? 
              (getConnections.get(selectedNode)?.includes(node.id) ?? false) : false;
            const isHovered = hoveredNode === node.id;

            return (
              <FloatingCard
                key={node.id}
                node={node}
                position={position}
                isSelected={isSelected}
                isConnected={isConnected}
                isHovered={isHovered}
                onClick={() => handleCardClick(node.id)}
                onHover={() => setHoveredNode(node.id)}
                onLeave={() => setHoveredNode(null)}
              />
            );
          })}
        </AnimatePresence>
      </div>

      {/* Detail Drawer */}
      <AnimatePresence>
        {anchoredNodeData && (
          <DetailDrawer
            node={anchoredNodeData}
            connections={getConnections.get(anchoredNodeData.id) || []}
            connectedNodes={nodes.filter(n => 
              getConnections.get(anchoredNodeData.id)?.includes(n.id)
            )}
            onClose={handleCloseAnchor}
          />
        )}
      </AnimatePresence>

      {/* Selection Info */}
      {selectedNode && (
        <div className="fixed bottom-4 right-4 glass-card p-4 max-w-sm z-40">
          <h3 className="font-semibold mb-2">Selected Node</h3>
          <p className="text-sm text-gray-300">
            {nodes.find(n => n.id === selectedNode)?.title}
          </p>
          <p className="text-xs text-gray-400 mt-1">
            {getConnections.get(selectedNode)?.length || 0} connections visible
          </p>
        </div>
      )}
    </div>
  );
}
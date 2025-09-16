'use client';

import { useState, useRef, useEffect, useMemo } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Search, Filter, X } from 'lucide-react';
import { RepositoryData, RepositoryNode, CardPosition } from '@/types';
import RepositoryCard from './RepositoryCard';
import RopeConnections from './RopeConnections';
import DetailPanel from './DetailPanel';
import { getFileIcon, getFileTypeColor } from '@/lib/data';

interface RepositoryLakeProps {
  data: RepositoryData;
}

export default function RepositoryLake({ data }: RepositoryLakeProps) {
  const canvasRef = useRef<HTMLDivElement>(null);
  const [dimensions, setDimensions] = useState({ width: 0, height: 0 });
  const [positions, setPositions] = useState<Map<string, CardPosition>>(new Map());
  const [selectedCard, setSelectedCard] = useState<string | null>(null);
  const [anchoredCards, setAnchoredCards] = useState<Set<string>>(new Set());
  const [searchTerm, setSearchTerm] = useState('');
  const [typeFilter, setTypeFilter] = useState<string>('all');
  const [showFilters, setShowFilters] = useState(false);

  // Initialize card positions
  useEffect(() => {
    if (!canvasRef.current) return;

    const updateDimensions = () => {
      const rect = canvasRef.current!.getBoundingClientRect();
      setDimensions({ width: rect.width, height: rect.height });
    };

    updateDimensions();
    window.addEventListener('resize', updateDimensions);
    return () => window.removeEventListener('resize', updateDimensions);
  }, []);

  // Initialize positions when dimensions change
  useEffect(() => {
    if (dimensions.width === 0 || positions.size > 0) return;

    const newPositions = new Map<string, CardPosition>();
    const padding = 100;
    const usableWidth = dimensions.width - 2 * padding;
    const usableHeight = dimensions.height - 2 * padding;

    data.nodes.forEach((node, index) => {
      // Use deterministic positioning based on file hash for consistency
      const hash = parseInt(node.id, 16);
      const x = padding + (hash % usableWidth);
      const y = padding + ((hash * 7) % usableHeight);

      newPositions.set(node.id, {
        id: node.id,
        x,
        y,
        vx: (Math.random() - 0.5) * 0.1,
        vy: (Math.random() - 0.5) * 0.1,
      });
    });

    setPositions(newPositions);
  }, [dimensions, data.nodes]);

  // Physics simulation for floating effect
  useEffect(() => {
    if (positions.size === 0) return;

    const animationFrame = requestAnimationFrame(function animate() {
      setPositions(prev => {
        const newPositions = new Map(prev);
        
        for (const [id, pos] of Array.from(newPositions)) {
          if (pos.anchored) continue;

          // Apply gentle floating motion
          const time = Date.now() * 0.001;
          const floatX = Math.sin(time + parseInt(id, 16) * 0.1) * 0.5;
          const floatY = Math.cos(time * 0.7 + parseInt(id, 16) * 0.05) * 0.3;

          // Boundary constraints
          const newX = Math.max(50, Math.min(dimensions.width - 50, pos.x + floatX));
          const newY = Math.max(50, Math.min(dimensions.height - 50, pos.y + floatY));

          newPositions.set(id, {
            ...pos,
            x: newX,
            y: newY,
          });
        }

        return newPositions;
      });

      requestAnimationFrame(animate);
    });

    return () => cancelAnimationFrame(animationFrame);
  }, [dimensions]); // Remove positions.size dependency as it causes infinite re-renders

  // Filtered nodes based on search and type filter
  const filteredNodes = useMemo(() => {
    return data.nodes.filter(node => {
      const matchesSearch = searchTerm === '' || 
        node.title.toLowerCase().includes(searchTerm.toLowerCase()) ||
        node.summary.toLowerCase().includes(searchTerm.toLowerCase()) ||
        node.tags.some(tag => tag.toLowerCase().includes(searchTerm.toLowerCase()));
      
      const matchesType = typeFilter === 'all' || node.type === typeFilter;
      
      return matchesSearch && matchesType;
    });
  }, [data.nodes, searchTerm, typeFilter]);

  // Handle card click - pull related cards
  const handleCardClick = (nodeId: string) => {
    if (anchoredCards.has(nodeId)) {
      setSelectedCard(nodeId);
      return;
    }

    setSelectedCard(nodeId);
    
    // Find related nodes
    const relatedEdges = data.edges.filter(edge => 
      edge.from === nodeId || edge.to === nodeId
    );
    const relatedNodeIds = new Set([
      ...relatedEdges.map(edge => edge.from),
      ...relatedEdges.map(edge => edge.to)
    ]);

    // Pull related cards toward the clicked card
    setPositions(prev => {
      const newPositions = new Map(prev);
      const centerPos = newPositions.get(nodeId);
      if (!centerPos) return prev;

      for (const relatedId of relatedNodeIds) {
        if (relatedId === nodeId) continue;
        
        const relatedPos = newPositions.get(relatedId);
        if (!relatedPos || relatedPos.anchored) continue;

        // Calculate attraction force
        const dx = centerPos.x - relatedPos.x;
        const dy = centerPos.y - relatedPos.y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        const targetDistance = 150;

        if (distance > targetDistance) {
          const force = 0.3;
          const fx = (dx / distance) * force * (distance - targetDistance);
          const fy = (dy / distance) * force * (distance - targetDistance);

          newPositions.set(relatedId, {
            ...relatedPos,
            x: relatedPos.x + fx,
            y: relatedPos.y + fy,
          });
        }
      }

      return newPositions;
    });
  };

  // Handle related card click - anchor it
  const handleRelatedCardClick = (nodeId: string) => {
    if (selectedCard && data.edges.some(edge => 
      (edge.from === selectedCard && edge.to === nodeId) ||
      (edge.to === selectedCard && edge.from === nodeId)
    )) {
      setAnchoredCards(prev => new Set([...prev, nodeId]));
      setSelectedCard(nodeId);
    }
  };

  // Close detail panel
  const closeDetailPanel = () => {
    setSelectedCard(null);
  };

  // Remove anchor
  const removeAnchor = (nodeId: string) => {
    setAnchoredCards(prev => {
      const newSet = new Set(prev);
      newSet.delete(nodeId);
      return newSet;
    });
  };

  const fileTypes = [...new Set(data.nodes.map(node => node.type))];

  return (
    <div className="relative w-full h-screen overflow-hidden">
      {/* Search and Filter Controls */}
      <div className="absolute top-4 left-1/2 transform -translate-x-1/2 z-30">
        <div className="flex items-center space-x-4">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-gray-400" />
            <input
              type="text"
              placeholder="Search files, content, or tags..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-10 pr-4 py-2 w-80 glass-effect rounded-lg border border-white/30 focus:border-lake-500 focus:outline-none"
            />
          </div>
          <button
            onClick={() => setShowFilters(!showFilters)}
            className="flex items-center space-x-2 px-4 py-2 glass-effect rounded-lg border border-white/30 hover:border-white/50 transition-colors"
          >
            <Filter className="h-4 w-4" />
            <span>Filters</span>
          </button>
        </div>

        {/* Filter Panel */}
        <AnimatePresence>
          {showFilters && (
            <motion.div
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              className="absolute top-full mt-2 left-0 glass-effect rounded-lg p-4 border border-white/30 min-w-80"
            >
              <div className="flex items-center justify-between mb-3">
                <span className="font-medium text-gray-700">File Types</span>
                <button
                  onClick={() => setShowFilters(false)}
                  className="text-gray-400 hover:text-gray-600"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>
              <div className="grid grid-cols-3 gap-2">
                <button
                  onClick={() => setTypeFilter('all')}
                  className={`px-3 py-1 text-sm rounded transition-colors ${
                    typeFilter === 'all' ? 'bg-lake-600 text-white' : 'bg-white/50 hover:bg-white/70'
                  }`}
                >
                  All ({data.nodes.length})
                </button>
                {fileTypes.map(type => (
                  <button
                    key={type}
                    onClick={() => setTypeFilter(type)}
                    className={`px-3 py-1 text-sm rounded transition-colors flex items-center space-x-1 ${
                      typeFilter === type ? 'bg-lake-600 text-white' : 'bg-white/50 hover:bg-white/70'
                    }`}
                  >
                    <span>{getFileIcon(type)}</span>
                    <span>{type} ({data.metadata.stats.byType[type] || 0})</span>
                  </button>
                ))}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Canvas */}
      <div ref={canvasRef} className="w-full h-full relative">
        {/* Rope Connections */}
        <RopeConnections
          edges={data.edges}
          positions={positions}
          selectedCard={selectedCard}
          anchoredCards={anchoredCards}
        />

        {/* Repository Cards */}
        <AnimatePresence>
          {filteredNodes.map(node => {
            const position = positions.get(node.id);
            if (!position) return null;

            const isSelected = selectedCard === node.id;
            const isAnchored = anchoredCards.has(node.id);
            const isRelated = selectedCard && data.edges.some(edge => 
              (edge.from === selectedCard && edge.to === node.id) ||
              (edge.to === selectedCard && edge.from === node.id)
            );

            return (
              <RepositoryCard
                key={node.id}
                node={node}
                position={position}
                isSelected={isSelected}
                isAnchored={isAnchored}
                isRelated={!!isRelated}
                onClick={() => isRelated ? handleRelatedCardClick(node.id) : handleCardClick(node.id)}
                onRemoveAnchor={() => removeAnchor(node.id)}
              />
            );
          })}
        </AnimatePresence>
      </div>

      {/* Detail Panel */}
      <AnimatePresence>
        {selectedCard && (
          <DetailPanel
            node={data.nodes.find(n => n.id === selectedCard)!}
            edges={data.edges.filter(edge => 
              edge.from === selectedCard || edge.to === selectedCard
            )}
            allNodes={data.nodes}
            onClose={closeDetailPanel}
          />
        )}
      </AnimatePresence>
    </div>
  );
}
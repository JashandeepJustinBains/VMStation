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

interface CardPosition {
  x: number;
  y: number;
  scale: number;
  isAnchored?: boolean;
}

interface FloatingCardProps {
  node: Node;
  position: CardPosition;
  isSelected: boolean;
  isConnected: boolean;
  isHovered: boolean;
  onClick: () => void;
  onHover: () => void;
  onLeave: () => void;
}

const getTypeIcon = (type: string) => {
  switch (type) {
    case 'script':
      return '⚡';
    case 'doc':
      return '📄';
    case 'todo':
      return '✓';
    case 'manifest':
      return '⚙️';
    case 'config':
      return '🔧';
    default:
      return '📁';
  }
};

const getTypeColor = (type: string) => {
  switch (type) {
    case 'script':
      return 'from-yellow-500 to-orange-500';
    case 'doc':
      return 'from-blue-500 to-cyan-500';
    case 'todo':
      return 'from-green-500 to-emerald-500';
    case 'manifest':
      return 'from-purple-500 to-pink-500';
    case 'config':
      return 'from-gray-500 to-slate-500';
    default:
      return 'from-gray-400 to-gray-600';
  }
};

export default function FloatingCard({
  node,
  position,
  isSelected,
  isConnected,
  isHovered,
  onClick,
  onHover,
  onLeave
}: FloatingCardProps) {
  const baseScale = isSelected ? 1.2 : isConnected ? 1.1 : 1;
  const hoverScale = isHovered ? 1.05 : 1;
  const finalScale = baseScale * hoverScale * position.scale;

  return (
    <motion.div
      className="absolute cursor-pointer select-none"
      style={{
        left: position.x - 60,
        top: position.y - 40,
        zIndex: isSelected ? 30 : isConnected ? 20 : 10
      }}
      animate={{
        scale: finalScale,
        rotate: isSelected ? [0, 2, -2, 0] : 0
      }}
      transition={{
        scale: { type: "spring", stiffness: 300, damping: 30 },
        rotate: { duration: 2, repeat: isSelected ? Infinity : 0 }
      }}
      onClick={onClick}
      onMouseEnter={onHover}
      onMouseLeave={onLeave}
      role="button"
      tabIndex={0}
      aria-label={`${node.type} file: ${node.title}`}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          onClick();
        }
      }}
    >
      <div 
        className={`
          relative w-32 h-20 rounded-lg overflow-hidden
          backdrop-blur-sm border transition-all duration-300
          ${isSelected 
            ? 'border-cyan-400 shadow-lg shadow-cyan-400/50' 
            : isConnected 
              ? 'border-blue-400 shadow-md shadow-blue-400/30'
              : 'border-white/20 shadow-sm'
          }
        `}
      >
        {/* Background gradient */}
        <div 
          className={`
            absolute inset-0 bg-gradient-to-br opacity-80
            ${getTypeColor(node.type)}
          `}
        />
        
        {/* Glass overlay */}
        <div className="absolute inset-0 bg-white/10 backdrop-blur-sm" />
        
        {/* Content */}
        <div className="relative h-full p-3 flex flex-col justify-between">
          <div className="flex items-start justify-between">
            <span className="text-2xl">{getTypeIcon(node.type)}</span>
            {node.tags.includes('kubernetes') && (
              <span className="text-xs text-blue-200">K8s</span>
            )}
          </div>
          
          <div>
            <h3 className="text-xs font-semibold text-white leading-tight truncate">
              {node.title}
            </h3>
            {isHovered && (
              <motion.p 
                className="text-xs text-gray-200 mt-1 leading-tight line-clamp-2"
                initial={{ opacity: 0, height: 0 }}
                animate={{ opacity: 1, height: 'auto' }}
                exit={{ opacity: 0, height: 0 }}
              >
                {node.summary.substring(0, 60)}...
              </motion.p>
            )}
          </div>
        </div>
        
        {/* Ripple effect on selection */}
        {isSelected && (
          <motion.div
            className="absolute inset-0 border-2 border-cyan-400 rounded-lg"
            animate={{
              scale: [1, 1.1, 1],
              opacity: [0.8, 0, 0.8]
            }}
            transition={{
              duration: 2,
              repeat: Infinity,
              ease: "easeInOut"
            }}
          />
        )}
      </div>
    </motion.div>
  );
}
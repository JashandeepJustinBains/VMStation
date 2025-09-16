'use client';

import { motion } from 'framer-motion';
import { Anchor, X } from 'lucide-react';
import { RepositoryNode, CardPosition } from '@/types';
import { getFileIcon, getFileTypeColor, formatFileSize } from '@/lib/data';

interface RepositoryCardProps {
  node: RepositoryNode;
  position: CardPosition;
  isSelected: boolean;
  isAnchored: boolean;
  isRelated: boolean;
  onClick: () => void;
  onRemoveAnchor: () => void;
}

export default function RepositoryCard({
  node,
  position,
  isSelected,
  isAnchored,
  isRelated,
  onClick,
  onRemoveAnchor
}: RepositoryCardProps) {
  const icon = getFileIcon(node.type);
  const colorClass = getFileTypeColor(node.type);

  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.8 }}
      animate={{ 
        opacity: 1, 
        scale: isSelected ? 1.1 : isRelated ? 1.05 : 1,
        x: position.x,
        y: position.y,
        zIndex: isSelected ? 50 : isAnchored ? 40 : isRelated ? 30 : 10
      }}
      exit={{ opacity: 0, scale: 0.8 }}
      whileHover={{ scale: isSelected ? 1.1 : 1.05 }}
      className={`absolute cursor-pointer select-none ${
        isAnchored ? 'fixed' : ''
      }`}
      style={{
        transform: `translate(-50%, -50%)`,
      }}
      onClick={onClick}
      layout
    >
      {/* Ripple effect on selection */}
      {isSelected && (
        <motion.div
          initial={{ scale: 0, opacity: 0.8 }}
          animate={{ scale: 3, opacity: 0 }}
          transition={{ duration: 0.6 }}
          className="absolute inset-0 bg-lake-400 rounded-lg"
        />
      )}

      {/* Card */}
      <motion.div
        className={`
          relative rounded-lg p-3 border-2 shadow-lg backdrop-blur-sm
          ${colorClass}
          ${isSelected ? 'ring-2 ring-lake-500 ring-opacity-50' : ''}
          ${isRelated ? 'border-lake-400 bg-lake-50' : ''}
          ${isAnchored ? 'shadow-xl border-indigo-500' : ''}
          card-float
        `}
        whileHover={{ 
          scale: 1.02,
          filter: 'brightness(1.1)'
        }}
      >
        {/* Anchor indicator */}
        {isAnchored && (
          <motion.button
            initial={{ scale: 0 }}
            animate={{ scale: 1 }}
            className="absolute -top-2 -right-2 w-6 h-6 bg-indigo-600 text-white rounded-full flex items-center justify-center text-xs hover:bg-indigo-700 transition-colors"
            onClick={(e) => {
              e.stopPropagation();
              onRemoveAnchor();
            }}
          >
            <X className="h-3 w-3" />
          </motion.button>
        )}

        {/* File icon and type */}
        <div className="flex items-center space-x-2 mb-2">
          <span className="text-lg">{icon}</span>
          <span className="text-xs font-medium text-gray-600 uppercase tracking-wide">
            {node.type}
          </span>
        </div>

        {/* Title */}
        <div className="font-medium text-gray-900 text-sm mb-1 line-clamp-2">
          {node.title}
        </div>

        {/* Summary (on hover or when selected) */}
        <motion.div
          initial={{ height: 0, opacity: 0 }}
          animate={{ 
            height: isSelected || isRelated ? 'auto' : 0, 
            opacity: isSelected || isRelated ? 1 : 0 
          }}
          className="overflow-hidden"
        >
          <div className="text-xs text-gray-600 mb-2 line-clamp-3">
            {node.summary}
          </div>
        </motion.div>

        {/* Metadata */}
        <div className="flex items-center justify-between text-xs text-gray-500">
          <span>{formatFileSize(node.sizeBytes)}</span>
          <span>{node.lines} lines</span>
        </div>

        {/* Tags */}
        {(isSelected || isRelated) && node.tags.length > 0 && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="flex flex-wrap gap-1 mt-2"
          >
            {node.tags.slice(0, 3).map(tag => (
              <span
                key={tag}
                className="inline-block px-2 py-1 text-xs bg-white/60 text-gray-700 rounded-full"
              >
                {tag}
              </span>
            ))}
            {node.tags.length > 3 && (
              <span className="inline-block px-2 py-1 text-xs bg-gray-100 text-gray-500 rounded-full">
                +{node.tags.length - 3}
              </span>
            )}
          </motion.div>
        )}

        {/* Selection indicator */}
        {isSelected && (
          <motion.div
            initial={{ scale: 0 }}
            animate={{ scale: 1 }}
            className="absolute -bottom-1 left-1/2 transform -translate-x-1/2 w-2 h-2 bg-lake-500 rounded-full"
          />
        )}
      </motion.div>
    </motion.div>
  );
}
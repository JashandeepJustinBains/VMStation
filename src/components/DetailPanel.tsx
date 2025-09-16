'use client';

import { useState } from 'react';
import { motion } from 'framer-motion';
import { X, FileText, Eye, Copy, ExternalLink } from 'lucide-react';
import { RepositoryNode, RepositoryEdge } from '@/types';
import { getFileIcon, formatFileSize } from '@/lib/data';

interface DetailPanelProps {
  node: RepositoryNode;
  edges: RepositoryEdge[];
  allNodes: RepositoryNode[];
  onClose: () => void;
}

export default function DetailPanel({ node, edges, allNodes, onClose }: DetailPanelProps) {
  const [viewMode, setViewMode] = useState<'summary' | 'raw'>('summary');
  const [fileContent, setFileContent] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  // Get related nodes
  const relatedNodes = edges.map(edge => {
    const relatedId = edge.from === node.id ? edge.to : edge.from;
    const relatedNode = allNodes.find(n => n.id === relatedId);
    return relatedNode ? { node: relatedNode, relation: edge.relation, context: edge.context } : null;
  }).filter((related): related is NonNullable<typeof related> => related !== null);

  // Load file content (simulated - in real implementation would fetch from API)
  const loadFileContent = async () => {
    if (fileContent) return;
    
    setLoading(true);
    try {
      // Simulate API call - in real app would fetch actual file content
      await new Promise(resolve => setTimeout(resolve, 500));
      setFileContent(`# File content for ${node.path}\n\n${node.summary}\n\n# This is a simulated view\n# In a real implementation, this would show the actual file content\n# with proper syntax highlighting using Shiki\n\nFile Type: ${node.type}\nSize: ${formatFileSize(node.sizeBytes)}\nLines: ${node.lines}\n\nTags: ${node.tags.join(', ')}\n\nLast Modified: ${new Date(node.lastModified).toLocaleDateString()}`);
    } catch (error) {
      console.error('Failed to load file content:', error);
    } finally {
      setLoading(false);
    }
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  return (
    <motion.div
      initial={{ x: '100%' }}
      animate={{ x: 0 }}
      exit={{ x: '100%' }}
      className="fixed right-0 top-0 h-full w-1/2 max-w-2xl bg-white shadow-2xl z-50 overflow-hidden"
    >
      {/* Header */}
      <div className="bg-gradient-to-r from-lake-600 to-lake-700 text-white p-4">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center space-x-3">
            <span className="text-2xl">{getFileIcon(node.type)}</span>
            <div>
              <h2 className="text-lg font-semibold">{node.title}</h2>
              <p className="text-lake-100 text-sm">{node.path}</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 hover:bg-white/10 rounded-lg transition-colors"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Metadata */}
        <div className="flex items-center space-x-4 text-sm text-lake-100">
          <span>{node.type.toUpperCase()}</span>
          <span>•</span>
          <span>{formatFileSize(node.sizeBytes)}</span>
          <span>•</span>
          <span>{node.lines} lines</span>
          <span>•</span>
          <span>{new Date(node.lastModified).toLocaleDateString()}</span>
        </div>
      </div>

      {/* View Mode Toggle */}
      <div className="bg-gray-50 border-b border-gray-200 p-2">
        <div className="flex items-center space-x-1">
          <button
            onClick={() => setViewMode('summary')}
            className={`flex items-center space-x-2 px-3 py-2 rounded-lg text-sm transition-colors ${
              viewMode === 'summary' ? 'bg-lake-600 text-white' : 'hover:bg-gray-100'
            }`}
          >
            <FileText className="h-4 w-4" />
            <span>Summary</span>
          </button>
          <button
            onClick={() => {
              setViewMode('raw');
              loadFileContent();
            }}
            className={`flex items-center space-x-2 px-3 py-2 rounded-lg text-sm transition-colors ${
              viewMode === 'raw' ? 'bg-lake-600 text-white' : 'hover:bg-gray-100'
            }`}
          >
            <Eye className="h-4 w-4" />
            <span>Raw Content</span>
          </button>
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4">
        {viewMode === 'summary' ? (
          <div className="space-y-6">
            {/* Summary */}
            <div>
              <h3 className="font-semibold text-gray-900 mb-2">Summary</h3>
              <p className="text-gray-700 leading-relaxed">{node.summary}</p>
            </div>

            {/* Tags */}
            {node.tags.length > 0 && (
              <div>
                <h3 className="font-semibold text-gray-900 mb-2">Tags</h3>
                <div className="flex flex-wrap gap-2">
                  {node.tags.map(tag => (
                    <span
                      key={tag}
                      className="inline-block px-3 py-1 bg-lake-100 text-lake-800 rounded-full text-sm"
                    >
                      {tag}
                    </span>
                  ))}
                </div>
              </div>
            )}

            {/* Related Files */}
            {relatedNodes.length > 0 && (
              <div>
                <h3 className="font-semibold text-gray-900 mb-3">Related Files ({relatedNodes.length})</h3>
                <div className="space-y-3">
                  {relatedNodes.map((related, index) => (
                    <div key={index} className="border border-gray-200 rounded-lg p-3 hover:bg-gray-50 transition-colors">
                      <div className="flex items-start space-x-3">
                        <span className="text-lg">{getFileIcon(related.node.type)}</span>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center space-x-2 mb-1">
                            <span className="font-medium text-gray-900">{related.node.title}</span>
                            <span className={`text-xs px-2 py-1 rounded-full ${
                              related.relation === 'calls' ? 'bg-green-100 text-green-800' :
                              related.relation === 'references' ? 'bg-blue-100 text-blue-800' :
                              'bg-gray-100 text-gray-800'
                            }`}>
                              {related.relation}
                            </span>
                          </div>
                          <p className="text-sm text-gray-600 mb-2">{related.node.path}</p>
                          <p className="text-xs text-gray-500 italic">&ldquo;{related.context}&rdquo;</p>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        ) : (
          <div>
            {/* Raw Content Header */}
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-semibold text-gray-900">Raw Content</h3>
              <div className="flex items-center space-x-2">
                <button
                  onClick={() => copyToClipboard(fileContent || '')}
                  className="flex items-center space-x-1 px-3 py-1 text-sm text-gray-600 hover:text-gray-900 transition-colors"
                >
                  <Copy className="h-4 w-4" />
                  <span>Copy</span>
                </button>
                <button className="flex items-center space-x-1 px-3 py-1 text-sm text-gray-600 hover:text-gray-900 transition-colors">
                  <ExternalLink className="h-4 w-4" />
                  <span>Open</span>
                </button>
              </div>
            </div>

            {/* File Content */}
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <motion.div
                  animate={{ rotate: 360 }}
                  transition={{ duration: 2, repeat: Infinity, ease: "linear" }}
                  className="w-6 h-6 border-2 border-lake-600 border-t-transparent rounded-full"
                />
                <span className="ml-3 text-gray-600">Loading content...</span>
              </div>
            ) : (
              <div className="bg-gray-900 rounded-lg p-4 overflow-x-auto">
                <pre className="text-sm text-gray-100 font-mono whitespace-pre-wrap">
                  {fileContent || 'No content available'}
                </pre>
              </div>
            )}
          </div>
        )}
      </div>
    </motion.div>
  );
}
'use client';

import { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import SyntaxHighlighter from './SyntaxHighlighter';

interface Node {
  id: string;
  path: string;
  type: string;
  title: string;
  summary: string;
  tags: string[];
}

interface DetailDrawerProps {
  node: Node;
  connections: string[];
  connectedNodes: Node[];
  onClose: () => void;
}

export default function DetailDrawer({ 
  node, 
  connections, 
  connectedNodes, 
  onClose 
}: DetailDrawerProps) {
  const [activeTab, setActiveTab] = useState<'summary' | 'raw'>('summary');
  const [fileContent, setFileContent] = useState<string>('');
  const [loading, setLoading] = useState(false);

  const loadFileContent = async () => {
    setLoading(true);
    try {
      // In a real implementation, you'd fetch the actual file content
      // For now, we'll generate a mock based on the file type
      const mockContent = generateMockContent(node);
      setFileContent(mockContent);
    } catch (error) {
      setFileContent('Error loading file content');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (activeTab === 'raw' && !fileContent) {
      loadFileContent();
    }
  }, [activeTab, node.path, fileContent]);

  const generateMockContent = (node: Node): string => {
    switch (node.type) {
      case 'script':
        return `#!/bin/bash\n\n# ${node.title}\n# ${node.summary}\n\nset -e\n\necho "Running ${node.title}..."\n\n# Mock script content based on tags\n${node.tags.includes('kubernetes') ? 'kubectl get nodes\n' : ''}${node.tags.includes('docker') ? 'docker ps\n' : ''}${node.tags.includes('monitoring') ? 'systemctl status prometheus\n' : ''}\necho "Done!"`;
      
      case 'doc':
        return `# ${node.title}\n\n${node.summary}\n\n## Overview\n\nThis document describes...\n\n## Usage\n\n\`\`\`bash\n# Example command\n./script.sh\n\`\`\`\n\n## Tags\n\n${node.tags.map(tag => `- ${tag}`).join('\n')}`;
      
      case 'manifest':
        return `apiVersion: v1\nkind: ${node.tags.includes('monitoring') ? 'ConfigMap' : 'Deployment'}\nmetadata:\n  name: ${node.title.replace(/\.[^/.]+$/, "")}\n  namespace: default\nspec:\n  # Configuration for ${node.title}`;
      
      default:
        return `# ${node.title}\n\n${node.summary}\n\nPath: ${node.path}\nType: ${node.type}\nTags: ${node.tags.join(', ')}`;
    }
  };

  const copyToClipboard = async () => {
    try {
      await navigator.clipboard.writeText(fileContent);
      // Could add a toast notification here
    } catch (error) {
      console.error('Failed to copy to clipboard:', error);
    }
  };

  return (
    <motion.div
      className="fixed right-0 top-0 h-full w-96 glass-card border-l border-white/20 z-50"
      initial={{ x: '100%' }}
      animate={{ x: 0 }}
      exit={{ x: '100%' }}
      transition={{ type: 'spring', stiffness: 300, damping: 30 }}
    >
      <div className="h-full flex flex-col">
        {/* Header */}
        <div className="border-b border-white/20 p-4">
          <div className="flex items-start justify-between">
            <div className="flex-1 min-w-0">
              <h2 className="text-lg font-semibold text-white truncate">
                {node.title}
              </h2>
              <p className="text-sm text-gray-400 truncate">{node.path}</p>
              <div className="flex flex-wrap gap-1 mt-2">
                {node.tags.slice(0, 5).map(tag => (
                  <span
                    key={tag}
                    className="px-2 py-1 text-xs bg-blue-500/20 text-blue-300 rounded-full"
                  >
                    {tag}
                  </span>
                ))}
              </div>
            </div>
            <button
              onClick={onClose}
              className="p-1 hover:bg-white/10 rounded-full transition-colors"
              aria-label="Close detail panel"
            >
              <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
              </svg>
            </button>
          </div>

          {/* Tabs */}
          <div className="flex gap-4 mt-4">
            <button
              onClick={() => setActiveTab('summary')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                activeTab === 'summary'
                  ? 'bg-blue-500 text-white'
                  : 'text-gray-300 hover:text-white'
              }`}
            >
              Summary
            </button>
            <button
              onClick={() => setActiveTab('raw')}
              className={`px-3 py-1 text-sm rounded-md transition-colors ${
                activeTab === 'raw'
                  ? 'bg-blue-500 text-white'
                  : 'text-gray-300 hover:text-white'
              }`}
            >
              Raw File
            </button>
          </div>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-hidden">
          {activeTab === 'summary' ? (
            <div className="p-4 space-y-4">
              {/* AI-Generated Summary */}
              <div>
                <h3 className="font-medium text-white mb-2">Description</h3>
                <p className="text-gray-300 text-sm leading-relaxed">
                  {node.summary}
                </p>
              </div>

              {/* Connections */}
              {connectedNodes.length > 0 && (
                <div>
                  <h3 className="font-medium text-white mb-2">
                    Connected Files ({connectedNodes.length})
                  </h3>
                  <div className="space-y-2 max-h-40 overflow-y-auto">
                    {connectedNodes.map(connectedNode => (
                      <div
                        key={connectedNode.id}
                        className="p-2 bg-white/5 rounded-md border border-white/10"
                      >
                        <div className="flex items-center gap-2">
                          <span className="text-sm">
                            {connectedNode.type === 'script' ? '⚡' : 
                             connectedNode.type === 'doc' ? '📄' : 
                             connectedNode.type === 'manifest' ? '⚙️' : '📁'}
                          </span>
                          <span className="text-sm font-medium text-white">
                            {connectedNode.title}
                          </span>
                        </div>
                        <p className="text-xs text-gray-400 mt-1 line-clamp-2">
                          {connectedNode.summary}
                        </p>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Metadata */}
              <div>
                <h3 className="font-medium text-white mb-2">File Info</h3>
                <div className="text-sm text-gray-300 space-y-1">
                  <div>Type: <span className="text-white">{node.type}</span></div>
                  <div>Path: <span className="text-white">{node.path}</span></div>
                  <div>Tags: <span className="text-white">{node.tags.join(', ')}</span></div>
                </div>
              </div>
            </div>
          ) : (
            <div className="h-full flex flex-col">
              {/* File Actions */}
              <div className="p-4 border-b border-white/20">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-gray-300">File Content</span>
                  <button
                    onClick={copyToClipboard}
                    className="px-3 py-1 text-xs bg-blue-500/20 text-blue-300 rounded-md hover:bg-blue-500/30 transition-colors"
                    disabled={!fileContent}
                  >
                    Copy
                  </button>
                </div>
              </div>

              {/* File Content */}
              <div className="flex-1 overflow-auto">
                {loading ? (
                  <div className="p-4 text-center">
                    <div className="loading-spinner mx-auto"></div>
                    <p className="text-sm text-gray-400 mt-2">Loading file...</p>
                  </div>
                ) : (
                  <SyntaxHighlighter
                    code={fileContent}
                    language={getLanguageFromFile(node.path)}
                  />
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </motion.div>
  );
}

function getLanguageFromFile(path: string): string {
  const ext = path.split('.').pop()?.toLowerCase();
  switch (ext) {
    case 'sh':
    case 'bash':
      return 'bash';
    case 'md':
      return 'markdown';
    case 'yaml':
    case 'yml':
      return 'yaml';
    case 'json':
      return 'json';
    case 'js':
      return 'javascript';
    case 'ts':
      return 'typescript';
    default:
      return 'text';
  }
}
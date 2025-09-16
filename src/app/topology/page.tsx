'use client';

import { useState } from 'react';
import { motion } from 'framer-motion';
import { ArrowLeft, GitBranch } from 'lucide-react';
import Link from 'next/link';
import ClusterTopologyGraph from '@/components/ClusterTopologyGraph';
import { generateClusterTopology } from '@/lib/data';

export default function TopologyPage() {
  const [animationSpeed, setAnimationSpeed] = useState(1);
  const topology = generateClusterTopology();

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="relative z-10 bg-white/10 backdrop-blur-sm border-b border-white/20">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            <div className="flex items-center space-x-3">
              <Link
                href="/"
                className="flex items-center space-x-2 px-3 py-2 rounded-lg hover:bg-white/10 transition-colors"
              >
                <ArrowLeft className="h-4 w-4 text-lake-600" />
                <span className="text-gray-700">Back to Repository</span>
              </Link>
              <div className="h-6 w-px bg-gray-300 mx-2" />
              <GitBranch className="h-8 w-8 text-cluster-control" />
              <div>
                <h1 className="text-xl font-bold text-gray-900">Cluster Topology</h1>
                <p className="text-sm text-gray-600">
                  {topology.nodes.length} components • {topology.edges.length} connections
                </p>
              </div>
            </div>
            <div className="flex items-center space-x-4">
              <label className="flex items-center space-x-2 text-sm text-gray-700">
                <span>Animation Speed:</span>
                <input
                  type="range"
                  min="0.1"
                  max="3"
                  step="0.1"
                  value={animationSpeed}
                  onChange={(e) => setAnimationSpeed(parseFloat(e.target.value))}
                  className="w-20"
                />
                <span>{animationSpeed}x</span>
              </label>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="relative">
        <ClusterTopologyGraph topology={topology} animationSpeed={animationSpeed} />
      </main>

      {/* Component Legend */}
      <div className="fixed bottom-4 left-4 z-20">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="glass-effect rounded-lg p-4 text-sm"
        >
          <div className="text-gray-700 font-medium mb-3">Component Types</div>
          <div className="space-y-2">
            <div className="flex items-center space-x-2">
              <div className="w-3 h-3 rounded bg-cluster-control"></div>
              <span>Control Plane</span>
            </div>
            <div className="flex items-center space-x-2">
              <div className="w-3 h-3 rounded bg-cluster-worker"></div>
              <span>Worker Nodes</span>
            </div>
            <div className="flex items-center space-x-2">
              <div className="w-3 h-3 rounded bg-cluster-network"></div>
              <span>Network Services</span>
            </div>
            <div className="flex items-center space-x-2">
              <div className="w-3 h-3 rounded bg-cluster-storage"></div>
              <span>Applications</span>
            </div>
            <div className="flex items-center space-x-2">
              <div className="w-3 h-3 rounded bg-cluster-monitor"></div>
              <span>Monitoring</span>
            </div>
          </div>
        </motion.div>
      </div>

      {/* Connection Legend */}
      <div className="fixed bottom-4 right-4 z-20">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.2 }}
          className="glass-effect rounded-lg p-4 text-sm max-w-sm"
        >
          <div className="text-gray-700 font-medium mb-3">Connection Types</div>
          <div className="space-y-2">
            <div className="flex items-center space-x-2">
              <svg width="20" height="3">
                <line x1="0" y1="1.5" x2="20" y2="1.5" stroke="#06b6d4" strokeWidth="2" className="barber-pole-link" />
              </svg>
              <span>Active Network</span>
            </div>
            <div className="flex items-center space-x-2">
              <svg width="20" height="3">
                <line x1="0" y1="1.5" x2="20" y2="1.5" stroke="#10b981" strokeWidth="2" strokeDasharray="3,3" />
              </svg>
              <span>Communication</span>
            </div>
            <div className="flex items-center space-x-2">
              <svg width="20" height="3">
                <line x1="0" y1="1.5" x2="20" y2="1.5" stroke="#f59e0b" strokeWidth="2" strokeDasharray="1,2" />
              </svg>
              <span>Dependencies</span>
            </div>
          </div>
          <div className="mt-3 pt-3 border-t border-white/20">
            <div className="text-gray-600">
              🎯 Click nodes for detailed information
            </div>
          </div>
        </motion.div>
      </div>
    </div>
  );
}
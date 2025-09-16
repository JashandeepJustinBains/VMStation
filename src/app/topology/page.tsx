'use client';

import { useState } from 'react';
import Link from 'next/link';
import ClusterTopologyVisualization from '@/components/ClusterTopologyVisualization';

export default function TopologyPage() {
  const [animationSpeed, setAnimationSpeed] = useState(1);
  const [showTooltips, setShowTooltips] = useState(true);

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-900 via-gray-900 to-slate-800">
      {/* Header */}
      <header className="relative z-50 p-4 border-b border-white/10">
        <div className="flex items-center justify-between max-w-7xl mx-auto">
          <div className="glass-card px-6 py-3">
            <h1 className="text-2xl font-bold text-white">
              VMStation Cluster Topology
            </h1>
            <p className="text-sm text-gray-300">
              Interactive Kubernetes cluster visualization
            </p>
          </div>
          
          <nav className="glass-card px-4 py-2">
            <div className="flex gap-4">
              <Link href="/" className="btn btn-secondary">
                Repository Lake
              </Link>
              <Link href="/topology" className="btn btn-primary">
                Cluster Topology
              </Link>
            </div>
          </nav>
        </div>
      </header>

      {/* Controls */}
      <div className="p-4">
        <div className="max-w-7xl mx-auto">
          <div className="glass-card p-4 mb-4">
            <div className="flex items-center gap-6">
              <div className="flex items-center gap-2">
                <label htmlFor="animation-speed" className="text-sm text-gray-300">
                  Animation Speed:
                </label>
                <input
                  id="animation-speed"
                  type="range"
                  min="0.1"
                  max="3"
                  step="0.1"
                  value={animationSpeed}
                  onChange={(e) => setAnimationSpeed(parseFloat(e.target.value))}
                  className="w-24"
                />
                <span className="text-sm text-white">{animationSpeed}x</span>
              </div>
              
              <label className="flex items-center gap-2 text-sm text-gray-300">
                <input
                  type="checkbox"
                  checked={showTooltips}
                  onChange={(e) => setShowTooltips(e.target.checked)}
                  className="form-checkbox"
                />
                Show Tooltips
              </label>
            </div>
          </div>
        </div>
      </div>

      {/* Main Visualization */}
      <main className="flex-1">
        <ClusterTopologyVisualization
          animationSpeed={animationSpeed}
          showTooltips={showTooltips}
        />
      </main>

      {/* Legend */}
      <div className="fixed bottom-4 left-4 glass-card p-4 max-w-sm z-40">
        <h3 className="font-semibold mb-3">Component Status</h3>
        <div className="space-y-2 text-sm">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 bg-green-500 rounded-full"></div>
            <span className="text-gray-300">Healthy</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 bg-yellow-500 rounded-full"></div>
            <span className="text-gray-300">Warning</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 bg-red-500 rounded-full"></div>
            <span className="text-gray-300">Critical</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 bg-gray-500 rounded-full"></div>
            <span className="text-gray-300">Unknown</span>
          </div>
        </div>
        
        <div className="mt-4 pt-3 border-t border-white/20">
          <h4 className="font-medium mb-2">Link Animation</h4>
          <div className="flex items-center gap-2">
            <div className="w-8 h-1 bg-gradient-to-r from-blue-500 to-cyan-500 rounded animate-pulse"></div>
            <span className="text-xs text-gray-400">Active Connection</span>
          </div>
        </div>
      </div>

      {/* Node Info Panel */}
      <div className="fixed bottom-4 right-4 glass-card p-4 max-w-sm z-40">
        <h3 className="font-semibold mb-2">Cluster Overview</h3>
        <div className="text-sm text-gray-300 space-y-1">
          <div>Control Plane: <span className="text-green-400">masternode</span></div>
          <div>Storage Node: <span className="text-green-400">storagenodet3500</span></div>
          <div>Compute Node: <span className="text-green-400">homelab</span></div>
          <div className="pt-2 border-t border-white/20">
            <div>CNI: <span className="text-blue-400">Flannel</span></div>
            <div>DNS: <span className="text-blue-400">CoreDNS</span></div>
            <div>Proxy: <span className="text-blue-400">kube-proxy</span></div>
          </div>
        </div>
      </div>
    </div>
  );
}
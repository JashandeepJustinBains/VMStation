'use client';

import { useState, useEffect } from 'react';
import { motion } from 'framer-motion';
import { ArrowRight, GitBranch, Network } from 'lucide-react';
import Link from 'next/link';
import RepositoryLake from '@/components/RepositoryLake';
import { loadRepositoryData } from '@/lib/data';
import { RepositoryData } from '@/types';

export default function HomePage() {
  const [data, setData] = useState<RepositoryData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadRepositoryData()
      .then(setData)
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <motion.div
          animate={{ rotate: 360 }}
          transition={{ duration: 2, repeat: Infinity, ease: "linear" }}
          className="w-8 h-8 border-2 border-lake-600 border-t-transparent rounded-full"
        />
        <span className="ml-3 text-lake-700">Loading repository data...</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-center">
          <div className="text-red-600 text-xl mb-4">⚠️ Error loading data</div>
          <div className="text-gray-600">{error}</div>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="relative z-10 bg-white/10 backdrop-blur-sm border-b border-white/20">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            <div className="flex items-center space-x-3">
              <GitBranch className="h-8 w-8 text-lake-600" />
              <div>
                <h1 className="text-xl font-bold text-gray-900">VMStation Repository Explorer</h1>
                <p className="text-sm text-gray-600">
                  {data?.metadata.totalFiles} files • {data?.edges.length} connections
                </p>
              </div>
            </div>
            <nav className="flex items-center space-x-4">
              <Link
                href="/topology"
                className="flex items-center space-x-2 px-4 py-2 rounded-lg bg-lake-600 text-white hover:bg-lake-700 transition-colors"
              >
                <Network className="h-4 w-4" />
                <span>Cluster Topology</span>
                <ArrowRight className="h-4 w-4" />
              </Link>
            </nav>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="relative">
        {data && <RepositoryLake data={data} />}
      </main>

      {/* Footer Info */}
      <div className="fixed bottom-4 left-4 z-20">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          className="glass-effect rounded-lg p-3 text-sm"
        >
          <div className="text-gray-700 font-medium mb-1">Repository Statistics</div>
          <div className="text-gray-600 space-y-1">
            <div>📜 Scripts: {data?.metadata.stats.byType.script || 0}</div>
            <div>📚 Docs: {data?.metadata.stats.byType.doc || 0}</div>
            <div>⚙️ Configs: {data?.metadata.stats.byType.config || 0}</div>
            <div>📝 TODOs: {data?.metadata.stats.byType.todo || 0}</div>
          </div>
        </motion.div>
      </div>

      {/* Instructions */}
      <div className="fixed bottom-4 right-4 z-20">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.5 }}
          className="glass-effect rounded-lg p-3 text-sm max-w-sm"
        >
          <div className="text-gray-700 font-medium mb-2">🎮 How to Explore</div>
          <div className="text-gray-600 space-y-1">
            <div>• Click a card to pull related files</div>
            <div>• Click related cards to anchor & expand</div>
            <div>• Use search to filter by type or content</div>
            <div>• Watch the ropes show relationships</div>
          </div>
        </motion.div>
      </div>
    </div>
  );
}
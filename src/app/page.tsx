'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import FloatingLake from '@/components/FloatingLake';

interface RepositoryData {
  metadata: {
    generated: string;
    nodeCount: number;
    edgeCount: number;
  };
  nodes: Array<{
    id: string;
    path: string;
    type: string;
    title: string;
    summary: string;
    tags: string[];
  }>;
  edges: Array<{
    from: string;
    to: string;
    relation: string;
  }>;
}

export default function HomePage() {
  const [data, setData] = useState<RepositoryData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const loadData = async () => {
      try {
        const response = await fetch('/data/repo_index.json');
        if (!response.ok) {
          throw new Error('Failed to load repository data');
        }
        const repoData = await response.json();
        setData(repoData);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Unknown error');
      } finally {
        setLoading(false);
      }
    };

    loadData();
  }, []);

  if (loading) {
    return (
      <div className="min-h-screen water-background flex items-center justify-center">
        <div className="glass-card p-8 text-center">
          <div className="loading-spinner mx-auto mb-4"></div>
          <p>Loading VMStation Repository Explorer...</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen water-background flex items-center justify-center">
        <div className="glass-card p-8 text-center max-w-md">
          <h1 className="text-xl font-bold mb-4 text-red-400">Error Loading Data</h1>
          <p className="text-gray-300 mb-4">{error}</p>
          <button 
            onClick={() => window.location.reload()} 
            className="btn btn-primary"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen water-background">
      {/* Header */}
      <header className="relative z-50 p-4">
        <div className="flex items-center justify-between max-w-7xl mx-auto">
          <div className="glass-card px-6 py-3">
            <h1 className="text-2xl font-bold text-white">
              VMStation Repository Explorer
            </h1>
            <p className="text-sm text-gray-300">
              {data?.metadata.nodeCount} files • {data?.metadata.edgeCount} connections
            </p>
          </div>
          
          <nav className="glass-card px-4 py-2">
            <div className="flex gap-4">
              <Link href="/" className="btn btn-secondary">
                Repository Lake
              </Link>
              <Link href="/topology" className="btn btn-secondary">
                Cluster Topology
              </Link>
            </div>
          </nav>
        </div>
      </header>

      {/* Main Content */}
      <main className="relative">
        {data && (
          <FloatingLake 
            nodes={data.nodes} 
            edges={data.edges}
          />
        )}
      </main>

      {/* Info Panel */}
      <div className="fixed bottom-4 left-4 glass-card p-4 max-w-sm z-40">
        <h3 className="font-semibold mb-2">How to Explore</h3>
        <ul className="text-sm text-gray-300 space-y-1">
          <li>• Click cards to see connections</li>
          <li>• Click connected cards to anchor & expand</li>
          <li>• Use search to filter by type or tag</li>
          <li>• Hover for quick summaries</li>
        </ul>
      </div>
    </div>
  );
}
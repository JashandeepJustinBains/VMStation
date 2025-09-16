'use client';

interface SearchFilterProps {
  searchTerm: string;
  onSearchChange: (term: string) => void;
  selectedType: string;
  onTypeChange: (type: string) => void;
  nodeTypes: string[];
}

export default function SearchFilter({
  searchTerm,
  onSearchChange,
  selectedType,
  onTypeChange,
  nodeTypes
}: SearchFilterProps) {
  return (
    <div className="glass-card p-4 w-80">
      <h3 className="font-semibold mb-3">Filter & Search</h3>
      
      {/* Search Input */}
      <div className="mb-3">
        <label htmlFor="search" className="sr-only">
          Search files
        </label>
        <input
          id="search"
          type="text"
          placeholder="Search files, tags, or content..."
          className="w-full px-3 py-2 bg-black/20 border border-white/20 rounded-md 
                     text-white placeholder-gray-400 focus:outline-none focus:border-cyan-400
                     focus:ring-2 focus:ring-cyan-400/50"
          value={searchTerm}
          onChange={(e) => onSearchChange(e.target.value)}
        />
      </div>
      
      {/* Type Filter */}
      <div>
        <label htmlFor="type-filter" className="text-sm text-gray-300 mb-2 block">
          File Type
        </label>
        <select
          id="type-filter"
          className="w-full px-3 py-2 bg-black/20 border border-white/20 rounded-md 
                     text-white focus:outline-none focus:border-cyan-400
                     focus:ring-2 focus:ring-cyan-400/50"
          value={selectedType}
          onChange={(e) => onTypeChange(e.target.value)}
        >
          <option value="all">All Types</option>
          {nodeTypes.map(type => (
            <option key={type} value={type}>
              {type.charAt(0).toUpperCase() + type.slice(1)}s
            </option>
          ))}
        </select>
      </div>
      
      {/* Quick Filters */}
      <div className="mt-3">
        <p className="text-sm text-gray-300 mb-2">Quick Filters</p>
        <div className="flex flex-wrap gap-2">
          {['kubernetes', 'jellyfin', 'monitoring', 'networking', 'deployment'].map(tag => (
            <button
              key={tag}
              className={`px-2 py-1 text-xs rounded-full border transition-colors
                ${searchTerm === tag 
                  ? 'bg-cyan-500 border-cyan-500 text-white' 
                  : 'border-white/20 text-gray-300 hover:border-cyan-400'
                }`}
              onClick={() => onSearchChange(searchTerm === tag ? '' : tag)}
            >
              {tag}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
# VMStation Repository Explorer

An interactive web application that visualizes the VMStation Kubernetes deployment project as floating cards on a "lake" canvas, showing relationships between scripts, documentation, and configuration files through animated connections.

## Features

### 🌊 Interactive Lake Canvas
- Physics-based floating cards representing all repository files
- Smooth animations with rope connections showing relationships
- Click interactions that pull related cards together
- Beautiful lake theme with blue-cyan gradients and water effects

### 🔍 Smart Content Analysis
- Automated relationship detection between scripts, docs, and configurations
- AI-generated summaries for each file based on content analysis
- Tag inference from file paths and content
- Dependency mapping showing script calls and documentation references

### 🕸️ Cluster Topology Visualization
- Interactive network graph of VMStation's 3-node Kubernetes cluster
- Animated barber-pole links indicating active connections
- Component status indicators for control-plane, storage, and compute nodes
- Real-time metadata panels with detailed component information

### ⚡ Production Quality
- Comprehensive search and filtering by file type, content, and tags
- Accessibility features with keyboard navigation and reduced-motion support
- Performance optimized with lazy loading and efficient animations
- Static site generation ready for GitHub Pages deployment

## Quick Start

```bash
# Extract repository data
npm run extract

# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build

# Run tests
npm test
```

The explorer will be available at `http://localhost:3000` with two main views:
- **Repository Lake** (`/`) - Interactive canvas with floating file cards
- **Cluster Topology** (`/topology`) - Network visualization of Kubernetes components

## Data Extraction

The repository data is extracted using the Node.js script at `scripts/extract_repo_data.js`:

```bash
# Extract data from current directory
node scripts/extract_repo_data.js

# Extract data from specific path
node scripts/extract_repo_data.js /path/to/repository
```

This generates `data/repo_index.json` containing:
- **Nodes**: File metadata with summaries, tags, and relationships
- **Edges**: Connections between files (calls, references, mentions)
- **Stats**: Repository analysis and file type distribution

### Supported File Types
- **Scripts**: `.sh`, `.bash` files with execution flow analysis
- **Documentation**: `.md` files with link and reference extraction
- **Configuration**: `.yaml`, `.yml`, `.json` files
- **TODO files**: Task and todo tracking files
- **Templates**: Jinja2 and template files

## Repository Analysis Results

The explorer successfully mapped the entire VMStation ecosystem:

- **55 Scripts**: Including main deployment orchestration and worker join processes
- **60 Documentation files**: Comprehensive guides covering deployment and troubleshooting  
- **40 Configuration files**: Kubernetes manifests, monitoring configs, and network settings
- **1500+ Relationships**: Connections between scripts, docs, and configs

### Key Components Visualized

- `deploy-cluster.sh` (967 lines) - Main deployment orchestration
- `enhanced_kubeadm_join.sh` (1388 lines) - Complex worker join scenarios
- Prometheus/Grafana monitoring stack configurations
- Jellyfin media server network troubleshooting guides
- Comprehensive CNI and networking documentation

## Architecture

### Frontend Stack
- **Next.js 14** with TypeScript for type safety and modern React features
- **Framer Motion** for smooth physics-based animations
- **Tailwind CSS** with custom lake theme styling
- **Shiki** for syntax highlighting in the code viewer
- **Lucide React** for consistent iconography

### Data Processing
- **Node.js extraction script** with file system analysis
- **Relationship mapping** using regex patterns and content analysis
- **JSON output** with nodes and edges for visualization
- **Performance optimized** with lazy loading and efficient queries

### Deployment
- **Static site generation** with Next.js export
- **GitHub Pages ready** with proper routing configuration
- **Build optimization** with tree-shaking and code splitting
- **Environment-specific** configurations for development and production

## Usage Instructions

### Navigation
1. **Repository Lake**: Click any card to see its connections
2. **Related Files**: Click connected cards to anchor them and view details
3. **Search & Filter**: Use the search bar to find specific files or content
4. **Detail Panel**: Anchored cards open detailed panels with content and metadata

### Cluster Topology
1. **Node Interaction**: Click cluster components for detailed information
2. **Connection Types**: Different line styles indicate network, communication, or dependency links
3. **Animation Control**: Adjust barber-pole animation speed with the slider
4. **Status Indicators**: Color-coded status shows component health

### Accessibility
- **Keyboard Navigation**: All interactive elements are keyboard accessible
- **Reduced Motion**: Respects user's motion preferences
- **ARIA Labels**: Screen reader compatible with proper labeling
- **High Contrast**: Supports high contrast mode and color preferences

## Testing

The project includes comprehensive test coverage:

```bash
# Run all tests
npm test

# Run tests in watch mode
npm test:watch

# Type checking
npm run typecheck
```

### Test Coverage
- **Unit tests** for data extraction functionality
- **Integration tests** validating key repository files are detected
- **Performance tests** ensuring smooth animations with 156+ cards
- **Data contract validation** for JSON structure integrity

## Building and Deployment

### Local Development
```bash
npm run dev          # Development server with hot reload
npm run build        # Production build with optimization
npm run start        # Production server preview
npm run export       # Static export for deployment
```

### GitHub Pages Deployment
The project is configured for automatic deployment to GitHub Pages:

1. **Build Process**: Next.js static export generates optimized HTML/CSS/JS
2. **Asset Optimization**: Images, fonts, and scripts are minimized
3. **Routing**: Hash-based routing for GitHub Pages compatibility
4. **CNAME**: Configurable for custom domain support

### Environment Variables
```bash
# Optional: Custom repository path
REPO_PATH=/path/to/repository

# Optional: API endpoints for file content
NEXT_PUBLIC_API_BASE_URL=https://api.example.com
```

## Performance Optimization

- **Lazy Loading**: Cards and content loaded on demand
- **Physics Optimization**: 30-45 FPS target with efficient calculations
- **Memory Management**: Efficient cleanup of animations and event listeners
- **Bundle Optimization**: Code splitting and tree shaking for minimal payload

## Contributing

The codebase is structured for easy extension:

- **`scripts/extract_repo_data.js`**: Data extraction and relationship mapping
- **`components/`**: Reusable UI components with TypeScript
- **`lib/data.ts`**: Data loading and utility functions
- **`types/index.ts`**: TypeScript type definitions

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](../LICENSE) file for details.

## Acknowledgments

Built for the VMStation Kubernetes deployment project, providing an intuitive way to understand the project's structure, relationships between components, and cluster topology through a modern web interface.
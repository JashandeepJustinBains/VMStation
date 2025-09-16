# VMStation Repository Explorer

Interactive repository explorer and cluster topology visualizer for the VMStation Kubernetes infrastructure project.

## Features

### Repository Lake (Home Page)
- **Interactive Floating Cards**: Repository files displayed as animated floating cards in a lake-themed canvas
- **Physics-Based Animation**: Cards float using realistic physics with springs and collision detection
- **Relationship Visualization**: Animated "ropes" connect related files with flowing gradients
- **Smart Interactions**: Click cards to reveal connections, click connected cards to anchor and expand details
- **Search & Filter**: Find files by name, content, or tags with real-time filtering
- **Accessibility**: Full keyboard navigation, ARIA labels, and reduced-motion support

### Cluster Topology Page
- **Interactive Network Graph**: Kubernetes cluster components visualized as an interactive graph
- **Animated Connections**: Barber-pole striped links show active/healthy connections
- **Real-time Status**: Component health indicators with color-coded status
- **Detailed Node Info**: Click nodes to see detailed information and metadata
- **Configurable Animation**: Adjustable animation speed and tooltip controls

## Technology Stack

- **Framework**: Next.js 14 with TypeScript
- **Animation**: Framer Motion for fluid animations and physics
- **Visualization**: D3.js for cluster topology graphs
- **Styling**: CSS-in-JS with custom glass morphism effects
- **Testing**: Vitest with React Testing Library
- **Build**: Static site generation for easy deployment

## Getting Started

### Prerequisites
- Node.js 18+ 
- npm or yarn

### Installation

1. Install dependencies:
```bash
npm install
```

2. Generate repository data:
```bash
npm run extract-data
```

3. Start development server:
```bash
npm run dev
```

4. Open [http://localhost:3000](http://localhost:3000) in your browser

### Build for Production

```bash
npm run build
```

This generates a static site in the `out/` directory ready for deployment.

## Development

### Available Scripts

- `npm run dev` - Start development server
- `npm run build` - Build for production
- `npm run export` - Export static site
- `npm run test` - Run unit tests
- `npm run test:watch` - Run tests in watch mode
- `npm run lint` - Run ESLint
- `npm run serve` - Serve built site locally

### Project Structure

```
src/
├── app/                    # Next.js app router pages
│   ├── layout.tsx         # Root layout component
│   ├── page.tsx           # Home page (Repository Lake)
│   ├── topology/          # Cluster topology page
│   └── globals.css        # Global styles
├── components/            # React components
│   ├── FloatingLake.tsx   # Main repository visualization
│   ├── FloatingCard.tsx   # Individual file cards
│   ├── RopesLayer.tsx     # Connection visualization
│   ├── SearchFilter.tsx   # Search and filtering
│   ├── DetailDrawer.tsx   # File detail panel
│   └── ClusterTopologyVisualization.tsx
├── scripts/               # Build and utility scripts
│   └── extract_repo_data.js  # Repository scanning script
├── data/                  # Generated data files
│   └── repo_index.json    # Repository structure data
├── tests/                 # Test files
└── README.md             # This file
```

### Data Extraction

The `extract_repo_data.js` script scans the repository and generates `repo_index.json` with:

- **Nodes**: Files found in the repository with metadata
- **Edges**: Relationships between files (calls, references, documents)

#### Supported File Types
- **Scripts**: `.sh`, `.bash` files
- **Documentation**: `.md`, `.txt` files  
- **Manifests**: `.yaml`, `.yml` files
- **TODOs**: `TODO.md`, `.todo` files
- **Configs**: `.json`, `.conf` files

#### Relationship Detection
- Script calls other scripts
- Documentation references other files
- Manifests define related resources
- Cross-references in content

## Deployment

### GitHub Pages

The project includes a GitHub Actions workflow for automatic deployment:

```yaml
# .github/workflows/deploy.yml
name: Deploy to GitHub Pages
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - run: npm ci
      - run: npm run build
      - uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./out
```

### Netlify

1. Connect your repository to Netlify
2. Set build command: `npm run build`
3. Set publish directory: `out`
4. Deploy

### Vercel

1. Import project to Vercel
2. Vercel auto-detects Next.js configuration
3. Deploy

## Customization

### Theming

Edit `app/globals.css` to customize:
- Color scheme (CSS custom properties)
- Animation timing
- Glass morphism effects
- Water background gradients

### Physics Parameters

Modify `components/FloatingLake.tsx`:
- `damping` - Animation smoothness (0.98)
- `attraction` - Connection strength (0.02) 
- `repulsion` - Card separation distance (30)

### Data Sources

Extend `scripts/extract_repo_data.js` to:
- Add new file types
- Customize relationship detection
- Include external data sources
- Generate AI summaries

## Performance

- **Lazy Loading**: File content loaded on demand
- **Virtualization**: Large lists use virtual scrolling
- **Reduced Motion**: Respects user preferences
- **Optimized Animations**: 30-45 FPS target for smooth performance

## Accessibility

- **Keyboard Navigation**: All interactive elements accessible via keyboard
- **ARIA Labels**: Screen reader support
- **Focus Management**: Clear focus indicators
- **Reduced Motion**: Animation disabled when requested
- **Color Contrast**: WCAG AA compliant colors

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

MIT License - see LICENSE file for details

## Support

For issues and questions:
- Check the GitHub Issues
- Review the troubleshooting guide below

## Troubleshooting

### Common Issues

**Build fails with "Module not found"**
- Run `npm install` to ensure all dependencies are installed
- Clear `.next` directory and rebuild

**Data extraction shows no files**
- Verify the repository path in `extract_repo_data.js`
- Check file permissions for repository directory

**Animations are choppy**
- Enable reduced motion in accessibility settings
- Reduce `animationSpeed` parameter in topology view

**Deployment fails**
- Ensure `out/` directory is gitignored
- Verify build artifacts aren't committed
- Check deployment logs for specific errors

### Browser Compatibility

- Chrome 88+
- Firefox 85+
- Safari 14+
- Edge 88+

Modern browser features required:
- ES2020 support
- CSS Custom Properties
- ResizeObserver API
- Intersection Observer API
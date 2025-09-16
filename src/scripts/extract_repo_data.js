#!/usr/bin/env node

/**
 * VMStation Repository Data Extraction Script
 * Scans the repository for scripts, docs, and TODOs to generate data for the UI
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Configuration
const REPO_ROOT = path.resolve(__dirname, '../..');
const OUTPUT_FILE = path.join(__dirname, '../data/repo_index.json');

// File patterns and types
const FILE_PATTERNS = {
  script: /\.(sh|bash)$/,
  doc: /\.(md|txt|rst)$/,
  todo: /\.(todo)$|^TODO/i,
  yaml: /\.(yaml|yml)$/,
  config: /\.(json|conf|config|cfg)$/
};

// Directories to scan
const SCAN_DIRS = [
  'scripts',
  'docs', 
  'ansible',
  'manifests',
  '.' // root directory
];

// Files to include from root
const ROOT_FILES = [
  'README.md',
  'TODO.md', 
  'deploy-cluster.sh',
  'generate_join_command.sh'
];

class RepositoryExtractor {
  constructor() {
    this.nodes = [];
    this.edges = [];
    this.processedFiles = new Set();
  }

  /**
   * Generate a unique ID for a file
   */
  generateId(filePath) {
    return crypto.createHash('md5').update(filePath).digest('hex').substring(0, 8);
  }

  /**
   * Determine file type based on path and extension
   */
  getFileType(filePath) {
    const fileName = path.basename(filePath);
    const ext = path.extname(filePath).toLowerCase();
    
    if (FILE_PATTERNS.script.test(fileName)) return 'script';
    if (FILE_PATTERNS.todo.test(fileName)) return 'todo';
    if (FILE_PATTERNS.doc.test(fileName)) return 'doc';
    if (FILE_PATTERNS.yaml.test(fileName)) return 'manifest';
    if (FILE_PATTERNS.config.test(fileName)) return 'config';
    
    return 'other';
  }

  /**
   * Extract first few lines for summary
   */
  extractSummary(content, type) {
    const lines = content.split('\n').filter(line => line.trim());
    
    if (type === 'script') {
      // Find comment lines after shebang
      const commentLines = lines
        .slice(1, 10)
        .filter(line => line.trim().startsWith('#'))
        .map(line => line.replace(/^#\s*/, ''))
        .filter(line => line.length > 0);
      
      return commentLines.slice(0, 3).join(' ') || 'Shell script for VMStation operations';
    }
    
    if (type === 'doc') {
      // Find first paragraph after title
      let summary = '';
      let foundTitle = false;
      
      for (const line of lines.slice(0, 20)) {
        if (line.startsWith('#')) {
          foundTitle = true;
          continue;
        }
        if (foundTitle && line.trim() && !line.startsWith('```')) {
          summary = line.trim();
          break;
        }
      }
      
      return summary || lines.slice(0, 2).join(' ');
    }
    
    if (type === 'todo') {
      return lines.slice(0, 3).join(' ') || 'Project TODO items and tasks';
    }
    
    return lines.slice(0, 2).join(' ') || 'Configuration file';
  }

  /**
   * Extract tags from file path and content
   */
  extractTags(filePath, content, type) {
    const tags = [];
    const pathParts = filePath.split(path.sep);
    
    // Add directory-based tags
    if (pathParts.includes('scripts')) tags.push('scripts');
    if (pathParts.includes('docs')) tags.push('documentation');
    if (pathParts.includes('ansible')) tags.push('ansible', 'automation');
    if (pathParts.includes('manifests')) tags.push('kubernetes', 'manifests');
    if (pathParts.includes('monitoring')) tags.push('monitoring');
    if (pathParts.includes('jellyfin')) tags.push('jellyfin', 'media');
    if (pathParts.includes('network') || pathParts.includes('cni')) tags.push('networking');
    
    // Add content-based tags
    const lowerContent = content.toLowerCase();
    if (lowerContent.includes('kubeadm') || lowerContent.includes('kubectl')) tags.push('kubernetes');
    if (lowerContent.includes('docker') || lowerContent.includes('containerd')) tags.push('containers');
    if (lowerContent.includes('prometheus') || lowerContent.includes('grafana')) tags.push('monitoring');
    if (lowerContent.includes('flannel') || lowerContent.includes('cni')) tags.push('networking');
    if (lowerContent.includes('jellyfin')) tags.push('jellyfin');
    if (lowerContent.includes('deploy') || lowerContent.includes('install')) tags.push('deployment');
    if (lowerContent.includes('fix') || lowerContent.includes('troubleshoot')) tags.push('troubleshooting');
    
    // Add type tag
    tags.push(type);
    
    return [...new Set(tags)]; // Remove duplicates
  }

  /**
   * Find dependencies and references in content
   */
  findReferences(filePath, content) {
    const references = [];
    const lines = content.split('\n');
    
    for (const line of lines) {
      // Find script calls: ./script.sh, script.sh, or "script.sh"
      const scriptMatches = line.match(/(?:\.\/)?([a-zA-Z0-9_-]+\.sh)/g);
      if (scriptMatches) {
        scriptMatches.forEach(match => {
          const scriptName = match.replace('./', '');
          if (scriptName !== path.basename(filePath)) {
            references.push({
              type: 'calls',
              target: scriptName,
              line: line.trim()
            });
          }
        });
      }
      
      // Find markdown links: [text](file.md) or file.md
      const docMatches = line.match(/(?:\[.*?\]\()?([a-zA-Z0-9_-]+\.md)(?:\))?/g);
      if (docMatches) {
        docMatches.forEach(match => {
          const docName = match.match(/([a-zA-Z0-9_-]+\.md)/)[1];
          if (docName !== path.basename(filePath)) {
            references.push({
              type: 'references',
              target: docName,
              line: line.trim()
            });
          }
        });
      }
      
      // Find YAML/manifest references
      const yamlMatches = line.match(/([a-zA-Z0-9_-]+\.ya?ml)/g);
      if (yamlMatches) {
        yamlMatches.forEach(match => {
          if (match !== path.basename(filePath)) {
            references.push({
              type: 'references',
              target: match,
              line: line.trim()
            });
          }
        });
      }
    }
    
    return references;
  }

  /**
   * Process a single file
   */
  processFile(filePath) {
    const relativePath = path.relative(REPO_ROOT, filePath);
    
    if (this.processedFiles.has(relativePath)) {
      return;
    }
    this.processedFiles.add(relativePath);
    
    try {
      const stats = fs.statSync(filePath);
      const content = fs.readFileSync(filePath, 'utf8');
      const type = this.getFileType(filePath);
      
      // Skip very large files or binary files
      if (stats.size > 1024 * 1024 || !content.trim()) {
        return;
      }
      
      const node = {
        id: this.generateId(relativePath),
        path: relativePath,
        type: type,
        title: path.basename(filePath),
        summary: this.extractSummary(content, type),
        sizeBytes: stats.size,
        tags: this.extractTags(relativePath, content, type),
        lastModified: stats.mtime.toISOString()
      };
      
      this.nodes.push(node);
      
      // Find references and create edges
      const references = this.findReferences(filePath, content);
      references.forEach(ref => {
        this.edges.push({
          from: node.id,
          to: ref.target, // Will be resolved later
          relation: ref.type,
          context: ref.line.substring(0, 100)
        });
      });
      
    } catch (error) {
      console.warn(`Warning: Could not process file ${relativePath}: ${error.message}`);
    }
  }

  /**
   * Scan a directory recursively
   */
  scanDirectory(dirPath, recursive = true) {
    try {
      const items = fs.readdirSync(dirPath);
      
      for (const item of items) {
        const itemPath = path.join(dirPath, item);
        const stats = fs.statSync(itemPath);
        
        if (stats.isDirectory()) {
          // Skip common directories that shouldn't be scanned
          if (['node_modules', '.git', '.next', 'out', 'dist', 'build'].includes(item)) {
            continue;
          }
          
          if (recursive) {
            this.scanDirectory(itemPath, true);
          }
        } else if (stats.isFile()) {
          const type = this.getFileType(itemPath);
          if (type !== 'other') {
            this.processFile(itemPath);
          }
        }
      }
    } catch (error) {
      console.warn(`Warning: Could not scan directory ${dirPath}: ${error.message}`);
    }
  }

  /**
   * Resolve edge targets to node IDs
   */
  resolveEdges() {
    const nodesByPath = new Map();
    const nodesByName = new Map();
    
    // Build lookup maps
    this.nodes.forEach(node => {
      nodesByPath.set(node.path, node.id);
      nodesByName.set(path.basename(node.path), node.id);
    });
    
    // Resolve edges
    this.edges = this.edges
      .map(edge => {
        let targetId = nodesByName.get(edge.to) || nodesByPath.get(edge.to);
        
        // Try to find by partial path match
        if (!targetId) {
          for (const [nodePath, nodeId] of nodesByPath) {
            if (nodePath.includes(edge.to)) {
              targetId = nodeId;
              break;
            }
          }
        }
        
        if (targetId) {
          return { ...edge, to: targetId };
        }
        
        return null; // Will be filtered out
      })
      .filter(edge => edge !== null);
  }

  /**
   * Main extraction process
   */
  extract() {
    console.log('🔍 Scanning VMStation repository...');
    
    // Scan specific directories
    SCAN_DIRS.forEach(dir => {
      const dirPath = path.join(REPO_ROOT, dir);
      if (fs.existsSync(dirPath)) {
        console.log(`📁 Scanning ${dir}/`);
        if (dir === '.') {
          // Only scan specific files from root
          ROOT_FILES.forEach(file => {
            const filePath = path.join(dirPath, file);
            if (fs.existsSync(filePath)) {
              this.processFile(filePath);
            }
          });
        } else {
          this.scanDirectory(dirPath);
        }
      }
    });
    
    console.log(`📄 Found ${this.nodes.length} files`);
    
    // Resolve edge references
    this.resolveEdges();
    console.log(`🔗 Created ${this.edges.length} connections`);
    
    // Generate output
    const output = {
      metadata: {
        generated: new Date().toISOString(),
        repositoryPath: REPO_ROOT,
        nodeCount: this.nodes.length,
        edgeCount: this.edges.length,
        version: '1.0.0'
      },
      nodes: this.nodes,
      edges: this.edges
    };
    
    // Ensure output directory exists
    const outputDir = path.dirname(OUTPUT_FILE);
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }
    
    // Write output file
    fs.writeFileSync(OUTPUT_FILE, JSON.stringify(output, null, 2));
    console.log(`✅ Repository index saved to: ${path.relative(REPO_ROOT, OUTPUT_FILE)}`);
    
    // Print summary
    console.log('\n📊 Summary:');
    const typeStats = this.nodes.reduce((acc, node) => {
      acc[node.type] = (acc[node.type] || 0) + 1;
      return acc;
    }, {});
    
    Object.entries(typeStats).forEach(([type, count]) => {
      console.log(`   ${type}: ${count} files`);
    });
    
    return output;
  }
}

// Run extraction if called directly
if (require.main === module) {
  const extractor = new RepositoryExtractor();
  extractor.extract();
}

module.exports = RepositoryExtractor;
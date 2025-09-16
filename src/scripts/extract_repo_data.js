#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

/**
 * VMStation Repository Data Extraction Script
 * Scans the repository for scripts, docs, and configs to generate visualization data
 */

class RepoDataExtractor {
    constructor(repoPath = process.cwd()) {
        this.repoPath = path.resolve(repoPath);
        this.nodes = [];
        this.edges = [];
        this.nodeMap = new Map();
    }

    /**
     * Main extraction process
     */
    async extract() {
        console.log(`🔍 Scanning repository: ${this.repoPath}`);
        
        try {
            await this.scanDirectory(this.repoPath);
            await this.extractRelationships();
            
            const output = {
                nodes: this.nodes,
                edges: this.edges,
                metadata: {
                    totalFiles: this.nodes.length,
                    extractedAt: new Date().toISOString(),
                    repoPath: this.repoPath,
                    stats: this.getStats()
                }
            };

            await this.writeOutput(output);
            console.log(`✅ Extracted ${this.nodes.length} nodes and ${this.edges.length} edges`);
            
            return output;
        } catch (error) {
            console.error('❌ Extraction failed:', error.message);
            process.exit(1);
        }
    }

    /**
     * Recursively scan directory for relevant files
     */
    async scanDirectory(dirPath, basePath = '') {
        const entries = fs.readdirSync(dirPath, { withFileTypes: true });
        
        for (const entry of entries) {
            const fullPath = path.join(dirPath, entry.name);
            const relativePath = path.join(basePath, entry.name);
            
            // Skip hidden files, git, node_modules, build artifacts
            if (this.shouldSkip(relativePath)) continue;
            
            if (entry.isDirectory()) {
                await this.scanDirectory(fullPath, relativePath);
            } else if (entry.isFile()) {
                await this.processFile(fullPath, relativePath);
            }
        }
    }

    /**
     * Check if file/directory should be skipped
     */
    shouldSkip(relativePath) {
        const skipPatterns = [
            /^\./,          // Hidden files
            /node_modules/, // Dependencies
            /\.git/,        // Git directory
            /dist/,         // Build output
            /build/,        // Build output
            /\.next/,       // Next.js build
            /out/,          // Static export
            /coverage/,     // Test coverage
            /__pycache__/,  // Python cache
            /\.pyc$/,       // Python compiled
            /\.log$/,       // Log files
            /\.tmp$/,       // Temp files
            /\.bak$/,       // Backup files
        ];
        
        return skipPatterns.some(pattern => pattern.test(relativePath));
    }

    /**
     * Process individual file and extract metadata
     */
    async processFile(fullPath, relativePath) {
        const ext = path.extname(relativePath).toLowerCase();
        const basename = path.basename(relativePath);
        
        let fileType = this.getFileType(relativePath, ext);
        if (!fileType) return; // Skip unsupported file types
        
        try {
            const stats = fs.statSync(fullPath);
            const content = fs.readFileSync(fullPath, 'utf8');
            
            const node = {
                id: this.generateId(relativePath),
                path: relativePath,
                type: fileType,
                title: this.extractTitle(basename, content, fileType),
                summary: this.extractSummary(content, fileType),
                sizeBytes: stats.size,
                tags: this.extractTags(relativePath, content, fileType),
                lastModified: stats.mtime.toISOString(),
                lines: content.split('\n').length
            };
            
            this.nodes.push(node);
            this.nodeMap.set(relativePath, node);
            
        } catch (error) {
            console.warn(`⚠️  Could not process ${relativePath}: ${error.message}`);
        }
    }

    /**
     * Determine file type based on extension and path
     */
    getFileType(relativePath, ext) {
        const basename = path.basename(relativePath);
        
        // Scripts
        if (ext === '.sh' || ext === '.bash') return 'script';
        
        // Documentation
        if (ext === '.md' || basename === 'README') return 'doc';
        
        // Configuration
        if (ext === '.yaml' || ext === '.yml') return 'config';
        if (ext === '.json' && !relativePath.includes('package-lock')) return 'config';
        if (ext === '.toml' || ext === '.ini' || ext === '.conf') return 'config';
        
        // TODO files
        if (basename.toLowerCase().includes('todo') || ext === '.todo') return 'todo';
        
        // Template files
        if (relativePath.includes('.j2') || relativePath.includes('template')) return 'template';
        
        return null; // Skip other file types
    }

    /**
     * Extract title from file content
     */
    extractTitle(basename, content, fileType) {
        // Remove extension for cleaner title
        let title = basename.replace(/\.[^/.]+$/, '');
        
        if (fileType === 'doc') {
            // Look for markdown title (# Title)
            const titleMatch = content.match(/^#\s+(.+)$/m);
            if (titleMatch) {
                title = titleMatch[1].trim();
            }
        } else if (fileType === 'script') {
            // Look for script description in comments
            const descMatch = content.match(/^#\s*(.+)$/m);
            if (descMatch && !descMatch[1].startsWith('!')) {
                title = descMatch[1].trim();
            }
        }
        
        return title;
    }

    /**
     * Extract summary from file content
     */
    extractSummary(content, fileType) {
        const lines = content.split('\n').filter(line => line.trim());
        
        if (fileType === 'doc') {
            // Find first paragraph after title
            let foundTitle = false;
            for (const line of lines) {
                if (line.startsWith('#')) {
                    foundTitle = true;
                    continue;
                }
                if (foundTitle && line.trim() && !line.startsWith('#')) {
                    return line.trim().substring(0, 200) + (line.length > 200 ? '...' : '');
                }
            }
        } else if (fileType === 'script') {
            // Look for description in initial comments
            const comments = [];
            for (const line of lines) {
                if (line.startsWith('#') && !line.startsWith('#!/')) {
                    comments.push(line.replace(/^#\s*/, ''));
                } else if (line.trim() && !line.startsWith('#')) {
                    break;
                }
            }
            if (comments.length > 0) {
                return comments.join(' ').substring(0, 200) + (comments.join(' ').length > 200 ? '...' : '');
            }
        }
        
        // Fallback: first few non-empty lines
        const firstLines = lines.slice(0, 3).join(' ').trim();
        return firstLines.substring(0, 200) + (firstLines.length > 200 ? '...' : '');
    }

    /**
     * Extract tags from file path and content
     */
    extractTags(relativePath, content, fileType) {
        const tags = [];
        
        // Path-based tags
        const pathParts = relativePath.split('/');
        for (const part of pathParts) {
            if (part !== '.' && part !== '..' && !part.includes('.')) {
                tags.push(part);
            }
        }
        
        // Content-based tags for scripts
        if (fileType === 'script') {
            if (content.includes('kubectl')) tags.push('kubernetes');
            if (content.includes('docker')) tags.push('docker');
            if (content.includes('ansible')) tags.push('ansible');
            if (content.includes('prometheus') || content.includes('grafana')) tags.push('monitoring');
            if (content.includes('jellyfin')) tags.push('jellyfin');
            if (content.includes('flannel') || content.includes('cni')) tags.push('networking');
            if (content.includes('kubeadm')) tags.push('cluster-setup');
        }
        
        // Content-based tags for docs
        if (fileType === 'doc') {
            if (content.toLowerCase().includes('troubleshoot')) tags.push('troubleshooting');
            if (content.toLowerCase().includes('guide')) tags.push('guide');
            if (content.toLowerCase().includes('fix')) tags.push('fix');
            if (content.toLowerCase().includes('setup')) tags.push('setup');
        }
        
        return [...new Set(tags)]; // Remove duplicates
    }

    /**
     * Extract relationships between files
     */
    async extractRelationships() {
        console.log('🔗 Extracting relationships...');
        
        for (const node of this.nodes) {
            try {
                const fullPath = path.join(this.repoPath, node.path);
                const content = fs.readFileSync(fullPath, 'utf8');
                
                // Find file references in content
                const references = this.findFileReferences(content, node.path);
                
                for (const ref of references) {
                    const targetNode = this.findNodeByPath(ref.path);
                    if (targetNode && targetNode.id !== node.id) {
                        this.edges.push({
                            from: node.id,
                            to: targetNode.id,
                            relation: ref.type,
                            context: ref.context
                        });
                    }
                }
            } catch (error) {
                console.warn(`⚠️  Could not extract relationships for ${node.path}: ${error.message}`);
            }
        }
    }

    /**
     * Find references to other files in content
     */
    findFileReferences(content, currentPath) {
        const references = [];
        const lines = content.split('\n');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            
            // Script calls (./script.sh, scripts/script.sh)
            const scriptMatches = line.match(/\.\/([^"\s]+\.sh)|([^"\s]*scripts\/[^"\s]+\.sh)/g);
            if (scriptMatches) {
                for (const match of scriptMatches) {
                    const cleanPath = match.replace(/^\.\//, '');
                    references.push({
                        path: cleanPath,
                        type: 'calls',
                        context: line.trim()
                    });
                }
            }
            
            // Markdown links [text](file.md)
            const mdMatches = line.match(/\[([^\]]+)\]\(([^)]+\.md[^)]*)\)/g);
            if (mdMatches) {
                for (const match of mdMatches) {
                    const pathMatch = match.match(/\(([^)]+\.md[^)]*)\)/);
                    if (pathMatch) {
                        let refPath = pathMatch[1];
                        // Handle relative paths
                        if (refPath.startsWith('./')) {
                            refPath = path.join(path.dirname(currentPath), refPath.substring(2));
                        } else if (!refPath.startsWith('/')) {
                            refPath = path.join(path.dirname(currentPath), refPath);
                        }
                        references.push({
                            path: refPath.replace(/^\//, ''),
                            type: 'references',
                            context: line.trim()
                        });
                    }
                }
            }
            
            // YAML file references
            const yamlMatches = line.match(/([^"\s]+\.ya?ml)/g);
            if (yamlMatches) {
                for (const match of yamlMatches) {
                    if (!match.includes('http') && !match.includes('://')) {
                        references.push({
                            path: match,
                            type: 'references',
                            context: line.trim()
                        });
                    }
                }
            }
            
            // File mentions in comments or text
            const fileMatches = line.match(/([a-zA-Z0-9_-]+\.(sh|md|yaml|yml|json))/g);
            if (fileMatches) {
                for (const match of fileMatches) {
                    references.push({
                        path: match,
                        type: 'mentions',
                        context: line.trim()
                    });
                }
            }
        }
        
        return references;
    }

    /**
     * Find node by file path (handles partial matches)
     */
    findNodeByPath(searchPath) {
        // Direct match
        if (this.nodeMap.has(searchPath)) {
            return this.nodeMap.get(searchPath);
        }
        
        // Partial match - find by filename
        const basename = path.basename(searchPath);
        for (const [nodePath, node] of this.nodeMap) {
            if (path.basename(nodePath) === basename) {
                return node;
            }
        }
        
        return null;
    }

    /**
     * Generate unique ID for file
     */
    generateId(filePath) {
        return crypto.createHash('md5').update(filePath).digest('hex').substring(0, 8);
    }

    /**
     * Get statistics about extracted data
     */
    getStats() {
        const stats = {
            byType: {},
            totalSize: 0,
            averageSize: 0
        };
        
        for (const node of this.nodes) {
            stats.byType[node.type] = (stats.byType[node.type] || 0) + 1;
            stats.totalSize += node.sizeBytes;
        }
        
        stats.averageSize = Math.round(stats.totalSize / this.nodes.length);
        
        return stats;
    }

    /**
     * Write output to JSON file
     */
    async writeOutput(data) {
        const outputDir = path.join(this.repoPath, 'src', 'data');
        const outputFile = path.join(outputDir, 'repo_index.json');
        
        // Ensure output directory exists
        fs.mkdirSync(outputDir, { recursive: true });
        
        // Write formatted JSON
        fs.writeFileSync(outputFile, JSON.stringify(data, null, 2));
        
        console.log(`📄 Output written to: ${outputFile}`);
    }
}

// CLI execution
if (require.main === module) {
    const repoPath = process.argv[2] || process.cwd();
    const extractor = new RepoDataExtractor(repoPath);
    extractor.extract().catch(console.error);
}

module.exports = RepoDataExtractor;
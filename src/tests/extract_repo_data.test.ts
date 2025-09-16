import { describe, it, expect, beforeEach } from 'vitest';
import RepositoryExtractor from '../scripts/extract_repo_data.js';
import fs from 'fs';
import path from 'path';

describe('Repository Data Extraction', () => {
  let extractor: RepositoryExtractor;
  
  beforeEach(() => {
    extractor = new RepositoryExtractor();
  });

  it('should extract repository data', () => {
    const result = extractor.extract();
    
    expect(result).toHaveProperty('metadata');
    expect(result).toHaveProperty('nodes');
    expect(result).toHaveProperty('edges');
    expect(result.metadata.nodeCount).toBeGreaterThan(0);
  });

  it('should find deploy-cluster.sh', () => {
    const result = extractor.extract();
    const deployScript = result.nodes.find(node => 
      node.path.includes('deploy-cluster.sh')
    );
    
    expect(deployScript).toBeDefined();
    expect(deployScript?.type).toBe('script');
  });

  it('should find README.md', () => {
    const result = extractor.extract();
    const readme = result.nodes.find(node => 
      node.title === 'README.md' && !node.path.includes('/')
    );
    
    expect(readme).toBeDefined();
    expect(readme?.type).toBe('doc');
  });

  it('should find jellyfin-network-fix.md', () => {
    const result = extractor.extract();
    const jellyfinDoc = result.nodes.find(node => 
      node.path.includes('jellyfin-network-fix.md')
    );
    
    expect(jellyfinDoc).toBeDefined();
    expect(jellyfinDoc?.type).toBe('doc');
  });

  it('should create connections between related files', () => {
    const result = extractor.extract();
    
    expect(result.edges.length).toBeGreaterThan(0);
    
    // Check for specific relationships
    const deployScriptNode = result.nodes.find(node => 
      node.path.includes('deploy-cluster.sh')
    );
    
    if (deployScriptNode) {
      const connectionsFromDeploy = result.edges.filter(edge => 
        edge.from === deployScriptNode.id
      );
      expect(connectionsFromDeploy.length).toBeGreaterThan(0);
    }
  });

  it('should generate valid JSON output', () => {
    const outputPath = path.join(__dirname, '../data/repo_index.json');
    
    // Run extraction
    extractor.extract();
    
    // Verify file exists and is valid JSON
    expect(fs.existsSync(outputPath)).toBe(true);
    
    const content = fs.readFileSync(outputPath, 'utf8');
    const data = JSON.parse(content);
    
    expect(data).toHaveProperty('metadata');
    expect(data).toHaveProperty('nodes');
    expect(data).toHaveProperty('edges');
    expect(Array.isArray(data.nodes)).toBe(true);
    expect(Array.isArray(data.edges)).toBe(true);
  });
});
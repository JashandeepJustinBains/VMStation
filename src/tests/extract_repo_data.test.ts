import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import RepoDataExtractor from '../scripts/extract_repo_data.js';
import fs from 'fs';
import path from 'path';

describe('Repository Data Extraction', () => {
  let tempDir: string;
  let extractor: RepoDataExtractor;

  beforeEach(() => {
    // Create temporary test directory
    tempDir = path.join(process.cwd(), 'tests', 'temp');
    if (!fs.existsSync(tempDir)) {
      fs.mkdirSync(tempDir, { recursive: true });
    }
    extractor = new RepoDataExtractor(tempDir);
  });

  it('should extract script files correctly', async () => {
    // Create test script file
    const scriptContent = `#!/bin/bash
# Test deployment script
# This script deploys the test infrastructure

echo "Deploying test infrastructure"
kubectl apply -f manifests/test.yaml
./scripts/validate-test.sh`;

    const scriptPath = path.join(tempDir, 'test-deploy.sh');
    fs.writeFileSync(scriptPath, scriptContent);

    await extractor.scanDirectory(tempDir);

    const scriptNode = extractor.nodes.find(node => node.path === 'test-deploy.sh');
    expect(scriptNode).toBeDefined();
    expect(scriptNode?.type).toBe('script');
    expect(scriptNode?.title).toContain('test-deploy'); // Uses filename when no clear description found
    expect(scriptNode?.tags).toContain('kubernetes');
  });

  it('should extract markdown documentation files', async () => {
    const docContent = `# Test Documentation

This is a comprehensive guide for testing the VMStation deployment.

## Getting Started

Follow these steps to set up your test environment.`;

    const docPath = path.join(tempDir, 'test-guide.md');
    fs.writeFileSync(docPath, docContent);

    await extractor.scanDirectory(tempDir);

    const docNode = extractor.nodes.find(node => node.path === 'test-guide.md');
    expect(docNode).toBeDefined();
    expect(docNode?.type).toBe('doc');
    expect(docNode?.title).toBe('Test Documentation');
    expect(docNode?.summary).toContain('comprehensive guide');
  });

  it('should extract YAML configuration files', async () => {
    const yamlContent = `apiVersion: v1
kind: Service
metadata:
  name: test-service
  namespace: test
spec:
  selector:
    app: test
  ports:
    - port: 80
      targetPort: 8080`;

    const yamlPath = path.join(tempDir, 'test-service.yaml');
    fs.writeFileSync(yamlPath, yamlContent);

    await extractor.scanDirectory(tempDir);

    const yamlNode = extractor.nodes.find(node => node.path === 'test-service.yaml');
    expect(yamlNode).toBeDefined();
    expect(yamlNode?.type).toBe('config');
  });

  it('should detect relationships between files', async () => {
    // Create script that references other files
    const mainScript = `#!/bin/bash
# Main deployment script
./scripts/setup-cluster.sh
kubectl apply -f manifests/monitoring.yaml
# See documentation at docs/deployment-guide.md`;

    const referencedScript = `#!/bin/bash
# Cluster setup script
kubeadm init`;

    const referencedYaml = `apiVersion: v1
kind: Namespace
metadata:
  name: monitoring`;

    const referencedDoc = `# Deployment Guide
Complete deployment instructions.`;

    // Create directory structure
    fs.mkdirSync(path.join(tempDir, 'scripts'), { recursive: true });
    fs.mkdirSync(path.join(tempDir, 'manifests'), { recursive: true });
    fs.mkdirSync(path.join(tempDir, 'docs'), { recursive: true });

    fs.writeFileSync(path.join(tempDir, 'deploy.sh'), mainScript);
    fs.writeFileSync(path.join(tempDir, 'scripts', 'setup-cluster.sh'), referencedScript);
    fs.writeFileSync(path.join(tempDir, 'manifests', 'monitoring.yaml'), referencedYaml);
    fs.writeFileSync(path.join(tempDir, 'docs', 'deployment-guide.md'), referencedDoc);

    await extractor.scanDirectory(tempDir);
    await extractor.extractRelationships();

    // Check that relationships were detected
    const mainScriptNode = extractor.nodes.find(node => node.path === 'deploy.sh');
    expect(mainScriptNode).toBeDefined();

    const edges = extractor.edges.filter(edge => edge.from === mainScriptNode?.id);
    expect(edges.length).toBeGreaterThan(0);

    // Should have relationships to referenced files
    const hasScriptCall = edges.some(edge => edge.relation === 'calls');
    const hasYamlReference = edges.some(edge => edge.relation === 'references');
    expect(hasScriptCall || hasYamlReference).toBe(true);
  });

  it('should generate valid JSON output', async () => {
    // Create minimal test files
    fs.writeFileSync(path.join(tempDir, 'README.md'), '# Test Project\nThis is a test.');
    fs.writeFileSync(path.join(tempDir, 'deploy.sh'), '#!/bin/bash\necho "deploy"');

    const result = await extractor.extract();

    expect(result).toBeDefined();
    expect(result.nodes).toBeInstanceOf(Array);
    expect(result.edges).toBeInstanceOf(Array);
    expect(result.metadata).toBeDefined();
    expect(result.metadata.totalFiles).toBeGreaterThan(0);

    // Verify output file was created
    const outputPath = path.join(tempDir, 'src', 'data', 'repo_index.json');
    expect(fs.existsSync(outputPath)).toBe(true);

    const outputData = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
    expect(outputData.nodes.length).toBeGreaterThan(0);
  });

  it('should handle file type detection correctly', () => {
    expect(extractor.getFileType('test.sh', '.sh')).toBe('script');
    expect(extractor.getFileType('README.md', '.md')).toBe('doc');
    expect(extractor.getFileType('config.yaml', '.yaml')).toBe('config');
    expect(extractor.getFileType('TODO.md', '.md')).toBe('doc'); // TODO.md is detected as doc, which is correct
    expect(extractor.getFileType('template.j2', '.j2')).toBe('template'); // .j2 files are templates
    expect(extractor.getFileType('unknown.txt', '.txt')).toBeNull();
  });

  it('should skip inappropriate files', () => {
    expect(extractor.shouldSkip('.git/config')).toBe(true);
    expect(extractor.shouldSkip('node_modules/package/index.js')).toBe(true);
    expect(extractor.shouldSkip('.hidden-file')).toBe(true);
    expect(extractor.shouldSkip('dist/build.js')).toBe(true);
    expect(extractor.shouldSkip('regular-file.md')).toBe(false);
  });

  // Cleanup
  afterEach(() => {
    if (fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true });
    }
  });
});
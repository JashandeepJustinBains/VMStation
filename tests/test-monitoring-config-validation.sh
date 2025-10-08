#!/usr/bin/env bash
# Validation script: Verify monitoring stack configuration
# Tests manifest syntax, Prometheus config, and deployment order
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Monitoring Stack Configuration Validator${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

FAILED=0
PASSED=0
WARNINGS=0

log_pass() {
  echo -e "${GREEN}✅ PASS${NC}: $*"
  PASSED=$((PASSED + 1))
}

log_fail() {
  echo -e "${RED}❌ FAIL${NC}: $*"
  FAILED=$((FAILED + 1))
}

log_warn() {
  echo -e "${YELLOW}⚠️  WARN${NC}: $*"
  WARNINGS=$((WARNINGS + 1))
}

log_info() {
  echo -e "${BLUE}ℹ️  INFO${NC}: $*"
}

# Test 1: Check all monitoring manifests exist
echo "[1/8] Checking monitoring manifests..."
REQUIRED_MANIFESTS=(
  "manifests/monitoring/node-exporter.yaml"
  "manifests/monitoring/kube-state-metrics.yaml"
  "manifests/monitoring/loki.yaml"
  "manifests/monitoring/prometheus.yaml"
  "manifests/monitoring/grafana.yaml"
  "manifests/monitoring/ipmi-exporter.yaml"
)

for manifest in "${REQUIRED_MANIFESTS[@]}"; do
  if [[ -f "$manifest" ]]; then
    log_pass "Found $manifest"
  else
    log_fail "Missing $manifest"
  fi
done
echo ""

# Test 2: Validate YAML syntax
echo "[2/8] Validating YAML syntax..."
if command -v yamllint >/dev/null 2>&1; then
  for manifest in "${REQUIRED_MANIFESTS[@]}"; do
    # Only fail on actual errors, not warnings
    if yamllint "$manifest" 2>&1 | grep -q "::error"; then
      log_fail "YAML syntax error: $(basename $manifest)"
    else
      log_pass "YAML syntax valid: $(basename $manifest)"
    fi
  done
else
  log_warn "yamllint not installed, skipping syntax validation"
fi
echo ""

# Test 3: Check Prometheus configuration
echo "[3/8] Validating Prometheus configuration..."
if command -v python3 >/dev/null 2>&1; then
  PROM_JOBS=$(python3 -c "
import yaml
with open('manifests/monitoring/prometheus.yaml', 'r') as f:
    docs = list(yaml.safe_load_all(f))
    for doc in docs:
        if doc.get('kind') == 'ConfigMap' and doc.get('metadata', {}).get('name') == 'prometheus-config':
            prom_config = yaml.safe_load(doc['data']['prometheus.yml'])
            print(len(prom_config['scrape_configs']))
            for job in prom_config['scrape_configs']:
                print(job['job_name'])
" 2>&1)
  
  if [[ $? -eq 0 ]]; then
    JOB_COUNT=$(echo "$PROM_JOBS" | head -1)
    log_pass "Prometheus config valid with $JOB_COUNT scrape jobs"
    
    # Check for required jobs
    for required_job in "node-exporter" "kube-state-metrics" "kubernetes-nodes" "kubernetes-cadvisor"; do
      if echo "$PROM_JOBS" | grep -q "$required_job"; then
        log_pass "Scrape job configured: $required_job"
      else
        log_fail "Missing scrape job: $required_job"
      fi
    done
  else
    log_fail "Failed to parse Prometheus config"
  fi
else
  log_warn "Python3 not installed, skipping Prometheus config validation"
fi
echo ""

# Test 4: Check Grafana datasources
echo "[4/8] Validating Grafana datasources..."
if command -v python3 >/dev/null 2>&1; then
  DATASOURCES=$(python3 -c "
import yaml
with open('manifests/monitoring/grafana.yaml', 'r') as f:
    docs = list(yaml.safe_load_all(f))
    for doc in docs:
        if doc.get('kind') == 'ConfigMap' and doc.get('metadata', {}).get('name') == 'grafana-datasources':
            ds_config = yaml.safe_load(doc['data']['prometheus.yaml'])
            for ds in ds_config['datasources']:
                print(f'{ds[\"name\"]},{ds[\"type\"]},{ds[\"url\"]}')
" 2>&1)
  
  if [[ $? -eq 0 ]]; then
    if echo "$DATASOURCES" | grep -q "Prometheus,prometheus,http://prometheus:9090"; then
      log_pass "Prometheus datasource configured correctly"
    else
      log_fail "Prometheus datasource misconfigured"
    fi
    
    if echo "$DATASOURCES" | grep -q "Loki,loki,http://loki:3100"; then
      log_pass "Loki datasource configured correctly"
    else
      log_fail "Loki datasource misconfigured"
    fi
  else
    log_fail "Failed to parse Grafana datasources"
  fi
else
  log_warn "Python3 not installed, skipping datasource validation"
fi
echo ""

# Test 5: Check deployment playbook includes all components
echo "[5/8] Validating deployment playbook..."
DEPLOY_PLAYBOOK="ansible/playbooks/deploy-cluster.yaml"

if [[ -f "$DEPLOY_PLAYBOOK" ]]; then
  log_pass "Found deployment playbook"
  
  # Check for deployment tasks
  for component in "Node Exporter" "Kube State Metrics" "Loki" "Prometheus" "Grafana"; do
    if grep -q "Deploy.*$component" "$DEPLOY_PLAYBOOK"; then
      log_pass "Deployment task found: $component"
    else
      log_fail "Missing deployment task: $component"
    fi
  done
  
  # Check for health checks
  if grep -qi "Wait for.*Node Exporter" "$DEPLOY_PLAYBOOK"; then
    log_pass "Health check found: node-exporter"
  else
    log_warn "No health check for: node-exporter"
  fi
  
  if grep -qi "Wait for.*Kube State Metrics" "$DEPLOY_PLAYBOOK"; then
    log_pass "Health check found: kube-state-metrics"
  else
    log_warn "No health check for: kube-state-metrics"
  fi
  
  for component in "loki" "prometheus" "grafana"; do
    if grep -qi "Wait for.*$component" "$DEPLOY_PLAYBOOK"; then
      log_pass "Health check found: $component"
    else
      log_warn "No health check for: $component"
    fi
  done
else
  log_fail "Deployment playbook not found"
fi
echo ""

# Test 6: Verify node-exporter DaemonSet configuration
echo "[6/8] Validating node-exporter DaemonSet..."
if command -v python3 >/dev/null 2>&1; then
  NODE_EXP_CHECK=$(python3 -c "
import yaml
with open('manifests/monitoring/node-exporter.yaml', 'r') as f:
    docs = list(yaml.safe_load_all(f))
    for doc in docs:
        if doc.get('kind') == 'DaemonSet':
            spec = doc['spec']['template']['spec']
            if spec.get('hostNetwork'):
                print('hostNetwork:true')
            containers = spec['containers']
            for c in containers:
                for port in c.get('ports', []):
                    if port.get('hostPort') == 9100:
                        print('hostPort:9100')
" 2>&1)
  
  if echo "$NODE_EXP_CHECK" | grep -q "hostNetwork:true"; then
    log_pass "Node-exporter uses hostNetwork"
  else
    log_fail "Node-exporter missing hostNetwork"
  fi
  
  if echo "$NODE_EXP_CHECK" | grep -q "hostPort:9100"; then
    log_pass "Node-exporter exposes hostPort 9100"
  else
    log_fail "Node-exporter missing hostPort 9100"
  fi
else
  log_warn "Python3 not installed, skipping node-exporter validation"
fi
echo ""

# Test 7: Check ServiceAccount and RBAC
echo "[7/8] Validating RBAC configuration..."
for manifest in "${REQUIRED_MANIFESTS[@]}"; do
  if grep -q "kind: ServiceAccount" "$manifest"; then
    COMPONENT=$(basename "$manifest" .yaml)
    log_pass "ServiceAccount defined in $COMPONENT"
  fi
  
  if grep -q "kind: ClusterRole" "$manifest"; then
    COMPONENT=$(basename "$manifest" .yaml)
    log_pass "ClusterRole defined in $COMPONENT"
  fi
done
echo ""

# Test 8: Verify test scripts exist
echo "[8/8] Checking validation test scripts..."
TEST_SCRIPTS=(
  "tests/test-comprehensive.sh"
  "tests/test-monitoring-exporters-health.sh"
  "tests/test-loki-validation.sh"
)

for script in "${TEST_SCRIPTS[@]}"; do
  if [[ -x "$script" ]]; then
    log_pass "Test script executable: $(basename $script)"
  elif [[ -f "$script" ]]; then
    log_warn "Test script exists but not executable: $(basename $script)"
  else
    log_fail "Test script missing: $(basename $script)"
  fi
done
echo ""

# Summary
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Validation Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Passed:${NC}   $PASSED"
echo -e "${RED}Failed:${NC}   $FAILED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}✅ All critical validations passed!${NC}"
  echo ""
  echo "The monitoring stack configuration is valid and ready for deployment."
  echo ""
  echo "Next steps:"
  echo "  1. Deploy: ./deploy.sh all --with-rke2 --yes"
  echo "  2. Test: ./tests/test-monitoring-exporters-health.sh"
  echo "  3. Access Grafana: http://192.168.4.63:30300"
  exit 0
else
  echo -e "${RED}❌ Validation failed with $FAILED errors${NC}"
  echo ""
  echo "Please fix the errors above before deploying."
  exit 1
fi

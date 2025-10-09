#!/usr/bin/env bash
# Test script: Validate Loki ConfigMap matches repository version
# Prevents configuration drift between repository and cluster
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
cd "$REPO_ROOT"

# Configuration
MASTERNODE_IP="${MASTERNODE_IP:-192.168.4.63}"

echo "========================================="
echo "VMStation Loki ConfigMap Drift Test"
echo "Validating in-cluster config matches repo"
echo "========================================="
echo ""

FAILED=0
PASSED=0
WARNINGS=0

# Logging functions
log_pass() {
  echo "✅ PASS: $*"
  PASSED=$((PASSED + 1))
}

log_fail() {
  echo "❌ FAIL: $*"
  FAILED=$((FAILED + 1))
}

log_warn() {
  echo "⚠️  WARN: $*"
  WARNINGS=$((WARNINGS + 1))
}

log_info() {
  echo "ℹ️  INFO: $*"
}

# Test 1: Verify Loki manifest exists in repository
echo "[1/5] Checking Loki manifest in repository..."
if [[ -f "manifests/monitoring/loki.yaml" ]]; then
  log_pass "Loki manifest exists in repository"
else
  log_fail "Loki manifest not found in repository"
  exit 1
fi
echo ""

# Test 2: Extract ConfigMap from repository file
echo "[2/5] Extracting ConfigMap from repository..."
REPO_CONFIG=$(python3 -c "
import yaml
import sys

try:
    with open('manifests/monitoring/loki.yaml', 'r') as f:
        docs = list(yaml.safe_load_all(f))
        for doc in docs:
            if doc and doc.get('kind') == 'ConfigMap' and doc.get('metadata', {}).get('name') == 'loki-config':
                config_data = doc.get('data', {}).get('local-config.yaml', '')
                print(config_data)
                sys.exit(0)
    print('')
    sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)

if [[ $? -eq 0 && -n "$REPO_CONFIG" ]]; then
  log_pass "Extracted ConfigMap from repository"
else
  log_fail "Failed to extract ConfigMap from repository"
  exit 1
fi
echo ""

# Test 3: Check for invalid fields in repository config
echo "[3/5] Validating repository config has no invalid fields..."
if echo "$REPO_CONFIG" | grep -q "wal_directory"; then
  log_fail "Repository config contains invalid 'wal_directory' field"
else
  log_pass "Repository config does not contain 'wal_directory' field"
fi

# Check that storage_config section exists and is valid
if echo "$REPO_CONFIG" | grep -q "storage_config:"; then
  log_pass "Repository config has storage_config section"
else
  log_fail "Repository config missing storage_config section"
fi
echo ""

# Test 4: Check in-cluster ConfigMap (requires cluster access)
echo "[4/5] Checking in-cluster ConfigMap..."
CLUSTER_CONFIG=$(ssh -o ConnectTimeout=5 root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get configmap loki-config -n monitoring -o yaml 2>/dev/null" 2>/dev/null || echo "")

if [[ -n "$CLUSTER_CONFIG" ]]; then
  log_pass "Retrieved in-cluster ConfigMap"
  
  # Extract the actual config data
  CLUSTER_CONFIG_DATA=$(echo "$CLUSTER_CONFIG" | python3 -c "
import yaml
import sys

try:
    data = yaml.safe_load(sys.stdin)
    config_data = data.get('data', {}).get('local-config.yaml', '')
    print(config_data)
except Exception as e:
    print('', file=sys.stderr)
    sys.exit(1)
" 2>&1)
  
  if [[ -n "$CLUSTER_CONFIG_DATA" ]]; then
    # Check for invalid fields
    if echo "$CLUSTER_CONFIG_DATA" | grep -q "wal_directory"; then
      log_fail "In-cluster ConfigMap contains invalid 'wal_directory' field"
      log_info "Run: ansible-playbook ansible/playbooks/fix-loki-config.yaml to fix"
    else
      log_pass "In-cluster ConfigMap does not contain 'wal_directory' field"
    fi
    
    # Compare configs (normalize whitespace)
    REPO_NORMALIZED=$(echo "$REPO_CONFIG" | sed 's/^[[:space:]]*//' | grep -v '^$' | sort)
    CLUSTER_NORMALIZED=$(echo "$CLUSTER_CONFIG_DATA" | sed 's/^[[:space:]]*//' | grep -v '^$' | sort)
    
    if [[ "$REPO_NORMALIZED" == "$CLUSTER_NORMALIZED" ]]; then
      log_pass "In-cluster ConfigMap matches repository version"
    else
      log_warn "In-cluster ConfigMap differs from repository version"
      log_info "This may be expected if customizations were applied"
      log_info "Run: ansible-playbook ansible/playbooks/fix-loki-config.yaml to sync"
    fi
  else
    log_fail "Failed to extract config data from cluster ConfigMap"
  fi
else
  log_warn "Could not retrieve in-cluster ConfigMap (cluster not accessible)"
  log_info "This test requires SSH access to masternode at ${MASTERNODE_IP}"
fi
echo ""

# Test 5: Validate Loki schema config for boltdb-shipper compatibility
echo "[5/5] Validating Loki schema configuration..."
if echo "$REPO_CONFIG" | grep -A 10 "schema_config:" | grep -q "period: 24h"; then
  log_pass "Loki schema uses 24h index period (boltdb-shipper compatible)"
elif echo "$REPO_CONFIG" | grep -A 10 "schema_config:" | grep -q "period: 168h"; then
  log_fail "Loki schema uses 168h period (incompatible with boltdb-shipper)"
  log_info "boltdb-shipper requires period: 24h"
else
  log_warn "Could not verify Loki schema period configuration"
fi
echo ""

# Summary
echo "========================================="
echo "Test Results Summary"
echo "========================================="
echo "Passed:   $PASSED"
echo "Failed:   $FAILED"
echo "Warnings: $WARNINGS"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo "✅ Loki ConfigMap validation passed!"
  echo ""
  echo "The repository and cluster configurations are in sync."
  echo ""
  exit 0
else
  echo "❌ Loki ConfigMap validation has issues."
  echo ""
  echo "Common fixes:"
  echo "  1. Reapply ConfigMap: ansible-playbook ansible/playbooks/fix-loki-config.yaml"
  echo "  2. Check Loki logs: kubectl logs -n monitoring -l app=loki"
  echo "  3. Verify schema config uses period: 24h (not 168h)"
  echo ""
  exit 1
fi

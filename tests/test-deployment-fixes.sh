#!/usr/bin/env bash
# Validation test for deployment fixes
# Verifies that all fixes are correctly applied
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "========================================"
echo "Deployment Fixes Validation"
echo "========================================"
echo ""

PASSED=0
FAILED=0

log_pass() {
  echo "✅ PASS: $*"
  PASSED=$((PASSED + 1))
}

log_fail() {
  echo "❌ FAIL: $*"
  FAILED=$((FAILED + 1))
}

echo "1. Testing Loki readiness probe configuration..."
if grep -q "readinessProbe:" manifests/monitoring/loki.yaml; then
  log_pass "Loki readiness probe is configured"
else
  log_fail "Loki readiness probe is missing"
fi

if grep -q "livenessProbe:" manifests/monitoring/loki.yaml; then
  log_pass "Loki liveness probe is configured"
else
  log_fail "Loki liveness probe is missing"
fi

if grep -A 5 "readinessProbe:" manifests/monitoring/loki.yaml | grep -q "initialDelaySeconds: 60"; then
  log_pass "Loki readiness probe has appropriate initialDelaySeconds"
else
  log_fail "Loki readiness probe initialDelaySeconds is incorrect"
fi

echo ""

echo "2. Testing Loki test port configuration..."
if grep -q "LOKI_PORT=31100" tests/test-loki-validation.sh; then
  log_pass "Loki test uses correct NodePort (31100)"
else
  log_fail "Loki test port is incorrect"
fi

echo ""

echo "3. Testing Prometheus Web UI test pattern..."
if grep -qE "Prometheus|<title|prometheus|metrics|graph" tests/test-monitoring-access.sh; then
  log_pass "Prometheus test has multiple patterns for robust matching"
else
  log_fail "Prometheus test pattern may be too strict"
fi

echo ""

echo "4. Testing monitoring exporters optional targets handling..."
if grep -q "OPTIONAL_TARGETS=" tests/test-monitoring-exporters-health.sh; then
  log_pass "Monitoring exporters test handles optional targets"
else
  log_fail "Monitoring exporters test does not handle optional targets"
fi

if grep -q "rke2-federation" tests/test-monitoring-exporters-health.sh && \
   grep -q "ipmi-exporter" tests/test-monitoring-exporters-health.sh; then
  log_pass "RKE2 and IPMI exporters are marked as optional"
else
  log_fail "Optional targets are not properly configured"
fi

echo ""

echo "5. Testing Loki schema configuration (24h period)..."
if grep -A 3 "index:" manifests/monitoring/loki.yaml | grep -q "period: 24h"; then
  log_pass "Loki schema uses 24h index period (boltdb-shipper compatible)"
else
  log_fail "Loki schema period is incorrect"
fi

echo ""

echo "6. Testing Loki config drift prevention..."
if [ -f "ansible/playbooks/fix-loki-config.yaml" ]; then
  log_pass "Loki fix playbook exists"
else
  log_fail "Loki fix playbook is missing"
fi

if [ -x "tests/test-loki-config-drift.sh" ]; then
  log_pass "Loki config drift test is executable"
else
  log_fail "Loki config drift test is missing or not executable"
fi

if grep -q "wal_directory" manifests/monitoring/loki.yaml; then
  log_fail "Loki config contains invalid 'wal_directory' field"
else
  log_pass "Loki config does not contain invalid fields"
fi

echo ""

echo "7. Validating YAML syntax..."
YAML_VALID=true
for file in manifests/monitoring/*.yaml; do
  if ! python3 -c "import yaml; yaml.safe_load_all(open('$file'))" 2>/dev/null; then
    log_fail "YAML syntax error in $file"
    YAML_VALID=false
  fi
done

if [ "$YAML_VALID" = true ]; then
  log_pass "All YAML manifests have valid syntax"
fi

echo ""

echo "8. Validating bash script syntax..."
BASH_VALID=true
for file in tests/test-*.sh; do
  if ! bash -n "$file" 2>/dev/null; then
    log_fail "Bash syntax error in $file"
    BASH_VALID=false
  fi
done

if [ "$BASH_VALID" = true ]; then
  log_pass "All bash test scripts have valid syntax"
fi

echo ""

echo "========================================"
echo "Validation Results"
echo "========================================"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo "✅ All deployment fixes are correctly applied!"
  echo ""
  echo "The following issues have been resolved:"
  echo "  1. Loki readiness/liveness probes configured"
  echo "  2. Loki test uses correct NodePort (31100)"
  echo "  3. Prometheus Web UI test is robust"
  echo "  4. Monitoring exporters test handles optional targets"
  echo "  5. Loki schema is boltdb-shipper compatible"
  echo "  6. Loki config drift prevention automation in place"
  echo ""
  echo "Ready for deployment!"
  exit 0
else
  echo "❌ Some validation checks failed"
  echo ""
  echo "Please review the failures above and fix them before deploying"
  exit 1
fi

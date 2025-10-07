#!/usr/bin/env bash
# =============================================================================
# Test: Monitoring Stack Tolerations
# Validates that Prometheus and Grafana have proper tolerations for control-plane
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMETHEUS_YAML="$REPO_ROOT/manifests/monitoring/prometheus.yaml"
GRAFANA_YAML="$REPO_ROOT/manifests/monitoring/grafana.yaml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "Monitoring Stack Tolerations Test"
echo "========================================="
echo ""

FAILED=0

# Test 1: Check Prometheus has control-plane toleration
echo "[1/4] Checking Prometheus tolerations..."
if grep -A 3 "tolerations:" "$PROMETHEUS_YAML" | grep -q "node-role.kubernetes.io/control-plane"; then
    echo -e "  ${GREEN}✅ PASS${NC}: Prometheus has control-plane toleration"
else
    echo -e "  ${RED}❌ FAIL${NC}: Prometheus missing control-plane toleration"
    FAILED=$((FAILED + 1))
fi

# Test 2: Check Prometheus has nodeSelector
echo "[2/4] Checking Prometheus nodeSelector..."
if grep -q "node-role.kubernetes.io/control-plane:" "$PROMETHEUS_YAML"; then
    echo -e "  ${GREEN}✅ PASS${NC}: Prometheus has control-plane nodeSelector"
else
    echo -e "  ${RED}❌ FAIL${NC}: Prometheus missing control-plane nodeSelector"
    FAILED=$((FAILED + 1))
fi

# Test 3: Check Grafana has control-plane toleration
echo "[3/4] Checking Grafana tolerations..."
if grep -A 3 "tolerations:" "$GRAFANA_YAML" | grep -q "node-role.kubernetes.io/control-plane"; then
    echo -e "  ${GREEN}✅ PASS${NC}: Grafana has control-plane toleration"
else
    echo -e "  ${RED}❌ FAIL${NC}: Grafana missing control-plane toleration"
    FAILED=$((FAILED + 1))
fi

# Test 4: Check Grafana has nodeSelector
echo "[4/4] Checking Grafana nodeSelector..."
if grep -q "node-role.kubernetes.io/control-plane:" "$GRAFANA_YAML"; then
    echo -e "  ${GREEN}✅ PASS${NC}: Grafana has control-plane nodeSelector"
else
    echo -e "  ${RED}❌ FAIL${NC}: Grafana missing control-plane nodeSelector"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "========================================="
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests PASSED${NC}"
    echo "========================================="
    exit 0
else
    echo -e "${RED}❌ $FAILED test(s) FAILED${NC}"
    echo "========================================="
    exit 1
fi

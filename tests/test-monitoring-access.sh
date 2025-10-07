#!/usr/bin/env bash
# Test script: Validate monitoring endpoints are accessible without authentication
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Configuration
MASTERNODE_IP="${MASTERNODE_IP:-192.168.4.63}"
STORAGE_IP="${STORAGE_IP:-192.168.4.61}"
HOMELAB_IP="${HOMELAB_IP:-192.168.4.62}"
GRAFANA_PORT=30300
PROMETHEUS_PORT=30090
NODE_EXPORTER_PORT=9100

echo "========================================="
echo "VMStation Monitoring Access Test"
echo "Testing anonymous access to endpoints"
echo "========================================="
echo ""

FAILED=0
PASSED=0

# Test function
test_endpoint() {
  local name="$1"
  local url="$2"
  local expect_pattern="${3:-}"
  
  echo -n "Testing $name... "
  
  if response=$(curl -sf --max-time 10 "$url" 2>&1); then
    if [[ -z "$expect_pattern" ]] || echo "$response" | grep -q "$expect_pattern"; then
      echo "✅ PASS"
      PASSED=$((PASSED + 1))
      return 0
    else
      echo "❌ FAIL (unexpected response)"
      FAILED=$((FAILED + 1))
      return 1
    fi
  else
    echo "❌ FAIL (not accessible)"
    FAILED=$((FAILED + 1))
    return 1
  fi
}

# Test Grafana
echo "[1/8] Testing Grafana Access..."
test_endpoint "Grafana Web UI" \
  "http://${MASTERNODE_IP}:${GRAFANA_PORT}" \
  "Grafana"

test_endpoint "Grafana API (anonymous)" \
  "http://${MASTERNODE_IP}:${GRAFANA_PORT}/api/health" \
  "database"

echo ""

# Test Prometheus
echo "[2/8] Testing Prometheus Access..."
test_endpoint "Prometheus Web UI" \
  "http://${MASTERNODE_IP}:${PROMETHEUS_PORT}" \
  "Prometheus"

test_endpoint "Prometheus Health" \
  "http://${MASTERNODE_IP}:${PROMETHEUS_PORT}/-/healthy" \
  "Prometheus is Healthy"

test_endpoint "Prometheus Targets API" \
  "http://${MASTERNODE_IP}:${PROMETHEUS_PORT}/api/v1/targets" \
  "activeTargets"

test_endpoint "Prometheus Federation" \
  "http://${MASTERNODE_IP}:${PROMETHEUS_PORT}/federate?match[]={__name__=~\"up\"}" \
  "up{"

echo ""

# Test Node Exporters
echo "[3/8] Testing Node Exporter (Masternode)..."
test_endpoint "Node Exporter Metrics" \
  "http://${MASTERNODE_IP}:${NODE_EXPORTER_PORT}/metrics" \
  "node_cpu_seconds_total"

echo ""

echo "[4/8] Testing Node Exporter (Storage)..."
if test_endpoint "Node Exporter Metrics" \
  "http://${STORAGE_IP}:${NODE_EXPORTER_PORT}/metrics" \
  "node_cpu_seconds_total"; then
  :
else
  echo "  ⚠️  Storage node may not be accessible from this host"
fi

echo ""

# Test Grafana Datasources
echo "[5/8] Testing Grafana Datasources..."
if datasources=$(curl -sf "http://${MASTERNODE_IP}:${GRAFANA_PORT}/api/datasources" 2>&1); then
  if echo "$datasources" | grep -q "Prometheus"; then
    echo "Testing Prometheus datasource... ✅ PASS"
    PASSED=$((PASSED + 1))
  else
    echo "Testing Prometheus datasource... ❌ FAIL (not found)"
    FAILED=$((FAILED + 1))
  fi
else
  echo "Testing Grafana datasources API... ❌ FAIL (not accessible)"
  FAILED=$((FAILED + 1))
fi

echo ""

# Test Grafana Dashboards
echo "[6/8] Testing Grafana Dashboards..."
if dashboards=$(curl -sf "http://${MASTERNODE_IP}:${GRAFANA_PORT}/api/search?type=dash-db" 2>&1); then
  dashboard_count=$(echo "$dashboards" | grep -o "\"title\"" | wc -l)
  if [[ "$dashboard_count" -gt 0 ]]; then
    echo "Testing dashboard availability... ✅ PASS ($dashboard_count dashboards found)"
    PASSED=$((PASSED + 1))
  else
    echo "Testing dashboard availability... ⚠️  WARNING (no dashboards found)"
  fi
else
  echo "Testing Grafana dashboards API... ❌ FAIL (not accessible)"
  FAILED=$((FAILED + 1))
fi

echo ""

# Test Prometheus Metrics Collection
echo "[7/8] Testing Prometheus Metrics Collection..."
if metrics=$(curl -sf "http://${MASTERNODE_IP}:${PROMETHEUS_PORT}/api/v1/query?query=up" 2>&1); then
  if echo "$metrics" | grep -q '"status":"success"'; then
    metric_count=$(echo "$metrics" | grep -o '"metric"' | wc -l)
    echo "Testing metrics query... ✅ PASS ($metric_count targets)"
    PASSED=$((PASSED + 1))
  else
    echo "Testing metrics query... ❌ FAIL (query failed)"
    FAILED=$((FAILED + 1))
  fi
else
  echo "Testing Prometheus query API... ❌ FAIL (not accessible)"
  FAILED=$((FAILED + 1))
fi

echo ""

# Test Anonymous Access Specifically
echo "[8/8] Testing Anonymous Access Configuration..."
if grafana_config=$(curl -sf "http://${MASTERNODE_IP}:${GRAFANA_PORT}/api/frontend/settings" 2>&1); then
  if echo "$grafana_config" | grep -q '"anonymousEnabled":true'; then
    echo "Testing anonymous access enabled... ✅ PASS"
    PASSED=$((PASSED + 1))
  else
    echo "Testing anonymous access enabled... ❌ FAIL (not enabled)"
    FAILED=$((FAILED + 1))
    echo "  Hint: Check GF_AUTH_ANONYMOUS_ENABLED in Grafana deployment"
  fi
else
  echo "Testing Grafana settings API... ⚠️  WARNING (API may not expose this)"
fi

echo ""
echo "========================================="
echo "Test Results"
echo "========================================="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo "✅ All monitoring endpoints are accessible!"
  echo ""
  echo "Access URLs:"
  echo "  Grafana:    http://${MASTERNODE_IP}:${GRAFANA_PORT}"
  echo "  Prometheus: http://${MASTERNODE_IP}:${PROMETHEUS_PORT}"
  echo "  Node Metrics: http://${MASTERNODE_IP}:${NODE_EXPORTER_PORT}/metrics"
  echo ""
  exit 0
else
  echo "❌ Some tests failed. See details above."
  echo ""
  echo "Troubleshooting:"
  echo "  1. Verify monitoring pods are running:"
  echo "     kubectl get pods -n monitoring"
  echo "  2. Check service endpoints:"
  echo "     kubectl get svc -n monitoring"
  echo "  3. Review pod logs:"
  echo "     kubectl logs -n monitoring deployment/grafana"
  echo "     kubectl logs -n monitoring deployment/prometheus"
  echo ""
  exit 1
fi

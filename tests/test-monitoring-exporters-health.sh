#!/usr/bin/env bash
# Test script: Validate monitoring exporters and dashboard health
# Tests IPMI exporter, node-exporter, Prometheus targets, and dashboard metrics
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
IPMI_EXPORTER_PORT=9290

echo "========================================="
echo "VMStation Monitoring Exporters Health"
echo "Validating exporters, targets, and dashboards"
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

# Concise curl test function
curl_test() {
  local name="$1"
  local url="$2"
  local expect_pattern="${3:-}"
  
  if response=$(curl -sf --max-time 10 "$url" 2>&1); then
    if [[ -z "$expect_pattern" ]] || echo "$response" | grep -q "$expect_pattern"; then
      echo "success"
      return 0
    else
      echo "failure"
      return 1
    fi
  else
    echo "error"
    return 1
  fi
}

# Test 1: Prometheus targets health
echo "[1/8] Testing Prometheus targets..."
if targets=$(curl -sf "http://${MASTERNODE_IP}:${PROMETHEUS_PORT}/api/v1/targets" 2>&1); then
  log_pass "Prometheus targets API accessible"
  
  # Parse and check target health
  DOWN_TARGETS=$(echo "$targets" | grep -o '"health":"down"' | wc -l || echo "0")
  UP_TARGETS=$(echo "$targets" | grep -o '"health":"up"' | wc -l || echo "0")
  
  log_info "Targets UP: $UP_TARGETS, DOWN: $DOWN_TARGETS"
  
  if [[ "$DOWN_TARGETS" -gt 0 ]]; then
    log_fail "$DOWN_TARGETS targets are DOWN"
    
    # List down targets for debugging
    echo "$targets" | grep -B2 '"health":"down"' | grep '"job":' | sed 's/.*"job":"\([^"]*\)".*/  - \1/' | sort -u || true
  else
    log_pass "All Prometheus targets are UP"
  fi
else
  log_fail "Cannot access Prometheus targets API"
fi
echo ""

# Test 2: Node exporter health on all nodes
echo "[2/8] Testing node-exporter on all nodes..."
result=$(curl_test "masternode node-exporter" "http://${MASTERNODE_IP}:${NODE_EXPORTER_PORT}/metrics" "node_cpu_seconds_total")
echo "curl http://${MASTERNODE_IP}:${NODE_EXPORTER_PORT}/metrics $result"
if [[ "$result" == "success" ]]; then
  log_pass "Node exporter healthy on masternode"
else
  log_fail "Node exporter unhealthy on masternode"
fi

result=$(curl_test "storage node-exporter" "http://${STORAGE_IP}:${NODE_EXPORTER_PORT}/metrics" "node_cpu_seconds_total")
echo "curl http://${STORAGE_IP}:${NODE_EXPORTER_PORT}/metrics $result"
if [[ "$result" == "success" ]]; then
  log_pass "Node exporter healthy on storagenodet3500"
else
  log_warn "Node exporter may be down on storagenodet3500 (node may be asleep)"
fi

result=$(curl_test "homelab node-exporter" "http://${HOMELAB_IP}:${NODE_EXPORTER_PORT}/metrics" "node_cpu_seconds_total")
echo "curl http://${HOMELAB_IP}:${NODE_EXPORTER_PORT}/metrics $result"
if [[ "$result" == "success" ]]; then
  log_pass "Node exporter healthy on homelab"
else
  log_warn "Node exporter may be down on homelab (node may be asleep or using RKE2)"
fi
echo ""

# Test 3: IPMI exporter health
echo "[3/8] Testing IPMI exporter..."
# Check if IPMI exporter is deployed
if ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring 2>/dev/null | grep ipmi-exporter" >/dev/null 2>&1; then
  IPMI_PODS=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring 2>/dev/null | grep ipmi-exporter")
  
  # Check if any IPMI exporter pods are running
  if echo "$IPMI_PODS" | grep -q "Running"; then
    log_pass "IPMI exporter pods are running"
    
    # Try to access IPMI exporter metrics
    result=$(curl_test "IPMI exporter" "http://${HOMELAB_IP}:${IPMI_EXPORTER_PORT}/metrics" "ipmi")
    echo "curl http://${HOMELAB_IP}:${IPMI_EXPORTER_PORT}/metrics $result"
    if [[ "$result" == "success" ]]; then
      log_pass "IPMI exporter metrics accessible"
    else
      log_warn "IPMI exporter metrics not accessible (may need credentials or IPMI configuration)"
    fi
  elif echo "$IPMI_PODS" | grep -q "0/1"; then
    log_info "IPMI exporter deployment exists but replicas=0 (credentials not configured)"
  else
    log_warn "IPMI exporter pods exist but not running"
  fi
else
  log_info "IPMI exporter not deployed (optional for non-enterprise hardware)"
fi
echo ""

# Test 4: Validate IPMI credentials (if needed)
echo "[4/8] Testing IPMI credentials configuration..."
if ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get secret ipmi-credentials -n monitoring 2>/dev/null" >/dev/null 2>&1; then
  log_pass "IPMI credentials secret exists"
else
  log_info "IPMI credentials not configured (optional - required only for remote IPMI)"
fi
echo ""

# Test 5: Dashboard metric validation
echo "[5/8] Testing Grafana dashboards..."
if dashboards=$(curl -sf "http://${MASTERNODE_IP}:${GRAFANA_PORT}/api/search?type=dash-db" 2>&1); then
  dashboard_count=$(echo "$dashboards" | grep -o '"title"' | wc -l)
  log_pass "Found $dashboard_count Grafana dashboards"
  
  # List dashboard names
  log_info "Available dashboards:"
  echo "$dashboards" | grep '"title":' | sed 's/.*"title":"\([^"]*\)".*/  - \1/' || true
  
  # Check for expected dashboards
  for expected_dash in "vmstation" "Node Metrics" "Cluster Overview" "Prometheus Metrics & Health"; do
    if echo "$dashboards" | grep -q "$expected_dash"; then
      log_pass "Dashboard found: $expected_dash"
    else
      log_warn "Dashboard may be missing: $expected_dash"
    fi
  done
else
  log_fail "Cannot access Grafana dashboards API"
fi
echo ""

# Test 6: Verify dashboard metrics are updating
echo "[6/8] Testing dashboard metrics are updating..."
# Query for basic metrics to ensure data is flowing
if metrics=$(curl -sf "http://${MASTERNODE_IP}:${PROMETHEUS_PORT}/api/v1/query?query=up" 2>&1); then
  if echo "$metrics" | grep -q '"status":"success"'; then
    # Check if metrics have non-zero values
    ZERO_METRICS=$(echo "$metrics" | grep -o '"value":\[.*,\s*"0"\]' | wc -l || echo "0")
    TOTAL_METRICS=$(echo "$metrics" | grep -o '"value":' | wc -l || echo "0")
    
    if [[ "$TOTAL_METRICS" -gt 0 ]]; then
      log_pass "Metrics are being collected ($TOTAL_METRICS targets)"
      
      if [[ "$ZERO_METRICS" -gt 0 ]]; then
        log_warn "$ZERO_METRICS targets have value=0 (may be normal for down targets)"
      fi
    else
      log_fail "No metrics found"
    fi
  else
    log_fail "Metrics query failed"
  fi
else
  log_fail "Cannot query Prometheus metrics"
fi
echo ""

# Test 7: Loki log aggregation health
echo "[7/8] Testing Loki log aggregation..."
# Check if Loki is running
if ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring 2>/dev/null | grep loki | grep Running" >/dev/null 2>&1; then
  log_pass "Loki pods are running"
  
  # Try to access Loki API
  LOKI_PORT=3100
  if curl -sf "http://${MASTERNODE_IP}:${LOKI_PORT}/ready" >/dev/null 2>&1; then
    log_pass "Loki is ready"
  else
    log_warn "Loki API not accessible via NodePort (may be ClusterIP only)"
  fi
else
  log_warn "Loki pods may not be running"
fi

# Check Promtail (log shipper)
if ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring 2>/dev/null | grep promtail | grep Running" >/dev/null 2>&1; then
  PROMTAIL_COUNT=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring 2>/dev/null | grep promtail | grep Running | wc -l")
  log_pass "Promtail pods are running ($PROMTAIL_COUNT instances)"
else
  log_warn "Promtail pods may not be running"
fi
echo ""

# Test 8: Service connectivity summary
echo "[8/8] Service connectivity summary..."
echo "Testing all monitoring endpoints with concise output:"
echo ""

# Prometheus
result=$(curl_test "Prometheus" "http://${MASTERNODE_IP}:${PROMETHEUS_PORT}/-/healthy" "Prometheus is Healthy")
echo "curl http://${MASTERNODE_IP}:${PROMETHEUS_PORT}/-/healthy $result"

# Grafana
result=$(curl_test "Grafana" "http://${MASTERNODE_IP}:${GRAFANA_PORT}/api/health" "database")
echo "curl http://${MASTERNODE_IP}:${GRAFANA_PORT}/api/health $result"

# Node exporters (only check master, others may be asleep)
result=$(curl_test "Node exporter (master)" "http://${MASTERNODE_IP}:${NODE_EXPORTER_PORT}/metrics" "node_")
echo "curl http://${MASTERNODE_IP}:${NODE_EXPORTER_PORT}/metrics $result"

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
  echo "✅ All critical monitoring health checks passed!"
  echo ""
  echo "Monitoring Stack Status:"
  echo "  - Prometheus: ✅ Healthy"
  echo "  - Grafana: ✅ Accessible"
  echo "  - Node Exporters: ✅ Available"
  echo "  - Dashboards: ✅ Configured"
  echo ""
  echo "Access URLs:"
  echo "  Grafana:    http://${MASTERNODE_IP}:${GRAFANA_PORT}"
  echo "  Prometheus: http://${MASTERNODE_IP}:${PROMETHEUS_PORT}"
  echo ""
  exit 0
else
  echo "❌ Some monitoring health checks failed."
  echo ""
  echo "Troubleshooting:"
  echo "  1. Check pod status: kubectl get pods -n monitoring"
  echo "  2. Check service endpoints: kubectl get svc -n monitoring"
  echo "  3. Review Prometheus targets: http://${MASTERNODE_IP}:${PROMETHEUS_PORT}/targets"
  echo "  4. Check pod logs: kubectl logs -n monitoring <pod-name>"
  echo ""
  echo "Common fixes for DOWN targets:"
  echo "  - Restart target service: systemctl restart node_exporter"
  echo "  - Check firewall rules: iptables -L -n"
  echo "  - Verify credentials for IPMI exporter"
  echo ""
  exit 1
fi

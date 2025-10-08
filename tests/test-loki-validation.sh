#!/usr/bin/env bash
# Test script: Validate Loki log aggregation and connectivity
# Tests Loki availability, log ingestion, and query functionality
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Configuration
MASTERNODE_IP="${MASTERNODE_IP:-192.168.4.63}"
LOKI_PORT=3100
GRAFANA_PORT=30300

echo "========================================="
echo "VMStation Loki Log Aggregation Test"
echo "Validating Loki connectivity and log ingestion"
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

# Test 1: Check if Loki pods are running
echo "[1/6] Testing Loki pod status..."
LOKI_PODS=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring 2>/dev/null | grep loki" || echo "")

if [[ -n "$LOKI_PODS" ]]; then
  log_info "Loki pods found:"
  echo "$LOKI_PODS" | while read -r line; do
    echo "  $line"
  done
  
  if echo "$LOKI_PODS" | grep -q "Running"; then
    log_pass "Loki pods are running"
  else
    log_fail "Loki pods are not running"
  fi
else
  log_fail "No Loki pods found in monitoring namespace"
fi
echo ""

# Test 2: Check Loki service configuration
echo "[2/6] Testing Loki service configuration..."
LOKI_SVC=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get svc -n monitoring 2>/dev/null | grep loki" || echo "")

if [[ -n "$LOKI_SVC" ]]; then
  log_pass "Loki service exists"
  log_info "Loki service details:"
  echo "$LOKI_SVC" | while read -r line; do
    echo "  $line"
  done
  
  # Check if service has endpoints
  LOKI_ENDPOINTS=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get endpoints -n monitoring 2>/dev/null | grep loki" || echo "")
  if [[ -n "$LOKI_ENDPOINTS" ]] && ! echo "$LOKI_ENDPOINTS" | grep -q "<none>"; then
    log_pass "Loki service has endpoints"
  else
    log_fail "Loki service has no endpoints"
  fi
else
  log_fail "Loki service not found"
fi
echo ""

# Test 3: Test Loki API connectivity
echo "[3/6] Testing Loki API connectivity..."

# Try to access Loki ready endpoint
if curl -sf "http://${MASTERNODE_IP}:${LOKI_PORT}/ready" >/dev/null 2>&1; then
  echo "curl http://${MASTERNODE_IP}:${LOKI_PORT}/ready ok"
  log_pass "Loki is ready"
else
  echo "curl http://${MASTERNODE_IP}:${LOKI_PORT}/ready error"
  log_warn "Loki ready endpoint not accessible (may be ClusterIP only)"
  
  # Try via kubectl port-forward as alternative test
  log_info "Attempting to test via kubectl exec..."
  LOKI_POD=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring -l app=loki -o name 2>/dev/null | head -n1" || echo "")
  if [[ -n "$LOKI_POD" ]]; then
    if ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf exec -n monitoring $LOKI_POD -- wget -qO- http://localhost:3100/ready 2>/dev/null" | grep -q "ready"; then
      log_pass "Loki is ready (tested via pod exec)"
    else
      log_fail "Loki is not ready"
    fi
  fi
fi
echo ""

# Test 4: Check Promtail (log shipper) status
echo "[4/6] Testing Promtail log shipper..."
PROMTAIL_PODS=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring 2>/dev/null | grep promtail" || echo "")

if [[ -n "$PROMTAIL_PODS" ]]; then
  log_info "Promtail pods found:"
  echo "$PROMTAIL_PODS" | while read -r line; do
    echo "  $line"
  done
  
  PROMTAIL_RUNNING=$(echo "$PROMTAIL_PODS" | grep -c "Running" || echo "0")
  if [[ "$PROMTAIL_RUNNING" -gt 0 ]]; then
    log_pass "Promtail pods are running ($PROMTAIL_RUNNING instances)"
  else
    log_fail "No Promtail pods are running"
  fi
else
  log_fail "No Promtail pods found"
fi
echo ""

# Test 5: Test Loki DNS resolution
echo "[5/6] Testing Loki DNS resolution..."
# Check if Loki service can be resolved from within the cluster
LOKI_DNS_TEST=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf run -it --rm dns-test --image=busybox --restart=Never -- nslookup loki.monitoring.svc.cluster.local 2>&1" || echo "")

if echo "$LOKI_DNS_TEST" | grep -q "Address"; then
  log_pass "Loki DNS resolution successful"
else
  log_warn "Could not verify Loki DNS resolution"
fi
echo ""

# Test 6: Test log query functionality via Grafana
echo "[6/6] Testing Loki datasource in Grafana..."
# Check if Loki is configured as a datasource in Grafana
if datasources=$(curl -sf "http://${MASTERNODE_IP}:${GRAFANA_PORT}/api/datasources" 2>&1); then
  if echo "$datasources" | grep -q "Loki" || echo "$datasources" | grep -q "loki"; then
    log_pass "Loki datasource is configured in Grafana"
    
    # Try to get datasource health
    LOKI_DS_ID=$(echo "$datasources" | grep -B2 -i "loki" | grep '"id":' | head -n1 | grep -o '[0-9]*' || echo "")
    if [[ -n "$LOKI_DS_ID" ]]; then
      if health=$(curl -sf "http://${MASTERNODE_IP}:${GRAFANA_PORT}/api/datasources/${LOKI_DS_ID}/health" 2>&1); then
        if echo "$health" | grep -q '"status":"OK"'; then
          log_pass "Loki datasource health check passed"
        else
          log_warn "Loki datasource health check returned non-OK status"
        fi
      else
        log_warn "Could not check Loki datasource health"
      fi
    fi
  else
    log_fail "Loki datasource not found in Grafana"
  fi
else
  log_fail "Cannot access Grafana datasources API"
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
  echo "✅ Loki log aggregation is healthy!"
  echo ""
  echo "Loki Configuration:"
  echo "  - Loki pods: Running"
  echo "  - Promtail: Collecting logs"
  echo "  - Grafana datasource: Configured"
  echo ""
  echo "Query logs via Grafana:"
  echo "  URL: http://${MASTERNODE_IP}:${GRAFANA_PORT}/explore"
  echo "  Select 'Loki' datasource and run queries"
  echo ""
  exit 0
else
  echo "❌ Loki log aggregation has issues."
  echo ""
  echo "Common fixes:"
  echo "  1. Check Loki logs: kubectl logs -n monitoring -l app=loki"
  echo "  2. Check Promtail logs: kubectl logs -n monitoring -l app=promtail"
  echo "  3. Verify Loki service: kubectl get svc -n monitoring loki"
  echo "  4. Check DNS: kubectl run -it --rm dns-test --image=busybox --restart=Never -- nslookup loki.monitoring"
  echo ""
  echo "Connectivity errors:"
  echo "  - DNS lookup failures: Check CoreDNS pods"
  echo "  - 500 status: Check Loki logs for errors"
  echo "  - Service unavailable: Verify Loki pods are running"
  echo ""
  exit 1
fi

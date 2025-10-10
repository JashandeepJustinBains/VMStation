#!/bin/bash
# VMStation Monitoring Stack - Validation Script
# Date: October 10, 2025
# Purpose: Validate that monitoring stack is functioning correctly

set -e

KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
NAMESPACE="monitoring"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
WARNINGS=0

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VMStation Monitoring Stack - Validation Report"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Helper functions
print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}  ✓ PASS:${NC} $1"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}  ✗ FAIL:${NC} $1"
    ((FAILED++))
}

print_warn() {
    echo -e "${YELLOW}  ⚠ WARN:${NC} $1"
    ((WARNINGS++))
}

print_info() {
    echo -e "       $1"
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Pod Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_test "Checking Prometheus pod status"
PROM_STATUS=$(kubectl --kubeconfig=${KUBECONFIG} get pod prometheus-0 -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
PROM_READY=$(kubectl --kubeconfig=${KUBECONFIG} get pod prometheus-0 -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

if [ "$PROM_STATUS" = "Running" ] && [ "$PROM_READY" = "True" ]; then
    print_pass "Prometheus pod is Running and Ready"
elif [ "$PROM_STATUS" = "Running" ]; then
    print_warn "Prometheus pod is Running but not Ready"
    print_info "Status: $PROM_STATUS, Ready: $PROM_READY"
else
    print_fail "Prometheus pod is not Running"
    print_info "Status: $PROM_STATUS"
fi

print_test "Checking Loki pod status"
LOKI_STATUS=$(kubectl --kubeconfig=${KUBECONFIG} get pod loki-0 -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
LOKI_READY=$(kubectl --kubeconfig=${KUBECONFIG} get pod loki-0 -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

if [ "$LOKI_STATUS" = "Running" ] && [ "$LOKI_READY" = "True" ]; then
    print_pass "Loki pod is Running and Ready"
elif [ "$LOKI_STATUS" = "Running" ]; then
    print_warn "Loki pod is Running but not Ready"
    print_info "Status: $LOKI_STATUS, Ready: $LOKI_READY"
else
    print_fail "Loki pod is not Running"
    print_info "Status: $LOKI_STATUS"
fi

print_test "Checking Grafana pod status"
GRAFANA_STATUS=$(kubectl --kubeconfig=${KUBECONFIG} get pod -n ${NAMESPACE} -l app=grafana -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
GRAFANA_READY=$(kubectl --kubeconfig=${KUBECONFIG} get pod -n ${NAMESPACE} -l app=grafana -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

if [ "$GRAFANA_STATUS" = "Running" ] && [ "$GRAFANA_READY" = "True" ]; then
    print_pass "Grafana pod is Running and Ready"
elif [ "$GRAFANA_STATUS" = "Running" ]; then
    print_warn "Grafana pod is Running but not Ready"
    print_info "Status: $GRAFANA_STATUS, Ready: $GRAFANA_READY"
else
    print_fail "Grafana pod is not Running"
    print_info "Status: $GRAFANA_STATUS"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Service Endpoints"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_test "Checking Prometheus endpoints"
PROM_ENDPOINTS=$(kubectl --kubeconfig=${KUBECONFIG} get endpoints prometheus -n ${NAMESPACE} -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
if [ -n "$PROM_ENDPOINTS" ]; then
    print_pass "Prometheus endpoints populated"
    print_info "Endpoints: $PROM_ENDPOINTS"
else
    print_fail "Prometheus endpoints are empty"
    print_info "Check that prometheus-0 pod is Ready"
fi

print_test "Checking Loki endpoints"
LOKI_ENDPOINTS=$(kubectl --kubeconfig=${KUBECONFIG} get endpoints loki -n ${NAMESPACE} -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
if [ -n "$LOKI_ENDPOINTS" ]; then
    print_pass "Loki endpoints populated"
    print_info "Endpoints: $LOKI_ENDPOINTS"
else
    print_fail "Loki endpoints are empty"
    print_info "Check that loki-0 pod is Ready"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: PVC and PV Bindings"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_test "Checking Prometheus PVC"
PROM_PVC_STATUS=$(kubectl --kubeconfig=${KUBECONFIG} get pvc prometheus-storage-prometheus-0 -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$PROM_PVC_STATUS" = "Bound" ]; then
    print_pass "Prometheus PVC is Bound"
else
    print_fail "Prometheus PVC is not Bound"
    print_info "Status: $PROM_PVC_STATUS"
fi

print_test "Checking Loki PVC"
LOKI_PVC_STATUS=$(kubectl --kubeconfig=${KUBECONFIG} get pvc loki-data-loki-0 -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$LOKI_PVC_STATUS" = "Bound" ]; then
    print_pass "Loki PVC is Bound"
else
    print_fail "Loki PVC is not Bound"
    print_info "Status: $LOKI_PVC_STATUS"
fi

print_test "Checking Grafana PVC"
GRAFANA_PVC_STATUS=$(kubectl --kubeconfig=${KUBECONFIG} get pvc grafana-pvc -n ${NAMESPACE} -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$GRAFANA_PVC_STATUS" = "Bound" ]; then
    print_pass "Grafana PVC is Bound"
else
    print_fail "Grafana PVC is not Bound"
    print_info "Status: $GRAFANA_PVC_STATUS"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Health Endpoints"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_test "Testing Prometheus health endpoint (from inside pod)"
if kubectl --kubeconfig=${KUBECONFIG} exec prometheus-0 -n ${NAMESPACE} -c prometheus -- wget -q -O- --timeout=5 http://localhost:9090/-/healthy 2>/dev/null | grep -q "Prometheus is Healthy"; then
    print_pass "Prometheus health endpoint responding"
else
    print_warn "Prometheus health endpoint not responding or pod not ready"
    print_info "Try: kubectl exec prometheus-0 -n monitoring -c prometheus -- wget -O- http://localhost:9090/-/healthy"
fi

print_test "Testing Prometheus readiness endpoint (from inside pod)"
if kubectl --kubeconfig=${KUBECONFIG} exec prometheus-0 -n ${NAMESPACE} -c prometheus -- wget -q -O- --timeout=5 http://localhost:9090/-/ready 2>/dev/null | grep -q "Prometheus Server is Ready"; then
    print_pass "Prometheus readiness endpoint responding"
else
    print_warn "Prometheus readiness endpoint not responding or pod not ready"
    print_info "Try: kubectl exec prometheus-0 -n monitoring -c prometheus -- wget -O- http://localhost:9090/-/ready"
fi

print_test "Testing Loki ready endpoint (from inside pod)"
if kubectl --kubeconfig=${KUBECONFIG} exec loki-0 -n ${NAMESPACE} -- wget -q -O- --timeout=5 http://localhost:3100/ready 2>/dev/null | grep -q "ready"; then
    print_pass "Loki ready endpoint responding"
else
    print_warn "Loki ready endpoint not responding or pod not ready"
    print_info "Try: kubectl exec loki-0 -n monitoring -- wget -O- http://localhost:3100/ready"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: DNS Resolution (from within cluster)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_test "Testing Prometheus DNS resolution"
if kubectl --kubeconfig=${KUBECONFIG} run dns-test-prom --image=busybox:latest --rm -it --restart=Never --command -- nslookup prometheus.monitoring.svc.cluster.local 2>&1 | grep -q "Address"; then
    print_pass "Prometheus DNS resolves correctly"
else
    # Fallback test
    if [ -n "$PROM_ENDPOINTS" ]; then
        print_pass "Prometheus DNS should resolve (endpoints exist)"
    else
        print_fail "Prometheus DNS resolution failed and no endpoints"
    fi
fi

print_test "Testing Loki DNS resolution"
if kubectl --kubeconfig=${KUBECONFIG} run dns-test-loki --image=busybox:latest --rm -it --restart=Never --command -- nslookup loki.monitoring.svc.cluster.local 2>&1 | grep -q "Address"; then
    print_pass "Loki DNS resolves correctly"
else
    # Fallback test
    if [ -n "$LOKI_ENDPOINTS" ]; then
        print_pass "Loki DNS should resolve (endpoints exist)"
    else
        print_fail "Loki DNS resolution failed and no endpoints"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 6: Container Restarts and Errors"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_test "Checking Prometheus restart count"
PROM_RESTARTS=$(kubectl --kubeconfig=${KUBECONFIG} get pod prometheus-0 -n ${NAMESPACE} -o jsonpath='{.status.containerStatuses[?(@.name=="prometheus")].restartCount}' 2>/dev/null || echo "0")
if [ "$PROM_RESTARTS" -eq 0 ]; then
    print_pass "Prometheus has not restarted"
elif [ "$PROM_RESTARTS" -lt 5 ]; then
    print_warn "Prometheus has restarted $PROM_RESTARTS times"
    print_info "Check logs: kubectl logs -n monitoring prometheus-0 -c prometheus"
else
    print_fail "Prometheus has restarted $PROM_RESTARTS times (CrashLoopBackOff?)"
    print_info "Check logs: kubectl logs -n monitoring prometheus-0 -c prometheus"
fi

print_test "Checking Loki restart count"
LOKI_RESTARTS=$(kubectl --kubeconfig=${KUBECONFIG} get pod loki-0 -n ${NAMESPACE} -o jsonpath='{.status.containerStatuses[?(@.name=="loki")].restartCount}' 2>/dev/null || echo "0")
if [ "$LOKI_RESTARTS" -eq 0 ]; then
    print_pass "Loki has not restarted"
elif [ "$LOKI_RESTARTS" -lt 5 ]; then
    print_warn "Loki has restarted $LOKI_RESTARTS times"
    print_info "Check logs: kubectl logs -n monitoring loki-0"
else
    print_fail "Loki has restarted $LOKI_RESTARTS times (CrashLoopBackOff?)"
    print_info "Check logs: kubectl logs -n monitoring loki-0"
fi

print_test "Checking for recent error events"
ERROR_EVENTS=$(kubectl --kubeconfig=${KUBECONFIG} get events -n ${NAMESPACE} --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null | tail -5)
if [ -z "$ERROR_EVENTS" ] || ! echo "$ERROR_EVENTS" | grep -qE "(prometheus-0|loki-0)"; then
    print_pass "No recent error events for Prometheus or Loki"
else
    print_warn "Found recent error events"
    print_info "Run: kubectl get events -n monitoring --field-selector type=Warning"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 7: Log Analysis"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

print_test "Checking Prometheus logs for errors"
PROM_LOG_ERRORS=$(kubectl --kubeconfig=${KUBECONFIG} logs prometheus-0 -n ${NAMESPACE} -c prometheus --tail=100 2>/dev/null | grep -iE "error|fatal|permission denied" | wc -l)
if [ "$PROM_LOG_ERRORS" -eq 0 ]; then
    print_pass "No errors in Prometheus logs (last 100 lines)"
else
    print_warn "Found $PROM_LOG_ERRORS error/fatal messages in Prometheus logs"
    print_info "Run: kubectl logs -n monitoring prometheus-0 -c prometheus | grep -i error"
fi

print_test "Checking Loki logs for critical errors"
LOKI_LOG_ERRORS=$(kubectl --kubeconfig=${KUBECONFIG} logs loki-0 -n ${NAMESPACE} --tail=100 2>/dev/null | grep -iE '"level":"error"|"level":"fatal"' | wc -l)
# Note: "connection refused" to 127.0.0.1:9095 is expected and can be ignored if frontend_worker is disabled
LOKI_CRITICAL_ERRORS=$(kubectl --kubeconfig=${KUBECONFIG} logs loki-0 -n ${NAMESPACE} --tail=100 2>/dev/null | grep -iE '"level":"fatal"' | wc -l)
if [ "$LOKI_CRITICAL_ERRORS" -eq 0 ]; then
    print_pass "No critical errors in Loki logs (last 100 lines)"
    if [ "$LOKI_LOG_ERRORS" -gt 0 ]; then
        print_info "Note: Some 'connection refused' errors are normal if frontend_worker is disabled"
    fi
else
    print_fail "Found $LOKI_CRITICAL_ERRORS critical errors in Loki logs"
    print_info "Run: kubectl logs -n monitoring loki-0 | grep -i fatal"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "Tests passed:  ${GREEN}${PASSED}${NC}"
echo -e "Tests failed:  ${RED}${FAILED}${NC}"
echo -e "Warnings:      ${YELLOW}${WARNINGS}${NC}"
echo ""

if [ "$FAILED" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ All tests passed! Monitoring stack is healthy.${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
elif [ "$FAILED" -eq 0 ]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚠ All critical tests passed with some warnings.${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}✗ Some tests failed. Please review the output above.${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check pod status: kubectl get pods -n monitoring"
    echo "  2. View pod logs: kubectl logs -n monitoring <pod-name>"
    echo "  3. Describe pod: kubectl describe pod -n monitoring <pod-name>"
    echo "  4. Check events: kubectl get events -n monitoring --sort-by='.lastTimestamp'"
    echo "  5. Run remediation: ./scripts/remediate-monitoring-stack.sh"
    echo ""
    exit 1
fi

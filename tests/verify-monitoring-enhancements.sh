#!/bin/bash
# Comprehensive Monitoring Stack Verification Script
# Tests all new features and enhancements

set -e

KUBECONFIG="/etc/kubernetes/admin.conf"
NAMESPACE="monitoring"

echo "=================================================="
echo "VMStation Monitoring Stack Verification"
echo "=================================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Test 1: Blackbox Exporter
echo "=== Test 1: Blackbox Exporter ==="
if kubectl --kubeconfig=$KUBECONFIG get deployment blackbox-exporter -n $NAMESPACE &>/dev/null; then
    STATUS=$(kubectl --kubeconfig=$KUBECONFIG get deployment blackbox-exporter -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
    if [ "$STATUS" == "True" ]; then
        pass "Blackbox exporter deployment is Available"
        
        # Check pod
        POD=$(kubectl --kubeconfig=$KUBECONFIG get pods -l app=blackbox-exporter -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [ -n "$POD" ]; then
            pass "Blackbox exporter pod: $POD"
            
            # Test metrics endpoint
            if kubectl --kubeconfig=$KUBECONFIG exec -n $NAMESPACE $POD -- curl -sf http://127.0.0.1:9115/metrics &>/dev/null; then
                pass "Metrics endpoint responding"
            else
                fail "Metrics endpoint not responding"
            fi
        fi
    else
        fail "Blackbox exporter deployment not Available"
        kubectl --kubeconfig=$KUBECONFIG describe deployment blackbox-exporter -n $NAMESPACE | tail -20
    fi
else
    fail "Blackbox exporter deployment not found"
fi
echo ""

# Test 2: Syslog Server
echo "=== Test 2: Syslog Server ==="
if kubectl --kubeconfig=$KUBECONFIG get daemonset syslog-server -n $NAMESPACE &>/dev/null; then
    DESIRED=$(kubectl --kubeconfig=$KUBECONFIG get daemonset syslog-server -n $NAMESPACE -o jsonpath='{.status.desiredNumberScheduled}')
    READY=$(kubectl --kubeconfig=$KUBECONFIG get daemonset syslog-server -n $NAMESPACE -o jsonpath='{.status.numberReady}')
    
    if [ "$DESIRED" == "$READY" ]; then
        pass "Syslog server DaemonSet: $READY/$DESIRED ready"
    else
        warn "Syslog server DaemonSet: $READY/$DESIRED ready (some pods may be pending)"
    fi
else
    fail "Syslog server DaemonSet not found"
fi
echo ""

# Test 3: Syslog Exporter
echo "=== Test 3: Syslog Exporter ==="
if kubectl --kubeconfig=$KUBECONFIG get daemonset syslog-exporter -n $NAMESPACE &>/dev/null; then
    DESIRED=$(kubectl --kubeconfig=$KUBECONFIG get daemonset syslog-exporter -n $NAMESPACE -o jsonpath='{.status.desiredNumberScheduled}')
    READY=$(kubectl --kubeconfig=$KUBECONFIG get daemonset syslog-exporter -n $NAMESPACE -o jsonpath='{.status.numberReady}')
    
    if [ "$DESIRED" == "$READY" ]; then
        pass "Syslog exporter DaemonSet: $READY/$DESIRED ready"
    else
        warn "Syslog exporter DaemonSet: $READY/$DESIRED ready (some pods may be pending)"
    fi
else
    fail "Syslog exporter DaemonSet not found"
fi
echo ""

# Test 4: Grafana Dashboards
echo "=== Test 4: Grafana Dashboards ==="
if kubectl --kubeconfig=$KUBECONFIG get configmap grafana-dashboards -n $NAMESPACE &>/dev/null; then
    DASHBOARDS=$(kubectl --kubeconfig=$KUBECONFIG get configmap grafana-dashboards -n $NAMESPACE -o json | jq -r '.data | keys[]' 2>/dev/null)
    
    if echo "$DASHBOARDS" | grep -q "blackbox-exporter-dashboard.json"; then
        pass "Blackbox Exporter dashboard found"
    else
        fail "Blackbox Exporter dashboard not found"
    fi
    
    if echo "$DASHBOARDS" | grep -q "network-security-dashboard.json"; then
        pass "Network Security dashboard found"
    else
        fail "Network Security dashboard not found"
    fi
    
    if echo "$DASHBOARDS" | grep -q "syslog-dashboard.json"; then
        pass "Syslog Analysis dashboard found"
    else
        fail "Syslog Analysis dashboard not found"
    fi
    
    echo ""
    echo "Total dashboards: $(echo "$DASHBOARDS" | wc -l)"
    echo "Dashboards:"
    echo "$DASHBOARDS" | sed 's/^/  - /'
else
    fail "Grafana dashboards ConfigMap not found"
fi
echo ""

# Test 5: RKE2 Federation
echo "=== Test 5: RKE2 Federation ==="
if kubectl --kubeconfig=$KUBECONFIG get configmap prometheus-config -n $NAMESPACE &>/dev/null; then
    if kubectl --kubeconfig=$KUBECONFIG get configmap prometheus-config -n $NAMESPACE -o yaml | grep -q "rke2-federation"; then
        pass "RKE2 federation configured"
        TARGET=$(kubectl --kubeconfig=$KUBECONFIG get configmap prometheus-config -n $NAMESPACE -o yaml | grep -A 2 "job_name: 'rke2-federation'" | grep "192.168.4.62" || echo "")
        if [ -n "$TARGET" ]; then
            pass "RKE2 target: 192.168.4.62:30090"
        fi
    else
        fail "RKE2 federation not configured"
    fi
else
    fail "Prometheus config not found"
fi
echo ""

# Test 6: Loki Status
echo "=== Test 6: Loki Status ==="
if kubectl --kubeconfig=$KUBECONFIG get deployment loki -n $NAMESPACE &>/dev/null; then
    STATUS=$(kubectl --kubeconfig=$KUBECONFIG get deployment loki -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
    if [ "$STATUS" == "True" ]; then
        pass "Loki deployment is Available"
        
        # Check if service is accessible
        SVC_IP=$(kubectl --kubeconfig=$KUBECONFIG get svc loki -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
        pass "Loki service IP: $SVC_IP"
    else
        warn "Loki deployment not Available (may cause 502 errors in Grafana)"
    fi
else
    fail "Loki deployment not found"
fi
echo ""

# Test 7: Grafana Status
echo "=== Test 7: Grafana Status ==="
if kubectl --kubeconfig=$KUBECONFIG get deployment grafana -n $NAMESPACE &>/dev/null; then
    STATUS=$(kubectl --kubeconfig=$KUBECONFIG get deployment grafana -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
    if [ "$STATUS" == "True" ]; then
        pass "Grafana deployment is Available"
        
        # Get NodePort
        NODEPORT=$(kubectl --kubeconfig=$KUBECONFIG get svc grafana -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')
        NODE_IP=$(kubectl --kubeconfig=$KUBECONFIG get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        pass "Grafana URL: http://$NODE_IP:$NODEPORT"
        echo "   Default credentials: admin / admin"
    else
        fail "Grafana deployment not Available"
    fi
else
    fail "Grafana deployment not found"
fi
echo ""

# Test 8: Prometheus Status
echo "=== Test 8: Prometheus Status ==="
if kubectl --kubeconfig=$KUBECONFIG get deployment prometheus -n $NAMESPACE &>/dev/null; then
    STATUS=$(kubectl --kubeconfig=$KUBECONFIG get deployment prometheus -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
    if [ "$STATUS" == "True" ]; then
        pass "Prometheus deployment is Available"
        
        # Get NodePort
        NODEPORT=$(kubectl --kubeconfig=$KUBECONFIG get svc prometheus -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}')
        NODE_IP=$(kubectl --kubeconfig=$KUBECONFIG get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        pass "Prometheus URL: http://$NODE_IP:$NODEPORT"
    else
        fail "Prometheus deployment not Available"
    fi
else
    fail "Prometheus deployment not found"
fi
echo ""

# Summary
echo "=================================================="
echo "Verification Complete"
echo "=================================================="
echo ""
echo "Next Steps:"
echo "1. Access Grafana and verify new dashboards are visible"
echo "2. Test syslog ingestion: logger -n <node-ip> -P 514 'Test message'"
echo "3. Check RKE2 metrics in Prometheus targets (if RKE2 is running)"
echo "4. Review COMPREHENSIVE_MONITORING_FIX.md for detailed documentation"
echo ""

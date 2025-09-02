#!/bin/bash

# Validation script for Grafana datasource conflict fix
# This script checks if the fix resolves the "Only one datasource per organization can be marked as default" error

set -e

echo "=== VMStation Grafana Datasource Conflict Fix Validation ==="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

MONITORING_NAMESPACE="monitoring"

echo "1. Checking Grafana pod logs for datasource conflicts..."
if kubectl get pods -n "$MONITORING_NAMESPACE" -l app.kubernetes.io/name=grafana --no-headers | grep -q Running; then
    echo "   Grafana pod found, checking logs for datasource errors..."
    
    # Check for the specific error
    if kubectl logs -n "$MONITORING_NAMESPACE" -l app.kubernetes.io/name=grafana --tail=100 | grep -q "Only one datasource per organization can be marked as default"; then
        echo -e "   ${RED}✗ Still seeing datasource conflict error${NC}"
        echo "   Recent logs showing the error:"
        kubectl logs -n "$MONITORING_NAMESPACE" -l app.kubernetes.io/name=grafana --tail=20 | grep "Only one datasource"
    else
        echo -e "   ${GREEN}✓ No datasource conflict errors found in recent logs${NC}"
    fi
    
    # Check for successful provisioning
    if kubectl logs -n "$MONITORING_NAMESPACE" -l app.kubernetes.io/name=grafana --tail=50 | grep -q "finished to provision"; then
        echo -e "   ${GREEN}✓ Grafana provisioning completed successfully${NC}"
    else
        echo -e "   ${YELLOW}⚠ No recent provisioning completion messages found${NC}"
    fi
else
    echo -e "   ${RED}✗ Grafana pod not found or not running${NC}"
fi

echo ""
echo "2. Checking Loki datasource configuration..."
if kubectl get configmap loki-datasource -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then
    echo "   Loki datasource ConfigMap found, checking configuration..."
    
    if kubectl get configmap loki-datasource -n "$MONITORING_NAMESPACE" -o yaml | grep -q "isDefault: false"; then
        echo -e "   ${GREEN}✓ Loki datasource correctly configured with isDefault: false${NC}"
    else
        echo -e "   ${RED}✗ Loki datasource missing isDefault: false configuration${NC}"
        echo "   Current configuration:"
        kubectl get configmap loki-datasource -n "$MONITORING_NAMESPACE" -o yaml | grep -A 10 "loki-datasource.yaml:"
    fi
else
    echo -e "   ${RED}✗ Loki datasource ConfigMap not found${NC}"
fi

echo ""
echo "3. Checking for manual Prometheus datasource (should not exist)..."
if kubectl get configmap prometheus-datasource -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then
    echo -e "   ${RED}✗ Manual Prometheus datasource ConfigMap still exists (should be removed)${NC}"
    echo "   This may be causing the conflict. Remove it with:"
    echo "   kubectl delete configmap prometheus-datasource -n $MONITORING_NAMESPACE"
else
    echo -e "   ${GREEN}✓ No manual Prometheus datasource ConfigMap found (correct)${NC}"
fi

echo ""
echo "4. Checking kube-prometheus-stack Grafana deployment..."
if kubectl get deployment kube-prometheus-stack-grafana -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then
    replicas=$(kubectl get deployment kube-prometheus-stack-grafana -n "$MONITORING_NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    if [ "$replicas" -gt 0 ] 2>/dev/null; then
        echo -e "   ${GREEN}✓ Grafana deployment is ready with $replicas replica(s)${NC}"
        echo "   (Automatic Prometheus datasource should be created by kube-prometheus-stack)"
    else
        echo -e "   ${YELLOW}⚠ Grafana deployment exists but no ready replicas${NC}"
    fi
else
    echo -e "   ${RED}✗ kube-prometheus-stack-grafana deployment not found${NC}"
fi

echo ""
echo "5. Testing Grafana API (if accessible)..."
# Try to get the node IP and test the API
if kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' | grep -q .; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    echo "   Testing Grafana API at http://$NODE_IP:30300..."
    
    if curl -s --connect-timeout 5 "http://$NODE_IP:30300/api/health" >/dev/null 2>&1; then
        echo -e "   ${GREEN}✓ Grafana API is accessible${NC}"
        
        # Check datasources via API
        if curl -s --connect-timeout 5 "http://$NODE_IP:30300/api/datasources" | grep -q "Prometheus\|Loki" 2>/dev/null; then
            echo "   Datasources found via API:"
            curl -s "http://$NODE_IP:30300/api/datasources" | jq -r '.[] | "   - \(.name) (\(.type)) - Default: \(.isDefault)"' 2>/dev/null || echo "   (jq not available, raw output)"
        else
            echo -e "   ${YELLOW}⚠ Could not retrieve datasources via API${NC}"
        fi
    else
        echo -e "   ${YELLOW}⚠ Grafana API not accessible (this is normal in some environments)${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠ Could not determine node IP for API testing${NC}"
fi

echo ""
echo "=== Validation Summary ==="
echo ""
echo "Expected fix behavior:"
echo "• Only one datasource should be marked as default (the automatic Prometheus from kube-prometheus-stack)"
echo "• Loki datasource should exist with isDefault: false"
echo "• No manual Prometheus datasource ConfigMap should exist"
echo "• Grafana logs should not show 'Only one datasource per organization can be marked as default'"
echo ""
echo "If issues persist:"
echo "1. Check Grafana pod logs: kubectl logs -n $MONITORING_NAMESPACE -l app.kubernetes.io/name=grafana"
echo "2. Restart Grafana deployment: kubectl rollout restart deployment kube-prometheus-stack-grafana -n $MONITORING_NAMESPACE"
echo "3. Verify no conflicting datasource ConfigMaps exist"
echo ""
echo "=== Validation Complete ==="
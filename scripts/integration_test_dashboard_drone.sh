#!/bin/bash
# Integration test for VMStation Dashboard and Drone deployment
# Run this on the monitoring node after deployment

set -e

echo "🧪 VMStation Dashboard & Drone Integration Test"
echo "=============================================="

# Test 1: Verify kubectl connectivity
echo "Test 1: Kubernetes cluster connectivity..."
if kubectl cluster-info &> /dev/null; then
    echo "✅ Kubernetes cluster accessible"
else
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi

# Test 2: Check namespaces
echo "Test 2: Required namespaces..."
NAMESPACES=("kubernetes-dashboard" "localhost.localdomain" "monitoring")
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        echo "✅ Namespace '$ns' exists"
    else
        echo "❌ Namespace '$ns' missing"
    fi
done

# Test 3: Check running pods
echo "Test 3: Pod status checks..."
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        READY_PODS=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        TOTAL_PODS=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
        echo "📊 Namespace '$ns': $READY_PODS/$TOTAL_PODS pods running"
    fi
done

# Test 4: Service endpoints
echo "Test 4: Service endpoint checks..."
SERVICES=(
    "kubernetes-dashboard:kubernetes-dashboard:30443"
    "localhost.localdomain:gitea:30300"
    "localhost.localdomain:drone-server:30080"
    "monitoring:kube-prometheus-stack-grafana:30300"
)

for service_info in "${SERVICES[@]}"; do
    IFS=':' read -r namespace service expected_port <<< "$service_info"
    if kubectl get service "$service" -n "$namespace" &> /dev/null 2>&1; then
        NODEPORT=$(kubectl get service "$service" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
        if [ -n "$NODEPORT" ]; then
            echo "✅ Service '$namespace/$service' on port $NODEPORT"
        else
            echo "⚠️  Service '$namespace/$service' exists but no NodePort"
        fi
    else
        echo "❌ Service '$namespace/$service' not found"
    fi
done

# Test 5: Basic connectivity test
echo "Test 5: Basic connectivity tests..."
NODE_IP=$(hostname -I | awk '{print $1}')
echo "Testing from node IP: $NODE_IP"

# Test Grafana connectivity (should be accessible)
if curl -s -f "http://$NODE_IP:30300/api/health" &> /dev/null; then
    echo "✅ Grafana API accessible"
else
    echo "⚠️  Grafana API not responding (may be normal if not fully started)"
fi

# Test 6: Storage checks
echo "Test 6: Persistent volume claims..."
for ns in "localhost.localdomain"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        PVC_COUNT=$(kubectl get pvc -n "$ns" --no-headers 2>/dev/null | wc -l)
        BOUND_PVC=$(kubectl get pvc -n "$ns" --no-headers 2>/dev/null | grep "Bound" | wc -l)
        echo "📦 Namespace '$ns': $BOUND_PVC/$PVC_COUNT PVCs bound"
    fi
done

echo ""
echo "🏁 Integration test completed!"
echo ""
echo "Next steps:"
echo "1. Access Kubernetes Dashboard: https://$NODE_IP:30443"
echo "2. Access Gitea: http://$NODE_IP:30300 (if on compute node)"
echo "3. Access Drone: http://$NODE_IP:30080 (if on compute node)"
echo "4. Access Grafana: http://$NODE_IP:30300"
echo ""
echo "For detailed validation, run: ./scripts/validate_dashboard_drone.sh"
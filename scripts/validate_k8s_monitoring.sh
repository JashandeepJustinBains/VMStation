#!/bin/bash

# Kubernetes monitoring validation script
# Replaces the Podman-based validate_monitoring.sh

set -e

echo "=== VMStation Kubernetes Monitoring Validation ==="
echo "Timestamp: $(date)"
echo ""

# Configuration
MONITORING_NODE="192.168.4.63"
GRAFANA_PORT="30300"
PROMETHEUS_PORT="30090"
LOKI_PORT="31100"
ALERTMANAGER_PORT="30903"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

check_endpoint() {
    local url=$1
    local name=$2
    if curl -s --connect-timeout 5 "$url" >/dev/null 2>&1; then
        success "$name is responding"
    else
        error "$name is not responding at $url"
    fi
}

echo "=== 1. Kubernetes Cluster Status ==="
if kubectl get nodes >/dev/null 2>&1; then
    success "Kubernetes cluster is accessible"
    echo ""
    kubectl get nodes -o wide
    echo ""
else
    error "Cannot access Kubernetes cluster"
    echo "Make sure kubectl is configured and cluster is running"
    exit 1
fi

echo "=== 2. Monitoring Namespace ==="
if kubectl get namespace monitoring >/dev/null 2>&1; then
    success "Monitoring namespace exists"
else
    error "Monitoring namespace not found"
fi

echo ""
echo "=== 3. Monitoring Pods Status ==="
kubectl get pods -n monitoring -o wide

echo ""
echo "=== 4. Monitoring Services ==="
kubectl get services -n monitoring

echo ""
echo "=== 5. PersistentVolumeClaims ==="
kubectl get pvc -n monitoring

echo ""
echo "=== 6. Service Endpoints Validation ==="
check_endpoint "http://$MONITORING_NODE:$GRAFANA_PORT" "Grafana"
check_endpoint "http://$MONITORING_NODE:$PROMETHEUS_PORT" "Prometheus"
check_endpoint "http://$MONITORING_NODE:$LOKI_PORT/ready" "Loki"
check_endpoint "http://$MONITORING_NODE:$ALERTMANAGER_PORT" "AlertManager"

echo ""
echo "=== 7. Prometheus Targets Status ==="
if curl -s "http://$MONITORING_NODE:$PROMETHEUS_PORT/api/v1/targets" >/tmp/prometheus_targets.json 2>/dev/null; then
    success "Retrieved Prometheus targets"
    
    # Check target health
    active_targets=$(jq -r '.data.activeTargets[].health' /tmp/prometheus_targets.json 2>/dev/null | sort | uniq -c)
    echo "Target health status:"
    echo "$active_targets"
else
    error "Could not retrieve Prometheus targets"
fi

echo ""
echo "=== 8. Certificate Status ==="
if kubectl get certificates -n monitoring >/dev/null 2>&1; then
    success "Certificates found"
    kubectl get certificates -n monitoring
else
    warning "No certificates found (cert-manager may not be deployed)"
fi

echo ""
echo "=== 9. Ingress Status ==="
kubectl get ingress -n monitoring 2>/dev/null || warning "No ingress resources found"

echo ""
echo "=== 10. Storage Classes ==="
kubectl get storageclass

echo ""
echo "=== Access URLs ==="
echo "🌐 Grafana: http://$MONITORING_NODE:$GRAFANA_PORT (admin/admin)"
echo "📊 Prometheus: http://$MONITORING_NODE:$PROMETHEUS_PORT"
echo "📝 Loki: http://$MONITORING_NODE:$LOKI_PORT"
echo "🚨 AlertManager: http://$MONITORING_NODE:$ALERTMANAGER_PORT"

echo ""
echo "=== Troubleshooting ==="
echo "If you see red status:"
echo "1. Check pod logs: kubectl logs -n monitoring <pod-name>"
echo "2. Check pod events: kubectl describe pod -n monitoring <pod-name>"
echo "3. Check service status: kubectl get svc -n monitoring"
echo "4. Restart deployment: kubectl rollout restart deployment/<deployment-name> -n monitoring"

echo ""
echo "=== Validation Complete ==="
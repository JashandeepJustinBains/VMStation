#!/bin/bash
# VMStation Monitoring Stack - Quick Fix Application Script
# This script applies all fixes for blackbox-exporter, Loki, and Jellyfin issues
#
# Usage: sudo ./apply-monitoring-fixes.sh
#
# Prerequisites:
# - kubectl configured with /etc/kubernetes/admin.conf
# - Running on masternode (192.168.4.63)
# - Cluster already initialized

set -e

KUBECONFIG="/etc/kubernetes/admin.conf"
REPO_ROOT="/home/runner/work/VMStation/VMStation"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "VMStation Monitoring Stack - Quick Fix Application"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Ensure all nodes are schedulable
echo "Step 1: Ensuring all nodes are schedulable..."
kubectl --kubeconfig=${KUBECONFIG} get nodes --no-headers | \
    awk '{print $1}' | \
    xargs -n1 kubectl --kubeconfig=${KUBECONFIG} uncordon
echo "✅ All nodes uncordoned"
echo ""

# Step 2: Apply fixed blackbox-exporter config
echo "Step 2: Applying fixed blackbox-exporter configuration..."
kubectl --kubeconfig=${KUBECONFIG} delete configmap blackbox-exporter-config -n monitoring --ignore-not-found
kubectl --kubeconfig=${KUBECONFIG} apply -f ${REPO_ROOT}/manifests/monitoring/prometheus.yaml
echo "✅ Blackbox-exporter config updated"
echo ""

# Step 3: Apply fixed Loki config
echo "Step 3: Applying fixed Loki configuration..."
kubectl --kubeconfig=${KUBECONFIG} delete configmap loki-config -n monitoring --ignore-not-found
kubectl --kubeconfig=${KUBECONFIG} apply -f ${REPO_ROOT}/manifests/monitoring/loki.yaml
echo "✅ Loki config updated"
echo ""

# Step 4: Restart affected deployments
echo "Step 4: Restarting affected deployments..."
kubectl --kubeconfig=${KUBECONFIG} rollout restart deployment/blackbox-exporter -n monitoring
kubectl --kubeconfig=${KUBECONFIG} rollout restart deployment/loki -n monitoring
echo "✅ Deployments restarted"
echo ""

# Step 5: Wait for deployments to be available
echo "Step 5: Waiting for deployments to be ready..."
echo "  - Waiting for blackbox-exporter..."
kubectl --kubeconfig=${KUBECONFIG} -n monitoring wait \
    --for=condition=available deployment/blackbox-exporter \
    --timeout=300s

echo "  - Waiting for Loki..."
kubectl --kubeconfig=${KUBECONFIG} -n monitoring wait \
    --for=condition=available deployment/loki \
    --timeout=300s
echo "✅ All deployments are ready"
echo ""

# Step 6: Verify Jellyfin scheduling
echo "Step 6: Checking Jellyfin pod status..."
JELLYFIN_STATUS=$(kubectl --kubeconfig=${KUBECONFIG} -n jellyfin get pod jellyfin -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

if [ "$JELLYFIN_STATUS" == "Running" ]; then
    echo "✅ Jellyfin pod is running"
elif [ "$JELLYFIN_STATUS" == "Pending" ]; then
    echo "⚠️  Jellyfin pod is pending - checking node..."
    kubectl --kubeconfig=${KUBECONFIG} -n jellyfin describe pod jellyfin | grep -A 10 Events
elif [ "$JELLYFIN_STATUS" == "NotFound" ]; then
    echo "⚠️  Jellyfin pod not found - may need to be deployed"
else
    echo "⚠️  Jellyfin pod status: $JELLYFIN_STATUS"
fi
echo ""

# Step 7: Display final status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Final Status Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Monitoring Pods:"
kubectl --kubeconfig=${KUBECONFIG} -n monitoring get pods | grep -E "NAME|blackbox|loki"
echo ""

echo "Jellyfin Pods:"
kubectl --kubeconfig=${KUBECONFIG} -n jellyfin get pods -o wide 2>/dev/null || echo "Jellyfin namespace not found"
echo ""

echo "Node Status:"
kubectl --kubeconfig=${KUBECONFIG} get nodes
echo ""

# Step 8: Test endpoints
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Endpoint Health Checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

NODE_IP=$(kubectl --kubeconfig=${KUBECONFIG} get nodes masternode -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

echo "Testing blackbox-exporter metrics endpoint..."
if curl -s -I http://${NODE_IP}:9115/metrics | grep -q "200 OK"; then
    echo "✅ Blackbox Exporter: http://${NODE_IP}:9115/metrics - OK"
else
    echo "❌ Blackbox Exporter: http://${NODE_IP}:9115/metrics - FAILED"
fi

echo "Testing Loki ready endpoint..."
if curl -s http://${NODE_IP}:31100/ready | grep -q "ready"; then
    echo "✅ Loki: http://${NODE_IP}:31100/ready - OK"
else
    echo "❌ Loki: http://${NODE_IP}:31100/ready - FAILED"
fi

echo "Testing Grafana..."
if curl -s -I http://${NODE_IP}:30300 | grep -q "200 OK"; then
    echo "✅ Grafana: http://${NODE_IP}:30300 - OK"
else
    echo "❌ Grafana: http://${NODE_IP}:30300 - FAILED"
fi

echo "Testing Prometheus..."
if curl -s -I http://${NODE_IP}:30090 | grep -q "200 OK"; then
    echo "✅ Prometheus: http://${NODE_IP}:30090 - OK"
else
    echo "❌ Prometheus: http://${NODE_IP}:30090 - FAILED"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Monitoring Stack Fix Application Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Access URLs:"
echo "  - Grafana:          http://${NODE_IP}:30300"
echo "  - Prometheus:       http://${NODE_IP}:30090"
echo "  - Blackbox Metrics: http://${NODE_IP}:9115/metrics"
echo "  - Loki:             http://${NODE_IP}:31100"
echo ""
echo "Next Steps:"
echo "  1. Check logs: kubectl --kubeconfig=${KUBECONFIG} -n monitoring logs deployment/blackbox-exporter"
echo "  2. Check logs: kubectl --kubeconfig=${KUBECONFIG} -n monitoring logs deployment/loki"
echo "  3. Monitor pods: kubectl --kubeconfig=${KUBECONFIG} -n monitoring get pods -w"
echo ""

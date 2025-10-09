#!/bin/bash
# VMStation Monitoring Stack - Permission and DNS Fix Script
# Date: October 9, 2025
# Purpose: Fix Prometheus/Loki permission errors and Grafana DNS resolution issues

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VMStation Monitoring Stack - Quick Fix"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This script will:"
echo "  1. Fix directory ownership for Prometheus, Loki, and Grafana"
echo "  2. Restart monitoring pods to apply fixes"
echo "  3. Wait for pods to become ready"
echo ""

# Fix directory permissions
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Fixing directory permissions..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sudo chown -R 65534:65534 /srv/monitoring_data/prometheus
echo "✅ Prometheus directory ownership set to 65534:65534"

sudo chown -R 10001:10001 /srv/monitoring_data/loki
echo "✅ Loki directory ownership set to 10001:10001"

sudo chown -R 472:472 /srv/monitoring_data/grafana
echo "✅ Grafana directory ownership set to 472:472"

sudo chmod -R 755 /srv/monitoring_data
echo "✅ Directory permissions set to 755"

# Delete pods to force recreation
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Restarting monitoring pods..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

kubectl --kubeconfig=/etc/kubernetes/admin.conf delete pod -n monitoring prometheus-0 --force --grace-period=0 2>/dev/null || echo "Prometheus pod already deleted or not found"
echo "✅ Prometheus pod deleted"

kubectl --kubeconfig=/etc/kubernetes/admin.conf delete pod -n monitoring loki-0 --force --grace-period=0 2>/dev/null || echo "Loki pod already deleted or not found"
echo "✅ Loki pod deleted"

GRAFANA_POD=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$GRAFANA_POD" ]; then
    kubectl --kubeconfig=/etc/kubernetes/admin.conf delete pod -n monitoring "$GRAFANA_POD" --force --grace-period=0 2>/dev/null || echo "Grafana pod already deleted"
    echo "✅ Grafana pod deleted"
else
    echo "⚠️  Grafana pod not found"
fi

# Wait for pods to be recreated
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Waiting for pods to become ready..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Waiting for Prometheus (timeout: 5 minutes)..."
kubectl --kubeconfig=/etc/kubernetes/admin.conf wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s 2>&1 | grep -v "no matching resources found" || echo "⚠️  Prometheus not ready yet"

echo "Waiting for Loki (timeout: 10 minutes)..."
kubectl --kubeconfig=/etc/kubernetes/admin.conf wait --for=condition=ready pod -l app=loki -n monitoring --timeout=600s 2>&1 | grep -v "no matching resources found" || echo "⚠️  Loki not ready yet (this can take several minutes)"

echo "Waiting for Grafana (timeout: 3 minutes)..."
kubectl --kubeconfig=/etc/kubernetes/admin.conf wait --for=condition=ready pod -l app=grafana -n monitoring --timeout=180s 2>&1 | grep -v "no matching resources found" || echo "⚠️  Grafana not ready yet"

# Display final status
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Quick Fix Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next Steps:"
echo "  1. Check pod logs: kubectl logs -n monitoring <pod-name>"
echo "  2. Access Grafana: http://192.168.4.63:30300"
echo "  3. Access Prometheus: http://192.168.4.63:30090"
echo "  4. Check Loki: curl http://192.168.4.63:31100/ready"
echo ""
echo "If pods are still not ready after 10 minutes, check logs:"
echo "  kubectl logs -n monitoring prometheus-0"
echo "  kubectl logs -n monitoring loki-0"
echo ""

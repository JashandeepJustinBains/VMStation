#!/bin/bash

# VMStation Post-Deployment Validation Script
# Run this after deploying the cluster to verify all fixes are working

echo "=== VMStation Post-Deployment Validation ==="
echo "Timestamp: $(date)"
echo

# Check if we have kubectl access
if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ kubectl not found. Please run this script on the control plane node."
    exit 1
fi

if ! kubectl get nodes >/dev/null 2>&1; then
    echo "❌ Cannot access Kubernetes cluster. Ensure you're on the control plane."
    exit 1
fi

echo "✅ kubectl access confirmed"
echo

# Test 1: DNS Resolution
echo "=== Testing DNS Resolution ==="

# Test homelab.com subdomain resolution using hosts file
for subdomain in jellyfin.homelab.com grafana.homelab.com storage.homelab.com; do
    if getent hosts "$subdomain" >/dev/null 2>&1; then
        IP=$(getent hosts "$subdomain" | awk '{print $1}')
        echo "✅ $subdomain resolves to $IP"
    else
        echo "❌ $subdomain does not resolve"
    fi
done
echo

# Test 2: Monitoring Pod Scheduling
echo "=== Testing Monitoring Pod Scheduling ==="

# Check if Grafana is running on control plane
GRAFANA_NODE=$(kubectl get pods -n monitoring -l app=grafana -o wide --no-headers 2>/dev/null | awk '{print $7}' | head -1)
if [ -n "$GRAFANA_NODE" ]; then
    if kubectl get node "$GRAFANA_NODE" --no-headers | grep -q "control-plane"; then
        echo "✅ Grafana is running on control plane node: $GRAFANA_NODE"
    else
        echo "⚠️  Grafana is running on worker node: $GRAFANA_NODE"
    fi
else
    echo "❌ Grafana pod not found"
fi

# Check if Prometheus is running on control plane  
PROMETHEUS_NODE=$(kubectl get pods -n monitoring -l app=prometheus -o wide --no-headers 2>/dev/null | awk '{print $7}' | head -1)
if [ -n "$PROMETHEUS_NODE" ]; then
    if kubectl get node "$PROMETHEUS_NODE" --no-headers | grep -q "control-plane"; then
        echo "✅ Prometheus is running on control plane node: $PROMETHEUS_NODE"
    else
        echo "⚠️  Prometheus is running on worker node: $PROMETHEUS_NODE"
    fi
else
    echo "❌ Prometheus pod not found"
fi
echo

# Test 3: Service Accessibility
echo "=== Testing Service Accessibility ==="

# Test Jellyfin access
echo "Testing Jellyfin access..."
if timeout 10 curl -s -f --connect-timeout 3 "http://192.168.4.61:30096/health" 2>/dev/null | grep -q "Healthy"; then
    echo "✅ Jellyfin health endpoint accessible and healthy at 192.168.4.61:30096"
elif timeout 10 curl -s -f --connect-timeout 3 "http://192.168.4.61:30096/" >/dev/null 2>&1; then
    echo "✅ Jellyfin web interface accessible at 192.168.4.61:30096"
else
    echo "❌ Jellyfin not accessible at 192.168.4.61:30096"
fi

if timeout 10 curl -s -f --connect-timeout 3 "http://jellyfin.homelab.com:30096/" >/dev/null 2>&1; then
    echo "✅ Jellyfin accessible via subdomain: jellyfin.homelab.com:30096"
else
    echo "❌ Jellyfin not accessible via subdomain"
fi

# Test Grafana access
echo "Testing Grafana access..."
if timeout 10 curl -s --connect-timeout 3 "http://192.168.4.63:30300/" >/dev/null 2>&1; then
    echo "✅ Grafana accessible at 192.168.4.63:30300"
else
    echo "❌ Grafana not accessible at 192.168.4.63:30300"
fi

if timeout 10 curl -s --connect-timeout 3 "http://grafana.homelab.com:30300/" >/dev/null 2>&1; then
    echo "✅ Grafana accessible via subdomain: grafana.homelab.com:30300"
else
    echo "❌ Grafana not accessible via subdomain"
fi

# Test Prometheus access
echo "Testing Prometheus access..."
if timeout 10 curl -s --connect-timeout 3 "http://192.168.4.63:30090/" >/dev/null 2>&1; then
    echo "✅ Prometheus accessible at 192.168.4.63:30090"
else
    echo "❌ Prometheus not accessible at 192.168.4.63:30090"
fi
echo

# Test 4: Homelab Node Health
echo "=== Testing Homelab Node Health ==="

# Check homelab node status
HOMELAB_STATUS=$(kubectl get node homelab --no-headers 2>/dev/null | awk '{print $2}')
if [ "$HOMELAB_STATUS" = "Ready" ]; then
    echo "✅ Homelab node is Ready"
else
    echo "⚠️  Homelab node status: $HOMELAB_STATUS"
fi

# Check for crashlooping pods on homelab
HOMELAB_CRASHES=$(kubectl get pods --all-namespaces -o wide | grep "homelab" | grep -E "(CrashLoopBackOff|Error|Unknown)" | wc -l)
if [ "$HOMELAB_CRASHES" -eq 0 ]; then
    echo "✅ No crashlooping pods on homelab node"
else
    echo "⚠️  Found $HOMELAB_CRASHES crashlooping pods on homelab node:"
    kubectl get pods --all-namespaces -o wide | grep "homelab" | grep -E "(CrashLoopBackOff|Error|Unknown)"
fi

# Check flannel and kube-proxy on homelab
FLANNEL_STATUS=$(kubectl get pods -n kube-flannel -o wide | grep "homelab" | awk '{print $3}' | head -1)
PROXY_STATUS=$(kubectl get pods -n kube-system -o wide | grep "kube-proxy" | grep "homelab" | awk '{print $3}' | head -1)

if [ "$FLANNEL_STATUS" = "Running" ]; then
    echo "✅ Flannel pod running on homelab"
else
    echo "⚠️  Flannel pod status on homelab: $FLANNEL_STATUS"
fi

if [ "$PROXY_STATUS" = "Running" ]; then
    echo "✅ kube-proxy pod running on homelab"
else
    echo "⚠️  kube-proxy pod status on homelab: $PROXY_STATUS"
fi
echo

# Summary
echo "=== Validation Summary ==="
echo
echo "🎯 Quick Access Commands:"
echo "  • Jellyfin:    curl http://jellyfin.homelab.com:30096/"
echo "  • Grafana:     curl http://grafana.homelab.com:30300/"
echo "  • Prometheus:  curl http://192.168.4.63:30090/"
echo
echo "📊 Web UI Access:"
echo "  • Jellyfin:    http://jellyfin.homelab.com:30096"
echo "  • Grafana:     http://grafana.homelab.com:30300 (admin/admin)"
echo "  • Prometheus:  http://192.168.4.63:30090"
echo
echo "If any tests failed, check the deployment logs and ensure the cluster is fully deployed."
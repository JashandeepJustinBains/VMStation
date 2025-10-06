#!/usr/bin/env bash
# Test script: Smoke tests - verify cluster is operational
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "========================================="
echo "VMStation Smoke Tests"
echo "========================================="
echo ""

FAILED=0

# Test 1: Check Debian cluster nodes
echo "[1/7] Checking Debian cluster nodes..."
if kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes 2>&1 | grep -q "Ready"; then
    NODES_COUNT=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --no-headers 2>/dev/null | wc -l)
    echo "  ✅ Debian cluster nodes: $NODES_COUNT node(s) Ready"
else
    echo "  ❌ Debian cluster nodes NOT Ready"
    FAILED=$((FAILED + 1))
fi

# Test 2: Check kube-system pods
echo ""
echo "[2/7] Checking kube-system pods..."
CRASHLOOP_COUNT=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system 2>/dev/null | grep -c "CrashLoopBackOff" || echo "0")
if [ "$CRASHLOOP_COUNT" -eq 0 ]; then
    echo "  ✅ No CrashLoopBackOff pods in kube-system"
else
    echo "  ❌ Found $CRASHLOOP_COUNT CrashLoopBackOff pod(s) in kube-system"
    kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n kube-system | grep "CrashLoopBackOff" || true
    FAILED=$((FAILED + 1))
fi

# Test 3: Check Flannel DaemonSet
echo ""
echo "[3/7] Checking Flannel DaemonSet..."
if kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-flannel get daemonset kube-flannel 2>&1 | grep -q "kube-flannel"; then
    DESIRED=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-flannel get daemonset kube-flannel -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
    READY=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-flannel get daemonset kube-flannel -o jsonpath='{.status.numberReady}' 2>/dev/null)
    if [ "$DESIRED" = "$READY" ]; then
        echo "  ✅ Flannel DaemonSet ready: $READY/$DESIRED pods"
    else
        echo "  ❌ Flannel DaemonSet NOT ready: $READY/$DESIRED pods"
        FAILED=$((FAILED + 1))
    fi
else
    echo "  ❌ Flannel DaemonSet not found"
    FAILED=$((FAILED + 1))
fi

# Test 4: Check kube-proxy
echo ""
echo "[4/7] Checking kube-proxy pods..."
KUBE_PROXY_COUNT=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system get pods -l k8s-app=kube-proxy --no-headers 2>/dev/null | grep "Running" | wc -l)
if [ "$KUBE_PROXY_COUNT" -gt 0 ]; then
    echo "  ✅ kube-proxy pods running: $KUBE_PROXY_COUNT pod(s)"
else
    echo "  ❌ No kube-proxy pods running"
    FAILED=$((FAILED + 1))
fi

# Test 5: Check CoreDNS
echo ""
echo "[5/7] Checking CoreDNS pods..."
COREDNS_COUNT=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system get pods -l k8s-app=kube-dns --no-headers 2>/dev/null | grep "Running" | wc -l)
if [ "$COREDNS_COUNT" -ge 2 ]; then
    echo "  ✅ CoreDNS pods running: $COREDNS_COUNT pod(s)"
else
    echo "  ⚠️  WARNING: Only $COREDNS_COUNT CoreDNS pod(s) running (expected 2+)"
fi

# Test 6: Check RKE2 cluster (if deployed)
echo ""
echo "[6/7] Checking RKE2 cluster..."
if [ -f ansible/artifacts/homelab-rke2-kubeconfig.yaml ]; then
    export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
    if kubectl get nodes 2>&1 | grep -q "Ready"; then
        RKE2_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
        echo "  ✅ RKE2 cluster nodes: $RKE2_NODES node(s) Ready"
    else
        echo "  ❌ RKE2 cluster nodes NOT Ready"
        FAILED=$((FAILED + 1))
    fi
    unset KUBECONFIG
else
    echo "  ⚠️  RKE2 kubeconfig not found (cluster may not be deployed)"
fi

# Test 7: Check Jellyfin (if deployed)
echo ""
echo "[7/7] Checking Jellyfin deployment..."
if kubectl --kubeconfig=/etc/kubernetes/admin.conf get deployment jellyfin 2>/dev/null | grep -q "jellyfin"; then
    JELLYFIN_READY=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get deployment jellyfin -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$JELLYFIN_READY" -gt 0 ]; then
        echo "  ✅ Jellyfin deployment ready: $JELLYFIN_READY replica(s)"
        
        # Try to get Jellyfin service NodePort
        JELLYFIN_PORT=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get svc jellyfin -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "unknown")
        if [ "$JELLYFIN_PORT" != "unknown" ]; then
            echo "  ℹ️  Jellyfin accessible at: http://192.168.4.61:$JELLYFIN_PORT"
        fi
    else
        echo "  ❌ Jellyfin deployment NOT ready"
        FAILED=$((FAILED + 1))
    fi
else
    echo "  ⚠️  Jellyfin deployment not found (may not be deployed yet)"
fi

echo ""
echo "========================================="
if [ $FAILED -eq 0 ]; then
    echo "✅ All smoke tests PASSED"
    echo "========================================="
    exit 0
else
    echo "❌ $FAILED test(s) FAILED"
    echo "========================================="
    echo ""
    echo "Run troubleshooting:"
    echo "  kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A"
    echo "  kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide"
    exit 1
fi

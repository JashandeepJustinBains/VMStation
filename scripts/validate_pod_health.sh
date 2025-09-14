#!/bin/bash

# Validate VMStation Pod Fixes
# Quick validation script to check if the pod issues have been resolved

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=== VMStation Pod Health Validation ==="
echo "Timestamp: $(date)"
echo

# Check if we have kubectl access
if ! timeout 30 kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    exit 1
fi

info "Checking cluster health..."

# Check node status
echo "=== Node Status ==="
kubectl get nodes -o wide

# Check critical system pods
echo
echo "=== System Pod Status ==="
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
kubectl get pods -n kube-flannel -o wide
kubectl get pods -n kube-system -l component=kube-proxy -o wide

# Check jellyfin specifically
echo
echo "=== Jellyfin Status ==="
if kubectl get namespace jellyfin >/dev/null 2>&1; then
    kubectl get pods -n jellyfin -o wide
    
    # Check jellyfin readiness
    JELLYFIN_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    JELLYFIN_RESTARTS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
    
    if [ "$JELLYFIN_READY" = "true" ]; then
        info "✅ Jellyfin pod is ready"
        
        # Additional health check using /health endpoint
        JELLYFIN_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}' 2>/dev/null)
        if [ -n "$JELLYFIN_IP" ]; then
            echo "Testing Jellyfin health endpoint..."
            HEALTH_RESPONSE=$(kubectl run health-test-$$RANDOM --image=busybox:1.35 --rm -i --restart=Never --timeout=30s -- \
                sh -c "wget -qO- http://$JELLYFIN_IP:8096/health" 2>/dev/null || echo "")
            
            if echo "$HEALTH_RESPONSE" | grep -q "Healthy"; then
                info "✅ Jellyfin health check passed (health endpoint responds 'Healthy')"
            elif [ -n "$HEALTH_RESPONSE" ]; then
                warn "⚠️  Jellyfin health endpoint responded but didn't contain 'Healthy': $HEALTH_RESPONSE"
            else
                warn "⚠️  Jellyfin health endpoint test failed or timed out"
            fi
        fi
    else
        warn "❌ Jellyfin pod is not ready (restarts: $JELLYFIN_RESTARTS)"
    fi
else
    warn "Jellyfin namespace not found"
fi

# Check monitoring pods
echo
echo "=== Monitoring Pod Status ==="
if kubectl get namespace monitoring >/dev/null 2>&1; then
    kubectl get pods -n monitoring -o wide
else
    warn "Monitoring namespace not found"
fi

# Summary of issues
echo
echo "=== Issue Summary ==="

CRASHLOOP_COUNT=$(kubectl get pods --all-namespaces | grep -c "CrashLoopBackOff" || echo "0")
PENDING_COUNT=$(kubectl get pods --all-namespaces | grep -c "Pending\|ContainerCreating" || echo "0")
ERROR_COUNT=$(kubectl get pods --all-namespaces | grep -c "Error" || echo "0")

echo "Pods in CrashLoopBackOff: $CRASHLOOP_COUNT"
echo "Pods Pending/ContainerCreating: $PENDING_COUNT"
echo "Pods in Error state: $ERROR_COUNT"

JELLYFIN_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")

if [ "$JELLYFIN_READY" = "true" ]; then
    echo "Jellyfin readiness: ✅ Ready"
    
    # Check health endpoint as well
    JELLYFIN_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}' 2>/dev/null)
    if [ -n "$JELLYFIN_IP" ]; then
        HEALTH_RESPONSE=$(kubectl run health-check-$$RANDOM --image=busybox:1.35 --rm -i --restart=Never --timeout=20s -- \
            sh -c "wget -qO- http://$JELLYFIN_IP:8096/health" 2>/dev/null || echo "")
        
        if echo "$HEALTH_RESPONSE" | grep -q "Healthy"; then
            echo "Jellyfin health endpoint: ✅ Healthy"
            JELLYFIN_HEALTH_OK="true"
        else
            echo "Jellyfin health endpoint: ❌ Not Healthy"
            JELLYFIN_HEALTH_OK="false"
        fi
    else
        echo "Jellyfin health endpoint: ❌ Cannot determine (no pod IP)"
        JELLYFIN_HEALTH_OK="false"
    fi
else
    echo "Jellyfin readiness: ❌ Not Ready"
    JELLYFIN_HEALTH_OK="false"
fi

# Overall health assessment
TOTAL_ISSUES=$((CRASHLOOP_COUNT + PENDING_COUNT + ERROR_COUNT))

if [ "$TOTAL_ISSUES" -eq 0 ] && [ "$JELLYFIN_READY" = "true" ] && [ "$JELLYFIN_HEALTH_OK" = "true" ]; then
    info "🎉 All pods appear healthy!"
    echo
    echo "Access Jellyfin at: http://192.168.4.61:30096"
elif [ "$TOTAL_ISSUES" -eq 0 ] && [ "$JELLYFIN_READY" = "true" ]; then
    warn "⚠️  System pods are healthy, Jellyfin pod is ready, but health check failed"
    echo
    echo "Jellyfin may be starting up or health endpoint may need attention"
    echo "Run: ./scripts/fix_remaining_pod_issues.sh"
elif [ "$TOTAL_ISSUES" -eq 0 ]; then
    warn "⚠️  System pods are healthy, but Jellyfin needs attention"
    echo
    echo "Run: ./scripts/fix_remaining_pod_issues.sh"
else
    warn "⚠️  $TOTAL_ISSUES pod issues remain"
    echo
    echo "Recommended actions:"
    echo "1. Run: ./scripts/fix_remaining_pod_issues.sh"
    echo "2. Check logs: kubectl logs -n <namespace> <pod-name>"
    echo "3. Check events: kubectl get events --all-namespaces --sort-by='.lastTimestamp'"
fi

echo
echo "=== Validation Complete ==="
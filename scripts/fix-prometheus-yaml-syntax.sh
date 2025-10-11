#!/bin/bash
# Remediation script for Prometheus YAML syntax error fix
# This script applies the corrected Prometheus configuration and restarts the pod

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    log_error "kubectl not found. Please install kubectl."
    exit 1
fi

# Check kubeconfig
KUBECONFIG=${KUBECONFIG:-~/.kube/config}
if [[ ! -f "$KUBECONFIG" ]]; then
    log_error "Kubeconfig not found at $KUBECONFIG"
    exit 1
fi

echo "========================================="
echo "Prometheus YAML Syntax Error Remediation"
echo "========================================="
echo ""

NAMESPACE="monitoring"
PROMETHEUS_MANIFEST="$REPO_ROOT/manifests/monitoring/prometheus.yaml"

# Step 1: Validate the manifest
log_info "Step 1/5: Validating Prometheus manifest..."
if [[ ! -f "$PROMETHEUS_MANIFEST" ]]; then
    log_error "Prometheus manifest not found at $PROMETHEUS_MANIFEST"
    exit 1
fi

# Run the alerts syntax test
if [[ -x "$REPO_ROOT/tests/test-prometheus-alerts-syntax.sh" ]]; then
    if "$REPO_ROOT/tests/test-prometheus-alerts-syntax.sh" >/dev/null 2>&1; then
        log_success "Manifest validation passed"
    else
        log_error "Manifest validation failed. Please fix YAML syntax errors first."
        exit 1
    fi
else
    log_warn "Test script not found, skipping validation"
fi
echo ""

# Step 2: Check current Prometheus pod status
log_info "Step 2/5: Checking current Prometheus pod status..."
POD_STATUS=$(kubectl get pod prometheus-0 -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [[ "$POD_STATUS" == "NotFound" ]]; then
    log_warn "Prometheus pod not found - will be created when manifest is applied"
else
    log_info "Current pod status: $POD_STATUS"
    if kubectl get pod prometheus-0 -n $NAMESPACE -o jsonpath='{.status.containerStatuses[?(@.name=="prometheus")].state}' 2>/dev/null | grep -q "CrashLoopBackOff"; then
        log_warn "Pod is in CrashLoopBackOff state (expected)"
    fi
fi
echo ""

# Step 3: Apply the corrected ConfigMap
log_info "Step 3/5: Applying corrected Prometheus configuration..."
if kubectl apply -f "$PROMETHEUS_MANIFEST" --kubeconfig="$KUBECONFIG"; then
    log_success "Configuration applied successfully"
else
    log_error "Failed to apply configuration"
    exit 1
fi
echo ""

# Wait a moment for the ConfigMap to be updated
sleep 2

# Step 4: Restart Prometheus pod
log_info "Step 4/5: Restarting Prometheus pod..."
if kubectl get pod prometheus-0 -n $NAMESPACE >/dev/null 2>&1; then
    if kubectl delete pod prometheus-0 -n $NAMESPACE --wait=true --timeout=60s --kubeconfig="$KUBECONFIG"; then
        log_success "Prometheus pod deleted successfully"
    else
        log_error "Failed to delete Prometheus pod"
        exit 1
    fi
else
    log_info "Prometheus pod doesn't exist yet, waiting for StatefulSet to create it..."
fi
echo ""

# Step 5: Wait for pod to become ready
log_info "Step 5/5: Waiting for Prometheus pod to become ready..."
log_info "This may take 1-2 minutes..."

MAX_WAIT=180  # 3 minutes
ELAPSED=0
READY=false

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    # Check if pod exists
    if ! kubectl get pod prometheus-0 -n $NAMESPACE >/dev/null 2>&1; then
        log_info "Waiting for pod to be created..."
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        continue
    fi
    
    # Check pod status
    POD_STATUS=$(kubectl get pod prometheus-0 -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    READY_STATUS=$(kubectl get pod prometheus-0 -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    CONTAINER_READY=$(kubectl get pod prometheus-0 -n $NAMESPACE -o jsonpath='{.status.containerStatuses[?(@.name=="prometheus")].ready}' 2>/dev/null || echo "false")
    
    if [[ "$POD_STATUS" == "Running" ]] && [[ "$READY_STATUS" == "True" ]] && [[ "$CONTAINER_READY" == "true" ]]; then
        READY=true
        break
    fi
    
    # Check for errors
    if kubectl get pod prometheus-0 -n $NAMESPACE -o jsonpath='{.status.containerStatuses[?(@.name=="prometheus")].state}' 2>/dev/null | grep -q "CrashLoopBackOff"; then
        log_warn "Pod is still in CrashLoopBackOff, checking logs..."
        echo ""
        echo "Recent logs:"
        kubectl logs prometheus-0 -n $NAMESPACE --tail=20 2>&1 || true
        echo ""
    fi
    
    log_info "Pod status: $POD_STATUS, Ready: $READY_STATUS (${ELAPSED}s elapsed)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo ""
echo "========================================="
if [[ "$READY" == "true" ]]; then
    log_success "Prometheus pod is now ready!"
    echo ""
    log_info "Pod status:"
    kubectl get pod prometheus-0 -n $NAMESPACE
    echo ""
    log_info "Checking for recent errors in logs..."
    if kubectl logs prometheus-0 -n $NAMESPACE --tail=50 | grep -i "error\|fail\|fatal" | grep -v "level=info"; then
        log_warn "Some errors found in logs (see above)"
    else
        log_success "No errors found in recent logs"
    fi
    echo ""
    log_success "Remediation completed successfully!"
    echo ""
    echo "Next steps:"
    echo "  - Verify Prometheus is scraping targets: kubectl port-forward -n monitoring prometheus-0 9090:9090"
    echo "  - Check Prometheus web UI at http://localhost:9090"
    echo "  - Verify alerts are loaded at http://localhost:9090/alerts"
    exit 0
else
    log_error "Prometheus pod did not become ready within $MAX_WAIT seconds"
    echo ""
    log_info "Current pod status:"
    kubectl get pod prometheus-0 -n $NAMESPACE
    echo ""
    log_info "Recent events:"
    kubectl describe pod prometheus-0 -n $NAMESPACE | grep -A 10 "Events:"
    echo ""
    log_info "Recent logs:"
    kubectl logs prometheus-0 -n $NAMESPACE --tail=50 2>&1 || true
    echo ""
    log_error "Remediation failed - please investigate the logs above"
    exit 1
fi

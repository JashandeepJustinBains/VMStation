#!/bin/bash

# VMStation API Server Authorization Mode Fix Script
# Fixes the kube-apiserver authorization mode from AlwaysAllow to Node,RBAC
# Addresses HTTP 401 health check failures and restores proper cluster security

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (try: sudo $0)"
    exit 1
fi

# Check if this is a control plane node
if [ ! -f /etc/kubernetes/admin.conf ]; then
    error "This script must be run on a Kubernetes control plane node"
    error "Missing: /etc/kubernetes/admin.conf"
    exit 1
fi

export KUBECONFIG=/etc/kubernetes/admin.conf

info "Starting VMStation API Server Authorization Mode Fix..."
echo ""

# Step 1: Check current API server status
info "1. Checking current API server status..."

if ! kubectl get nodes --request-timeout=10s >/dev/null 2>&1; then
    warn "API server is not responding to kubectl requests"
else
    success "API server is responding to kubectl requests"
fi

# Check current authorization mode
info "Checking current authorization mode..."
current_auth_mode=$(kubectl get pods -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].spec.containers[0].command}' 2>/dev/null | grep -o '\--authorization-mode=[^[:space:]]*' | cut -d= -f2 || echo "unknown")
info "Current authorization mode: $current_auth_mode"

if [[ "$current_auth_mode" == "AlwaysAllow" ]]; then
    error "API server is running in insecure AlwaysAllow mode!"
    info "This is the root cause of health check failures"
    NEEDS_AUTH_FIX=true
else
    success "Authorization mode is secure: $current_auth_mode"
    NEEDS_AUTH_FIX=false
fi

# Step 2: Check API server health status
info ""
info "2. Checking API server pod health..."

api_pod_status=$(kubectl get pods -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "unknown")
api_pod_ready=$(kubectl get pods -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "unknown")

info "API server pod status: $api_pod_status"
info "API server pod ready: $api_pod_ready"

if [[ "$api_pod_ready" != "True" ]]; then
    error "API server pod is not Ready"
    
    # Show recent events
    info "Recent API server pod events:"
    kubectl describe pod -n kube-system -l component=kube-apiserver | tail -20 || true
fi

# Step 3: Fix authorization mode if needed
if [[ "$NEEDS_AUTH_FIX" == "true" ]]; then
    info ""
    info "3. Fixing API server authorization mode..."
    
    # Backup current manifest
    cp /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml.backup
    success "Backed up API server manifest"
    
    # Fix the authorization mode
    info "Updating authorization mode from AlwaysAllow to Node,RBAC..."
    sed -i 's/--authorization-mode=AlwaysAllow/--authorization-mode=Node,RBAC/g' /etc/kubernetes/manifests/kube-apiserver.yaml
    
    if grep -q "authorization-mode=Node,RBAC" /etc/kubernetes/manifests/kube-apiserver.yaml; then
        success "Authorization mode updated to Node,RBAC"
    else
        error "Failed to update authorization mode"
        # Restore backup
        cp /etc/kubernetes/manifests/kube-apiserver.yaml.backup /etc/kubernetes/manifests/kube-apiserver.yaml
        exit 1
    fi
    
    info "Waiting for API server pod to restart..."
    sleep 30
    
    # Wait for new pod to start
    for i in {1..30}; do
        if kubectl get pods -n kube-system -l component=kube-apiserver --no-headers 2>/dev/null | grep -q "Running"; then
            success "API server pod restarted"
            break
        fi
        if [[ $i -eq 30 ]]; then
            error "API server pod did not restart within 5 minutes"
            exit 1
        fi
        sleep 10
    done
else
    info ""
    info "3. Authorization mode is already secure, skipping fix"
fi

# Step 4: Ensure proper RBAC configuration
info ""
info "4. Ensuring proper RBAC configuration..."

# Wait for API server to be fully ready
info "Waiting for API server to be ready..."
for i in {1..60}; do
    if kubectl get nodes --request-timeout=5s >/dev/null 2>&1; then
        success "API server is responding"
        break
    fi
    if [[ $i -eq 60 ]]; then
        error "API server is not responding after 5 minutes"
        exit 1
    fi
    sleep 5
done

# Check RBAC permissions
info "Checking kubernetes-admin RBAC permissions..."
if kubectl auth can-i create secrets --namespace=kube-system 2>/dev/null | grep -q "yes"; then
    success "kubernetes-admin has proper permissions"
else
    warn "kubernetes-admin lacks proper permissions, fixing..."
    
    # Create/update the ClusterRoleBinding
    kubectl create clusterrolebinding kubernetes-admin \
        --clusterrole=cluster-admin \
        --user=kubernetes-admin \
        --dry-run=client -o yaml | kubectl apply -f -
    
    success "Applied kubernetes-admin ClusterRoleBinding"
    
    # Verify fix
    if kubectl auth can-i create secrets --namespace=kube-system 2>/dev/null | grep -q "yes"; then
        success "RBAC permissions verified"
    else
        error "RBAC permissions still not working"
        exit 1
    fi
fi

# Step 5: Verify API server health
info ""
info "5. Verifying API server health..."

# Check pod readiness
api_pod_ready=$(kubectl get pods -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "unknown")

if [[ "$api_pod_ready" == "True" ]]; then
    success "API server pod is Ready"
else
    error "API server pod is still not Ready"
    
    info "Checking API server logs..."
    kubectl logs -n kube-system -l component=kube-apiserver --tail=50 || true
    
    exit 1
fi

# Test join command generation
info "Testing join command generation..."
if kubeadm token create --print-join-command >/dev/null 2>&1; then
    success "Join command generation works"
else
    error "Join command generation failed"
    exit 1
fi

# Step 6: Final verification
info ""
info "6. Final cluster health verification..."

# Check all control plane components
kubectl get pods -n kube-system

echo ""
success "API server authorization mode fix completed successfully!"
echo ""
info "Summary of changes:"
if [[ "$NEEDS_AUTH_FIX" == "true" ]]; then
    echo "  ✓ Fixed authorization mode: AlwaysAllow → Node,RBAC"
fi
echo "  ✓ Verified RBAC permissions for kubernetes-admin"
echo "  ✓ API server pod is healthy and ready"
echo "  ✓ Join command generation is working"
echo ""
info "The cluster should now be ready for worker node joins."
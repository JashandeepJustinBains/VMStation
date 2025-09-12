#!/bin/bash

# Diagnose Remaining Pod Issues
# This script analyzes specific pod failures mentioned in the problem statement

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

echo "=== VMStation Pod Issues Diagnostic ==="
echo "Timestamp: $(date)"
echo

# Check if we have kubectl access
if ! timeout 30 kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster or kubectl timed out"
    echo "Please ensure this script is run from the control plane node with kubectl configured"
    exit 1
fi

info "Step 1: Current cluster overview"
echo "=== Cluster Nodes ==="
kubectl get nodes -o wide

echo
echo "=== All Pod Status ==="
kubectl get pods --all-namespaces -o wide

echo
info "Step 2: Jellyfin pod analysis"

JELLYFIN_STATUS=$(kubectl get pods -n jellyfin jellyfin -o json 2>/dev/null || echo "null")

if [ "$JELLYFIN_STATUS" != "null" ]; then
    echo "=== Jellyfin Pod Details ==="
    kubectl get pod -n jellyfin jellyfin -o wide
    
    echo
    echo "=== Jellyfin Pod Conditions ==="
    kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.conditions[*]}' | jq -r '.[]' 2>/dev/null || \
    kubectl get pod -n jellyfin jellyfin -o json | grep -A 10 -B 2 '"conditions"'
    
    echo
    echo "=== Jellyfin Container Status ==="
    kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[*]}' | jq -r '.[]' 2>/dev/null || \
    kubectl get pod -n jellyfin jellyfin -o json | grep -A 20 '"containerStatuses"'
    
    echo
    echo "=== Jellyfin Pod Events ==="
    kubectl describe pod -n jellyfin jellyfin | grep -A 20 "Events:"
    
    echo
    echo "=== Jellyfin Recent Logs (last 50 lines) ==="
    kubectl logs -n jellyfin jellyfin --tail=50 2>/dev/null || echo "Could not retrieve logs"
    
    echo
    echo "=== Jellyfin Readiness/Liveness Probe Analysis ==="
    PROBE_PATH=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.containers[0].readinessProbe.httpGet.path}' 2>/dev/null || echo "N/A")
    PROBE_PORT=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.containers[0].readinessProbe.httpGet.port}' 2>/dev/null || echo "N/A")
    echo "Readiness probe: $PROBE_PATH on port $PROBE_PORT"
    
    # Test the probe endpoint from within the cluster
    JELLYFIN_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}' 2>/dev/null)
    if [ -n "$JELLYFIN_IP" ]; then
        echo "Pod IP: $JELLYFIN_IP"
        echo "Testing readiness endpoint from cluster..."
        kubectl run probe-test --image=busybox:1.35 --rm -i --restart=Never -- \
            sh -c "wget -qO- http://$JELLYFIN_IP:8096/health || echo 'Health endpoint failed'" 2>/dev/null || \
            echo "Could not test health endpoint"
    fi
    
else
    warn "Jellyfin pod not found"
fi

echo
info "Step 3: kube-proxy CrashLoopBackOff analysis (homelab node)"

PROXY_PODS=$(kubectl get pods -n kube-system -l component=kube-proxy -o wide | grep homelab || echo "")

if [ -n "$PROXY_PODS" ]; then
    PROXY_POD_NAME=$(echo "$PROXY_PODS" | awk '{print $1}')
    
    echo "=== kube-proxy Pod on homelab ==="
    kubectl get pod -n kube-system "$PROXY_POD_NAME" -o wide
    
    echo
    echo "=== kube-proxy Container Status ==="
    kubectl get pod -n kube-system "$PROXY_POD_NAME" -o jsonpath='{.status.containerStatuses[*]}' | jq -r '.[]' 2>/dev/null || \
    kubectl get pod -n kube-system "$PROXY_POD_NAME" -o json | grep -A 20 '"containerStatuses"'
    
    echo
    echo "=== kube-proxy Pod Events ==="
    kubectl describe pod -n kube-system "$PROXY_POD_NAME" | grep -A 20 "Events:"
    
    echo
    echo "=== kube-proxy Recent Logs ==="
    kubectl logs -n kube-system "$PROXY_POD_NAME" --tail=50 2>/dev/null || echo "Could not retrieve logs"
    
    echo
    echo "=== kube-proxy Previous Logs (if available) ==="
    kubectl logs -n kube-system "$PROXY_POD_NAME" --previous --tail=30 2>/dev/null || echo "No previous logs available"
    
else
    warn "kube-proxy pod on homelab not found"
fi

echo
info "Step 4: Overall networking and CNI status"

echo "=== Flannel Pod Status ==="
kubectl get pods -n kube-flannel -o wide

echo
echo "=== Recent cluster events ==="
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20

echo
echo "=== Node conditions ==="
kubectl get nodes -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[?(@.type=='Ready')].status,REASON:.status.conditions[?(@.type=='Ready')].reason"

echo
echo "=== CNI Configuration Check ==="
echo "Checking cni0 bridge status on control plane..."
if ip addr show cni0 >/dev/null 2>&1; then
    ip addr show cni0 | grep inet
else
    echo "No cni0 bridge found"
fi

echo
echo "=== Container Runtime Status ==="
sudo systemctl status containerd --no-pager -l | head -20

echo
info "Step 5: Directory and volume checks for jellyfin"

echo "=== Jellyfin Volume Directories ==="
if [ -d "/srv/media" ]; then
    echo "Media directory exists:"
    ls -la /srv/media | head -5
    echo "Media directory permissions:"
    stat /srv/media
else
    warn "/srv/media directory does not exist"
fi

if [ -d "/var/lib/jellyfin" ]; then
    echo "Config directory exists:"
    ls -la /var/lib/jellyfin | head -5
    echo "Config directory permissions:"
    stat /var/lib/jellyfin
else
    warn "/var/lib/jellyfin directory does not exist"
fi

echo
info "=== Diagnostic Summary ==="

echo "Issues found:"
JELLYFIN_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
PROXY_CRASHING=$(kubectl get pods -n kube-system -l component=kube-proxy | grep -c "CrashLoopBackOff" || echo "0")
PENDING_PODS=$(kubectl get pods --all-namespaces | grep -c "Pending\|ContainerCreating" || echo "0")

echo "- Jellyfin pod ready: $JELLYFIN_READY"
echo "- kube-proxy pods crashing: $PROXY_CRASHING"
echo "- Pods in Pending/ContainerCreating: $PENDING_PODS"

if [ "$JELLYFIN_READY" = "false" ]; then
    error "Jellyfin pod readiness probe is failing"
fi

if [ "$PROXY_CRASHING" -gt 0 ]; then
    error "$PROXY_CRASHING kube-proxy pods are crashing"
fi

if [ "$PENDING_PODS" -gt 0 ]; then
    warn "$PENDING_PODS pods are not running"
fi

echo
echo "Next steps:"
echo "1. Fix jellyfin health endpoint or probe configuration"
echo "2. Resolve kube-proxy networking issues"
echo "3. Check node-specific networking problems"
echo "4. Validate volume permissions and availability"
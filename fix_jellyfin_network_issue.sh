#!/bin/bash

# Fix Jellyfin "no route to host" Network Issue
# This script addresses the specific CNI bridge configuration problem
# that prevents health probes from reaching the pod IP

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

echo "=== Fix Jellyfin Network Connectivity Issue ==="
echo "Timestamp: $(date)"
echo
echo "This script fixes the 'no route to host' error that prevents"
echo "Jellyfin health probes from connecting to the pod IP."
echo

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl is required but not found"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot connect to Kubernetes cluster"
    error "Please ensure you're running this on the Kubernetes control plane node"
    exit 1
fi

info "Step 1: Diagnosing current network configuration"

# Check current pod status
if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    POD_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
    POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    POD_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    
    echo "Current Jellyfin pod:"
    echo "  Status: $POD_STATUS"
    echo "  Ready: $POD_READY"
    echo "  IP: ${POD_IP:-<none>}"
    
    if [ "$POD_READY" = "true" ]; then
        info "✓ Jellyfin pod is already ready - no action needed"
        exit 0
    fi
else
    warn "Jellyfin pod not found"
fi

# Check CNI bridge configuration
info "Step 2: Checking CNI bridge configuration"

if ip addr show cni0 >/dev/null 2>&1; then
    CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
    if [ -n "$CNI_IP" ]; then
        echo "Current cni0 bridge IP: $CNI_IP"
        
        # Check if it matches expected Flannel subnet
        if echo "$CNI_IP" | grep -q "10.244."; then
            info "✓ CNI bridge IP is in correct Flannel subnet"
            BRIDGE_OK=true
        else
            error "✗ CNI bridge IP ($CNI_IP) is NOT in expected Flannel subnet (10.244.0.0/16)"
            error "This is the root cause of the 'no route to host' errors"
            BRIDGE_OK=false
        fi
    else
        warn "Could not determine cni0 bridge IP"
        BRIDGE_OK=false
    fi
else
    error "✗ No cni0 bridge found"
    error "This indicates CNI networking is not properly initialized"
    BRIDGE_OK=false
fi

# Check Flannel pods
info "Step 3: Checking Flannel networking status"
FLANNEL_READY=0
FLANNEL_TOTAL=0

if kubectl get daemonset -n kube-flannel kube-flannel >/dev/null 2>&1; then
    FLANNEL_READY=$(kubectl get daemonset -n kube-flannel kube-flannel -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    FLANNEL_TOTAL=$(kubectl get daemonset -n kube-flannel kube-flannel -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    echo "Flannel DaemonSet: $FLANNEL_READY/$FLANNEL_TOTAL ready"
    
    if [ "$FLANNEL_READY" -eq "$FLANNEL_TOTAL" ] && [ "$FLANNEL_TOTAL" -gt 0 ]; then
        info "✓ Flannel is running on all nodes"
    else
        warn "⚠ Flannel is not ready on all nodes"
        kubectl get pods -n kube-flannel -o wide
    fi
else
    error "✗ Flannel DaemonSet not found"
fi

# Apply fix if needed
if [ "$BRIDGE_OK" = "false" ]; then
    info "Step 4: Applying CNI bridge fix"
    
    if [ ! -f "scripts/fix_cni_bridge_conflict.sh" ]; then
        error "CNI bridge fix script not found"
        error "Please ensure you're running this from the VMStation repository root"
        exit 1
    fi
    
    warn "This will temporarily restart containerd and kubelet services"
    warn "Some pods may be briefly unavailable during the fix"
    echo
    read -p "Continue with CNI bridge fix? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Running CNI bridge fix..."
        if sudo ./scripts/fix_cni_bridge_conflict.sh; then
            info "✓ CNI bridge fix completed successfully"
            
            # Wait for network to stabilize
            info "Waiting 30 seconds for network to stabilize..."
            sleep 30
            
            # Verify the fix
            if ip addr show cni0 >/dev/null 2>&1; then
                NEW_CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
                if [ -n "$NEW_CNI_IP" ] && echo "$NEW_CNI_IP" | grep -q "10.244."; then
                    info "✓ CNI bridge now has correct IP: $NEW_CNI_IP"
                else
                    warn "CNI bridge IP may still need adjustment: $NEW_CNI_IP"
                fi
            fi
        else
            error "CNI bridge fix failed"
            exit 1
        fi
    else
        warn "CNI bridge fix skipped by user"
        info "The 'no route to host' issue will likely persist"
        exit 1
    fi
else
    info "Step 4: CNI bridge configuration is correct"
fi

# Check if pod needs to be recreated
info "Step 5: Checking if Jellyfin pod needs to be recreated"

if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    # Check for recent network errors in events
    RECENT_ERRORS=$(kubectl get events -n jellyfin --field-selector involvedObject.name=jellyfin --sort-by='.lastTimestamp' -o json 2>/dev/null | jq -r '.items[] | select(.lastTimestamp > (now - 300 | strftime("%Y-%m-%dT%H:%M:%SZ"))) | select(.message | contains("no route to host") or contains("dial tcp")) | .message' 2>/dev/null || echo "")
    
    if [ -n "$RECENT_ERRORS" ]; then
        warn "Detected recent network errors - recreating pod to reset probe state"
        
        # Delete and recreate the pod
        kubectl delete pod -n jellyfin jellyfin
        
        # Wait for pod to be fully deleted
        info "Waiting for pod to be fully deleted..."
        while kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; do
            sleep 1
        done
        
        # Recreate the pod
        info "Recreating Jellyfin pod..."
        kubectl apply -f manifests/jellyfin/jellyfin.yaml
        
        # Wait for pod to be created
        info "Waiting for pod to be created..."
        timeout=60
        for i in $(seq 1 $timeout); do
            if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
                info "✓ Pod created successfully"
                break
            fi
            if [ $i -eq $timeout ]; then
                error "Timeout waiting for pod creation"
                exit 1
            fi
            sleep 1
        done
        
        # Wait for pod to become ready
        info "Waiting for pod to become ready (this may take up to 10 minutes)..."
        if kubectl wait --for=condition=ready pod/jellyfin -n jellyfin --timeout=600s; then
            info "✓ Jellyfin pod is now ready!"
        else
            error "Pod did not become ready within timeout"
            error "Check pod status: kubectl describe pod -n jellyfin jellyfin"
            exit 1
        fi
    else
        info "No recent network errors detected - monitoring pod status..."
        
        # Wait for existing pod to become ready
        info "Waiting for existing pod to become ready..."
        if kubectl wait --for=condition=ready pod/jellyfin -n jellyfin --timeout=300s; then
            info "✓ Jellyfin pod is now ready!"
        else
            warn "Pod did not become ready - may need manual intervention"
            kubectl describe pod -n jellyfin jellyfin
            exit 1
        fi
    fi
else
    info "Creating new Jellyfin pod..."
    kubectl apply -f manifests/jellyfin/jellyfin.yaml
    
    # Wait for pod to become ready
    info "Waiting for pod to become ready..."
    if kubectl wait --for=condition=ready pod/jellyfin -n jellyfin --timeout=600s; then
        info "✓ Jellyfin pod is now ready!"
    else
        error "Pod did not become ready within timeout"
        exit 1
    fi
fi

# Final verification
info "Step 6: Final verification"

POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}')
POD_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}')
POD_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}')

echo
echo "=== Final Status ==="
echo "Pod Status: $POD_STATUS"
echo "Pod Ready: $POD_READY"  
echo "Pod IP: $POD_IP"

if [ "$POD_READY" = "true" ]; then
    info "🎉 Success! Jellyfin pod is now ready (1/1)"
    info "Access Jellyfin at: http://192.168.4.61:30096"
    
    # Test connectivity if possible
    if [ -n "$POD_IP" ]; then
        info "Testing connectivity to pod IP..."
        if timeout 10 curl -s --connect-timeout 5 "http://$POD_IP:8096/" >/dev/null 2>&1; then
            info "✓ Pod connectivity test successful"
        else
            info "Pod connectivity test failed, but pod is ready (this may be normal)"
        fi
    fi
else
    error "❌ Pod is still not ready"
    error "Additional troubleshooting may be required"
    echo
    echo "Run these commands for more information:"
    echo "  kubectl describe pod -n jellyfin jellyfin"
    echo "  kubectl logs -n jellyfin jellyfin"
    echo "  kubectl get events -n jellyfin --sort-by='.lastTimestamp'"
fi

echo
info "Fix complete!"
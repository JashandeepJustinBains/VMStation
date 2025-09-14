#!/bin/bash

# VMStation Immediate Jellyfin Fix
# Specifically addresses CNI bridge IP conflict preventing Jellyfin pod from starting
# This script can be run without a full cluster reset

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "================================================================"
echo "  VMStation Immediate Jellyfin CNI Bridge Fix                   "
echo "================================================================"
echo "Purpose: Fix CNI bridge IP conflict preventing Jellyfin startup"
echo "Target: Fix without full cluster reset"
echo "Timestamp: $(date)"
echo

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (use sudo)"
    echo "Usage: sudo $0"
    exit 1
fi

# Check kubectl access
if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl is required but not found"
    exit 1
fi

if ! timeout 30 kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    error "Please ensure you're running this from the control plane node with kubectl configured"
    exit 1
fi

# Step 1: Check current Jellyfin pod status
info "Step 1: Checking current Jellyfin pod status"

if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null)
    info "Current Jellyfin pod status: $POD_STATUS"
    
    if [ "$POD_STATUS" = "Running" ]; then
        success "✓ Jellyfin pod is already running"
        POD_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}' 2>/dev/null)
        info "Pod IP: ${POD_IP:-<not assigned>}"
        info "Testing web interface at http://192.168.4.61:30096/web/#/home.html"
        exit 0
    elif [ "$POD_STATUS" = "Pending" ]; then
        warn "Jellyfin pod is in Pending state - likely CNI bridge issue"
    else
        warn "Jellyfin pod in unexpected state: $POD_STATUS"
    fi
else
    info "No Jellyfin pod found - will create after CNI fix"
fi

# Step 2: Check for CNI bridge conflict events
info "Step 2: Checking for CNI bridge conflict events"

CNI_ERRORS=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' 2>/dev/null | \
             grep -E "failed to set bridge addr.*cni0.*already has an IP address different" | \
             tail -3 || echo "")

if [ -n "$CNI_ERRORS" ]; then
    error "✗ Confirmed: CNI bridge IP conflict detected"
    echo "Recent error events:"
    echo "$CNI_ERRORS"
    echo
else
    info "No recent CNI bridge errors found in events"
fi

# Step 3: Check current CNI bridge configuration
info "Step 3: Checking current CNI bridge configuration"

if ip addr show cni0 >/dev/null 2>&1; then
    CURRENT_CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
    info "Current cni0 bridge IP: $CURRENT_CNI_IP"
    
    if echo "$CURRENT_CNI_IP" | grep -q "10.244."; then
        success "✓ CNI bridge has expected IP range"
        CNI_BRIDGE_OK=true
    else
        error "✗ CNI bridge has wrong IP range: $CURRENT_CNI_IP (expected 10.244.x.x)"
        CNI_BRIDGE_CONFLICT=true
    fi
else
    info "No cni0 bridge found"
fi

# Step 4: Apply immediate CNI bridge fix if needed
if [ "${CNI_BRIDGE_CONFLICT:-false}" = true ]; then
    warn "Applying immediate CNI bridge fix..."
    
    info "Step 4a: Stopping kubelet to prevent constant pod sandbox failures"
    systemctl stop kubelet
    
    info "Step 4b: Removing conflicting CNI bridge"
    if ip link show cni0 >/dev/null 2>&1; then
        ip link set cni0 down 2>/dev/null || true
        ip link delete cni0 2>/dev/null || true
        success "Removed conflicting cni0 bridge"
    fi
    
    info "Step 4c: Clearing CNI network state"
    if [ -d "/var/lib/cni" ]; then
        mv /var/lib/cni "/var/lib/cni.backup.$(date +%s)" 2>/dev/null || true
        success "CNI state cleared"
    fi
    
    info "Step 4d: Restarting container runtime"
    systemctl restart containerd
    sleep 5
    
    info "Step 4e: Starting kubelet"
    systemctl start kubelet
    
    success "CNI bridge conflict fix applied"
    
    # Wait for services to stabilize
    info "Waiting for services to stabilize..."
    sleep 30
    
else
    info "No CNI bridge conflict detected, skipping bridge reset"
fi

# Step 5: Restart Flannel to reconfigure networking
info "Step 5: Restarting Flannel to reconfigure networking"

# Find and restart Flannel pods
FLANNEL_PODS=$(kubectl get pods -n kube-flannel -l app=flannel -o name 2>/dev/null || echo "")

if [ -n "$FLANNEL_PODS" ]; then
    info "Restarting Flannel pods to reconfigure networking"
    kubectl delete $FLANNEL_PODS --force --grace-period=0 >/dev/null 2>&1 || true
    
    # Wait for Flannel to restart
    info "Waiting for Flannel to restart..."
    sleep 30
    
    # Check Flannel status
    for i in {1..12}; do
        FLANNEL_READY=$(kubectl get pods -n kube-flannel -l app=flannel 2>/dev/null | grep "Running" | wc -l)
        FLANNEL_TOTAL=$(kubectl get pods -n kube-flannel -l app=flannel 2>/dev/null | grep -v "NAME" | wc -l)
        
        if [ "$FLANNEL_READY" -eq "$FLANNEL_TOTAL" ] && [ "$FLANNEL_TOTAL" -gt 0 ]; then
            success "✓ Flannel pods are running ($FLANNEL_READY/$FLANNEL_TOTAL)"
            break
        else
            if [ $i -lt 12 ]; then
                info "Flannel status: $FLANNEL_READY/$FLANNEL_TOTAL ready - waiting..."
                sleep 10
            else
                warn "Flannel pods taking longer than expected to start"
            fi
        fi
    done
else
    warn "No Flannel pods found"
fi

# Step 6: Handle existing Jellyfin pod
info "Step 6: Handling existing Jellyfin pod"

if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$POD_STATUS" = "Pending" ]; then
        info "Deleting stuck Jellyfin pod to trigger recreation"
        kubectl delete pod -n jellyfin jellyfin --force --grace-period=0
        
        # Wait for pod to be fully deleted
        info "Waiting for pod deletion..."
        while kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; do
            sleep 2
        done
        success "Stuck Jellyfin pod deleted"
    fi
fi

# Step 7: Ensure Jellyfin pod is created
info "Step 7: Ensuring Jellyfin pod is created"

if ! kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    info "Creating Jellyfin pod from manifest"
    kubectl apply -f manifests/jellyfin/jellyfin.yaml || {
        warn "Failed to apply main manifest, trying minimal manifest"
        kubectl apply -f manifests/jellyfin/jellyfin-minimal.yaml
    }
    success "Jellyfin manifest applied"
fi

# Step 8: Monitor Jellyfin pod startup
info "Step 8: Monitoring Jellyfin pod startup"

info "Waiting for Jellyfin pod to be created..."
for i in {1..30}; do
    if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
        success "✓ Jellyfin pod created"
        break
    fi
    if [ $i -eq 30 ]; then
        error "Jellyfin pod not created within timeout"
        exit 1
    fi
    sleep 5
done

# Monitor pod status
info "Monitoring pod status (will wait up to 5 minutes for Running status)..."

for i in {1..60}; do
    POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    POD_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
    
    case "$POD_STATUS" in
        "Pending")
            if [ $((i % 6)) -eq 0 ]; then  # Check every 30 seconds
                info "Pod still Pending, checking for CNI errors..."
                RECENT_CNI_ERRORS=$(kubectl get events -n jellyfin --sort-by='.lastTimestamp' 2>/dev/null | \
                                   grep -E "(failed to set bridge addr|cni0 already has|sandbox)" | tail -1 || echo "")
                if [ -n "$RECENT_CNI_ERRORS" ]; then
                    error "✗ CNI bridge errors still occurring:"
                    echo "$RECENT_CNI_ERRORS"
                    error "The fix may not have been successful"
                    exit 1
                else
                    info "No recent CNI errors detected, pod may be starting normally..."
                fi
            fi
            ;;
        "Running")
            success "🎉 Jellyfin pod is now Running!"
            echo "Pod IP: ${POD_IP:-<not assigned yet>}"
            
            # Verify pod is ready
            if kubectl wait --for=condition=ready pod/jellyfin -n jellyfin --timeout=30s; then
                success "✓ Jellyfin pod is Ready!"
                
                # Show final status
                echo
                echo "=== Final Jellyfin Pod Status ==="
                kubectl get pod -n jellyfin jellyfin -o wide
                
                echo
                echo "=== Access Information ==="
                NODE_PORT=$(kubectl get service -n jellyfin jellyfin-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30096")
                echo "Jellyfin UI: http://192.168.4.61:${NODE_PORT}"
                echo "Corrected URL: http://192.168.4.61:${NODE_PORT}/web/#/home.html"
                echo "Pod IP: ${POD_IP}"
                
                success "CNI bridge IP conflict successfully resolved!"
                exit 0
            else
                warn "Pod is Running but not Ready yet - health probes may still be starting"
                success "CNI bridge IP conflict appears to be resolved (pod creation succeeded)"
                exit 0
            fi
            ;;
        "Failed"|"Error")
            error "✗ Pod failed to start: $POD_STATUS"
            exit 1
            ;;
        *)
            if [ $((i % 12)) -eq 0 ]; then  # Update every minute
                info "Pod status: $POD_STATUS (${i}/60 checks)"
            fi
            ;;
    esac
    
    sleep 5
done

# If we get here, the pod didn't start within the timeout
POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

if [ "$POD_STATUS" = "Pending" ]; then
    error "Pod is still Pending after 5 minutes"
    echo
    echo "=== Diagnostic Information ==="
    echo "Pod events:"
    kubectl get events -n jellyfin --sort-by='.lastTimestamp' | tail -10
    echo
    echo "Pod description:"
    kubectl describe pod -n jellyfin jellyfin | tail -20
    
    warn "The CNI bridge fix may need additional steps or manual intervention"
    exit 1
else
    warn "Pod status: $POD_STATUS - may need additional troubleshooting"
    exit 1
fi
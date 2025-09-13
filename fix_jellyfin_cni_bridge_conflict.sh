#!/bin/bash

# Fix Jellyfin CNI Bridge IP Conflict
# Addresses the specific issue from the problem statement where Jellyfin pod
# fails with: "cni0" already has an IP address different from 10.244.2.1/24
# This prevents pods from being created on storagenodet3500

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
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Cleanup function for any temporary resources
cleanup() {
    # Clean up any test pods that might have been created
    timeout 10 kubectl delete pod -n kube-system --selector="app=cni-test" --ignore-not-found >/dev/null 2>&1 || true
}

# Set up signal handlers for cleanup
trap cleanup EXIT INT TERM

echo "================================================================"
echo "    Fix Jellyfin CNI Bridge IP Conflict - VMStation Cluster    "
echo "================================================================"
echo "Problem: cni0 bridge has wrong IP, preventing pod creation"
echo "Error: failed to set bridge addr: cni0 already has IP different from 10.244.2.1/24"
echo "Target: storagenodet3500 worker node"
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
    error "Cannot access Kubernetes cluster or kubectl timed out"
    error "Please ensure you're running this from the control plane node with kubectl configured"
    exit 1
fi

# Step 1: Verify the problem exists
info "Step 1: Verifying the CNI bridge IP conflict issue"

# Check if Jellyfin pod is stuck in ContainerCreating
if timeout 30 kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    POD_STATUS=$(timeout 10 kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null)
    
    if [ "$POD_STATUS" = "Pending" ]; then
        warn "Jellyfin pod is in Pending state"
        
        # Check for the specific CNI bridge error
        CNI_ERROR=$(timeout 15 kubectl get events -n jellyfin --sort-by='.lastTimestamp' 2>/dev/null | \
                   grep -E "failed to set bridge addr.*cni0.*already has an IP address different" | \
                   tail -1 || echo "")
        
        if [ -n "$CNI_ERROR" ]; then
            error "✗ Confirmed: CNI bridge IP conflict detected"
            echo "Error message: $CNI_ERROR"
            echo
        else
            warn "Jellyfin pod is pending but specific CNI error not found in recent events"
            echo "Checking broader CNI errors..."
            kubectl get events -n jellyfin --sort-by='.lastTimestamp' | tail -5
            echo
        fi
    elif [ "$POD_STATUS" = "Running" ]; then
        success "✓ Jellyfin pod is already running - no action needed"
        kubectl get pod -n jellyfin jellyfin -o wide
        exit 0
    else
        warn "Jellyfin pod status: $POD_STATUS"
    fi
else
    warn "Jellyfin pod not found - will create after fixing CNI"
fi

# Check storagenodet3500 node exists
if ! timeout 15 kubectl get node storagenodet3500 >/dev/null 2>&1; then
    error "Target node 'storagenodet3500' not found in cluster"
    echo "Available nodes:"
    timeout 15 kubectl get nodes || echo "Could not list nodes"
    exit 1
fi

# Step 2: Check CNI bridge configuration on control plane
info "Step 2: Checking current CNI bridge configuration"

# Check if we have cni0 on this node
if ip addr show cni0 >/dev/null 2>&1; then
    echo "Current cni0 bridge configuration:"
    ip addr show cni0
    echo
    
    # Extract current IP
    CURRENT_CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
    if [ -n "$CURRENT_CNI_IP" ]; then
        info "Current cni0 IP: $CURRENT_CNI_IP"
        
        # Check if it matches any expected Flannel subnet
        if echo "$CURRENT_CNI_IP" | grep -q "10.244."; then
            # Check if it's the wrong subnet for the target node
            if echo "$CURRENT_CNI_IP" | grep -q "10.244.2.1/24"; then
                success "✓ cni0 has expected IP for storagenodet3500 subnet"
                CNI_BRIDGE_OK=true
            elif echo "$CURRENT_CNI_IP" | grep -qE "10.244.(0|1).1/24"; then
                warn "cni0 has control plane subnet IP instead of worker node subnet"
                CNI_BRIDGE_CONFLICT=true
            else
                warn "cni0 has unexpected Flannel subnet IP: $CURRENT_CNI_IP"
                CNI_BRIDGE_CONFLICT=true
            fi
        else
            error "✗ cni0 has non-Flannel IP: $CURRENT_CNI_IP (should be 10.244.x.x)"
            CNI_BRIDGE_CONFLICT=true
        fi
    fi
else
    info "No cni0 bridge found on control plane node"
fi

# Step 3: Check Flannel subnet allocation
info "Step 3: Checking Flannel subnet allocation"

# Check Flannel network configuration
if kubectl get configmap kube-flannel-cfg -n kube-flannel >/dev/null 2>&1; then
    echo "Flannel network configuration:"
    kubectl get configmap kube-flannel-cfg -n kube-flannel -o jsonpath='{.data.net-conf\.json}' | jq . 2>/dev/null || \
    kubectl get configmap kube-flannel-cfg -n kube-flannel -o jsonpath='{.data.net-conf\.json}'
    echo
fi

# Check node subnet annotations
info "Checking node subnet annotations:"
NODE_SUBNET=$(kubectl get node storagenodet3500 -o jsonpath='{.metadata.annotations.flannel\.alpha\.coreos\.com/pod-cidr}' 2>/dev/null || echo "")
if [ -n "$NODE_SUBNET" ]; then
    info "storagenodet3500 assigned subnet: $NODE_SUBNET"
    
    # Expected bridge IP would be the first IP in this subnet
    EXPECTED_BRIDGE_IP=$(echo "$NODE_SUBNET" | sed 's/\.0\/24/.1\/24/')
    info "Expected cni0 bridge IP: $EXPECTED_BRIDGE_IP"
else
    warn "No Flannel subnet annotation found for storagenodet3500"
    info "This may indicate Flannel hasn't allocated a subnet yet"
fi

# Step 4: Check Flannel pod status
info "Step 4: Checking Flannel pod status on storagenodet3500"

FLANNEL_POD=$(kubectl get pods -n kube-flannel -o wide 2>/dev/null | grep "storagenodet3500" | awk '{print $1}' | head -1)
if [ -n "$FLANNEL_POD" ]; then
    FLANNEL_STATUS=$(kubectl get pod -n kube-flannel "$FLANNEL_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
    info "Flannel pod on storagenodet3500: $FLANNEL_POD (Status: $FLANNEL_STATUS)"
    
    if [ "$FLANNEL_STATUS" != "Running" ]; then
        warn "Flannel pod is not running - this may be contributing to the issue"
        
        # Check recent logs
        echo "Recent Flannel pod logs:"
        kubectl logs -n kube-flannel "$FLANNEL_POD" --tail=10 2>/dev/null || \
        echo "Could not retrieve Flannel logs"
        echo
    fi
else
    error "No Flannel pod found on storagenodet3500"
fi

# Step 5: Apply the targeted fix
info "Step 5: Applying CNI bridge IP conflict fix"

if [ "${CNI_BRIDGE_CONFLICT:-false}" = true ] || [ "${CNI_BRIDGE_OK:-false}" != true ]; then
    warn "Applying CNI bridge conflict resolution"
    
    # Stop kubelet temporarily to prevent constant pod sandbox failures
    info "Temporarily stopping kubelet to prevent pod churn"
    systemctl stop kubelet || warn "Failed to stop kubelet"
    
    # Remove conflicting CNI bridge
    if ip link show cni0 >/dev/null 2>&1; then
        info "Removing conflicting cni0 bridge"
        ip link set cni0 down 2>/dev/null || true
        ip link delete cni0 2>/dev/null || true
        success "Removed conflicting cni0 bridge"
    fi
    
    # Clear any cached CNI network state that might cause conflicts
    if [ -d "/var/lib/cni" ]; then
        info "Backing up and clearing CNI network state"
        mv /var/lib/cni "/var/lib/cni.backup.$(date +%s)" 2>/dev/null || true
    fi
    
    # Remove any conflicting CNI configurations (preserve Flannel)
    if [ -d "/etc/cni/net.d" ]; then
        info "Cleaning conflicting CNI configurations"
        # Remove any CNI configs that aren't Flannel
        find /etc/cni/net.d -name "*.conflist" -not -name "*flannel*" -delete 2>/dev/null || true
        find /etc/cni/net.d -name "*.conf" -not -name "*flannel*" -delete 2>/dev/null || true
    fi
    
    # Restart containerd to clear any cached network state
    info "Restarting containerd to clear network state"
    systemctl restart containerd
    sleep 5
    
    # Start kubelet
    info "Starting kubelet"
    systemctl start kubelet
    
    success "CNI bridge conflict fix applied"
else
    info "CNI bridge configuration appears correct, skipping bridge reset"
fi

# Step 6: Restart Flannel pod on storagenodet3500
info "Step 6: Restarting Flannel pod on storagenodet3500"

if [ -n "$FLANNEL_POD" ]; then
    info "Deleting Flannel pod to force network reconfiguration"
    kubectl delete pod -n kube-flannel "$FLANNEL_POD" --force --grace-period=0
    
    # Wait for new Flannel pod to start
    info "Waiting for new Flannel pod to start..."
    sleep 15
    
    # Check if new Flannel pod is running
    for i in {1..24}; do  # Wait up to 2 minutes
        NEW_FLANNEL_POD=$(kubectl get pods -n kube-flannel -o wide 2>/dev/null | grep "storagenodet3500" | grep "Running" | awk '{print $1}' | head -1)
        if [ -n "$NEW_FLANNEL_POD" ]; then
            success "✓ New Flannel pod is running: $NEW_FLANNEL_POD"
            break
        fi
        if [ $i -eq 24 ]; then
            warn "Flannel pod taking longer than expected to start"
        fi
        sleep 5
    done
fi

# Step 7: Wait for network to stabilize and delete stuck Jellyfin pod
info "Step 7: Waiting for network to stabilize"
sleep 20

if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$POD_STATUS" = "Pending" ]; then
        info "Deleting stuck Jellyfin pod to trigger recreation with fixed networking"
        kubectl delete pod -n jellyfin jellyfin --force --grace-period=0
        
        # Wait for pod to be fully deleted
        while kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; do
            sleep 2
        done
        
        success "Stuck Jellyfin pod deleted"
    fi
fi

# Step 8: Recreate Jellyfin pod with fixed networking
info "Step 8: Creating Jellyfin pod with fixed networking"

if ! kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    info "Applying Jellyfin manifest to create pod"
    kubectl apply -f manifests/jellyfin/jellyfin.yaml
    
    success "Jellyfin manifest applied"
fi

# Step 9: Monitor pod creation and verify fix
info "Step 9: Monitoring Jellyfin pod creation and verifying fix"

info "Waiting for Jellyfin pod to be created..."
for i in {1..30}; do  # Wait up to 2.5 minutes for pod creation
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

# Monitor pod status changes
info "Monitoring pod status (will wait up to 5 minutes for Running status)..."

for i in {1..60}; do  # Wait up to 5 minutes
    POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    POD_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
    
    case "$POD_STATUS" in
        "Pending")
            if [ $((i % 6)) -eq 0 ]; then  # Check events every 30 seconds
                echo "Pod still Pending, checking for CNI errors..."
                RECENT_CNI_ERRORS=$(kubectl get events -n jellyfin --sort-by='.lastTimestamp' 2>/dev/null | \
                                   grep -E "(failed to set bridge addr|cni0 already has|sandbox)" | tail -1 || echo "")
                if [ -n "$RECENT_CNI_ERRORS" ]; then
                    error "✗ CNI bridge errors still occurring:"
                    echo "$RECENT_CNI_ERRORS"
                    error "The fix may not have been successful"
                    break
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
            break
            ;;
        *)
            if [ $((i % 12)) -eq 0 ]; then  # Update every minute
                info "Pod status: $POD_STATUS (${i}/60 checks)"
            fi
            ;;
    esac
    
    sleep 5
done

# If we get here, either the pod didn't start or there were issues
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
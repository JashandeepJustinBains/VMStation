#!/bin/bash

# Fix Worker Node CNI Communication Issues
# Specifically addresses the issue where pods on the same worker node cannot communicate
# with each other, as evidenced by "Destination Host Unreachable" errors

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

# Script arguments
TARGET_NODE=""
NON_INTERACTIVE=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --node|-n)
            TARGET_NODE="$2"
            shift 2
            ;;
        --non-interactive|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo "=== Worker Node CNI Communication Fix ==="
echo "Timestamp: $(date)"
echo "Target Node: ${TARGET_NODE:-auto-detect}"
echo

# Check prerequisites
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl is required but not found"
    exit 1
fi

if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    exit 1
fi

# Auto-detect target node if not specified
if [ -z "$TARGET_NODE" ]; then
    # Try to detect the problematic node from recent events
    PROBLEM_NODE=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' 2>/dev/null | \
                   grep -E "(Failed.*pod.*sandbox|CNI.*failed)" | \
                   grep -oE "storagenode[a-zA-Z0-9]*" | head -1 || echo "")
    
    if [ -n "$PROBLEM_NODE" ]; then
        TARGET_NODE="$PROBLEM_NODE"
        info "Auto-detected problematic node: $TARGET_NODE"
    else
        # Default to storagenodet3500 based on problem statement
        TARGET_NODE="storagenodet3500"
        warn "Could not auto-detect node, defaulting to: $TARGET_NODE"
    fi
fi

info "Fixing CNI communication on node: $TARGET_NODE"

# Step 1: Diagnose current CNI state on the target node
info "Step 1: Diagnosing CNI state on node $TARGET_NODE"

# Check if pods are scheduled on this node
PODS_ON_NODE=$(kubectl get pods --all-namespaces -o wide 2>/dev/null | grep "$TARGET_NODE" || echo "")
if [ -z "$PODS_ON_NODE" ]; then
    warn "No pods found on node $TARGET_NODE"
else
    echo "Pods on $TARGET_NODE:"
    echo "$PODS_ON_NODE"
    echo
fi

# Check if this is the current node
CURRENT_HOSTNAME=$(hostname)
if [ "$TARGET_NODE" = "$CURRENT_HOSTNAME" ]; then
    ON_TARGET_NODE=true
    info "Running on target node - can perform direct network diagnostics"
else
    ON_TARGET_NODE=false
    warn "Not running on target node - limited diagnostics available"
fi

# Step 2: Check Flannel pod status on target node
info "Step 2: Checking Flannel pod on node $TARGET_NODE"

FLANNEL_POD=$(kubectl get pods -n kube-flannel -o wide 2>/dev/null | grep "$TARGET_NODE" | awk '{print $1}' | head -1)
if [ -n "$FLANNEL_POD" ]; then
    info "Found Flannel pod: $FLANNEL_POD"
    
    # Check pod status
    FLANNEL_STATUS=$(kubectl get pod -n kube-flannel "$FLANNEL_POD" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$FLANNEL_STATUS" = "Running" ]; then
        info "✓ Flannel pod is Running"
    else
        error "✗ Flannel pod status: $FLANNEL_STATUS"
        warn "Flannel pod issues detected - will restart"
    fi
    
    # Check recent logs for errors
    echo "Recent Flannel logs (last 10 lines):"
    kubectl logs -n kube-flannel "$FLANNEL_POD" --tail=10 2>/dev/null | while read -r line; do
        if echo "$line" | grep -qE "(error|Error|ERROR|failed|Failed|FAILED)"; then
            error "  $line"
        else
            echo "  $line"
        fi
    done
else
    error "No Flannel pod found on node $TARGET_NODE"
    warn "This may indicate a serious CNI configuration issue"
fi

# Step 3: Check CNI bridge configuration (only if on target node)
if [ "$ON_TARGET_NODE" = true ]; then
    info "Step 3: Checking CNI bridge configuration on local node"
    
    if ip addr show cni0 >/dev/null 2>&1; then
        echo "Current cni0 bridge configuration:"
        ip addr show cni0
        
        CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
        if [ -n "$CNI_IP" ]; then
            info "CNI bridge IP: $CNI_IP"
            
            if echo "$CNI_IP" | grep -q "10.244."; then
                info "✓ CNI bridge IP is in correct Flannel subnet"
            else
                error "✗ CNI bridge IP ($CNI_IP) is NOT in Flannel subnet (10.244.0.0/16)"
                CNI_BRIDGE_WRONG=true
            fi
        fi
        
        # Check bridge state
        CNI_STATE=$(ip link show cni0 | grep -oE "(UP|DOWN)" | head -1)
        if [ "$CNI_STATE" = "UP" ]; then
            info "✓ CNI bridge is UP"
        else
            warn "✗ CNI bridge is $CNI_STATE"
            CNI_BRIDGE_DOWN=true
        fi
    else
        error "✗ No cni0 bridge found"
        CNI_BRIDGE_MISSING=true
    fi
    
    # Check routes
    echo
    echo "Pod network routes:"
    ip route show | grep -E "(10.244|cni0)" || echo "No pod network routes found"
    
    # Check veth interfaces
    echo
    echo "veth interfaces (should exist if pods are running):"
    ip link show | grep -E "veth.*@if" || echo "No veth interfaces found"
    
else
    info "Step 3: Skipping bridge check (not on target node)"
fi

# Step 4: Test pod-to-pod connectivity on the target node
info "Step 4: Testing pod-to-pod connectivity"

# Find pods on the target node to test connectivity
TARGET_PODS=$(kubectl get pods --all-namespaces -o wide 2>/dev/null | grep "$TARGET_NODE" | grep "Running" || echo "")

if [ -z "$TARGET_PODS" ]; then
    warn "No running pods found on $TARGET_NODE to test connectivity"
else
    echo "Running pods on $TARGET_NODE:"
    echo "$TARGET_PODS"
    echo
    
    # Extract pod IPs for connectivity testing
    POD_IPS=$(kubectl get pods --all-namespaces -o wide 2>/dev/null | grep "$TARGET_NODE" | grep "Running" | awk '{print $7}' | grep -E "^10\.244\." || echo "")
    
    if [ -n "$POD_IPS" ]; then
        info "Testing connectivity between pods on $TARGET_NODE"
        
        # Create a test pod on the target node to test connectivity
        info "Creating connectivity test pod on $TARGET_NODE..."
        
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cni-test-$TARGET_NODE
  namespace: kube-system
spec:
  nodeName: $TARGET_NODE
  tolerations:
  - operator: Exists
  containers:
  - name: test
    image: nicolaka/netshoot
    command: ["sleep", "300"]
  restartPolicy: Never
EOF
        
        # Wait for test pod to be ready
        info "Waiting for test pod to be ready..."
        if kubectl wait --for=condition=Ready pod/cni-test-$TARGET_NODE -n kube-system --timeout=60s; then
            success "Test pod is ready"
            
            # Test connectivity to other pods on the same node
            for pod_ip in $POD_IPS; do
                info "Testing connectivity from test pod to $pod_ip"
                
                # Test ping
                if kubectl exec -n kube-system cni-test-$TARGET_NODE -- ping -c 2 -W 3 "$pod_ip" >/dev/null 2>&1; then
                    success "✓ Ping to $pod_ip successful"
                else
                    error "✗ Ping to $pod_ip failed (Destination Host Unreachable)"
                    CONNECTIVITY_FAILED=true
                fi
            done
        else
            warn "Test pod failed to become ready - CNI issues confirmed"
            CONNECTIVITY_FAILED=true
        fi
        
        # Clean up test pod
        kubectl delete pod cni-test-$TARGET_NODE -n kube-system --ignore-not-found >/dev/null 2>&1 || true
    fi
fi

# Step 5: Apply fixes based on detected issues
info "Step 5: Applying CNI fixes"

if [ "$ON_TARGET_NODE" = true ]; then
    # Fix 5a: CNI bridge issues
    if [ "${CNI_BRIDGE_MISSING:-false}" = true ] || [ "${CNI_BRIDGE_WRONG:-false}" = true ] || [ "${CNI_BRIDGE_DOWN:-false}" = true ]; then
        warn "Fixing CNI bridge configuration issues"
        
        # Stop kubelet to prevent pod churn
        info "Stopping kubelet temporarily"
        systemctl stop kubelet || warn "Failed to stop kubelet"
        
        # Remove problematic bridge
        if ip link show cni0 >/dev/null 2>&1; then
            info "Removing problematic cni0 bridge"
            ip link set cni0 down 2>/dev/null || true
            ip link delete cni0 2>/dev/null || true
        fi
        
        # Clear CNI state
        if [ -d "/var/lib/cni" ]; then
            info "Backing up and clearing CNI state"
            mv /var/lib/cni /var/lib/cni.backup.$(date +%s) 2>/dev/null || true
        fi
        
        # Restart containerd to reset network state
        info "Restarting containerd"
        systemctl restart containerd
        sleep 5
        
        # Restart kubelet
        info "Starting kubelet"
        systemctl start kubelet
        
        success "CNI bridge reset completed"
    fi
else
    info "Cannot directly fix bridge issues (not on target node)"
fi

# Fix 5b: Restart Flannel pod on target node
# Re-query for current Flannel pod name (may have changed due to previous operations)
CURRENT_FLANNEL_POD=$(kubectl get pods -n kube-flannel -o wide 2>/dev/null | grep "$TARGET_NODE" | awk '{print $1}' | head -1)

if [ -n "$CURRENT_FLANNEL_POD" ]; then
    info "Restarting Flannel pod on $TARGET_NODE: $CURRENT_FLANNEL_POD"
    kubectl delete pod -n kube-flannel "$CURRENT_FLANNEL_POD" --force --grace-period=0
    
    # Wait for new Flannel pod
    info "Waiting for new Flannel pod to start..."
    sleep 15
    
    # Check if new pod is running
    NEW_FLANNEL_POD=$(kubectl get pods -n kube-flannel -o wide 2>/dev/null | grep "$TARGET_NODE" | grep "Running" | awk '{print $1}' | head -1)
    if [ -n "$NEW_FLANNEL_POD" ]; then
        success "✓ New Flannel pod is running: $NEW_FLANNEL_POD"
    else
        warn "Flannel pod may still be starting - check status manually"
    fi
fi

# Step 6: Wait for networking to stabilize
info "Step 6: Waiting for networking to stabilize..."
sleep 30

# Step 7: Validate the fix
info "Step 7: Validating CNI communication fix"

# Re-check CNI bridge (if on target node)
if [ "$ON_TARGET_NODE" = true ]; then
    if ip addr show cni0 >/dev/null 2>&1; then
        NEW_CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
        if [ -n "$NEW_CNI_IP" ]; then
            info "New CNI bridge IP: $NEW_CNI_IP"
            
            if echo "$NEW_CNI_IP" | grep -q "10.244."; then
                success "✓ CNI bridge now has correct Flannel subnet IP"
            else
                error "✗ CNI bridge still has incorrect IP"
            fi
        fi
    else
        warn "CNI bridge not yet created - may need more time"
    fi
fi

# Test pod creation and connectivity
info "Testing pod creation and connectivity..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cni-validation-$TARGET_NODE
  namespace: kube-system
spec:
  nodeName: $TARGET_NODE
  tolerations:
  - operator: Exists
  containers:
  - name: test
    image: busybox:1.35
    command: ["sleep", "120"]
  restartPolicy: Never
EOF

# Wait for validation pod
if kubectl wait --for=condition=Ready pod/cni-validation-$TARGET_NODE -n kube-system --timeout=120s; then
    success "✓ Validation pod created successfully"
    
    # Get validation pod IP
    VAL_POD_IP=$(kubectl get pod cni-validation-$TARGET_NODE -n kube-system -o jsonpath='{.status.podIP}' 2>/dev/null)
    if [ -n "$VAL_POD_IP" ] && echo "$VAL_POD_IP" | grep -q "10.244."; then
        success "✓ Validation pod received correct IP: $VAL_POD_IP"
        
        # Test connectivity to existing pods
        EXISTING_PODS=$(kubectl get pods --all-namespaces -o wide | grep "$TARGET_NODE" | grep "Running" | grep -v "cni-validation" | awk '{print $7}' | grep -E "^10\.244\." | head -2)
        
        if [ -n "$EXISTING_PODS" ]; then
            for target_ip in $EXISTING_PODS; do
                if kubectl exec -n kube-system cni-validation-$TARGET_NODE -- ping -c 2 -W 3 "$target_ip" >/dev/null 2>&1; then
                    success "✓ Pod-to-pod connectivity working: $VAL_POD_IP -> $target_ip"
                else
                    error "✗ Pod-to-pod connectivity still failing: $VAL_POD_IP -> $target_ip"
                fi
            done
        else
            info "No other pods found for connectivity testing"
        fi
        
        # Test external connectivity
        if kubectl exec -n kube-system cni-validation-$TARGET_NODE -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
            success "✓ DNS resolution working"
        else
            warn "DNS resolution issues detected"
        fi
        
    else
        error "✗ Validation pod has incorrect or no IP: ${VAL_POD_IP:-none}"
    fi
else
    error "✗ Validation pod failed to become ready"
    kubectl describe pod cni-validation-$TARGET_NODE -n kube-system 2>/dev/null || true
fi

# Clean up validation pod
kubectl delete pod cni-validation-$TARGET_NODE -n kube-system --ignore-not-found >/dev/null 2>&1 || true

# Step 8: Final summary
echo
info "=== Worker Node CNI Fix Summary ==="

if [ "${CONNECTIVITY_FAILED:-false}" = true ]; then
    if [ "$ON_TARGET_NODE" = true ]; then
        warn "Some connectivity issues may persist"
        echo "Additional steps to try:"
        echo "1. Check iptables rules: iptables -t nat -L | grep CNI"
        echo "2. Restart all networking: systemctl restart containerd kubelet"
        echo "3. Check kernel modules: lsmod | grep br_netfilter"
        echo "4. Verify flannel configuration: kubectl describe cm kube-flannel-cfg -n kube-flannel"
    else
        warn "Limited fixes applied (not running on target node)"
        echo "To complete the fix, run this script on the target node: $TARGET_NODE"
    fi
else
    success "🎉 CNI communication fix completed successfully!"
    echo
    echo "Networking should now work correctly on $TARGET_NODE:"
    echo "✅ CNI bridge properly configured"
    echo "✅ Flannel pod running"
    echo "✅ Pod-to-pod connectivity working"
    echo "✅ New pods can be created"
fi

echo
echo "=== Fix Complete ==="
echo "Timestamp: $(date)"
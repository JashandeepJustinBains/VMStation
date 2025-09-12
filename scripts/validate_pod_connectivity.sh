#!/bin/bash

# Validate Pod-to-Pod CNI Communication
# Tests the exact scenario from the problem statement:
# - Debug pod on storagenodet3500 trying to reach Jellyfin pod
# - Validates both internal and external connectivity

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

echo "=== Pod-to-Pod CNI Communication Validation ==="
echo "Timestamp: $(date)"
echo "Testing the exact scenario from the problem statement"
echo

# Check prerequisites
if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    exit 1
fi

# Step 1: Check if Jellyfin pod exists and get its details
info "Step 1: Checking Jellyfin pod status"

if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    JELLYFIN_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}')
    JELLYFIN_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}')
    JELLYFIN_NODE=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.nodeName}')
    
    info "Jellyfin pod status: $JELLYFIN_STATUS"
    info "Jellyfin pod IP: ${JELLYFIN_IP:-none}"
    info "Jellyfin pod node: ${JELLYFIN_NODE:-none}"
    
    if [ "$JELLYFIN_STATUS" = "Running" ] && [ -n "$JELLYFIN_IP" ]; then
        success "✓ Jellyfin pod is running with IP"
    else
        error "✗ Jellyfin pod is not ready"
        kubectl describe pod -n jellyfin jellyfin | grep -A 10 -B 5 -E "(Ready|Events|Conditions)"
        exit 1
    fi
else
    error "Jellyfin pod not found - deploying test pod instead"
    JELLYFIN_IP=""
    JELLYFIN_NODE="storagenodet3500"
fi

# Step 2: Create debug pod exactly as in problem statement
info "Step 2: Creating debug pod as in problem statement"

# Clean up any existing debug pod first
kubectl delete pod debug-net -n kube-system --ignore-not-found >/dev/null 2>&1 || true
sleep 5

# Create debug pod exactly as in the problem statement
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: debug-net
  namespace: kube-system
spec:
  nodeName: storagenodet3500
  tolerations:
  - operator: Exists
  containers:
  - name: debug
    image: nicolaka/netshoot
    command: ["sleep","3600"]
  restartPolicy: Never
EOF

info "Waiting for debug pod to be ready..."
if kubectl wait --for=condition=Ready pod/debug-net -n kube-system --timeout=120s; then
    success "✓ Debug pod is ready"
else
    error "✗ Debug pod failed to become ready"
    kubectl describe pod debug-net -n kube-system | grep -A 10 -B 5 -E "(Ready|Events|Conditions)"
    exit 1
fi

# Get debug pod details
DEBUG_IP=$(kubectl get pod debug-net -n kube-system -o jsonpath='{.status.podIP}')
DEBUG_NODE=$(kubectl get pod debug-net -n kube-system -o jsonpath='{.spec.nodeName}')

info "Debug pod IP: $DEBUG_IP"
info "Debug pod node: $DEBUG_NODE"

# Step 3: Run the exact commands from the problem statement
info "Step 3: Running network diagnostics from debug pod"

echo "=== Network Configuration ==="
kubectl -n kube-system exec debug-net -- bash -c "ip -4 addr show; echo; ip -4 route show; echo; ip neigh show"

echo
echo "=== Testing pod-to-pod connectivity ==="

if [ -n "$JELLYFIN_IP" ]; then
    TARGET_IP="$JELLYFIN_IP"
    TARGET_DESC="Jellyfin pod ($JELLYFIN_IP)"
else
    # If no Jellyfin pod, try to find another pod on the same node for testing
    OTHER_POD_IP=$(kubectl get pods --all-namespaces -o wide | grep "$DEBUG_NODE" | grep "Running" | grep -v "debug-net" | awk '{print $7}' | grep -E "^10\.244\." | head -1)
    if [ -n "$OTHER_POD_IP" ]; then
        TARGET_IP="$OTHER_POD_IP"
        TARGET_DESC="Other pod on same node ($OTHER_POD_IP)"
    else
        # Create a simple test pod if none exist
        info "Creating simple test pod for connectivity testing..."
        kubectl run test-target --image=nginx:alpine --restart=Never --overrides='{"spec":{"nodeName":"storagenodet3500"}}' >/dev/null 2>&1 || true
        kubectl wait --for=condition=Ready pod/test-target --timeout=60s >/dev/null 2>&1 || true
        TARGET_IP=$(kubectl get pod test-target -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
        TARGET_DESC="Test nginx pod ($TARGET_IP)"
        CLEANUP_TEST_POD=true
    fi
fi

if [ -n "$TARGET_IP" ]; then
    info "Testing connectivity to $TARGET_DESC"
    
    # Test 1: Ping connectivity
    echo "--- Ping Test ---"
    if kubectl -n kube-system exec debug-net -- ping -c2 "$TARGET_IP"; then
        success "✓ Ping test PASSED"
        PING_SUCCESS=true
    else
        error "✗ Ping test FAILED (matches problem statement)"
        PING_SUCCESS=false
    fi
    
    echo
    # Test 2: HTTP connectivity (if target supports it)
    if [ -n "$JELLYFIN_IP" ]; then
        echo "--- HTTP Test to Jellyfin ---"
        if kubectl -n kube-system exec debug-net -- timeout 10 curl -sv --max-time 5 "http://$TARGET_IP:8096/" 2>&1; then
            success "✓ HTTP test PASSED"
            HTTP_SUCCESS=true
        else
            error "✗ HTTP test FAILED (matches problem statement)"
            HTTP_SUCCESS=false
        fi
    elif echo "$TARGET_DESC" | grep -q "nginx"; then
        echo "--- HTTP Test to Nginx ---"
        if kubectl -n kube-system exec debug-net -- timeout 10 curl -s --max-time 5 "http://$TARGET_IP/" >/dev/null 2>&1; then
            success "✓ HTTP test PASSED"
            HTTP_SUCCESS=true
        else
            error "✗ HTTP test FAILED"
            HTTP_SUCCESS=false
        fi
    fi
else
    error "No target pod found for connectivity testing"
    PING_SUCCESS=false
    HTTP_SUCCESS=false
fi

echo
echo "=== Testing external connectivity ==="

# Test external connectivity as in problem statement
echo "--- External HTTP Test ---"
if kubectl -n kube-system exec debug-net -- timeout 10 curl -sv --max-time 8 https://repo.jellyfin.org/files/plugin/manifest.json 2>&1; then
    success "✓ External connectivity test PASSED"
    EXTERNAL_SUCCESS=true
else
    error "✗ External connectivity test FAILED (matches problem statement)"
    EXTERNAL_SUCCESS=false
fi

# Step 4: Detailed CNI diagnostics if tests failed
if [ "$PING_SUCCESS" = false ] || [ "$HTTP_SUCCESS" = false ]; then
    echo
    info "Step 4: CNI failure analysis"
    
    echo "=== CNI Bridge Status on Debug Pod Node ==="
    # Try to get bridge status from a privileged pod
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cni-debug
  namespace: kube-system
spec:
  nodeName: storagenodet3500
  hostNetwork: true
  hostPID: true
  tolerations:
  - operator: Exists
  containers:
  - name: debug
    image: nicolaka/netshoot
    command: ["sleep", "300"]
    securityContext:
      privileged: true
  restartPolicy: Never
EOF
    
    if kubectl wait --for=condition=Ready pod/cni-debug -n kube-system --timeout=60s >/dev/null 2>&1; then
        echo "CNI bridge status on $DEBUG_NODE:"
        kubectl exec -n kube-system cni-debug -- ip addr show cni0 2>/dev/null || echo "No cni0 bridge found"
        
        echo
        echo "Routes to pod network:"
        kubectl exec -n kube-system cni-debug -- ip route show | grep -E "(10.244|cni0)" || echo "No pod network routes"
        
        echo
        echo "iptables CNI rules:"
        kubectl exec -n kube-system cni-debug -- iptables -t nat -L | grep -A 5 -B 5 CNI || echo "No CNI iptables rules"
        
        # Clean up debug pod
        kubectl delete pod cni-debug -n kube-system --ignore-not-found >/dev/null 2>&1 || true
    fi
    
    echo
    echo "=== Flannel Pod Status on $DEBUG_NODE ==="
    FLANNEL_POD=$(kubectl get pods -n kube-flannel -o wide | grep "$DEBUG_NODE" | awk '{print $1}' | head -1)
    if [ -n "$FLANNEL_POD" ]; then
        info "Flannel pod: $FLANNEL_POD"
        kubectl get pod -n kube-flannel "$FLANNEL_POD" -o wide
        
        echo
        echo "Recent Flannel logs:"
        kubectl logs -n kube-flannel "$FLANNEL_POD" --tail=20 | while read -r line; do
            if echo "$line" | grep -qE "(error|Error|ERROR|failed|Failed)"; then
                error "  $line"
            else
                echo "  $line"
            fi
        done
    else
        error "No Flannel pod found on $DEBUG_NODE"
    fi
fi

# Step 5: Summary and recommendations
echo
info "=== Connectivity Test Summary ==="

echo "Test Results:"
if [ "$PING_SUCCESS" = true ]; then
    success "✓ Pod-to-Pod Ping: PASSED"
else
    error "✗ Pod-to-Pod Ping: FAILED"
fi

if [ "$HTTP_SUCCESS" = true ]; then
    success "✓ Pod-to-Pod HTTP: PASSED"
elif [ -n "$TARGET_IP" ]; then
    error "✗ Pod-to-Pod HTTP: FAILED"
else
    warn "? Pod-to-Pod HTTP: NOT TESTED (no target)"
fi

if [ "$EXTERNAL_SUCCESS" = true ]; then
    success "✓ External Connectivity: PASSED"
else
    error "✗ External Connectivity: FAILED"
fi

echo
echo "=== Recommendations ==="

if [ "$PING_SUCCESS" = false ] || [ "$HTTP_SUCCESS" = false ]; then
    error "Pod-to-pod connectivity is broken - this matches the problem statement"
    echo
    echo "To fix this issue, run:"
    echo "  1. sudo ./scripts/fix_worker_node_cni.sh --node storagenodet3500"
    echo "  2. ./scripts/fix_cni_bridge_conflict.sh"
    echo "  3. kubectl rollout restart daemonset/kube-flannel-ds -n kube-flannel"
    echo
    echo "Root cause analysis:"
    echo "  - CNI bridge on $DEBUG_NODE likely has wrong IP or is misconfigured"
    echo "  - Flannel networking is not properly routing traffic between pods"
    echo "  - This prevents Jellyfin health probes from working"
    
elif [ "$EXTERNAL_SUCCESS" = false ]; then
    warn "Pod-to-pod connectivity works but external connectivity is broken"
    echo "This may be a DNS or routing issue, not CNI"
    
else
    success "🎉 All connectivity tests passed!"
    echo "CNI networking is working correctly"
fi

# Cleanup
echo
info "Cleaning up test resources..."

kubectl delete pod debug-net -n kube-system --ignore-not-found >/dev/null 2>&1 || true
kubectl delete pod cni-debug -n kube-system --ignore-not-found >/dev/null 2>&1 || true

if [ "${CLEANUP_TEST_POD:-false}" = true ]; then
    kubectl delete pod test-target --ignore-not-found >/dev/null 2>&1 || true
fi

echo
echo "=== Validation Complete ==="
echo "Timestamp: $(date)"

# Exit with appropriate code
if [ "$PING_SUCCESS" = false ] || [ "$HTTP_SUCCESS" = false ]; then
    exit 1
else
    exit 0
fi
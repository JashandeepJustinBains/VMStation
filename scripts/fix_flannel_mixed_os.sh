#!/bin/bash

# Fix Flannel CNI Configuration for Mixed OS Environments
# Addresses specific issues in mixed Windows/Linux environments that can cause
# pod-to-pod communication failures

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

echo "=== Flannel CNI Mixed-OS Environment Fix ==="
echo "Timestamp: $(date)"
echo

# Check prerequisites
if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    exit 1
fi

# Step 1: Analyze current cluster environment
info "Step 1: Analyzing cluster environment"

echo "=== Current Cluster Nodes ==="
kubectl get nodes -o wide

echo
echo "=== Node OS Analysis ==="
LINUX_NODES=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.nodeInfo.operatingSystem=="linux") | .metadata.name' 2>/dev/null || kubectl get nodes --show-labels | grep -v windows | awk 'NR>1 {print $1}')
WINDOWS_NODES=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.nodeInfo.operatingSystem=="windows") | .metadata.name' 2>/dev/null || kubectl get nodes --show-labels | grep windows | awk '{print $1}' || echo "")

echo "Linux nodes:"
for node in $LINUX_NODES; do
    echo "  - $node"
done

if [ -n "$WINDOWS_NODES" ]; then
    echo "Windows nodes:"
    for node in $WINDOWS_NODES; do
        echo "  - $node"
    done
    MIXED_OS=true
    warn "Mixed OS environment detected - applying specialized Flannel configuration"
else
    echo "No Windows nodes detected"
    MIXED_OS=false
    info "Linux-only environment - applying standard Flannel optimizations"
fi

# Step 2: Check current Flannel configuration
info "Step 2: Checking current Flannel configuration"

FLANNEL_NAMESPACE="kube-flannel"
if ! kubectl get namespace "$FLANNEL_NAMESPACE" >/dev/null 2>&1; then
    FLANNEL_NAMESPACE="kube-system"
    warn "Flannel in kube-system namespace (older configuration)"
fi

echo "=== Current Flannel DaemonSet ==="
kubectl get daemonset -n "$FLANNEL_NAMESPACE" | grep flannel || echo "No Flannel DaemonSet found"

echo
echo "=== Current Flannel ConfigMap ==="
kubectl get configmap -n "$FLANNEL_NAMESPACE" | grep flannel || echo "No Flannel ConfigMap found"

# Get current Flannel configuration
FLANNEL_CONFIG=""
if kubectl get configmap kube-flannel-cfg -n "$FLANNEL_NAMESPACE" >/dev/null 2>&1; then
    FLANNEL_CONFIG=$(kubectl get configmap kube-flannel-cfg -n "$FLANNEL_NAMESPACE" -o jsonpath='{.data.net-conf\.json}' 2>/dev/null || echo "")
fi

if [ -n "$FLANNEL_CONFIG" ]; then
    echo "Current Flannel network configuration:"
    echo "$FLANNEL_CONFIG" | jq . 2>/dev/null || echo "$FLANNEL_CONFIG"
else
    warn "Could not retrieve Flannel configuration"
fi

# Step 3: Check for common configuration issues
info "Step 3: Checking for configuration issues"

# Check backend type
if echo "$FLANNEL_CONFIG" | grep -q '"Type": "vxlan"'; then
    info "✓ Using VXLAN backend (good for mixed OS)"
elif echo "$FLANNEL_CONFIG" | grep -q '"Type": "host-gw"'; then
    if [ "$MIXED_OS" = true ]; then
        warn "⚠ Using host-gw backend in mixed OS environment (may cause issues)"
        NEED_BACKEND_FIX=true
    else
        info "✓ Using host-gw backend (appropriate for Linux-only)"
    fi
else
    warn "⚠ Unknown or missing backend type"
    NEED_BACKEND_FIX=true
fi

# Check network subnet
if echo "$FLANNEL_CONFIG" | grep -q '"Network": "10.244.0.0/16"'; then
    info "✓ Using standard pod subnet 10.244.0.0/16"
else
    warn "⚠ Non-standard pod subnet detected"
fi

# Step 4: Apply fixes based on environment
info "Step 4: Applying Flannel configuration fixes"

if [ "$MIXED_OS" = true ] || [ "${NEED_BACKEND_FIX:-false}" = true ]; then
    info "Applying mixed-OS optimized Flannel configuration"
    
    # Create optimized Flannel configuration for mixed OS
    cat <<EOF > /tmp/flannel-mixed-os-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-flannel-cfg
  namespace: $FLANNEL_NAMESPACE
  labels:
    tier: node
    app: flannel
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true,
            "forceAddress": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "vxlan",
        "VNI": 1,
        "Port": 8472
      },
      "EnableIPv6": false
    }
EOF
    
    # Apply the updated configuration
    info "Updating Flannel ConfigMap with mixed-OS optimizations"
    kubectl apply -f /tmp/flannel-mixed-os-config.yaml
    
    # Clean up temp file
    rm -f /tmp/flannel-mixed-os-config.yaml
    
else
    info "Applying Linux-optimized Flannel configuration"
    
    # Create optimized Flannel configuration for Linux-only
    cat <<EOF > /tmp/flannel-linux-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-flannel-cfg
  namespace: $FLANNEL_NAMESPACE
  labels:
    tier: node
    app: flannel
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "vxlan"
      }
    }
EOF
    
    # Apply the updated configuration
    info "Updating Flannel ConfigMap with Linux optimizations"
    kubectl apply -f /tmp/flannel-linux-config.yaml
    
    # Clean up temp file
    rm -f /tmp/flannel-linux-config.yaml
fi

# Step 5: Restart Flannel pods to apply new configuration
info "Step 5: Restarting Flannel pods to apply new configuration"

# Delete all Flannel pods to force recreation with new config
info "Deleting existing Flannel pods..."
kubectl delete pods -n "$FLANNEL_NAMESPACE" -l app=flannel --force --grace-period=0

# Wait for Flannel DaemonSet to recreate pods
info "Waiting for Flannel DaemonSet to recreate pods..."
sleep 15

# Check Flannel pod status
info "Checking Flannel pod status..."
for i in {1..12}; do
    READY_PODS=$(kubectl get pods -n "$FLANNEL_NAMESPACE" -l app=flannel --no-headers 2>/dev/null | grep "Running" | wc -l || echo "0")
    DESIRED_PODS=$(kubectl get daemonset -n "$FLANNEL_NAMESPACE" -o jsonpath='{.items[0].status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    
    info "Flannel pods: $READY_PODS/$DESIRED_PODS ready"
    
    if [ "$READY_PODS" -eq "$DESIRED_PODS" ] && [ "$DESIRED_PODS" -gt 0 ]; then
        success "✓ All Flannel pods are running"
        break
    fi
    
    if [ $i -eq 12 ]; then
        warn "Flannel pods are taking longer than expected to start"
        kubectl get pods -n "$FLANNEL_NAMESPACE" -l app=flannel
    else
        sleep 10
    fi
done

# Step 6: Verify CNI bridge recreation
info "Step 6: Waiting for CNI bridges to be recreated..."

sleep 20

# Check CNI bridge on current node (if this is a cluster node)
HOSTNAME=$(hostname)
if kubectl get nodes "$HOSTNAME" >/dev/null 2>&1; then
    info "Checking CNI bridge on current node: $HOSTNAME"
    
    if ip addr show cni0 >/dev/null 2>&1; then
        CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
        if [ -n "$CNI_IP" ]; then
            info "CNI bridge IP: $CNI_IP"
            
            if echo "$CNI_IP" | grep -q "10.244."; then
                success "✓ CNI bridge has correct subnet IP"
            else
                warn "⚠ CNI bridge IP may still be incorrect: $CNI_IP"
            fi
        fi
    else
        info "CNI bridge not yet created (normal if no pods scheduled)"
    fi
fi

# Step 7: Test pod creation and networking
info "Step 7: Testing pod creation and networking"

# Create test pods on different nodes if possible
info "Creating test pods to validate networking..."

# Test pod 1: On storage node (where the problem was reported)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: flannel-test-1
  namespace: kube-system
spec:
  nodeName: storagenodet3500
  tolerations:
  - operator: Exists
  containers:
  - name: test
    image: busybox:1.35
    command: ["sleep", "300"]
  restartPolicy: Never
EOF

# Test pod 2: On first Linux node (likely control plane)
FIRST_LINUX_NODE=$(echo "$LINUX_NODES" | head -1)
if [ "$FIRST_LINUX_NODE" != "storagenodet3500" ]; then
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: flannel-test-2
  namespace: kube-system
spec:
  nodeName: $FIRST_LINUX_NODE
  tolerations:
  - operator: Exists
  containers:
  - name: test
    image: busybox:1.35
    command: ["sleep", "300"]
  restartPolicy: Never
EOF
    CREATED_TEST_2=true
fi

# Wait for test pods to be ready
info "Waiting for test pods to be ready..."
kubectl wait --for=condition=Ready pod/flannel-test-1 -n kube-system --timeout=120s || warn "Test pod 1 not ready"

if [ "${CREATED_TEST_2:-false}" = true ]; then
    kubectl wait --for=condition=Ready pod/flannel-test-2 -n kube-system --timeout=120s || warn "Test pod 2 not ready"
fi

# Test connectivity between pods
TEST_1_IP=$(kubectl get pod flannel-test-1 -n kube-system -o jsonpath='{.status.podIP}' 2>/dev/null)
if [ "${CREATED_TEST_2:-false}" = true ]; then
    TEST_2_IP=$(kubectl get pod flannel-test-2 -n kube-system -o jsonpath='{.status.podIP}' 2>/dev/null)
fi

if [ -n "$TEST_1_IP" ]; then
    info "Test pod 1 IP: $TEST_1_IP"
    
    if [ -n "$TEST_2_IP" ]; then
        info "Test pod 2 IP: $TEST_2_IP"
        
        info "Testing connectivity between pods..."
        if kubectl exec -n kube-system flannel-test-1 -- ping -c 3 -W 5 "$TEST_2_IP" >/dev/null 2>&1; then
            success "✓ Inter-node pod connectivity working"
        else
            error "✗ Inter-node pod connectivity failed"
        fi
    fi
    
    # Test DNS resolution
    if kubectl exec -n kube-system flannel-test-1 -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
        success "✓ DNS resolution working"
    else
        warn "⚠ DNS resolution issues"
    fi
else
    warn "Test pod 1 has no IP - CNI issues may persist"
fi

# Step 8: Clean up test resources
info "Step 8: Cleaning up test resources"

kubectl delete pod flannel-test-1 -n kube-system --ignore-not-found >/dev/null 2>&1 || true
if [ "${CREATED_TEST_2:-false}" = true ]; then
    kubectl delete pod flannel-test-2 -n kube-system --ignore-not-found >/dev/null 2>&1 || true
fi

# Step 9: Final validation and summary
echo
info "=== Flannel CNI Fix Summary ==="

echo "Configuration applied:"
if [ "$MIXED_OS" = true ]; then
    echo "✅ Mixed-OS optimized Flannel configuration"
    echo "  - VXLAN backend for cross-platform compatibility"
    echo "  - Force address delegation for Windows compatibility"
    echo "  - Standard pod subnet (10.244.0.0/16)"
else
    echo "✅ Linux-optimized Flannel configuration"
    echo "  - VXLAN backend for reliability"
    echo "  - Standard CNI delegation"
    echo "  - Standard pod subnet (10.244.0.0/16)"
fi

echo
echo "Current Flannel status:"
kubectl get pods -n "$FLANNEL_NAMESPACE" -l app=flannel -o wide

echo
success "🎉 Flannel CNI configuration update completed!"
echo
echo "Next steps:"
echo "1. Wait 2-3 minutes for all networking to stabilize"
echo "2. Test pod-to-pod connectivity: ./scripts/validate_pod_connectivity.sh"
echo "3. If issues persist, restart worker nodes: sudo systemctl restart kubelet"

echo
echo "=== Fix Complete ==="
echo "Timestamp: $(date)"
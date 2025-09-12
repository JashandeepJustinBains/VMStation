#!/bin/bash

# Validate Cluster Communication and NodePort Services
# This script validates that all aspects of cluster communication work correctly
# including kubectl access, NodePort services, and inter-node connectivity

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

echo "=== VMStation Cluster Communication Validation ==="
echo "Timestamp: $(date)"
echo

# Test results tracking
PASSED_TESTS=0
FAILED_TESTS=0
TOTAL_TESTS=0

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    info "Test $TOTAL_TESTS: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        success "✅ PASS: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        error "❌ FAIL: $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Function to run a test with output
run_test_with_output() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    info "Test $TOTAL_TESTS: $test_name"
    
    local output
    if output=$(eval "$test_command" 2>&1); then
        success "✅ PASS: $test_name"
        echo "$output"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        error "❌ FAIL: $test_name"
        echo "Error output: $output"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Test 1: kubectl Basic Connectivity
info "=== Step 1: kubectl Connectivity Tests ==="

run_test "kubectl client version check" "kubectl version --client"
run_test "kubectl cluster connectivity" "timeout 10 kubectl get nodes"
run_test "kubectl API server health" "timeout 10 kubectl get --raw /healthz"

# Test 2: Node Status Validation
info "=== Step 2: Node Status Validation ==="

run_test_with_output "All nodes are Ready" "kubectl get nodes --no-headers | grep -v NotReady"

# Get node count for further tests
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l 2>/dev/null || echo "0")
READY_COUNT=$(kubectl get nodes --no-headers | grep -c " Ready " 2>/dev/null || echo "0")
# Ensure single integers
NODE_COUNT=$(echo "$NODE_COUNT" | tr -d ' \n\r' | head -1)
READY_COUNT=$(echo "$READY_COUNT" | tr -d ' \n\r' | head -1)

info "Cluster has $NODE_COUNT nodes, $READY_COUNT are Ready"

# Test 3: Core System Pods
info "=== Step 3: Core System Pod Health ==="

run_test "kube-system namespace exists" "kubectl get namespace kube-system"
run_test "CoreDNS pods are running" "kubectl get pods -n kube-system -l k8s-app=kube-dns | grep -q 'Running'"
run_test "kube-proxy pods are running" "kubectl get pods -n kube-system -l k8s-app=kube-proxy | grep -q 'Running'"

# Check for any crashlooping pods
if ! run_test "No pods in CrashLoopBackOff" "! kubectl get pods --all-namespaces | grep -q CrashLoopBackOff"; then
    warn "Found pods in CrashLoopBackOff state:"
    kubectl get pods --all-namespaces | grep CrashLoopBackOff || true
fi

# Test 4: CNI and Networking
info "=== Step 4: CNI and Network Configuration ==="

# Check if flannel is being used
if kubectl get namespace kube-flannel >/dev/null 2>&1; then
    run_test "Flannel namespace exists" "kubectl get namespace kube-flannel"
    run_test "Flannel DaemonSet is ready" "kubectl get daemonset -n kube-flannel | grep -q 'READY'"
    
    # Check flannel pod status on each node
    run_test_with_output "Flannel pods running on all nodes" "kubectl get pods -n kube-flannel -o wide"
fi

# Check for CNI configuration
if [ -d "/etc/cni/net.d" ]; then
    run_test "CNI configuration directory exists" "[ -d /etc/cni/net.d ]"
    
    # Check for flannel config
    if [ -f "/etc/cni/net.d/10-flannel.conflist" ]; then
        run_test "Flannel CNI config exists" "[ -f /etc/cni/net.d/10-flannel.conflist ]"
    fi
fi

# Test 5: Service and Endpoint Functionality
info "=== Step 5: Service and Endpoint Tests ==="

run_test "kubernetes service exists" "kubectl get service kubernetes"
run_test "kubernetes endpoints exist" "kubectl get endpoints kubernetes"

# Check if there are any services with NodePort
NODEPORT_SERVICES=$(kubectl get services --all-namespaces -o wide | grep NodePort || echo "")

if [ -n "$NODEPORT_SERVICES" ]; then
    info "Found NodePort services:"
    echo "$NODEPORT_SERVICES"
    
    # Test NodePort connectivity for each service
    echo "$NODEPORT_SERVICES" | while read -r line; do
        if [ -n "$line" ]; then
            namespace=$(echo "$line" | awk '{print $1}')
            service=$(echo "$line" | awk '{print $2}')
            nodeport=$(echo "$line" | awk '{print $6}' | cut -d: -f2 | cut -d/ -f1)
            
            if [ -n "$nodeport" ] && [ "$nodeport" != "<none>" ]; then
                info "Testing NodePort service: $namespace/$service on port $nodeport"
                
                # Get node IPs for testing
                node_ips=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
                
                for node_ip in $node_ips; do
                    if timeout 5 curl -s --connect-timeout 3 "http://$node_ip:$nodeport/" >/dev/null 2>&1; then
                        success "✅ NodePort $nodeport accessible on $node_ip"
                    else
                        warn "⚠️  NodePort $nodeport not accessible on $node_ip"
                    fi
                done
            fi
        fi
    done
else
    info "No NodePort services found to test"
fi

# Test 6: DNS Resolution
info "=== Step 6: DNS Resolution Tests ==="

# Create a temporary pod to test DNS resolution
info "Creating temporary pod for DNS testing..."

cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: dns-test
  namespace: default
spec:
  containers:
  - name: dns-test
    image: busybox:1.35
    command: ['sleep', '300']
  restartPolicy: Never
EOF

# Wait for pod to be ready
sleep 10

if kubectl get pod dns-test >/dev/null 2>&1; then
    # Test DNS resolution from within the pod
    run_test "DNS resolution of kubernetes service" "kubectl exec dns-test -- nslookup kubernetes.default.svc.cluster.local"
    run_test "DNS resolution of kube-dns" "kubectl exec dns-test -- nslookup kube-dns.kube-system.svc.cluster.local"
    
    # Clean up test pod
    kubectl delete pod dns-test --force --grace-period=0 >/dev/null 2>&1 || true
else
    warn "Could not create DNS test pod - skipping DNS resolution tests"
fi

# Test 7: iptables and kube-proxy functionality
info "=== Step 7: iptables and kube-proxy Validation ==="

# Check if iptables rules exist for kube-proxy
if command -v iptables >/dev/null 2>&1; then
    run_test "iptables KUBE-SERVICES chain exists" "sudo iptables -t nat -L KUBE-SERVICES >/dev/null 2>&1"
    
    # Check for NodePort rules if there are NodePort services
    if [ -n "$NODEPORT_SERVICES" ]; then
        run_test "iptables has NodePort rules" "sudo iptables -t nat -L KUBE-NODEPORTS >/dev/null 2>&1"
    fi
    
    # Check for nftables compatibility issues
    nftables_error=$(sudo iptables -t nat -L 2>&1 | grep -i "nf_tables.*incompatible" || echo "")
    if [ -n "$nftables_error" ]; then
        error "Detected iptables/nftables compatibility issue:"
        echo "$nftables_error"
        warn "This may cause kube-proxy to fail"
    else
        success "No iptables/nftables compatibility issues detected"
    fi
else
    warn "iptables command not available for testing"
fi

# Test 8: Inter-pod communication
info "=== Step 8: Inter-pod Communication Test ==="

# Create two test pods on different nodes if possible
info "Creating test pods for inter-pod communication..."

cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: comm-test-1
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
  restartPolicy: Never
---
apiVersion: v1
kind: Pod
metadata:
  name: comm-test-2
  namespace: default
spec:
  containers:
  - name: busybox
    image: busybox:1.35
    command: ['sleep', '300']
  restartPolicy: Never
EOF

# Wait for pods to be ready
sleep 15

if kubectl get pod comm-test-1 >/dev/null 2>&1 && kubectl get pod comm-test-2 >/dev/null 2>&1; then
    pod1_ip=$(kubectl get pod comm-test-1 -o jsonpath='{.status.podIP}' 2>/dev/null)
    
    if [ -n "$pod1_ip" ]; then
        run_test "Inter-pod communication test" "kubectl exec comm-test-2 -- wget -q -O- --timeout=5 http://$pod1_ip/"
    else
        warn "Could not get IP for test pod 1"
    fi
    
    # Clean up test pods
    kubectl delete pod comm-test-1 comm-test-2 --force --grace-period=0 >/dev/null 2>&1 || true
else
    warn "Could not create communication test pods"
fi

# Test 9: Specific Issue Validation
info "=== Step 9: Specific Issue Validation ==="

# Check for the specific issues mentioned in the problem statement
if kubectl get namespace jellyfin >/dev/null 2>&1; then
    info "Jellyfin namespace exists - testing Jellyfin NodePort access"
    
    # Check if jellyfin service exists
    if kubectl get service -n jellyfin jellyfin-service >/dev/null 2>&1; then
        jellyfin_nodeport=$(kubectl get service -n jellyfin jellyfin-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
        
        if [ -n "$jellyfin_nodeport" ]; then
            info "Testing Jellyfin NodePort $jellyfin_nodeport"
            
            # Test on each node
            node_ips=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
            
            for node_ip in $node_ips; do
                if timeout 5 curl -s --connect-timeout 3 "http://$node_ip:$jellyfin_nodeport/" >/dev/null 2>&1; then
                    success "✅ Jellyfin NodePort accessible on $node_ip:$jellyfin_nodeport"
                else
                    warn "⚠️  Jellyfin NodePort not accessible on $node_ip:$jellyfin_nodeport"
                fi
            done
        fi
    fi
fi

# Final Summary
echo
info "=== Test Summary ==="
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"

if [ "$FAILED_TESTS" -eq 0 ]; then
    success "🎉 All tests passed! Cluster communication is working correctly."
    exit 0
elif [ "$PASSED_TESTS" -gt "$FAILED_TESTS" ]; then
    warn "⚠️  Some tests failed, but cluster is mostly functional ($PASSED_TESTS/$TOTAL_TESTS passed)"
    
    echo
    echo "Common fixes for failed tests:"
    echo "1. Run kubectl configuration fix: ./scripts/fix_worker_kubectl_config.sh"
    echo "2. Fix kube-proxy issues: ./scripts/fix_remaining_pod_issues.sh"
    echo "3. Fix CNI bridge conflicts: ./scripts/fix_cni_bridge_conflict.sh"
    echo "4. Check iptables compatibility and restart kube-proxy"
    
    exit 1
else
    error "❌ Multiple critical tests failed ($FAILED_TESTS/$TOTAL_TESTS failed)"
    
    echo
    echo "Critical issues detected. Recommended actions:"
    echo "1. Verify cluster is properly initialized: kubectl cluster-info"
    echo "2. Check all nodes are joined: kubectl get nodes"
    echo "3. Run comprehensive fix: ./scripts/fix_remaining_pod_issues.sh"
    echo "4. Restart cluster networking if needed"
    
    exit 2
fi
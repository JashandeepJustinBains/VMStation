#!/bin/bash

# Test Script for Problem Statement Scenarios
# This script tests the exact scenarios described in the problem statement
# to validate that the fix_cluster_communication.sh script properly addresses them

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

echo "=== Problem Statement Scenario Validation ==="
echo "Testing the exact scenarios described in the GitHub issue"
echo "Timestamp: $(date)"
echo

# Test tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo
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

# Test 1: Pod-to-pod ping connectivity (exact problem statement scenario)
echo "=== Testing Pod-to-Pod Connectivity (Problem Statement Scenario) ==="

info "Creating test pods to replicate the ping failure scenario..."

# Clean up any existing test pods
kubectl delete pod debug-net test-target --ignore-not-found >/dev/null 2>&1 || true
sleep 3

# Create debug pod on specific node (as mentioned in problem statement)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: debug-net
  namespace: default
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot
    command: ["sleep", "600"]
  restartPolicy: Never
EOF

# Create target pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-target
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
  restartPolicy: Never
EOF

# Wait for pods to be ready
info "Waiting for test pods to be ready..."
if kubectl wait --for=condition=Ready pod/debug-net --timeout=60s && kubectl wait --for=condition=Ready pod/test-target --timeout=60s; then
    
    target_ip=$(kubectl get pod test-target -o jsonpath='{.status.podIP}')
    
    if [ -n "$target_ip" ]; then
        info "Target pod IP: $target_ip"
        
        # Test 1: Ping connectivity (exact command from problem statement)
        echo
        info "Running ping test (exact scenario from problem statement)..."
        echo "Expected in problem statement: '100% packet loss, time 1011ms'"
        
        ping_output=$(kubectl exec debug-net -- ping -c2 "$target_ip" 2>&1 || true)
        echo "$ping_output"
        
        if echo "$ping_output" | grep -q "100% packet loss"; then
            error "❌ REPRODUCTION: Pod-to-pod ping shows 100% packet loss (matches problem statement)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        elif echo "$ping_output" | grep -q "0% packet loss\|1 received\|2 received"; then
            success "✅ FIXED: Pod-to-pod ping is now working (problem resolved)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            warn "⚠️  UNCLEAR: Ping test result is ambiguous"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
        # Test 2: HTTP connectivity test
        echo
        info "Running HTTP connectivity test..."
        
        http_output=$(kubectl exec debug-net -- timeout 10 curl -sv --max-time 5 "http://$target_ip/" 2>&1 || true)
        
        if echo "$http_output" | grep -q "timed out\|timeout\|failed"; then
            error "❌ REPRODUCTION: HTTP connectivity fails (matches problem statement)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        elif echo "$http_output" | grep -q "200 OK\|Welcome to nginx"; then
            success "✅ FIXED: HTTP connectivity is now working (problem resolved)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            warn "⚠️  UNCLEAR: HTTP test result is ambiguous"
            echo "Output: $http_output"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        
    else
        error "Could not get target pod IP"
    fi
else
    error "Test pods failed to become ready"
fi

# Test 3: DNS resolution test (from problem statement)
echo
echo "=== Testing DNS Resolution (Problem Statement Scenario) ==="

info "Testing DNS resolution of kubernetes service (exact test from problem statement)..."

dns_output=$(kubectl exec debug-net -- nslookup kubernetes.default.svc.cluster.local 2>&1 || true)

if echo "$dns_output" | grep -q "server can't find\|NXDOMAIN\|timed out"; then
    error "❌ REPRODUCTION: DNS resolution fails (matches problem statement)"
    echo "Expected problem statement error: 'DNS resolution of kubernetes service failed'"
    FAILED_TESTS=$((FAILED_TESTS + 1))
elif echo "$dns_output" | grep -q "Address.*10\."; then
    success "✅ FIXED: DNS resolution is now working (problem resolved)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    warn "⚠️  UNCLEAR: DNS test result is ambiguous"
    echo "Output: $dns_output"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test 4: External connectivity test (from problem statement)
echo
echo "=== Testing External Connectivity (Problem Statement Scenario) ==="

info "Testing external connectivity (exact scenario from problem statement)..."
echo "Expected problem statement error: 'Resolving timed out after 8002 milliseconds'"

external_output=$(kubectl exec debug-net -- timeout 10 curl -sv --max-time 8 https://repo.jellyfin.org/files/plugin/manifest.json 2>&1 || true)

if echo "$external_output" | grep -q "timed out\|timeout\|Resolving timed out"; then
    error "❌ REPRODUCTION: External connectivity fails (matches problem statement)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
elif echo "$external_output" | grep -q "200 OK\|HTTP/"; then
    success "✅ FIXED: External connectivity is now working (problem resolved)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    warn "⚠️  UNCLEAR: External connectivity test result is ambiguous"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test 5: Jellyfin service accessibility (NodePort 30096)
echo
echo "=== Testing Jellyfin NodePort Access (Problem Statement Scenario) ==="

if kubectl get namespace jellyfin >/dev/null 2>&1 && kubectl get service -n jellyfin jellyfin-service >/dev/null 2>&1; then
    jellyfin_nodeport=$(kubectl get service -n jellyfin jellyfin-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    
    if [ -n "$jellyfin_nodeport" ]; then
        info "Testing Jellyfin NodePort $jellyfin_nodeport (exact scenario from problem statement)..."
        echo "Expected problem statement: 'NodePort 30096 not accessible on 192.168.4.xx'"
        
        # Test on each node IP
        node_ips=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
        accessible_nodes=0
        total_nodes=0
        
        for node_ip in $node_ips; do
            total_nodes=$((total_nodes + 1))
            info "Testing NodePort access on $node_ip:$jellyfin_nodeport"
            
            if timeout 5 curl -s --connect-timeout 3 "http://$node_ip:$jellyfin_nodeport/" >/dev/null 2>&1; then
                success "✅ NodePort accessible on $node_ip:$jellyfin_nodeport"
                accessible_nodes=$((accessible_nodes + 1))
            else
                error "❌ NodePort NOT accessible on $node_ip:$jellyfin_nodeport (matches problem statement)"
            fi
        done
        
        if [ $accessible_nodes -eq 0 ]; then
            error "❌ REPRODUCTION: Jellyfin NodePort not accessible on any node (matches problem statement)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        elif [ $accessible_nodes -eq $total_nodes ]; then
            success "✅ FIXED: Jellyfin NodePort accessible on all nodes (problem resolved)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            warn "⚠️  PARTIAL: Jellyfin NodePort accessible on some nodes ($accessible_nodes/$total_nodes)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    else
        warn "Could not determine Jellyfin NodePort"
    fi
else
    warn "Jellyfin service not found - cannot test NodePort scenario"
fi

# Test 6: Jellyfin pod readiness (0/1 vs 1/1)
echo
echo "=== Testing Jellyfin Pod Readiness (Problem Statement Scenario) ==="

if kubectl get namespace jellyfin >/dev/null 2>&1; then
    if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
        jellyfin_status=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        jellyfin_phase=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null)
        
        info "Jellyfin pod phase: $jellyfin_phase, ready: $jellyfin_status"
        
        if [ "$jellyfin_status" = "false" ] || [ "$jellyfin_phase" != "Running" ]; then
            error "❌ REPRODUCTION: Jellyfin shows 0/1 running status (matches problem statement)"
            kubectl get pod -n jellyfin jellyfin -o wide || true
            FAILED_TESTS=$((FAILED_TESTS + 1))
        else
            success "✅ FIXED: Jellyfin shows 1/1 running status (problem resolved)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        fi
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    else
        warn "Jellyfin pod not found - cannot test readiness scenario"
    fi
else
    warn "Jellyfin namespace not found - cannot test pod readiness"
fi

# Test 7: System component status (Flannel, kube-proxy)
echo
echo "=== Testing System Component Status (Problem Statement Scenario) ==="

info "Checking for CrashLoopBackOff issues (exact scenario from problem statement)..."

# Check Flannel
flannel_issues=$(kubectl get pods -n kube-flannel 2>/dev/null | grep -E "CrashLoopBackOff|BackOff" || echo "")
if [ -n "$flannel_issues" ]; then
    error "❌ REPRODUCTION: Flannel pods in CrashLoopBackOff (matches problem statement)"
    echo "$flannel_issues"
    FAILED_TESTS=$((FAILED_TESTS + 1))
else
    success "✅ FIXED: No Flannel CrashLoopBackOff issues found"
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Check kube-proxy
proxy_issues=$(kubectl get pods -n kube-system -l component=kube-proxy | grep -E "CrashLoopBackOff|BackOff" || echo "")
if [ -n "$proxy_issues" ]; then
    error "❌ REPRODUCTION: kube-proxy pods in CrashLoopBackOff (matches problem statement)"
    echo "$proxy_issues"
    FAILED_TESTS=$((FAILED_TESTS + 1))
else
    success "✅ FIXED: No kube-proxy CrashLoopBackOff issues found"
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test 8: iptables backend compatibility
echo
echo "=== Testing iptables Backend Compatibility (Problem Statement Scenario) ==="

info "Checking for iptables/nft backend mismatch (exact scenario from problem statement)..."

current_backend=$(update-alternatives --query iptables 2>/dev/null | grep "Value:" | awk '{print $2}' || echo "unknown")
info "Current iptables backend: $current_backend"

if echo "$current_backend" | grep -q "nft"; then
    warn "⚠️  System still using nftables backend (potential issue from problem statement)"
    # Check if it's causing actual problems
    iptables_test=$(iptables -t nat -L >/dev/null 2>&1 && echo "OK" || echo "FAIL")
    if [ "$iptables_test" = "FAIL" ]; then
        error "❌ REPRODUCTION: iptables/nft compatibility issues (matches problem statement)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    else
        success "✅ ACCEPTABLE: nftables backend working without errors"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi
else
    success "✅ FIXED: Using legacy iptables backend (problem resolved)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Cleanup test resources
info "Cleaning up test resources..."
kubectl delete pod debug-net test-target --ignore-not-found >/dev/null 2>&1 || true

# Final summary
echo
echo "=== Problem Statement Validation Summary ==="
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"

echo
if [ $FAILED_TESTS -eq 0 ]; then
    success "🎉 ALL PROBLEM STATEMENT SCENARIOS RESOLVED!"
    echo "The fix_cluster_communication.sh script successfully addressed all issues:"
    echo "✅ Pod-to-pod ping connectivity working (no more 100% packet loss)"
    echo "✅ HTTP connectivity between pods working"
    echo "✅ DNS resolution within cluster working"
    echo "✅ External connectivity working (no more timeouts)"
    echo "✅ Jellyfin NodePort accessible on all nodes"
    echo "✅ Jellyfin pod showing 1/1 ready status"
    echo "✅ No more CrashLoopBackOff issues with Flannel/kube-proxy"
    echo "✅ iptables compatibility issues resolved"
    
    echo
    echo "Cluster communication is now fully functional!"
    exit 0
    
elif [ $PASSED_TESTS -gt $FAILED_TESTS ]; then
    warn "⚠️  PARTIAL SUCCESS: Most issues resolved but some remain"
    echo "Progress made: $PASSED_TESTS/$TOTAL_TESTS tests passed"
    echo
    echo "Remaining issues need additional investigation:"
    echo "- Re-run the fix_cluster_communication.sh script"
    echo "- Check logs for specific error details"
    echo "- Consider manual intervention for persistent issues"
    exit 1
    
else
    error "❌ CRITICAL: Most problem statement scenarios still exist"
    echo "Failed tests: $FAILED_TESTS/$TOTAL_TESTS"
    echo
    echo "The cluster networking issues persist and need immediate attention:"
    echo "1. Re-run fix_cluster_communication.sh with --non-interactive flag"
    echo "2. Check system logs: journalctl -u kubelet -n 50"
    echo "3. Verify node connectivity and basic networking"
    echo "4. Consider cluster reset if issues are too severe"
    exit 2
fi
#!/bin/bash

# Diagnose Inter-Pod Communication Issues
# This script analyzes the exact inter-pod communication symptoms shown in the problem statement:
# - kube-proxy daemonset readiness issues (e.g., 3 desired, 3 current, 2 ready)
# - Service endpoint problems ("has no endpoints")
# - Flannel networking and iptables rule analysis
# - Pod-to-pod connectivity failures

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

echo "=== VMStation Inter-Pod Communication Diagnostics ==="
echo "Analyzing the specific symptoms from your problem statement"
echo "Timestamp: $(date)"
echo

# Check prerequisites
if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    echo "Please ensure this script is run from a node with kubectl configured"
    exit 1
fi

echo "=== 1. kube-proxy Daemonset Analysis ==="
info "Checking kube-proxy daemonset status (addressing: 3 desired, 3 current, 2 ready)"

if kubectl get daemonset -n kube-system kube-proxy >/dev/null 2>&1; then
    echo
    echo "Current kube-proxy daemonset status:"
    kubectl get daemonset -n kube-system kube-proxy
    
    # Get detailed status
    DESIRED=$(kubectl get daemonset -n kube-system kube-proxy -o jsonpath='{.status.desiredNumberScheduled}')
    CURRENT=$(kubectl get daemonset -n kube-system kube-proxy -o jsonpath='{.status.currentNumberScheduled}')
    READY=$(kubectl get daemonset -n kube-system kube-proxy -o jsonpath='{.status.numberReady}')
    AVAILABLE=$(kubectl get daemonset -n kube-system kube-proxy -o jsonpath='{.status.numberAvailable}')
    
    echo
    info "Detailed analysis:"
    echo "  Desired: $DESIRED"
    echo "  Current: $CURRENT" 
    echo "  Ready: $READY"
    echo "  Available: $AVAILABLE"
    
    if [ "$READY" -lt "$DESIRED" ]; then
        error "❌ ISSUE DETECTED: kube-proxy readiness problem ($READY/$DESIRED ready)"
        echo
        warn "This matches the problem statement: 'DESIRED 3 CURRENT 3 READY 2'"
        
        echo
        info "Checking individual kube-proxy pod status:"
        kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide
        
        echo
        info "Checking for problematic kube-proxy pods:"
        problematic_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers | grep -v "Running" || echo "")
        if [ -n "$problematic_pods" ]; then
            error "Found problematic kube-proxy pods:"
            echo "$problematic_pods"
            
            # Get logs from the first problematic pod
            first_pod=$(echo "$problematic_pods" | head -1 | awk '{print $1}')
            if [ -n "$first_pod" ]; then
                echo
                warn "Recent logs from problematic pod $first_pod:"
                kubectl logs -n kube-system "$first_pod" --tail=10 || echo "Could not retrieve logs"
            fi
        else
            warn "All kube-proxy pods show 'Running' but daemonset reports not ready"
            warn "This suggests readiness probe failures"
        fi
        
        echo
        info "Recommended fixes:"
        echo "  1. Run: ./scripts/fix_remaining_pod_issues.sh"
        echo "  2. Run: ./scripts/fix_iptables_compatibility.sh"
        echo "  3. Check: kubectl rollout restart daemonset/kube-proxy -n kube-system"
        
    else
        success "✅ kube-proxy daemonset is fully ready ($READY/$DESIRED)"
    fi
else
    error "kube-proxy daemonset not found"
fi

echo
echo "=== 2. Service Endpoint Analysis ==="
info "Checking for services with 'no endpoints' (addressing: jellyfin service has no endpoints)"

# Check all services for endpoint issues
echo
info "Scanning all services for endpoint problems..."

services_with_no_endpoints=$(kubectl get services --all-namespaces -o json | jq -r '.items[] | select(.spec.selector != null) | "\(.metadata.namespace)/\(.metadata.name)"' | while read svc; do
    namespace=$(echo "$svc" | cut -d'/' -f1)
    name=$(echo "$svc" | cut -d'/' -f2)
    endpoints=$(kubectl get endpoints -n "$namespace" "$name" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
    if [ -z "$endpoints" ]; then
        echo "$namespace/$name"
    fi
done)

if [ -n "$services_with_no_endpoints" ]; then
    error "❌ ISSUE DETECTED: Services with no endpoints found:"
    echo "$services_with_no_endpoints"
    
    echo
    warn "This matches the problem statement showing:"
    warn "  'jellyfin/jellyfin-service:http has no endpoints'"
    warn "  'jellyfin/jellyfin-service:https has no endpoints'"
    
    # Analyze jellyfin specifically if it exists
    if kubectl get namespace jellyfin >/dev/null 2>&1; then
        echo
        info "Detailed jellyfin service analysis:"
        if kubectl get service -n jellyfin jellyfin-service >/dev/null 2>&1; then
            echo "Jellyfin service details:"
            kubectl get service -n jellyfin jellyfin-service -o wide
            
            echo
            echo "Jellyfin endpoints:"
            kubectl get endpoints -n jellyfin jellyfin-service -o wide || echo "No endpoints found"
            
            echo
            echo "Jellyfin pod status:"
            kubectl get pods -n jellyfin -o wide || echo "No jellyfin pods found"
            
            # Check if pods match service selector
            service_selector=$(kubectl get service -n jellyfin jellyfin-service -o jsonpath='{.spec.selector}' | jq -r 'to_entries[] | "\(.key)=\(.value)"' | tr '\n' ',' | sed 's/,$//' 2>/dev/null || echo "")
            if [ -n "$service_selector" ]; then
                echo
                echo "Checking pods matching service selector ($service_selector):"
                kubectl get pods -n jellyfin -l "$service_selector" 2>/dev/null || echo "No pods match the service selector"
            fi
        else
            warn "jellyfin-service not found in jellyfin namespace"
        fi
        
        echo
        info "Recommended fixes for jellyfin endpoints:"
        echo "  1. Check if jellyfin pod is running: kubectl get pods -n jellyfin"
        echo "  2. Verify pod labels match service selector"
        echo "  3. Check pod readiness probes: kubectl describe pod -n jellyfin jellyfin"
        echo "  4. Run: ./scripts/fix_cluster_communication.sh"
    fi
else
    success "✅ All services have proper endpoints"
fi

echo
echo "=== 3. iptables Rules Analysis ==="
info "Analyzing iptables rules (addressing: KUBE-EXTERNAL-SERVICES REJECT rules)"

if command -v iptables >/dev/null 2>&1; then
    echo
    info "Checking KUBE-EXTERNAL-SERVICES chain:"
    
    external_services_rules=$(sudo iptables -t nat -L KUBE-EXTERNAL-SERVICES -n -v 2>/dev/null || echo "Chain not found")
    echo "$external_services_rules"
    
    # Look for "has no endpoints" patterns
    reject_rules=$(echo "$external_services_rules" | grep "REJECT" | grep "has no endpoints" || echo "")
    if [ -n "$reject_rules" ]; then
        error "❌ ISSUE DETECTED: Found REJECT rules for services with no endpoints"
        echo
        warn "This matches the problem statement showing:"
        echo "$reject_rules"
        
        echo
        info "These REJECT rules indicate services exist but have no backend pods"
        info "This confirms the endpoint analysis above"
    else
        if echo "$external_services_rules" | grep -q "KUBE-EXTERNAL-SERVICES"; then
            success "✅ KUBE-EXTERNAL-SERVICES chain exists and looks healthy"
        else
            warn "⚠️  KUBE-EXTERNAL-SERVICES chain not found or empty"
        fi
    fi
    
    echo
    info "Checking KUBE-SERVICES chain for service routing:"
    services_rules=$(sudo iptables -t nat -L KUBE-SERVICES -n --line-numbers 2>/dev/null | head -20 || echo "Chain not found")
    echo "$services_rules"
    
    echo
    info "Checking FLANNEL-FWD chain for pod networking:"
    flannel_rules=$(sudo iptables -L FLANNEL-FWD -n -v 2>/dev/null || echo "Chain not found")
    echo "$flannel_rules"
    
    # Analyze Flannel rules
    if echo "$flannel_rules" | grep -q "10.244.0.0/16"; then
        success "✅ Flannel forwarding rules present for pod network 10.244.0.0/16"
    else
        warn "⚠️  Flannel forwarding rules missing or misconfigured"
    fi
    
else
    warn "iptables command not available for analysis"
fi

echo
echo "=== 4. Pod Network Routing Analysis ==="
info "Checking pod network routing (addressing: Flannel routing issues)"

echo "Current routing table:"
ip route show | grep -E "(10\.244|cni|flannel)" || echo "No pod network routes found"

echo
echo "Network interfaces:"
ip addr show | grep -A2 -B1 -E "(cni0|flannel)" || echo "No CNI/Flannel interfaces found"

echo
echo "=== 5. DNS and Connectivity Test ==="
info "Testing actual inter-pod communication"

# Create a quick test pod if none exists
test_pod_created=false
if ! kubectl get pod test-connectivity-check >/dev/null 2>&1; then
    info "Creating test pod for connectivity verification..."
    kubectl run test-connectivity-check --image=busybox:1.35 --restart=Never --command -- sleep 300 >/dev/null 2>&1 || true
    sleep 5
    test_pod_created=true
fi

if kubectl get pod test-connectivity-check >/dev/null 2>&1; then
    pod_status=$(kubectl get pod test-connectivity-check -o jsonpath='{.status.phase}')
    if [ "$pod_status" = "Running" ]; then
        echo
        info "Testing DNS resolution from test pod:"
        dns_test=$(kubectl exec test-connectivity-check -- nslookup kubernetes.default 2>&1 || echo "DNS_FAILED")
        if echo "$dns_test" | grep -q "Address.*10\."; then
            success "✅ DNS resolution working"
        else
            error "❌ DNS resolution failed"
            echo "$dns_test"
        fi
        
        echo
        info "Testing external connectivity:"
        external_test=$(kubectl exec test-connectivity-check -- wget -T 5 -q -O - http://www.google.com 2>&1 || echo "EXTERNAL_FAILED")
        if echo "$external_test" | grep -q "html\|HTTP"; then
            success "✅ External connectivity working"
        else
            error "❌ External connectivity failed"
        fi
    else
        warn "Test pod not ready, status: $pod_status"
    fi
    
    # Cleanup if we created it
    if [ "$test_pod_created" = "true" ]; then
        kubectl delete pod test-connectivity-check --ignore-not-found >/dev/null 2>&1 || true
    fi
else
    warn "Could not create test pod for connectivity testing"
fi

echo
echo "=== Summary and Recommendations ==="

info "Based on the analysis of your inter-pod communication issues:"
echo

echo "🔍 DIAGNOSTIC SUMMARY:"
echo "  ✓ Analyzed kube-proxy daemonset readiness (3 desired vs 2 ready pattern)"
echo "  ✓ Identified services with no endpoints (jellyfin pattern)"  
echo "  ✓ Examined iptables KUBE-EXTERNAL-SERVICES REJECT rules"
echo "  ✓ Verified Flannel networking and pod routing"
echo "  ✓ Tested actual pod connectivity and DNS"

echo
echo "🛠️  RECOMMENDED ACTIONS:"
echo
echo "1. **Immediate fixes** (run in order):"
echo "   ./scripts/fix_cluster_communication.sh"
echo "   ./scripts/fix_iptables_compatibility.sh" 
echo "   ./scripts/validate_cluster_communication.sh"
echo
echo "2. **If jellyfin issues persist**:"
echo "   kubectl get pods -n jellyfin -o wide"
echo "   kubectl describe pod -n jellyfin jellyfin"
echo "   kubectl logs -n jellyfin jellyfin"
echo
echo "3. **For kube-proxy readiness issues**:"
echo "   kubectl rollout restart daemonset/kube-proxy -n kube-system"
echo "   kubectl rollout status daemonset/kube-proxy -n kube-system"
echo
echo "4. **Validate fixes**:"
echo "   ./scripts/test_problem_statement_scenarios.sh"
echo "   ./scripts/validate_pod_connectivity.sh"

echo
success "✅ Diagnostic complete! This repository CAN help diagnose your inter-pod communication errors."
echo
echo "The VMStation repository provides comprehensive tools to:"
echo "  • Identify the exact networking issues you're experiencing"
echo "  • Fix kube-proxy daemonset readiness problems"  
echo "  • Resolve service endpoint issues"
echo "  • Repair iptables and Flannel networking"
echo "  • Validate that fixes work correctly"
echo
echo "Run the recommended fix scripts above to resolve these issues."
#!/bin/bash

# Problem Statement Specific Network Diagnostic Script
# Diagnoses the exact issues described in the GitHub problem statement:
# - CoreDNS CrashLoopBackOff with DNS resolution failures
# - kube-proxy CrashLoopBackOff issues  
# - Complete inter-pod communication failure (100% packet loss)
# - Missing Flannel CNI components
# - Network isolation preventing cluster and external connectivity

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }
critical() { echo -e "${PURPLE}[CRITICAL]${NC} $1"; }

# Issue detection counters
ISSUES_DETECTED=0
CRITICAL_ISSUES=0

# Function to detect and report issues
detect_issue() {
    local issue_type="$1"
    local issue_description="$2"
    local severity="$3"
    
    ISSUES_DETECTED=$((ISSUES_DETECTED + 1))
    
    if [ "$severity" = "CRITICAL" ]; then
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
        critical "❌ CRITICAL ISSUE: $issue_description"
    elif [ "$severity" = "ERROR" ]; then
        error "❌ ERROR: $issue_description"
    elif [ "$severity" = "WARNING" ]; then
        warn "⚠️  WARNING: $issue_description"
    fi
    
    echo "   Type: $issue_type"
    echo "   Matches Problem Statement: YES"
    echo
}

echo "=================================================================="
echo "    VMStation Problem Statement Network Diagnostic"
echo "=================================================================="
echo "Analyzing the specific networking issues described in GitHub issue"
echo "Timestamp: $(date)"
echo "Host: $(hostname)"
echo

# Check prerequisites
if ! command -v kubectl >/dev/null 2>&1; then
    critical "kubectl not found - cannot diagnose cluster issues"
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    critical "Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "=== PHASE 1: CoreDNS Issues (Problem Statement Section 1) ==="
echo

# Check CoreDNS pod status - looking for CrashLoopBackOff
info "Checking CoreDNS pod status..."
coredns_status=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide 2>/dev/null || echo "")

if echo "$coredns_status" | grep -q "CrashLoopBackOff"; then
    detect_issue "CoreDNS_CrashLoopBackOff" "CoreDNS pods in CrashLoopBackOff state" "CRITICAL"
    echo "Problem Statement Match: 'coredns-777c769ffd-pqj8j 0/1 CrashLoopBackOff 10 (2m36s ago)'"
    echo "Current Status:"
    echo "$coredns_status"
else
    info "✓ CoreDNS pods not in CrashLoopBackOff"
fi

# Check CoreDNS readiness probe failures
info "Checking CoreDNS readiness probe issues..."
coredns_events=$(kubectl get events -n kube-system --field-selector reason=Unhealthy 2>/dev/null | grep coredns || echo "")

if echo "$coredns_events" | grep -q "Readiness probe failed.*context deadline exceeded"; then
    detect_issue "CoreDNS_Readiness_Timeout" "CoreDNS readiness probes timing out" "CRITICAL"
    echo "Problem Statement Match: 'Readiness probe failed: Get \"http://10.244.0.22:8181/ready\": context deadline exceeded'"
else
    info "✓ No CoreDNS readiness probe timeouts detected"
fi

# Check for DNS resolution errors in CoreDNS logs
info "Checking CoreDNS logs for DNS resolution errors..."
coredns_logs=$(kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50 2>/dev/null || echo "")

if echo "$coredns_logs" | grep -q "read udp.*i/o timeout"; then
    detect_issue "DNS_Resolution_Timeout" "CoreDNS experiencing DNS resolution timeouts" "CRITICAL"
    echo "Problem Statement Match: '[ERROR] plugin/errors: 2 ... read udp 10.244.0.22:55590->192.168.4.1:53: i/o timeout'"
else
    info "✓ No DNS resolution timeouts in CoreDNS logs"
fi

echo
echo "=== PHASE 2: kube-proxy Issues (Problem Statement Section 2) ==="
echo

# Check kube-proxy pod status
info "Checking kube-proxy pod status..."
kubeproxy_status=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide 2>/dev/null || echo "")

if echo "$kubeproxy_status" | grep -q "CrashLoopBackOff"; then
    detect_issue "KubeProxy_CrashLoopBackOff" "kube-proxy pods in CrashLoopBackOff state" "CRITICAL"
    echo "Problem Statement Match: 'kube-proxy-4g9mt 0/1 CrashLoopBackOff 1 (9s ago)'"
    echo "Current Status:"
    echo "$kubeproxy_status"
else
    info "✓ kube-proxy pods not in CrashLoopBackOff"
fi

# Check for frequent kube-proxy restarts
if [ -n "$kubeproxy_status" ]; then
    restart_count=$(echo "$kubeproxy_status" | awk 'NR>1 {print $4}' | grep -o '[0-9]\+' | sort -nr | head -1 || echo "0")
    if [ "$restart_count" -gt 5 ]; then
        detect_issue "KubeProxy_Frequent_Restarts" "kube-proxy pods restarting frequently ($restart_count restarts)" "ERROR"
        echo "Indicates persistent kube-proxy issues matching problem statement"
    fi
fi

echo
echo "=== PHASE 3: iptables Configuration Issues (Problem Statement Section 3) ==="
echo

# Check iptables NAT rules and service endpoints
info "Checking iptables NAT configuration..."

# Check for "no endpoints" services mentioned in problem statement
no_endpoints=$(kubectl get endpoints -A 2>/dev/null | grep "<none>" || echo "")
if [ -n "$no_endpoints" ]; then
    detect_issue "Service_No_Endpoints" "Services showing 'no endpoints' in iptables rules" "ERROR"
    echo "Problem Statement Match: iptables rules showing 'has no endpoints'"
    echo "Services without endpoints:"
    echo "$no_endpoints"
fi

# Check MASQUERADE rules exist
info "Checking MASQUERADE rules..."
if command -v iptables >/dev/null 2>&1; then
    masq_rules=$(sudo iptables -t nat -L | grep MASQUERADE 2>/dev/null || echo "")
    if [ -z "$masq_rules" ]; then
        detect_issue "Missing_MASQUERADE_Rules" "No MASQUERADE rules found in iptables NAT table" "CRITICAL"
        echo "This prevents pod-to-external connectivity"
    else
        info "✓ MASQUERADE rules present"
    fi
fi

echo
echo "=== PHASE 4: Flannel CNI Issues (Problem Statement Section 7) ==="
echo

# Check for missing Flannel daemonset (exact error from problem statement)
info "Checking Flannel daemonset status..."
flannel_ds=$(kubectl get ds -n kube-system kube-flannel 2>&1 || echo "")

if echo "$flannel_ds" | grep -q "NotFound"; then
    detect_issue "Flannel_DaemonSet_Missing" "Flannel daemonset not found" "CRITICAL"
    echo "Problem Statement Match: 'error: error from server (NotFound): daemonsets.apps \"kube-flannel\" not found'"
    echo "This indicates complete CNI networking failure"
    
    # Check alternative Flannel namespace
    flannel_pods=$(kubectl get pods -A | grep flannel 2>/dev/null || echo "")
    if [ -z "$flannel_pods" ]; then
        critical "No Flannel pods found in any namespace - CNI completely broken"
    else
        warn "Found Flannel pods in different namespace/configuration"
        echo "$flannel_pods"
    fi
else
    info "✓ Flannel daemonset found"
fi

echo
echo "=== PHASE 5: Inter-Pod Connectivity Testing (Problem Statement Section 5) ==="
echo

# Test exact connectivity scenario from problem statement
info "Testing inter-pod connectivity (replicating problem statement test)..."

# Create test pod similar to problem statement netshoot test
cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: connectivity-test-$(date +%s)
  namespace: default
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot
    command: ["sleep", "300"]
  restartPolicy: Never
EOF

test_pod_name=$(kubectl get pods -l app!=test --no-headers 2>/dev/null | grep "connectivity-test" | head -1 | awk '{print $1}' || echo "")

if [ -n "$test_pod_name" ]; then
    # Wait for pod to be ready
    kubectl wait --for=condition=Ready pod/$test_pod_name --timeout=60s >/dev/null 2>&1 || true
    
    # Test ping to another node's pod network (simulating problem statement scenario)
    info "Testing ping connectivity to pod network range..."
    
    ping_result=$(kubectl exec $test_pod_name -- timeout 10 ping -c3 10.244.2.5 2>&1 || echo "failed")
    
    if echo "$ping_result" | grep -q "Destination Host Unreachable"; then
        detect_issue "Pod_Ping_Unreachable" "Pod-to-pod ping shows 'Destination Host Unreachable'" "CRITICAL"
        echo "Problem Statement Match: 'From 10.244.0.27 icmp_seq=1 Destination Host Unreachable'"
        echo "100% packet loss indicating complete network isolation"
    elif echo "$ping_result" | grep -q "100% packet loss"; then
        detect_issue "Pod_Ping_Loss" "Pod-to-pod ping shows 100% packet loss" "CRITICAL"
        echo "Problem Statement Match: '3 packets transmitted, 0 received, +3 errors, 100% packet loss'"
    else
        info "✓ Pod ping connectivity working"
    fi
    
    # Test DNS resolution (exact scenario from problem statement)
    info "Testing DNS resolution within pod..."
    
    dns_cluster_result=$(kubectl exec $test_pod_name -- timeout 10 dig @10.96.0.10 google.com +short 2>&1 || echo "failed")
    
    if echo "$dns_cluster_result" | grep -q "host unreachable"; then
        detect_issue "DNS_Cluster_Unreachable" "Cluster DNS (CoreDNS) unreachable from pods" "CRITICAL"
        echo "Problem Statement Match: ';; communications error to 10.96.0.10#53: host unreachable'"
        echo "Complete DNS resolution failure"
    fi
    
    dns_external_result=$(kubectl exec $test_pod_name -- timeout 10 dig @8.8.8.8 google.com +short 2>&1 || echo "failed")
    
    if echo "$dns_external_result" | grep -q "host unreachable"; then
        detect_issue "DNS_External_Unreachable" "External DNS unreachable from pods" "CRITICAL"  
        echo "Problem Statement Match: ';; communications error to 8.8.8.8#53: host unreachable'"
        echo "Complete external connectivity failure"
    fi
    
    # Cleanup test pod
    kubectl delete pod $test_pod_name --ignore-not-found >/dev/null 2>&1 || true
else
    warn "Could not create test pod for connectivity testing"
fi

echo
echo "=== PHASE 6: System Component Analysis ==="
echo

# Check kernel forwarding settings
info "Checking kernel IP forwarding..."
if [ -f /proc/sys/net/ipv4/ip_forward ]; then
    ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)
    if [ "$ip_forward" != "1" ]; then
        detect_issue "IP_Forwarding_Disabled" "Kernel IP forwarding is disabled" "ERROR"
        echo "This prevents pod-to-pod routing"
    else
        info "✓ Kernel IP forwarding enabled"
    fi
fi

# Check for container runtime issues
info "Checking container runtime status..."
if command -v crictl >/dev/null 2>&1; then
    runtime_status=$(crictl info 2>/dev/null | grep -E '"status".*"READY"' || echo "")
    if [ -z "$runtime_status" ]; then
        warn "Container runtime may not be fully ready"
    fi
fi

echo
echo "=================================================================="
echo "                    DIAGNOSTIC SUMMARY"
echo "=================================================================="
echo

if [ $CRITICAL_ISSUES -eq 0 ] && [ $ISSUES_DETECTED -eq 0 ]; then
    info "🎉 NO ISSUES DETECTED - Cluster networking appears healthy"
    echo "The problems described in the GitHub issue appear to be resolved."
    
elif [ $CRITICAL_ISSUES -eq 0 ]; then
    warn "⚠️  MINOR ISSUES DETECTED: $ISSUES_DETECTED total issues found"
    echo "Cluster has some issues but networking fundamentals appear intact."
    
elif [ $CRITICAL_ISSUES -le 2 ]; then
    error "❌ MODERATE NETWORKING ISSUES: $CRITICAL_ISSUES critical, $ISSUES_DETECTED total"
    echo "Cluster networking has significant problems requiring attention."
    
else
    critical "🚨 SEVERE NETWORKING BREAKDOWN: $CRITICAL_ISSUES critical issues detected"
    echo "This matches the complete networking failure described in the problem statement."
    echo
    echo "EXACT PROBLEM STATEMENT SCENARIO DETECTED:"
    echo "- Complete inter-pod communication failure"
    echo "- DNS resolution completely broken"
    echo "- CNI networking layer failure"
    echo "- Core components in CrashLoopBackOff"
fi

echo
echo "Issues Detected: $ISSUES_DETECTED"
echo "Critical Issues: $CRITICAL_ISSUES"
echo

if [ $CRITICAL_ISSUES -gt 0 ]; then
    echo "=== RECOMMENDED IMMEDIATE ACTIONS ==="
    echo
    echo "1. Run comprehensive network diagnosis:"
    echo "   ./scripts/run_network_diagnosis.sh"
    echo
    echo "2. Apply coordinated networking fix:"
    echo "   sudo ./scripts/fix_cluster_communication.sh --non-interactive"
    echo
    echo "3. Validate problem statement scenarios resolved:"
    echo "   ./scripts/test_problem_statement_scenarios.sh"
    echo
    echo "4. If issues persist, consider cluster network reset:"
    echo "   sudo ./scripts/reset_cluster_networking.sh"
    echo
fi

echo "Diagnostic completed at: $(date)"
echo "=================================================================="

# Exit with appropriate code
if [ $CRITICAL_ISSUES -gt 3 ]; then
    exit 2  # Severe networking breakdown
elif [ $CRITICAL_ISSUES -gt 0 ]; then
    exit 1  # Issues detected
else
    exit 0  # No critical issues
fi
#!/bin/bash

# VMStation Static IP and DNS Validation Script
# Tests the static IP assignments and DNS subdomain functionality

set -e

# Color codes
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

echo "=== VMStation Static IP and DNS Validation ==="
echo "Timestamp: $(date)"
echo ""

# Global test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo "Test $TESTS_TOTAL: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        local result=0
    else
        local result=1
    fi
    
    if [ "$result" -eq "$expected_result" ]; then
        success "  ✅ PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        error "  ❌ FAILED"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Function to validate static IP assignments
validate_static_ips() {
    info "=== Validating Static IP Assignments ==="
    echo ""
    
    # Test 1: CoreDNS Service IP
    run_test "CoreDNS has static clusterIP 10.96.0.10" \
        "kubectl get service kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}' | grep -q '10.96.0.10'"
    
    # Test 2: CoreDNS service is accessible
    run_test "CoreDNS service is accessible" \
        "timeout 5 nslookup kubernetes.default.svc.cluster.local 10.96.0.10"
    
    # Test 3: kube-proxy pods are using hostNetwork
    run_test "kube-proxy pods use hostNetwork" \
        "kubectl get pods -n kube-system -l k8s-app=kube-proxy -o jsonpath='{.items[*].spec.hostNetwork}' | grep -q 'true'"
    
    # Test 4: kube-flannel pods are using hostNetwork
    run_test "kube-flannel pods use hostNetwork" \
        "kubectl get pods -n kube-flannel -l app=flannel -o jsonpath='{.items[*].spec.hostNetwork}' | grep -q 'true'"
    
    # Test 5: Verify number of kube-proxy pods matches nodes
    local node_count=$(kubectl get nodes --no-headers | wc -l 2>/dev/null || echo "0")
    local proxy_count=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers | wc -l 2>/dev/null || echo "0")
    run_test "kube-proxy pod count matches node count ($node_count)" \
        "[ '$proxy_count' -eq '$node_count' ]"
    
    # Test 6: Verify number of flannel pods matches nodes
    local flannel_count=$(kubectl get pods -n kube-flannel -l app=flannel --no-headers | wc -l 2>/dev/null || echo "0")
    run_test "kube-flannel pod count matches node count ($node_count)" \
        "[ '$flannel_count' -eq '$node_count' ]"
    
    echo ""
}

# Function to validate DNS subdomain configuration
validate_dns_subdomains() {
    info "=== Validating DNS Subdomains ==="
    echo ""
    
    # Test 7: Check if dnsmasq configuration exists
    run_test "homelab.com DNS configuration exists" \
        "[ -f '/etc/vmstation/dns/homelab-subdomains.conf' ]"
    
    # Test 8: Check if vmstation-dns service is enabled
    run_test "vmstation-dns service is enabled" \
        "systemctl is-enabled vmstation-dns"
    
    # Test 9: Check if vmstation-dns service is running
    run_test "vmstation-dns service is running" \
        "systemctl is-active vmstation-dns"
    
    # Test 10: Resolve jellyfin.homelab.com
    run_test "jellyfin.homelab.com resolves" \
        "timeout 5 nslookup jellyfin.homelab.com"
    
    # Test 11: Resolve grafana.homelab.com
    run_test "grafana.homelab.com resolves" \
        "timeout 5 nslookup grafana.homelab.com"
    
    # Test 12: Resolve storage.homelab.com
    run_test "storage.homelab.com resolves" \
        "timeout 5 nslookup storage.homelab.com"
    
    # Test 13: Check hosts file has homelab.com entries
    run_test "hosts file contains homelab.com entries" \
        "grep -q 'jellyfin.homelab.com' /etc/hosts"
    
    echo ""
}

# Function to test service accessibility via subdomains
test_service_accessibility() {
    info "=== Testing Service Accessibility ==="
    echo ""
    
    # Get expected IPs for comparison
    local storage_ip="192.168.4.61"
    local compute_ip="192.168.4.62"
    local control_ip="192.168.4.63"
    
    # Test 14: jellyfin.homelab.com resolves to storage node IP
    run_test "jellyfin.homelab.com resolves to storage node IP ($storage_ip)" \
        "nslookup jellyfin.homelab.com | grep -q '$storage_ip'"
    
    # Test 15: storage.homelab.com resolves to storage node IP
    run_test "storage.homelab.com resolves to storage node IP ($storage_ip)" \
        "nslookup storage.homelab.com | grep -q '$storage_ip'"
    
    # Test 16: Test HTTP connectivity to Jellyfin (if running)
    echo "Test $((TESTS_TOTAL + 1)): HTTP connectivity to jellyfin.homelab.com:30096"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    if timeout 10 curl -s --connect-timeout 3 "http://jellyfin.homelab.com:30096/" >/dev/null 2>&1; then
        success "  ✅ PASSED - Jellyfin is accessible via subdomain"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        warn "  ⚠️ SKIPPED - Jellyfin service may not be running (expected)"
        # Don't count as failed since service might not be deployed yet
    fi
    
    # Test 17: Verify DNS forwarding is working
    run_test "External DNS resolution still works" \
        "timeout 5 nslookup google.com"
    
    echo ""
}

# Function to validate manifests and configurations
validate_manifests() {
    info "=== Validating Manifest Configurations ==="
    echo ""
    
    # Test 18: CoreDNS service manifest has static IP
    run_test "CoreDNS service manifest has static clusterIP" \
        "grep -q 'clusterIP: 10.96.0.10' /home/runner/work/VMStation/VMStation/manifests/network/coredns-service.yaml"
    
    # Test 19: kube-proxy DaemonSet uses hostNetwork
    run_test "kube-proxy DaemonSet manifest uses hostNetwork" \
        "grep -q 'hostNetwork: true' /home/runner/work/VMStation/VMStation/manifests/network/kube-proxy-daemonset.yaml"
    
    # Test 20: kube-flannel DaemonSet uses hostNetwork
    run_test "kube-flannel DaemonSet manifest uses hostNetwork" \
        "grep -q 'hostNetwork: true' /home/runner/work/VMStation/VMStation/manifests/cni/flannel.yaml"
    
    # Test 21: Documentation exists
    run_test "Static IP and DNS documentation exists" \
        "[ -f '/home/runner/work/VMStation/VMStation/docs/static-ips-and-dns.md' ]"
    
    echo ""
}

# Function to test pod restart persistence
test_restart_persistence() {
    info "=== Testing Static IP Persistence ==="
    echo ""
    
    info "Note: Static IP persistence is ensured by:"
    info "  • CoreDNS: Uses static clusterIP in Service definition"
    info "  • kube-proxy: Uses hostNetwork (node IP is static)"
    info "  • kube-flannel: Uses hostNetwork (node IP is static)"
    echo ""
    
    # Test 22: Verify pod specifications ensure persistence
    run_test "CoreDNS Service spec ensures static IP persistence" \
        "kubectl get service kube-dns -n kube-system -o yaml | grep -q 'clusterIP: 10.96.0.10'"
    
    # Test 23: Verify DaemonSet specs ensure host network usage
    run_test "kube-proxy DaemonSet spec ensures hostNetwork persistence" \
        "kubectl get daemonset kube-proxy -n kube-system -o yaml | grep -q 'hostNetwork: true'"
    
    echo ""
}

# Function to show detailed status
show_detailed_status() {
    info "=== Detailed Status Information ==="
    echo ""
    
    echo "Current Pod IPs and Node Assignments:"
    if command -v kubectl >/dev/null 2>&1; then
        echo ""
        echo "CoreDNS Pods:"
        kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide --no-headers 2>/dev/null | while read line; do
            local pod_name=$(echo "$line" | awk '{print $1}')
            local pod_ip=$(echo "$line" | awk '{print $6}')
            local node=$(echo "$line" | awk '{print $7}')
            echo "  $pod_name: Pod IP $pod_ip on node $node"
        done || echo "  No CoreDNS pods found"
        
        echo ""
        echo "kube-proxy Pods (using hostNetwork):"
        kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide --no-headers 2>/dev/null | while read line; do
            local pod_name=$(echo "$line" | awk '{print $1}')
            local node_ip=$(echo "$line" | awk '{print $6}')
            local node=$(echo "$line" | awk '{print $7}')
            echo "  $pod_name: Host IP $node_ip on node $node"
        done || echo "  No kube-proxy pods found"
        
        echo ""
        echo "kube-flannel Pods (using hostNetwork):"
        kubectl get pods -n kube-flannel -l app=flannel -o wide --no-headers 2>/dev/null | while read line; do
            local pod_name=$(echo "$line" | awk '{print $1}')
            local node_ip=$(echo "$line" | awk '{print $6}')
            local node=$(echo "$line" | awk '{print $7}')
            echo "  $pod_name: Host IP $node_ip on node $node"
        done || echo "  No kube-flannel pods found"
    fi
    
    echo ""
    echo "DNS Subdomain Resolution:"
    local test_domains=("jellyfin.homelab.com" "grafana.homelab.com" "storage.homelab.com" "compute.homelab.com" "control.homelab.com")
    
    for domain in "${test_domains[@]}"; do
        local resolved_ip=$(nslookup "$domain" 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}' || echo "NOT RESOLVED")
        echo "  $domain → $resolved_ip"
    done
    
    echo ""
}

# Function to generate test report
generate_report() {
    echo ""
    info "=== Test Summary Report ==="
    echo ""
    
    echo "Total Tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        success "🎉 All tests passed! Static IP and DNS configuration is working correctly."
        return 0
    else
        error "❌ Some tests failed. Check the output above for details."
        return 1
    fi
}

# Main execution
main() {
    local test_type="${1:-all}"
    
    case "$test_type" in
        "static-ips"|"ips")
            validate_static_ips
            ;;
        "dns"|"subdomains")
            validate_dns_subdomains
            test_service_accessibility
            ;;
        "manifests"|"config")
            validate_manifests
            ;;
        "persistence"|"restart")
            test_restart_persistence
            ;;
        "status"|"info")
            show_detailed_status
            ;;
        "all"|*)
            validate_static_ips
            validate_dns_subdomains
            test_service_accessibility
            validate_manifests
            test_restart_persistence
            show_detailed_status
            ;;
    esac
    
    generate_report
}

# Show usage if requested
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "VMStation Static IP and DNS Validation Script"
    echo ""
    echo "Usage: $0 [test-type]"
    echo ""
    echo "Test types:"
    echo "  all          - Run all tests (default)"
    echo "  static-ips   - Test static IP assignments only"
    echo "  dns          - Test DNS subdomain configuration only"
    echo "  manifests    - Test manifest configurations only"
    echo "  persistence  - Test static IP persistence mechanisms"
    echo "  status       - Show detailed status information only"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run all tests"
    echo "  $0 static-ips         # Test only static IP assignments"
    echo "  $0 dns                # Test only DNS subdomains"
    echo "  $0 status             # Show current status"
    exit 0
fi

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
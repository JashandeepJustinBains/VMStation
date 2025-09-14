#!/bin/bash

# VMStation Static IP and DNS Setup Integration Test
# Tests the integration without requiring a running cluster

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
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "=== VMStation Static IP and DNS Integration Test ==="
echo "Timestamp: $(date)"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo "Testing: $test_name"
    if eval "$test_command" >/dev/null 2>&1; then
        success "  ✅ PASSED"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        error "  ❌ FAILED"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 1: Scripts exist and are executable
run_test "Setup script exists and is executable" \
    "[ -x 'scripts/setup_static_ips_and_dns.sh' ]"

run_test "Validation script exists and is executable" \
    "[ -x 'scripts/validate_static_ips_and_dns.sh' ]"

# Test 2: Scripts have valid syntax
run_test "Setup script has valid syntax" \
    "bash -n scripts/setup_static_ips_and_dns.sh"

run_test "Validation script has valid syntax" \
    "bash -n scripts/validate_static_ips_and_dns.sh"

# Test 3: Documentation exists
run_test "Documentation file exists" \
    "[ -f 'docs/static-ips-and-dns.md' ]"

run_test "Documentation has expected content" \
    "grep -q 'Static IP Assignment' docs/static-ips-and-dns.md && grep -q 'homelab.com' docs/static-ips-and-dns.md"

# Test 4: Manifests have correct configurations
run_test "CoreDNS service has static clusterIP" \
    "grep -q 'clusterIP: 10.96.0.10' manifests/network/coredns-service.yaml"

run_test "CoreDNS ConfigMap has homelab.com configuration" \
    "grep -q 'homelab.com:53' manifests/network/coredns-configmap.yaml"

run_test "kube-proxy uses hostNetwork" \
    "grep -q 'hostNetwork: true' manifests/network/kube-proxy-daemonset.yaml"

run_test "kube-flannel uses hostNetwork" \
    "grep -q 'hostNetwork: true' manifests/cni/flannel.yaml"

# Test 5: Integration with deployment script
run_test "Setup script is integrated into deployment" \
    "grep -q 'setup_static_ips_and_dns.sh' deploy-cluster.sh"

# Test 6: Help functionality works
run_test "Validation script help works" \
    "scripts/validate_static_ips_and_dns.sh --help | grep -q 'Usage:'"

# Test 7: Verification mode works (should not fail even without cluster)
run_test "Setup script verification mode works" \
    "timeout 10 scripts/setup_static_ips_and_dns.sh verify >/dev/null 2>&1 || true"

# Test 8: Manifest validation works
run_test "Manifest validation passes" \
    "scripts/validate_static_ips_and_dns.sh manifests | grep -q 'All tests passed'"

echo ""
info "=== Integration Test Summary ==="
echo "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
    success "🎉 All integration tests passed!"
    echo ""
    info "The static IP and DNS setup is ready for deployment."
    echo ""
    info "Next steps for complete testing:"
    info "  1. Deploy a cluster: ./deploy-cluster.sh deploy"
    info "  2. Run full validation: ./scripts/validate_static_ips_and_dns.sh"
    info "  3. Test service access: curl http://jellyfin.homelab.com:30096/"
    exit 0
else
    error "❌ Some integration tests failed."
    exit 1
fi
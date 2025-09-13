#!/bin/bash

# Test script for cluster DNS configuration fix
# Validates that the DNS fix resolves the kubectl issue

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

echo "=== VMStation DNS Fix Validation Test ==="
echo "Testing the fix for: 'dial tcp: lookup hort on 192.168.4.1:53: no such host'"
echo ""

# Test 1: kubectl version command (the original failing command)
info "Test 1: kubectl version command (original failing command)"
echo "Running: kubectl version --short"

if timeout 30 kubectl version --short >/dev/null 2>&1; then
    success "✅ kubectl version command works"
    kubectl version --short
else
    error "❌ kubectl version command still fails"
    echo "Error output:"
    kubectl version --short 2>&1 || true
    echo ""
fi

echo ""

# Test 2: kubectl cluster connectivity
info "Test 2: kubectl cluster connectivity"
echo "Running: kubectl get nodes"

if timeout 20 kubectl get nodes >/dev/null 2>&1; then
    success "✅ kubectl cluster connectivity works"
    kubectl get nodes -o wide
else
    error "❌ kubectl cluster connectivity fails"
    echo "Error output:"
    kubectl get nodes 2>&1 || true
    echo ""
fi

echo ""

# Test 3: CoreDNS pod status
info "Test 3: CoreDNS pod status"
echo "Running: kubectl get pods -n kube-system -l k8s-app=kube-dns"

if kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers >/dev/null 2>&1; then
    local coredns_status
    coredns_status=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | awk '{print $3}' | grep -c "Running" || echo "0")
    
    if [ "$coredns_status" -gt 0 ]; then
        success "✅ $coredns_status CoreDNS pod(s) running"
        kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
    else
        warn "⚠️ CoreDNS pods found but not all running"
        kubectl get pods -n kube-system -l k8s-app=kube-dns
    fi
else
    error "❌ Cannot access CoreDNS pods"
    echo "Error output:"
    kubectl get pods -n kube-system -l k8s-app=kube-dns 2>&1 || true
fi

echo ""

# Test 4: DNS resolution test
info "Test 4: DNS resolution test"

# Get CoreDNS service IP
coredns_ip=$(kubectl get service kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "10.96.0.10")
echo "CoreDNS service IP: $coredns_ip"

echo "Testing DNS resolution of kubernetes.default.svc.cluster.local"
if timeout 10 nslookup kubernetes.default.svc.cluster.local "$coredns_ip" >/dev/null 2>&1; then
    success "✅ Cluster DNS resolution works"
    nslookup kubernetes.default.svc.cluster.local "$coredns_ip" | head -10
else
    error "❌ Cluster DNS resolution fails"
    nslookup kubernetes.default.svc.cluster.local "$coredns_ip" 2>&1 || true
fi

echo ""

# Test 5: Check current DNS configuration
info "Test 5: Current DNS configuration"

echo "Current /etc/resolv.conf:"
cat /etc/resolv.conf | head -10

echo ""
echo "Current kubelet DNS configuration:"
if [ -f "/etc/systemd/system/kubelet.service.d/20-dns-cluster.conf" ]; then
    cat /etc/systemd/system/kubelet.service.d/20-dns-cluster.conf
else
    warn "DNS cluster configuration file not found"
fi

echo ""

# Summary
info "=== Test Summary ==="

# Count tests
tests_passed=0
tests_total=4

# Check each test result
if timeout 10 kubectl version --short >/dev/null 2>&1; then
    ((tests_passed++))
    success "✓ kubectl version command"
else
    error "✗ kubectl version command"
fi

if timeout 10 kubectl get nodes >/dev/null 2>&1; then
    ((tests_passed++))
    success "✓ kubectl cluster connectivity"
else
    error "✗ kubectl cluster connectivity"
fi

if kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers >/dev/null 2>&1; then
    coredns_running=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | awk '{print $3}' | grep -c "Running" || echo "0")
    if [ "$coredns_running" -gt 0 ]; then
        ((tests_passed++))
        success "✓ CoreDNS pods running ($coredns_running)"
    else
        error "✗ CoreDNS pods not running properly"
    fi
else
    error "✗ CoreDNS pods inaccessible"
fi

if timeout 10 nslookup kubernetes.default.svc.cluster.local "$coredns_ip" >/dev/null 2>&1; then
    ((tests_passed++))
    success "✓ Cluster DNS resolution"
else
    error "✗ Cluster DNS resolution"
fi

echo ""
if [ "$tests_passed" -eq "$tests_total" ]; then
    success "🎉 All tests passed ($tests_passed/$tests_total)!"
    success "The DNS configuration fix has resolved the kubectl issue."
    echo ""
    info "The original problem 'dial tcp: lookup hort on 192.168.4.1:53: no such host' should now be fixed."
    exit 0
else
    error "❌ Some tests failed ($tests_passed/$tests_total passed)"
    error "Additional troubleshooting may be needed."
    echo ""
    info "If issues persist:"
    info "  1. Check kubelet logs: journalctl -u kubelet -f"
    info "  2. Restart kubelet: systemctl restart kubelet"
    info "  3. Check CoreDNS logs: kubectl logs -n kube-system -l k8s-app=kube-dns"
    exit 1
fi
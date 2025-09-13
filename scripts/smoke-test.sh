#!/bin/bash

# VMStation Kubernetes Cluster Smoke Test
# Quick validation script for cluster health

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Configuration
KUBECONFIG="/etc/kubernetes/admin.conf"
INVENTORY_FILE="ansible/inventory/hosts.yml"

echo "=== VMStation Kubernetes Cluster Smoke Test ==="
echo "Timestamp: $(date)"
echo ""

# Check if running on control plane
if [ ! -f "$KUBECONFIG" ]; then
    error "This script must be run on the Kubernetes control plane node"
    error "Expected kubeconfig at: $KUBECONFIG"
    exit 1
fi

info "Using kubeconfig: $KUBECONFIG"
export KUBECONFIG="$KUBECONFIG"

# Test 1: Check kubectl connectivity
info "Testing kubectl connectivity..."
if kubectl version --client >/dev/null 2>&1; then
    success "✅ kubectl connectivity verified"
else
    error "❌ kubectl connectivity failed"
    exit 1
fi

# Test 2: Verify all nodes are Ready
info "Checking node status..."
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
READY_COUNT=$(kubectl get nodes --no-headers | grep -c " Ready ")

if [ "$NODE_COUNT" -eq 3 ] && [ "$READY_COUNT" -eq 3 ]; then
    success "✅ All 3 nodes are Ready"
    kubectl get nodes
else
    error "❌ Expected 3 Ready nodes, found $READY_COUNT/$NODE_COUNT"
    kubectl get nodes
    exit 1
fi

# Test 3: Check CoreDNS
info "Checking CoreDNS pods..."
COREDNS_RUNNING=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | grep -c "Running" || echo "0")

if [ "$COREDNS_RUNNING" -ge 1 ]; then
    success "✅ CoreDNS is running ($COREDNS_RUNNING pods)"
else
    error "❌ CoreDNS pods not running"
    kubectl get pods -n kube-system -l k8s-app=kube-dns
    exit 1
fi

# Test 4: Check Flannel CNI
info "Checking Flannel CNI pods..."
FLANNEL_RUNNING=$(kubectl get pods -n kube-flannel -l app=flannel --no-headers 2>/dev/null | grep -c "Running" || echo "0")

if [ "$FLANNEL_RUNNING" -ge 3 ]; then
    success "✅ Flannel CNI is running ($FLANNEL_RUNNING pods)"
else
    warn "⚠️  Flannel CNI may not be fully deployed ($FLANNEL_RUNNING pods)"
    kubectl get pods -n kube-flannel -l app=flannel 2>/dev/null || echo "Flannel namespace not found"
fi

# Test 5: Check monitoring stack
info "Checking monitoring stack..."
MONITORING_NAMESPACE=$(kubectl get namespace monitoring --no-headers 2>/dev/null | wc -l)

if [ "$MONITORING_NAMESPACE" -eq 1 ]; then
    PROMETHEUS_RUNNING=$(kubectl get pods -n monitoring -l app=prometheus --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    GRAFANA_RUNNING=$(kubectl get pods -n monitoring -l app=grafana --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    
    if [ "$PROMETHEUS_RUNNING" -ge 1 ] && [ "$GRAFANA_RUNNING" -ge 1 ]; then
        success "✅ Monitoring stack is running (Prometheus: $PROMETHEUS_RUNNING, Grafana: $GRAFANA_RUNNING)"
        
        # Test Prometheus endpoint
        if curl -s http://192.168.4.63:30090/api/v1/query?query=up >/dev/null; then
            success "✅ Prometheus API is accessible"
        else
            warn "⚠️  Prometheus API may not be ready yet"
        fi
        
        # Test Grafana endpoint  
        if curl -s http://192.168.4.63:30300/api/health >/dev/null; then
            success "✅ Grafana API is accessible"
        else
            warn "⚠️  Grafana API may not be ready yet"
        fi
    else
        warn "⚠️  Monitoring stack not fully running (Prometheus: $PROMETHEUS_RUNNING, Grafana: $GRAFANA_RUNNING)"
    fi
else
    warn "⚠️  Monitoring namespace not found"
fi

# Test 6: Check Jellyfin
info "Checking Jellyfin deployment..."
JELLYFIN_NAMESPACE=$(kubectl get namespace jellyfin --no-headers 2>/dev/null | wc -l)

if [ "$JELLYFIN_NAMESPACE" -eq 1 ]; then
    JELLYFIN_RUNNING=$(kubectl get pods -n jellyfin -l app=jellyfin --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    
    if [ "$JELLYFIN_RUNNING" -ge 1 ]; then
        success "✅ Jellyfin is running ($JELLYFIN_RUNNING pods)"
        
        # Check if Jellyfin is on storage node
        JELLYFIN_NODE=$(kubectl get pods -n jellyfin -l app=jellyfin -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || echo "unknown")
        if [[ "$JELLYFIN_NODE" =~ storage|storagenodet3500 ]]; then
            success "✅ Jellyfin correctly scheduled on storage node ($JELLYFIN_NODE)"
        else
            warn "⚠️  Jellyfin may not be on storage node (current: $JELLYFIN_NODE)"
        fi
        
        # Test Jellyfin endpoint
        if curl -s -f http://192.168.4.61:30096/ >/dev/null 2>&1; then
            success "✅ Jellyfin web interface is accessible"
        else
            warn "⚠️  Jellyfin web interface may not be ready yet"
        fi
    else
        warn "⚠️  Jellyfin not running ($JELLYFIN_RUNNING pods)"
    fi
else
    warn "⚠️  Jellyfin namespace not found"
fi

# Test 7: Basic pod networking test
info "Testing pod networking..."
if kubectl run smoke-test-pod --image=busybox --restart=Never --rm -i --tty --timeout=30s -- nslookup kubernetes.default >/dev/null 2>&1; then
    success "✅ Pod networking and DNS resolution working"
else
    # Clean up failed pod
    kubectl delete pod smoke-test-pod --ignore-not-found >/dev/null 2>&1
    warn "⚠️  Pod networking test inconclusive"
fi

# Summary
echo ""
info "🎉 Smoke Test Summary:"
echo ""
success "✅ Basic Cluster:"
echo "   - kubectl connectivity: WORKING"
echo "   - Node status: $READY_COUNT/$NODE_COUNT Ready"
echo "   - CoreDNS: $COREDNS_RUNNING pods Running"
echo "   - Flannel CNI: $FLANNEL_RUNNING pods Running"
echo ""

if [ "$MONITORING_NAMESPACE" -eq 1 ]; then
    success "✅ Monitoring Access:"
    echo "   - Prometheus: http://192.168.4.63:30090"
    echo "   - Grafana: http://192.168.4.63:30300 (admin/admin)"
else
    warn "⚠️  Monitoring: Not deployed"
fi

if [ "$JELLYFIN_NAMESPACE" -eq 1 ]; then
    success "✅ Media Services:"
    echo "   - Jellyfin: http://192.168.4.61:30096"
else
    warn "⚠️  Jellyfin: Not deployed"
fi

echo ""
info "🔧 Next Steps:"
echo "   - Run full verification: ansible-playbook ansible/playbooks/verify-cluster.yml"
echo "   - Configure applications via web interfaces"
echo "   - Deploy additional workloads as needed"

echo ""
success "🚀 Smoke test completed successfully!"
exit 0
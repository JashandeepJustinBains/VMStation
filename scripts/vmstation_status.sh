#!/bin/bash

# VMStation Deployment Status and Troubleshooting Summary
# Provides a comprehensive overview of cluster status and recommended actions

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
note() { echo -e "${BLUE}[NOTE]${NC} $1"; }

echo "=== VMStation Deployment Status Summary ==="
echo "Timestamp: $(date)"
echo

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl not found - cannot check cluster status"
    echo "This summary requires access to a running Kubernetes cluster."
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    echo "Make sure you have access to the cluster and kubeconfig is properly configured."
    exit 1
fi

info "Cluster is accessible - generating status report..."
echo

# 1. Node Status
echo "=== 1. Node Status ==="
kubectl get nodes -o wide
echo

# 2. Critical System Pods
echo "=== 2. Critical System Pod Status ==="
echo "CoreDNS:"
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
echo
echo "Flannel:"
kubectl get pods -n kube-flannel -o wide
echo
echo "kube-proxy:"
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide
echo

# 3. Problematic Pods
echo "=== 3. Problematic Pods ==="
PROBLEM_PODS=$(kubectl get pods --all-namespaces | grep -E "(CrashLoopBackOff|Error|Unknown|Pending)" | grep -v "Completed" || true)
if [ -n "$PROBLEM_PODS" ]; then
    error "Found problematic pods:"
    echo "$PROBLEM_PODS"
    echo
    HAS_PROBLEMS=true
else
    info "✅ No problematic pods found"
    echo
    HAS_PROBLEMS=false
fi

# 4. Stuck ContainerCreating Pods
echo "=== 4. Stuck ContainerCreating Pods ==="
STUCK_PODS=$(kubectl get pods --all-namespaces | grep "ContainerCreating" || true)
if [ -n "$STUCK_PODS" ]; then
    warn "Found stuck ContainerCreating pods:"
    echo "$STUCK_PODS"
    echo
    HAS_STUCK_PODS=true
else
    info "✅ No stuck ContainerCreating pods"
    echo
    HAS_STUCK_PODS=false
fi

# 5. Application Status
echo "=== 5. Application Status ==="

# Monitoring
echo "Monitoring Stack:"
kubectl get pods -n monitoring -o wide 2>/dev/null || echo "  No monitoring namespace found"
echo

# Jellyfin
echo "Jellyfin:"
kubectl get pods -n jellyfin -o wide 2>/dev/null || echo "  No jellyfin namespace found"
echo

# Dashboard
echo "Kubernetes Dashboard:"
kubectl get pods -n kubernetes-dashboard -o wide 2>/dev/null || echo "  No kubernetes-dashboard namespace found"
echo

# 6. Network Status
echo "=== 6. Network Status ==="

# Check if CoreDNS is on correct node
COREDNS_NODE=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null || echo "unknown")
MASTER_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "unknown")

if [ "$COREDNS_NODE" = "$MASTER_NODE" ]; then
    info "✅ CoreDNS is correctly scheduled on control-plane node: $COREDNS_NODE"
else
    warn "⚠️  CoreDNS is not on control-plane node. Current: $COREDNS_NODE, Expected: $MASTER_NODE"
fi

# Check homelab node issues
HOMELAB_PROBLEMS=$(kubectl get pods --all-namespaces -o wide | grep "homelab" | grep -E "(CrashLoopBackOff|Error|Unknown)" || true)
if [ -n "$HOMELAB_PROBLEMS" ]; then
    warn "⚠️  Homelab node has networking issues:"
    echo "$HOMELAB_PROBLEMS"
else
    info "✅ Homelab node appears stable"
fi
echo

# 7. Recommendations
echo "=== 7. Recommendations ==="

if [ "$HAS_PROBLEMS" = "true" ] || [ "$HAS_STUCK_PODS" = "true" ]; then
    error "Action Required: Cluster has networking or deployment issues"
    echo
    echo "Recommended fix steps:"
    echo "1. Run homelab node networking fix:"
    echo "   ./scripts/fix_homelab_node_issues.sh"
    echo
    echo "2. Check CoreDNS status:"
    echo "   ./scripts/check_coredns_status.sh"
    echo
    echo "3. If issues persist, run comprehensive CoreDNS fix:"
    echo "   ./scripts/fix_coredns_unknown_status.sh"
    echo
    echo "4. For fresh deployment after fixes:"
    echo "   ./deploy.sh apps"
    echo
    echo "5. Monitor progress:"
    echo "   watch kubectl get pods --all-namespaces"
elif [ "$COREDNS_NODE" != "$MASTER_NODE" ]; then
    warn "Optimization Needed: CoreDNS scheduling can be improved"
    echo
    echo "Recommended action:"
    echo "1. Run CoreDNS scheduling fix:"
    echo "   ./scripts/fix_homelab_node_issues.sh"
else
    info "✅ Cluster appears healthy"
    echo
    echo "Optional actions:"
    echo "1. Deploy applications if not already deployed:"
    echo "   ./deploy.sh apps"
    echo
    echo "2. Check specific application status:"
    echo "   kubectl get pods -n monitoring"
    echo "   kubectl get pods -n jellyfin"
    echo
    echo "3. Access services:"
    echo "   - Grafana: http://192.168.4.63:30300"
    echo "   - Prometheus: http://192.168.4.63:30090"
    echo "   - Jellyfin: http://192.168.4.61:30096"
fi

echo
note "For detailed troubleshooting, see: docs/HOMELAB_NODE_FIXES.md"
echo
echo "=== Status Summary Complete ==="
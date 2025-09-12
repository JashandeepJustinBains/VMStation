#!/bin/bash

# Quick CoreDNS Status Checker
# Quickly identify if CoreDNS has the "Unknown" status issue after flannel regeneration

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if we have kubectl access
if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    exit 1
fi

echo "=== Quick CoreDNS Status Check ==="

# Check CoreDNS pod status
COREDNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].metadata.name}')

if [ -z "$COREDNS_PODS" ]; then
    error "No CoreDNS pods found!"
    exit 1
fi

ISSUES_FOUND=false

echo "CoreDNS pods status:"
for pod in $COREDNS_PODS; do
    POD_STATUS=$(kubectl get pod -n kube-system "$pod" -o jsonpath='{.status.phase}')
    POD_IP=$(kubectl get pod -n kube-system "$pod" -o jsonpath='{.status.podIP}')
    NODE_NAME=$(kubectl get pod -n kube-system "$pod" -o jsonpath='{.spec.nodeName}')
    
    echo "  $pod: Status=$POD_STATUS, IP=${POD_IP:-<none>}, Node=${NODE_NAME:-<none>}"
    
    if [ "$POD_STATUS" = "Unknown" ] || [ -z "$POD_IP" ] || [ "$POD_IP" = "null" ]; then
        warn "    ↳ This pod has issues!"
        ISSUES_FOUND=true
    fi
done

echo
echo "Flannel DaemonSet status:"
kubectl get daemonset -n kube-flannel -o wide

echo
echo "Problematic pods across cluster:"
PROBLEM_PODS=$(kubectl get pods --all-namespaces | grep -E "(ContainerCreating|Pending|Unknown|Error|CrashLoopBackOff)" | grep -v "NAME" || true)

if [ -n "$PROBLEM_PODS" ]; then
    echo "$PROBLEM_PODS"
    ISSUES_FOUND=true
else
    echo "  No problematic pods found"
fi

echo

if [ "$ISSUES_FOUND" = "true" ]; then
    error "CoreDNS or related networking issues detected!"
    echo
    echo "Recommended action:"
    echo "  ./scripts/fix_coredns_unknown_status.sh"
    echo
    echo "Or integrate into deployment:"
    echo "  ./deploy.sh full && ./scripts/fix_coredns_unknown_status.sh"
    exit 1
else
    info "CoreDNS appears to be working correctly"
    exit 0
fi
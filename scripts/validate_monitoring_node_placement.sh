#!/bin/bash

# VMStation Monitoring Node Validation Script
# Validates that monitoring components are properly deployed on the masternode

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

echo -e "${BOLD}=== VMStation Monitoring Deployment Validation ===${NC}"
echo "Checking if monitoring components are properly deployed on masternode"
echo ""

# Expected node IPs
MASTERNODE_IP="192.168.4.63"
HOMELAB_IP="192.168.4.62"
STORAGE_IP="192.168.4.61"

# Check kubectl connectivity
if ! command -v kubectl &> /dev/null; then
    error "kubectl not found. Please ensure Kubernetes is installed."
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    error "Cannot connect to Kubernetes cluster. Please check kubeconfig."
    exit 1
fi

info "Connected to Kubernetes cluster successfully"

# Check if monitoring namespace exists
if ! kubectl get namespace monitoring &> /dev/null; then
    error "Monitoring namespace not found. Has the monitoring stack been deployed?"
    echo ""
    echo "To deploy monitoring:"
    echo "  ./ansible/deploy.sh"
    echo "  # OR"  
    echo "  ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml"
    exit 1
fi

info "✓ Monitoring namespace exists"

# Check node labels
echo ""
info "Checking node labels..."

MASTERNODE_NAME=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null | grep "$MASTERNODE_IP" | cut -f1 || true)
HOMELAB_NAME=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null | grep "$HOMELAB_IP" | cut -f1 || true)

if [[ -z "$MASTERNODE_NAME" ]]; then
    error "Could not find masternode with IP $MASTERNODE_IP in cluster"
    exit 1
fi

debug "Found masternode: $MASTERNODE_NAME ($MASTERNODE_IP)"
if [[ -n "$HOMELAB_NAME" ]]; then
    debug "Found homelab node: $HOMELAB_NAME ($HOMELAB_IP)"
fi

# Check masternode has monitoring label
if kubectl get node "$MASTERNODE_NAME" --show-labels | grep -q "node-role.vmstation.io/monitoring=true"; then
    info "✓ Masternode has monitoring label"
else
    warn "✗ Masternode missing monitoring label"
    echo "  Fix: kubectl label node $MASTERNODE_NAME node-role.vmstation.io/monitoring=true"
fi

# Check homelab node doesn't have monitoring label
if [[ -n "$HOMELAB_NAME" ]]; then
    if kubectl get node "$HOMELAB_NAME" --show-labels | grep -q "node-role.vmstation.io/monitoring=true"; then
        warn "✗ Homelab node incorrectly has monitoring label"
        echo "  Fix: kubectl label node $HOMELAB_NAME node-role.vmstation.io/monitoring-"
    else
        info "✓ Homelab node does not have monitoring label"
    fi
fi

# Check pod placement
echo ""
info "Checking monitoring pod placement..."

# Get all monitoring pods and their nodes
MONITORING_PODS=$(kubectl get pods -n monitoring -o wide --no-headers 2>/dev/null || true)

if [[ -z "$MONITORING_PODS" ]]; then
    warn "No monitoring pods found. Deployment may be in progress or failed."
    echo ""
    echo "Check deployment status:"
    echo "  kubectl get pods -n monitoring"
    echo "  kubectl get events -n monitoring --sort-by='.lastTimestamp'"
    exit 1
fi

echo ""
debug "Current monitoring pods:"
echo "$MONITORING_PODS"
echo ""

# Count pods on each node
MASTERNODE_PODS=$(echo "$MONITORING_PODS" | grep "$MASTERNODE_IP" | wc -l || echo "0")
HOMELAB_PODS=$(echo "$MONITORING_PODS" | grep "$HOMELAB_IP" | wc -l || echo "0")
STORAGE_PODS=$(echo "$MONITORING_PODS" | grep "$STORAGE_IP" | wc -l || echo "0")

# Analyze placement
TOTAL_PODS=$(echo "$MONITORING_PODS" | wc -l)

info "Pod placement summary:"
echo "  Total monitoring pods: $TOTAL_PODS"
echo "  Pods on masternode ($MASTERNODE_IP): $MASTERNODE_PODS"
if [[ -n "$HOMELAB_NAME" ]]; then
    echo "  Pods on homelab node ($HOMELAB_IP): $HOMELAB_PODS"
fi
echo "  Pods on storage node ($STORAGE_IP): $STORAGE_PODS"

# Validation results
echo ""
ISSUES_FOUND=0

if [[ $MASTERNODE_PODS -eq 0 ]]; then
    error "✗ No monitoring pods found on masternode!"
    echo "  This indicates a serious scheduling issue."
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    info "✓ Monitoring pods found on masternode ($MASTERNODE_PODS pods)"
fi

if [[ $HOMELAB_PODS -gt 0 ]]; then
    warn "✗ Found $HOMELAB_PODS monitoring pods on homelab node"
    echo "  Homelab node should be for compute workloads only."
    echo "  Pods on homelab node:"
    echo "$MONITORING_PODS" | grep "$HOMELAB_IP" | while read line; do
        echo "    $line"
    done
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    info "✓ No monitoring pods on homelab node (correct)"
fi

# Check service accessibility
echo ""
info "Checking monitoring service accessibility..."

SERVICES=$(kubectl get services -n monitoring --no-headers 2>/dev/null || true)
if [[ -n "$SERVICES" ]]; then
    debug "Available monitoring services:"
    echo "$SERVICES"
    
    # Show access URLs
    echo ""
    info "Access URLs (from masternode $MASTERNODE_IP):"
    
    if kubectl get service -n monitoring | grep -q "grafana"; then
        GRAFANA_PORT=$(kubectl get service -n monitoring -o jsonpath='{.items[?(@.metadata.name=="kube-prometheus-stack-grafana")].spec.ports[0].nodePort}' 2>/dev/null || echo "30300")
        echo "  📊 Grafana: http://$MASTERNODE_IP:$GRAFANA_PORT"
    fi
    
    if kubectl get service -n monitoring | grep -q "prometheus"; then
        PROMETHEUS_PORT=$(kubectl get service -n monitoring -o jsonpath='{.items[?(@.metadata.name=="kube-prometheus-stack-prometheus")].spec.ports[0].nodePort}' 2>/dev/null || echo "30090")
        echo "  📈 Prometheus: http://$MASTERNODE_IP:$PROMETHEUS_PORT"
    fi
    
    if kubectl get service -n monitoring | grep -q "alertmanager"; then
        ALERTMANAGER_PORT=$(kubectl get service -n monitoring -o jsonpath='{.items[?(@.metadata.name=="kube-prometheus-stack-alertmanager")].spec.ports[0].nodePort}' 2>/dev/null || echo "30903")
        echo "  🚨 AlertManager: http://$MASTERNODE_IP:$ALERTMANAGER_PORT"
    fi
    
    if kubectl get service -n monitoring | grep -q "loki"; then
        LOKI_PORT=$(kubectl get service -n monitoring -o jsonpath='{.items[?(@.metadata.name=="loki-stack")].spec.ports[0].nodePort}' 2>/dev/null || echo "31100")
        echo "  📝 Loki: http://$MASTERNODE_IP:$LOKI_PORT"
    fi
else
    warn "No monitoring services found"
fi

# Final summary
echo ""
echo -e "${BOLD}=== Validation Summary ===${NC}"

if [[ $ISSUES_FOUND -eq 0 ]]; then
    info "🎉 All monitoring components are correctly deployed on masternode!"
    info "✓ Monitoring deployment is optimal for the VMStation architecture"
else
    error "❌ Found $ISSUES_FOUND issue(s) with monitoring deployment"
    echo ""
    echo "To fix scheduling issues:"
    echo "1. Run node labeling setup:"
    echo "   ./scripts/setup_monitoring_node_labels.sh"
    echo ""
    echo "2. Force pod rescheduling:"
    echo "   kubectl delete pods -n monitoring --all"
    echo ""
    echo "3. Wait for pods to reschedule:"
    echo "   kubectl get pods -n monitoring -w"
    echo ""
    echo "4. Re-run this validation:"
    echo "   ./scripts/validate_monitoring_node_placement.sh"
fi
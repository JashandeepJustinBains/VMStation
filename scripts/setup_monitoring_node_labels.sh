#!/bin/bash

# Setup proper node labels for VMStation monitoring deployment
# Ensures monitoring components are scheduled only on the masternode (192.168.4.63)

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

echo -e "${BOLD}=== VMStation Monitoring Node Label Setup ===${NC}"
echo "Setting up node labels to ensure monitoring is deployed only on masternode"
echo ""

# Verify kubectl is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl command not found. Please ensure Kubernetes is properly configured."
    exit 1
fi

# Test kubectl connectivity
if ! kubectl get nodes &> /dev/null; then
    error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

info "Connected to Kubernetes cluster successfully"

# Define the expected monitoring node IP (masternode)
MONITORING_NODE_IP="192.168.4.63"
HOMELAB_NODE_IP="192.168.4.62"
STORAGE_NODE_IP="192.168.4.61"

echo ""
info "Current cluster nodes:"
kubectl get nodes -o wide

echo ""
debug "Looking for monitoring node with IP: $MONITORING_NODE_IP"

# Get the node name for the monitoring node (masternode)
# Use range-based approach instead of nested filters for better compatibility
MONITORING_NODE_NAME=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' | grep "$MONITORING_NODE_IP" | cut -f1)

if [[ -z "$MONITORING_NODE_NAME" ]]; then
    error "Could not find node with IP $MONITORING_NODE_IP in the cluster"
    error "Available nodes:"
    kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'
    exit 1
fi

info "Found monitoring node: $MONITORING_NODE_NAME (IP: $MONITORING_NODE_IP)"

# Label the monitoring node
info "Labeling monitoring node for monitoring workloads..."
kubectl label node "$MONITORING_NODE_NAME" node-role.vmstation.io/monitoring=true --overwrite

info "✓ Monitoring node labeled successfully"

# Remove monitoring labels from other nodes
echo ""
info "Removing monitoring labels from compute and storage nodes..."

# Get homelab node name using range-based approach
HOMELAB_NODE_NAME=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null | grep "$HOMELAB_NODE_IP" | cut -f1 || true)
if [[ -n "$HOMELAB_NODE_NAME" ]]; then
    debug "Found homelab node: $HOMELAB_NODE_NAME (IP: $HOMELAB_NODE_IP)"
    if kubectl get node "$HOMELAB_NODE_NAME" --show-labels | grep -q "node-role.vmstation.io/monitoring=true"; then
        warn "Removing monitoring label from homelab node: $HOMELAB_NODE_NAME"
        kubectl label node "$HOMELAB_NODE_NAME" node-role.vmstation.io/monitoring- 2>/dev/null || true
    else
        info "✓ Homelab node does not have monitoring label"
    fi
else
    debug "Homelab node not found in cluster (this is normal if it's not joined)"
fi

# Get storage node name using range-based approach
STORAGE_NODE_NAME=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null | grep "$STORAGE_NODE_IP" | cut -f1 || true)
if [[ -n "$STORAGE_NODE_NAME" ]]; then
    debug "Found storage node: $STORAGE_NODE_NAME (IP: $STORAGE_NODE_IP)"
    if kubectl get node "$STORAGE_NODE_NAME" --show-labels | grep -q "node-role.vmstation.io/monitoring=true"; then
        warn "Removing monitoring label from storage node: $STORAGE_NODE_NAME"
        kubectl label node "$STORAGE_NODE_NAME" node-role.vmstation.io/monitoring- 2>/dev/null || true
    else
        info "✓ Storage node does not have monitoring label"
    fi
else
    debug "Storage node not found in cluster (this is normal if it's not joined)"
fi

# Remove labels from any other nodes that shouldn't have monitoring labels
echo ""
info "Checking for any other nodes with monitoring labels..."
OTHER_MONITORING_NODES=$(kubectl get nodes -l node-role.vmstation.io/monitoring=true -o jsonpath='{.items[?(@.metadata.name!="'$MONITORING_NODE_NAME'")].metadata.name}' 2>/dev/null || true)

if [[ -n "$OTHER_MONITORING_NODES" ]]; then
    warn "Found other nodes with monitoring labels that will be removed:"
    for node in $OTHER_MONITORING_NODES; do
        warn "  - Removing monitoring label from: $node"
        kubectl label node "$node" node-role.vmstation.io/monitoring- 2>/dev/null || true
    done
else
    info "✓ No other nodes have monitoring labels"
fi

echo ""
info "Final node labeling status:"
echo "Nodes with monitoring labels:"
kubectl get nodes -l node-role.vmstation.io/monitoring=true --show-labels 2>/dev/null || echo "  (none found)"

echo ""
info "All nodes in cluster:"
kubectl get nodes --show-labels | grep -E "(NAME|node-role\.vmstation\.io/monitoring)" || kubectl get nodes -o wide

echo ""
info "✓ Node labeling setup completed successfully!"
info "Monitoring components will now be scheduled only on: $MONITORING_NODE_NAME (IP: $MONITORING_NODE_IP)"
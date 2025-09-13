#!/bin/bash

# Validation script for the enhanced CNI bridge conflict fix
# This script helps test the fix in a live environment

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

echo "=== CNI Bridge Conflict Fix Validation ==="
echo "Timestamp: $(date)"
echo "This script validates the environment and tests SSH connectivity before running the fix"
echo

# Check 1: Root privileges
info "Step 1: Checking privileges"
if [ "$EUID" -ne 0 ]; then
    error "This validation script should be run as root (use sudo)"
    echo "Usage: sudo $0"
    exit 1
else
    success "✓ Running as root"
fi

# Check 2: Kubernetes access
info "Step 2: Checking Kubernetes cluster access"
if kubectl cluster-info >/dev/null 2>&1; then
    success "✓ Kubernetes cluster is accessible"
else
    error "✗ Cannot access Kubernetes cluster"
    exit 1
fi

# Check 3: Check if storagenodet3500 node exists
info "Step 3: Checking target worker node"
if kubectl get node storagenodet3500 >/dev/null 2>&1; then
    NODE_STATUS=$(kubectl get node storagenodet3500 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$NODE_STATUS" = "True" ]; then
        success "✓ storagenodet3500 node is Ready"
    else
        warn "⚠ storagenodet3500 node status: $NODE_STATUS"
    fi
else
    error "✗ storagenodet3500 node not found in cluster"
    exit 1
fi

# Check 4: SSH connectivity to worker node
info "Step 4: Testing SSH connectivity to storagenodet3500"
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"
WORKER_IP="192.168.4.61"
SSH_USER="root"

if ssh "$SSH_OPTS" "${SSH_USER}@${WORKER_IP}" "echo 'SSH connection successful'" >/dev/null 2>&1; then
    success "✓ SSH connectivity to ${SSH_USER}@${WORKER_IP} works"
else
    error "✗ Cannot establish SSH connection to ${SSH_USER}@${WORKER_IP}"
    echo "Please ensure:"
    echo "  1. SSH key authentication is set up"
    echo "  2. The worker node is accessible on 192.168.4.61"
    echo "  3. The root user allows SSH access"
    exit 1
fi

# Check 5: Current CNI bridge status on worker node
info "Step 5: Checking current CNI bridge status on worker node"
CNI_BRIDGE_STATUS=$(ssh "$SSH_OPTS" "${SSH_USER}@${WORKER_IP}" "ip addr show cni0 2>/dev/null | grep 'inet ' | awk '{print \$2}' || echo 'No cni0 bridge'")
echo "Current cni0 bridge on storagenodet3500: $CNI_BRIDGE_STATUS"

if echo "$CNI_BRIDGE_STATUS" | grep -q "10.244."; then
    if echo "$CNI_BRIDGE_STATUS" | grep -q "10.244.2.1"; then
        success "✓ cni0 bridge has correct subnet (10.244.2.x)"
    else
        warn "⚠ cni0 bridge has unexpected Flannel subnet: $CNI_BRIDGE_STATUS"
        echo "This may be the source of the conflict"
    fi
else
    info "No CNI bridge found or non-Flannel IP detected"
fi

# Check 6: Current Jellyfin pod status
info "Step 6: Checking current Jellyfin pod status"
if kubectl get namespace jellyfin >/dev/null 2>&1; then
    if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
        POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}')
        POD_NODE=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.nodeName}')
        echo "Jellyfin pod status: $POD_STATUS (scheduled on: $POD_NODE)"
        
        if [ "$POD_STATUS" = "Pending" ]; then
            warn "⚠ Jellyfin pod is Pending - checking for CNI errors"
            RECENT_ERRORS=$(kubectl get events -n jellyfin --sort-by='.lastTimestamp' | grep -E "(failed to set bridge addr|cni0.*IP.*different)" | tail -1 || echo "")
            if [ -n "$RECENT_ERRORS" ]; then
                error "✗ CNI bridge conflict detected:"
                echo "$RECENT_ERRORS"
                echo
                warn "This confirms the issue exists and the fix should be applied"
            else
                info "No recent CNI bridge errors found"
            fi
        elif [ "$POD_STATUS" = "Running" ]; then
            success "✓ Jellyfin pod is already Running - no fix needed"
            exit 0
        fi
    else
        info "No Jellyfin pod found"
    fi
else
    info "Jellyfin namespace not found"
fi

# Check 7: Flannel status
info "Step 7: Checking Flannel pod status on storagenodet3500"
FLANNEL_POD=$(kubectl get pods -n kube-flannel -o wide 2>/dev/null | grep "storagenodet3500" | awk '{print $1 " " $3}' | head -1)
if [ -n "$FLANNEL_POD" ]; then
    echo "Flannel pod on storagenodet3500: $FLANNEL_POD"
else
    warn "⚠ No Flannel pod found on storagenodet3500"
fi

echo
echo "=== Validation Summary ==="
success "✓ All prerequisites met for running the CNI bridge fix"
echo
info "To apply the fix, run:"
echo "  sudo ./fix_jellyfin_cni_bridge_conflict.sh"
echo
info "The enhanced fix will:"
echo "  1. Detect the CNI bridge conflict"
echo "  2. SSH to storagenodet3500 to directly reset the cni0 bridge"
echo "  3. Clear CNI state on the worker node"
echo "  4. Allow Jellyfin pod creation to succeed"
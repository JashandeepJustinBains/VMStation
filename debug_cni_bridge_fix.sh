#!/bin/bash

# Debug script for CNI Bridge Fix Issues
# This script helps identify why the fix_jellyfin_cni_bridge_conflict.sh might still fail

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

echo "=== CNI Bridge Fix Debug Helper ==="
echo "Timestamp: $(date)"
echo
echo "This script diagnoses common issues that prevent the CNI bridge fix from working"
echo

# Check 1: SSH connectivity to worker node
info "Step 1: Testing SSH connectivity to storagenodet3500"

WORKER_IP="192.168.4.61"
SSH_USER="root"

# Test basic SSH connectivity
debug "Testing basic SSH connection..."
if timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${SSH_USER}@${WORKER_IP}" "echo 'SSH test successful'" >/dev/null 2>&1; then
    success "✓ SSH connectivity to ${SSH_USER}@${WORKER_IP} works"
else
    error "✗ Cannot establish SSH connection to ${SSH_USER}@${WORKER_IP}"
    echo "  This is likely why the fix script fails with 'command-line line 0' error"
    echo "  Check:"
    echo "    1. SSH key authentication is configured"
    echo "    2. The worker node IP (192.168.4.61) is correct and reachable"
    echo "    3. Root SSH access is enabled on the worker node"
    exit 1
fi

# Test SCP capability (needed for our improved SSH function)
debug "Testing SCP capability..."
if timeout 10 scp -o ConnectTimeout=5 -o StrictHostKeyChecking=no /dev/null "${SSH_USER}@${WORKER_IP}:/tmp/scp_test" >/dev/null 2>&1; then
    success "✓ SCP functionality works"
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "${SSH_USER}@${WORKER_IP}" "rm -f /tmp/scp_test" >/dev/null 2>&1
else
    warn "⚠ SCP functionality may have issues - script will fall back to alternative methods"
fi

# Check 2: Current Flannel subnet allocation status
info "Step 2: Checking Flannel subnet allocation status"

NODE_SUBNET=$(kubectl get node storagenodet3500 -o jsonpath='{.metadata.annotations.flannel\.alpha\.coreos\.com/pod-cidr}' 2>/dev/null || echo "")
if [ -n "$NODE_SUBNET" ]; then
    success "✓ storagenodet3500 has Flannel subnet: $NODE_SUBNET"
    EXPECTED_BRIDGE_IP=$(echo "$NODE_SUBNET" | sed 's/\.0\/24/.1/')
    info "Expected cni0 bridge IP: $EXPECTED_BRIDGE_IP"
else
    error "✗ storagenodet3500 has no Flannel subnet allocation"
    echo "  This is the ROOT CAUSE mentioned in the problem statement"
    echo "  The fix script should detect and address this"
fi

# Check 3: Current CNI bridge state on worker node
info "Step 3: Checking current CNI bridge state on worker node"

WORKER_CNI_STATUS=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${SSH_USER}@${WORKER_IP}" "ip addr show cni0 2>/dev/null | grep 'inet ' | awk '{print \$2}' || echo 'No cni0 bridge'" 2>/dev/null || echo "Cannot check")

if [ "$WORKER_CNI_STATUS" = "Cannot check" ]; then
    error "✗ Cannot check CNI bridge status on worker node via SSH"
elif [ "$WORKER_CNI_STATUS" = "No cni0 bridge" ]; then
    info "✓ No cni0 bridge found on worker node"
    echo "  This is normal if no pods are currently scheduled"
else
    info "Current cni0 bridge on worker node: $WORKER_CNI_STATUS"
    
    # Check if it matches expected subnet
    if [ -n "$NODE_SUBNET" ]; then
        EXPECTED_BRIDGE_IP=$(echo "$NODE_SUBNET" | sed 's/\.0\/24/.1\/24/')
        if [ "$WORKER_CNI_STATUS" = "$EXPECTED_BRIDGE_IP" ]; then
            success "✓ CNI bridge IP matches expected subnet"
        else
            error "✗ CNI bridge IP conflict detected:"
            echo "  Current: $WORKER_CNI_STATUS"
            echo "  Expected: $EXPECTED_BRIDGE_IP"
            echo "  This is the exact issue the fix script should resolve"
        fi
    fi
fi

# Check 4: Flannel pod status
info "Step 4: Checking Flannel pod status on storagenodet3500"

FLANNEL_POD=$(kubectl get pods -n kube-flannel -o wide 2>/dev/null | grep "storagenodet3500" | awk '{print $1 " " $3}' | head -1)
if [ -n "$FLANNEL_POD" ]; then
    info "Flannel pod on storagenodet3500: $FLANNEL_POD"
    
    POD_NAME=$(echo "$FLANNEL_POD" | awk '{print $1}')
    POD_STATUS=$(echo "$FLANNEL_POD" | awk '{print $2}')
    
    if [ "$POD_STATUS" = "Running" ]; then
        success "✓ Flannel pod is Running"
    else
        warn "⚠ Flannel pod status: $POD_STATUS"
        echo "  Check Flannel logs: kubectl logs -n kube-flannel $POD_NAME"
    fi
else
    error "✗ No Flannel pod found on storagenodet3500"
fi

# Check 5: Current Jellyfin pod status
info "Step 5: Checking Jellyfin pod status"

if kubectl get namespace jellyfin >/dev/null 2>&1; then
    if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
        POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}')
        POD_NODE=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.nodeName}')
        echo "Jellyfin pod status: $POD_STATUS (scheduled on: $POD_NODE)"
        
        if [ "$POD_STATUS" = "Pending" ]; then
            warn "⚠ Jellyfin pod is Pending - checking for CNI errors"
            RECENT_ERRORS=$(kubectl get events -n jellyfin --sort-by='.lastTimestamp' | grep -E "(failed to set bridge addr|cni0.*IP.*different)" | tail -3 || echo "")
            if [ -n "$RECENT_ERRORS" ]; then
                error "✗ Recent CNI bridge conflicts detected:"
                echo "$RECENT_ERRORS"
                echo
                echo "  This confirms the issue still exists"
            else
                info "No recent CNI bridge errors found"
            fi
        elif [ "$POD_STATUS" = "Running" ]; then
            success "✓ Jellyfin pod is Running - no fix needed"
        fi
    else
        info "No Jellyfin pod found"
    fi
else
    info "Jellyfin namespace not found"
fi

# Check 6: Kubernetes cluster health
info "Step 6: Checking cluster health indicators"

# Check node status
NODE_STATUS=$(kubectl get node storagenodet3500 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
if [ "$NODE_STATUS" = "True" ]; then
    success "✓ storagenodet3500 node is Ready"
else
    warn "⚠ storagenodet3500 node status: $NODE_STATUS"
fi

# Check kubelet status on worker node
KUBELET_STATUS=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${SSH_USER}@${WORKER_IP}" "systemctl is-active kubelet" 2>/dev/null || echo "unknown")
if [ "$KUBELET_STATUS" = "active" ]; then
    success "✓ kubelet is active on worker node"
else
    warn "⚠ kubelet status on worker node: $KUBELET_STATUS"
fi

# Check containerd status on worker node  
CONTAINERD_STATUS=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${SSH_USER}@${WORKER_IP}" "systemctl is-active containerd" 2>/dev/null || echo "unknown")
if [ "$CONTAINERD_STATUS" = "active" ]; then
    success "✓ containerd is active on worker node"
else
    warn "⚠ containerd status on worker node: $CONTAINERD_STATUS"
fi

echo
echo "=== Diagnosis Summary ==="

# Determine if the fix should work
if [ -z "$NODE_SUBNET" ]; then
    echo "🔍 PRIMARY ISSUE: Missing Flannel subnet allocation"
    echo "   The fix script should:"
    echo "   1. Restart Flannel DaemonSet to trigger subnet allocation"
    echo "   2. Wait for subnet to be allocated"
    echo "   3. Reset CNI state on worker node"
    echo "   4. Allow Jellyfin pod to be created successfully"
elif [ "$WORKER_CNI_STATUS" != "No cni0 bridge" ] && [ -n "$NODE_SUBNET" ]; then
    EXPECTED_BRIDGE_IP=$(echo "$NODE_SUBNET" | sed 's/\.0\/24/.1\/24/')
    if [ "$WORKER_CNI_STATUS" != "$EXPECTED_BRIDGE_IP" ]; then
        echo "🔍 PRIMARY ISSUE: CNI bridge IP conflict"
        echo "   Current bridge IP: $WORKER_CNI_STATUS"
        echo "   Expected bridge IP: $EXPECTED_BRIDGE_IP"
        echo "   The fix script should reset the worker node CNI state"
    else
        echo "✅ NO ISSUES DETECTED: CNI configuration appears correct"
        echo "   If Jellyfin is still failing, check other issues like:"
        echo "   - Security contexts or health probe configuration"
        echo "   - Pod resource constraints"
        echo "   - Container image pull issues"
    fi
else
    echo "ℹ️ CURRENT STATE: No immediate CNI issues detected"
    echo "   Flannel subnet is allocated and no CNI bridge conflicts found"
fi

echo
echo "=== Recommended Action ==="
if [ -z "$NODE_SUBNET" ] || ([ "$WORKER_CNI_STATUS" != "No cni0 bridge" ] && [ -n "$NODE_SUBNET" ]); then
    echo "Run the enhanced fix script:"
    echo "  sudo ./fix_jellyfin_cni_bridge_conflict.sh"
    echo
    echo "The script has been improved to:"
    echo "  ✓ Handle SSH connectivity issues"
    echo "  ✓ Better coordinate Flannel subnet allocation"
    echo "  ✓ Provide more thorough verification"
    echo "  ✓ Include better error diagnostics"
else
    echo "No CNI fix needed. If Jellyfin still fails:"
    echo "  1. Check pod logs: kubectl logs -n jellyfin jellyfin"
    echo "  2. Check events: kubectl get events -n jellyfin"
    echo "  3. Review pod security context or resource constraints"
fi
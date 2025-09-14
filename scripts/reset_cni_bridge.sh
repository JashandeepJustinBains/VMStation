#!/bin/bash

# Reset CNI Bridge for VMStation Kubernetes Cluster
# This script resets the CNI bridge to align with proper kube-flannel, kube-proxy, and CoreDNS configuration
# Addresses the specific issue where cni0 has an IP address that conflicts with the expected 10.244.0.0/16 subnet

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
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Expected Flannel configuration from manifests
FLANNEL_NETWORK="10.244.0.0/16"
FLANNEL_BACKEND="vxlan"

echo "=== VMStation CNI Bridge Reset ==="
echo "Target: Reset CNI bridge to align with Flannel network $FLANNEL_NETWORK"
echo "Timestamp: $(date)"
echo

# Pre-flight checks
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl not found - this script must run on the control plane node"
    exit 1
fi

if ! timeout 30 kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    exit 1
fi

# Step 1: Check current CNI bridge status
info "Step 1: Checking current CNI bridge status"
if ip addr show cni0 >/dev/null 2>&1; then
    CURRENT_CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
    info "Current cni0 bridge IP: $CURRENT_CNI_IP"
    
    if echo "$CURRENT_CNI_IP" | grep -q "10.244."; then
        info "✓ CNI bridge is in Flannel subnet range"
    else
        warn "✗ CNI bridge IP ($CURRENT_CNI_IP) is NOT in Flannel subnet ($FLANNEL_NETWORK)"
        warn "This is the source of the pod creation conflicts"
    fi
else
    info "No cni0 bridge found"
fi

# Step 2: Check for stuck pods 
info "Step 2: Checking for stuck pods"
STUCK_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase=Pending | grep -v "NAMESPACE" | wc -l)
if [ "$STUCK_PODS" -gt 0 ]; then
    warn "Found $STUCK_PODS pods in Pending state"
    echo "Stuck pods:"
    kubectl get pods --all-namespaces --field-selector=status.phase=Pending | head -5
else
    info "✓ No stuck pods found"
fi

# Step 3: Check Flannel configuration
info "Step 3: Verifying Flannel configuration"
if kubectl get configmap kube-flannel-cfg -n kube-flannel >/dev/null 2>&1; then
    FLANNEL_CONFIG=$(kubectl get configmap kube-flannel-cfg -n kube-flannel -o jsonpath='{.data.net-conf\.json}')
    if echo "$FLANNEL_CONFIG" | grep -q "10.244.0.0/16"; then
        info "✓ Flannel configured for network $FLANNEL_NETWORK"
    else
        warn "⚠ Flannel network configuration may be incorrect"
        echo "Flannel config: $FLANNEL_CONFIG"
    fi
else
    error "Flannel ConfigMap not found"
    exit 1
fi

# Step 4: Backup current state
BACKUP_DIR="/tmp/cni-bridge-reset-$(date +%s)"
info "Step 4: Backing up current CNI state to $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# Backup CNI configuration
if [ -d /etc/cni/net.d ]; then
    cp -r /etc/cni/net.d "$BACKUP_DIR/" 2>/dev/null || true
fi

# Backup CNI runtime state
if [ -d /var/lib/cni ]; then
    cp -r /var/lib/cni "$BACKUP_DIR/" 2>/dev/null || true
fi

success "✓ Backup completed"

# Step 5: Reset CNI bridge
info "Step 5: Resetting CNI bridge"

# Stop kubelet to prevent pod creation during reset
info "Stopping kubelet..."
systemctl stop kubelet

# Stop containerd to clear network state
info "Stopping containerd..."
systemctl stop containerd
sleep 3

# Remove conflicting CNI bridge
if ip link show cni0 >/dev/null 2>&1; then
    info "Removing existing cni0 bridge..."
    ip link set cni0 down 2>/dev/null || true
    ip link delete cni0 2>/dev/null || true
    success "✓ Removed conflicting cni0 bridge"
else
    info "No cni0 bridge to remove"
fi

# Clear CNI network state
if [ -d /var/lib/cni ]; then
    info "Clearing CNI network state..."
    mv /var/lib/cni "/var/lib/cni.backup.$(date +%s)" 2>/dev/null || true
    mkdir -p /var/lib/cni
    success "✓ CNI state cleared"
fi

# Step 6: Restart services
info "Step 6: Restarting container runtime and kubelet"

# Start containerd
info "Starting containerd..."
systemctl start containerd
sleep 5

# Start kubelet
info "Starting kubelet..."
systemctl start kubelet
sleep 5

success "✓ Services restarted"

# Step 7: Wait for Flannel to recreate bridge
info "Step 7: Waiting for Flannel to recreate CNI bridge with correct IP..."

# Wait up to 60 seconds for cni0 to be recreated with correct IP
for i in {1..12}; do
    sleep 5
    if ip addr show cni0 >/dev/null 2>&1; then
        NEW_CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
        if echo "$NEW_CNI_IP" | grep -q "10.244."; then
            success "✓ CNI bridge recreated with correct IP: $NEW_CNI_IP"
            break
        else
            warn "CNI bridge has unexpected IP: $NEW_CNI_IP"
        fi
    else
        info "Waiting for cni0 bridge... (attempt $i/12)"
    fi
    
    if [ $i -eq 12 ]; then
        warn "⚠ CNI bridge not recreated within 60 seconds"
        warn "This may be normal if no pods are scheduled yet"
    fi
done

# Step 8: Restart Flannel pods to ensure clean state
info "Step 8: Restarting Flannel pods to ensure clean network state"
kubectl delete pods -n kube-flannel -l app=flannel --grace-period=0 --force 2>/dev/null || true

# Wait for Flannel pods to restart
info "Waiting for Flannel pods to restart..."
sleep 10

# Step 9: Verify Flannel pods are running
info "Step 9: Verifying Flannel pods are running"
for i in {1..6}; do
    FLANNEL_READY=$(kubectl get pods -n kube-flannel -l app=flannel --no-headers | grep "Running" | wc -l)
    FLANNEL_TOTAL=$(kubectl get pods -n kube-flannel -l app=flannel --no-headers | wc -l)
    
    if [ "$FLANNEL_READY" -eq "$FLANNEL_TOTAL" ] && [ "$FLANNEL_TOTAL" -gt 0 ]; then
        success "✓ All Flannel pods are running ($FLANNEL_READY/$FLANNEL_TOTAL)"
        break
    else
        info "Flannel pods status: $FLANNEL_READY/$FLANNEL_TOTAL running (attempt $i/6)"
        sleep 10
    fi
    
    if [ $i -eq 6 ]; then
        warn "⚠ Not all Flannel pods are running yet"
        echo "Current Flannel pod status:"
        kubectl get pods -n kube-flannel -l app=flannel
    fi
done

# Step 10: Final verification
echo
info "=== CNI Bridge Reset Complete ==="
echo

# Show final CNI bridge status
if ip addr show cni0 >/dev/null 2>&1; then
    echo "Final cni0 bridge status:"
    ip addr show cni0 | grep -E "inet|state"
    echo
    
    FINAL_CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
    if echo "$FINAL_CNI_IP" | grep -q "10.244."; then
        success "✅ CNI bridge is correctly configured: $FINAL_CNI_IP"
    else
        warn "⚠ CNI bridge may still have incorrect IP: $FINAL_CNI_IP"
    fi
else
    info "No cni0 bridge found - will be created when pods are scheduled"
fi

# Check if there are any remaining stuck pods
echo "Checking for any remaining stuck pods:"
REMAINING_STUCK=$(kubectl get pods --all-namespaces --field-selector=status.phase=Pending | grep -v "NAMESPACE" | wc -l)
if [ "$REMAINING_STUCK" -eq 0 ]; then
    success "✅ No pods stuck in Pending state"
else
    warn "⚠ $REMAINING_STUCK pods still in Pending state - may need additional troubleshooting"
fi

echo
success "🎉 CNI bridge reset completed!"
echo
echo "The CNI bridge has been reset to align with:"
echo "  ✓ kube-flannel network: $FLANNEL_NETWORK"
echo "  ✓ kube-proxy configuration"
echo "  ✓ CoreDNS networking requirements"
echo
echo "If you still have pod creation issues, check:"
echo "  1. Node readiness: kubectl get nodes"
echo "  2. Flannel logs: kubectl logs -n kube-flannel -l app=flannel"
echo "  3. Recent events: kubectl get events --sort-by='.lastTimestamp' | tail -10"
echo
echo "Backup saved to: $BACKUP_DIR"
#!/usr/bin/env bash
set -euo pipefail

# fix_cni_bridge_conflict.sh
# Enhanced CNI bridge conflict resolution for VMStation cluster
# Addresses specific issues with Jellyfin pod IP assignment failures
# Run this on the control-plane node as root.
# It will:
#  - back up current /etc/cni/net.d and /var/lib/cni state
#  - stop kubelet to prevent constant pod sandbox churn
#  - remove the cni0 bridge and flush CNI state
#  - restart containerd and kubelet so the CNI plugin (flannel) recreates the correct bridge
#  - wait for flannel DaemonSet and CoreDNS to reach Running
#  - validate pod IP assignment is working

DESIRED_BRIDGE_CIDR="10.244.0.1/16"
BACKUP_DIR="/tmp/cni-backup-$(date +%s)"
FLANNEL_SUBNET="10.244.0.0/16"

info() { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*"; }
err() { echo -e "[ERROR] $*"; exit 1; }

if [ "$EUID" -ne 0 ]; then
  err "This script must be run as root on the control-plane node"
fi

# Pre-flight checks for VMStation specific networking
info "VMStation CNI bridge conflict resolution starting..."
info "Target Flannel subnet: $FLANNEL_SUBNET"
info "Expected bridge CIDR: $DESIRED_BRIDGE_CIDR"

# Check if kubectl is available and cluster is accessible
if ! command -v kubectl >/dev/null 2>&1; then
  err "kubectl not found. This script must run on the control plane node."
fi

if ! timeout 30 kubectl get nodes >/dev/null 2>&1; then
  err "Cannot access Kubernetes cluster. Ensure this runs on the control plane."
fi

# Check for stuck pods in ContainerCreating state (key symptom)
STUCK_PODS=$(kubectl get pods --all-namespaces | grep "ContainerCreating" | wc -l)
if [ "$STUCK_PODS" -gt 0 ]; then
  warn "Found $STUCK_PODS pods stuck in ContainerCreating state"
  info "This typically indicates CNI bridge IP conflicts"
fi

# Check for specific CNI bridge errors in events
info "Checking for CNI bridge conflict errors..."
BRIDGE_ERRORS=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i "failed to set bridge addr.*cni0.*already has an IP address" | wc -l)
if [ "$BRIDGE_ERRORS" -gt 0 ]; then
  warn "Found $BRIDGE_ERRORS CNI bridge conflict events"
else
  info "No recent CNI bridge conflict events found"
fi

info "Backing up CNI configuration and state to $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
if [ -d /etc/cni/net.d ]; then
  cp -a /etc/cni/net.d "$BACKUP_DIR/" || true
fi
if [ -d /var/lib/cni ]; then
  cp -a /var/lib/cni "$BACKUP_DIR/" || true
fi

info "Inspecting current cni0 bridge"
if ip link show cni0 >/dev/null 2>&1; then
  current_ip=$(ip -4 addr show dev cni0 | awk '/inet /{print $2; exit}') || true
  info "cni0 exists with IP: ${current_ip:-<none>}"
  if [ "${current_ip:-}" != "${DESIRED_BRIDGE_CIDR}" ]; then
    warn "cni0 IP (${current_ip:-none}) does not match desired ${DESIRED_BRIDGE_CIDR}. Proceeding to reset CNI bridge."
  else
    info "cni0 already matches desired bridge IP. No action needed."
    exit 0
  fi
else
  warn "cni0 bridge not present. Flannel should create it when pods start. Exiting." 
  exit 0
fi

info "Stopping kubelet to avoid pod sandbox churn"
systemctl stop kubelet || warn "Failed to stop kubelet; continuing"

info "Stopping containerd"
systemctl stop containerd || warn "Failed to stop containerd; continuing"

# Wait for containerd to fully stop
sleep 5

info "Removing cni0 bridge and flushing CNI state"
# bring down and delete bridge if present
ip link set dev cni0 down 2>/dev/null || true
ip addr flush dev cni0 2>/dev/null || true
ip link delete cni0 2>/dev/null || true

# Check if bridge was successfully removed
if ip link show cni0 >/dev/null 2>&1; then
  warn "cni0 bridge still exists after deletion attempt"
else
  info "Successfully removed cni0 bridge"
fi

# Remove per-pod CNI network state so plugins can reinitialize cleanly
if [ -d /var/lib/cni ]; then
  info "Backing up and clearing /var/lib/cni"
  mv /var/lib/cni "$BACKUP_DIR/var-lib-cni" || true
  mkdir -p /var/lib/cni
fi

if [ -d /var/lib/cni/networks ]; then
  info "Backing up and clearing /var/lib/cni/networks" 
  mv /var/lib/cni/networks "$BACKUP_DIR/cni-networks" || true
fi

# Clear any remaining CNI network namespace state
if [ -d /var/run/netns ]; then
  info "Cleaning up network namespaces"
  for ns in $(ip netns list 2>/dev/null | awk '{print $1}' | grep -E '^cni-|^[0-9a-f-]+$' || true); do
    if [ -n "$ns" ]; then
      ip netns delete "$ns" 2>/dev/null || true
    fi
  done
fi

# Clean up any iptables rules related to old CNI setup
info "Cleaning up stale iptables rules"
# Remove any rules related to old CNI bridges
iptables -t nat -S | grep -E "cni0|cbr0" | sed 's/^-A/-D/' | while read rule; do
  iptables -t nat $rule 2>/dev/null || true
done

iptables -S | grep -E "cni0|cbr0" | sed 's/^-A/-D/' | while read rule; do
  iptables $rule 2>/dev/null || true
done

info "Starting containerd"
systemctl start containerd || err "Failed to start containerd"

info "Waiting 5s for containerd socket"
sleep 5

info "Starting kubelet"
systemctl start kubelet || err "Failed to start kubelet"

# Wait for kubelet to stabilize
info "Waiting for kubelet to stabilize..."
sleep 10

# Restart any stuck pods that were in ContainerCreating state
info "Checking for pods that need restart after CNI reset..."
JELLYFIN_STUCK=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$JELLYFIN_STUCK" = "Pending" ]; then
  warn "Jellyfin pod is still pending, restarting it..."
  kubectl delete pod -n jellyfin jellyfin --force --grace-period=0 2>/dev/null || true
  sleep 5
fi

# Delete any other stuck pods
STUCK_PODS_LIST=$(kubectl get pods --all-namespaces | grep "ContainerCreating" | awk '{print $2 " " $1}' || true)
if [ -n "$STUCK_PODS_LIST" ]; then
  warn "Restarting stuck pods..."
  echo "$STUCK_PODS_LIST" | while read pod namespace; do
    if [ -n "$pod" ] && [ -n "$namespace" ]; then
      info "Restarting stuck pod: $namespace/$pod"
      kubectl delete pod -n "$namespace" "$pod" --force --grace-period=0 || true
    fi
  done
fi

info "Waiting for flannel DaemonSet pods to become Ready (up to 2 minutes)"
timeout=120
interval=5
elapsed=0
while [ $elapsed -lt $timeout ]; do
  # check flannel daemonset pods ready count
  ds_ready=$(kubectl get ds -n kube-flannel kube-flannel -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
  ds_desired=$(kubectl get ds -n kube-flannel kube-flannel -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
  if [ -n "$ds_ready" ] && [ -n "$ds_desired" ] && [ "$ds_ready" -ge "$ds_desired" ] && [ "$ds_desired" -ne 0 ]; then
    info "Flannel daemonset ready: $ds_ready/$ds_desired"
    break
  fi
  sleep $interval
  elapsed=$((elapsed + interval))
done

if [ $elapsed -ge $timeout ]; then
  warn "Flannel did not reach Ready state in time. Check daemonset logs: kubectl -n kube-flannel logs ds/kube-flannel"
fi

info "Waiting for CoreDNS to obtain IP and become Running (up to 2 minutes)"
timeout=120
interval=5
elapsed=0
while [ $elapsed -lt $timeout ]; do
  coredns_ready=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "")
  if [ "$coredns_ready" = "Running" ]; then
    info "CoreDNS is Running"
    break
  fi
  sleep $interval
  elapsed=$((elapsed + interval))
done

if [ $elapsed -ge $timeout ]; then
  warn "CoreDNS did not reach Running state in time. Inspect: kubectl -n kube-system describe pod -l k8s-app=kube-dns"
fi

info "CNI reset script completed. Backups saved under $BACKUP_DIR"

# Additional validation for VMStation specific issues
info "Performing VMStation-specific networking validation..."

# Wait a bit more for the new cni0 bridge to be created
sleep 20

# Check if new bridge has correct IP
if ip link show cni0 >/dev/null 2>&1; then
  new_ip=$(ip -4 addr show dev cni0 | awk '/inet /{print $2; exit}') || true
  info "New cni0 bridge IP: ${new_ip:-<none>}"
  
  if echo "${new_ip:-}" | grep -q "10.244."; then
    info "✓ cni0 bridge now has correct Flannel subnet IP"
  else
    warn "cni0 bridge IP may still be incorrect: ${new_ip:-none}"
  fi
else
  warn "cni0 bridge not recreated yet - this may be normal during startup"
fi

# Test pod creation to validate CNI is working
info "Testing pod creation to validate CNI functionality..."
cat <<EOF | kubectl apply -f - || warn "Test pod creation failed"
apiVersion: v1
kind: Pod
metadata:
  name: cni-validation-test
  namespace: kube-system
spec:
  containers:
  - name: test
    image: busybox:1.35
    command: ['sleep', '30']
  restartPolicy: Never
EOF

# Wait and check test pod
sleep 15
TEST_STATUS=$(kubectl get pod cni-validation-test -n kube-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
TEST_IP=$(kubectl get pod cni-validation-test -n kube-system -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")

if [ "$TEST_STATUS" = "Running" ] && [ -n "$TEST_IP" ]; then
  info "✓ CNI validation test successful - Pod IP: $TEST_IP"
else
  warn "CNI validation test failed - Status: $TEST_STATUS, IP: ${TEST_IP:-none}"
fi

# Clean up test pod
kubectl delete pod cni-validation-test -n kube-system --ignore-not-found >/dev/null 2>&1 || true

info "CNI bridge conflict resolution completed!"
info "If pods still fail, run: kubectl -n kube-system describe pod <pod> and check kubelet logs: journalctl -u kubelet -n 200"

exit 0
#!/bin/bash

# Fix CNI Bridge IP Conflict Issue
# This script addresses the specific issue where pods are stuck in ContainerCreating
# due to CNI bridge (cni0) having an IP address different from the expected Flannel subnet

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
if ! timeout 30 kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster or kubectl timed out"
    echo "Please ensure:"
    echo "  1. kubectl is properly configured"
    echo "  2. The cluster is accessible"
    echo "  3. You are running this from the control plane node"
    exit 1
fi

echo "=== CNI Bridge Conflict Fix ==="
echo "Timestamp: $(date)"
echo "Fixing: cni0 bridge IP address conflicts preventing pod creation"
echo

# Step 1: Diagnose the CNI bridge issue
info "Step 1: Diagnosing CNI bridge configuration on all nodes"

# Get all cluster nodes
NODES=$(timeout 30 kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

for node in $NODES; do
    echo
    echo "=== Node: $node ==="
    
    # Check if this is a node we can access directly (control plane)
    if [ "$node" = "masternode" ] || timeout 30 kubectl get nodes "$node" -o jsonpath='{.metadata.labels.node-role\.kubernetes\.io/control-plane}' 2>/dev/null | grep -q ""; then
        echo "Checking CNI bridge configuration on control plane node..."
        
        # Check current bridge configuration
        if ip addr show cni0 >/dev/null 2>&1; then
            echo "Current cni0 bridge configuration:"
            ip addr show cni0 | grep -E "inet|state"
            
            CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
            if [ -n "$CNI_IP" ]; then
                echo "Current cni0 IP: $CNI_IP"
                
                # Check if it matches expected Flannel subnet
                if echo "$CNI_IP" | grep -q "10.244."; then
                    info "cni0 bridge IP is in correct Flannel subnet"
                else
                    warn "cni0 bridge IP ($CNI_IP) is NOT in expected Flannel subnet (10.244.0.0/16)"
                    echo "This is likely causing the ContainerCreating issues"
                fi
            fi
        else
            echo "No cni0 bridge found on this node"
        fi
    else
        echo "Worker node - will be handled by CNI reset on control plane"
    fi
done

# Step 2: Check current pod status to confirm the issue
info "Step 2: Checking current pod status"

echo "Pods stuck in ContainerCreating:"
timeout 30 kubectl get pods --all-namespaces 2>/dev/null | grep "ContainerCreating" || echo "No pods currently stuck in ContainerCreating"

echo
echo "Recent pod creation errors:"
timeout 30 kubectl get events --all-namespaces --sort-by='.lastTimestamp' 2>/dev/null | grep -i "failed to create pod sandbox" | tail -5 || echo "No recent pod sandbox creation errors found"

# Step 3: Fix the CNI bridge configuration
info "Step 3: Applying CNI bridge fix"

# First, check if any pods are currently using the bridge
PODS_ON_CNI=$(ip route | grep cni0 | wc -l 2>/dev/null || echo "0")
if [ "$PODS_ON_CNI" -gt 0 ]; then
    warn "Found $PODS_ON_CNI routes using cni0 - will need to reset networking"
fi

# Delete problematic CNI bridge to allow Flannel to recreate it properly
if ip addr show cni0 >/dev/null 2>&1; then
    warn "Deleting existing cni0 bridge to fix IP conflict"
    
    # First, bring down the interface
    sudo ip link set cni0 down 2>/dev/null || true
    
    # Delete the bridge
    sudo ip link delete cni0 2>/dev/null || true
    
    info "Deleted existing cni0 bridge"
else
    info "No existing cni0 bridge found"
fi

# Clean up any remaining CNI network configurations that might conflict
warn "Cleaning up potentially conflicting CNI configurations"

# Remove any conflicting CNI network configs (but preserve flannel config)
if [ -d "/etc/cni/net.d" ]; then
    # Keep only flannel configuration and remove others that might conflict
    sudo find /etc/cni/net.d -name "*.conflist" -not -name "*flannel*" -delete 2>/dev/null || true
    sudo find /etc/cni/net.d -name "*.conf" -not -name "*flannel*" -delete 2>/dev/null || true
    
    echo "Remaining CNI configurations:"
    ls -la /etc/cni/net.d/ 2>/dev/null || echo "No CNI config directory found"
fi

# Step 4: Restart network-related services to apply changes
info "Step 4: Restarting containerd to apply CNI changes"

sudo systemctl restart containerd

# Wait for containerd to stabilize
sleep 10

# Step 5: Restart Flannel pods to recreate bridge with correct configuration
info "Step 5: Restarting Flannel pods to recreate CNI bridge"

# Delete flannel pods to force recreation with clean network state
timeout 60 kubectl delete pods -n kube-flannel --all --force --grace-period=0

echo "Waiting for Flannel pods to recreate..."
sleep 20

# Check if Flannel DaemonSet is ready
info "Waiting for Flannel DaemonSet to be ready..."
if timeout 120 kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel; then
    info "Flannel DaemonSet is ready"
else
    warn "Flannel DaemonSet rollout timed out - may still be recovering"
fi

# Step 6: Verify the CNI bridge is now correctly configured
info "Step 6: Verifying CNI bridge fix"

# Wait a moment for the bridge to be created
sleep 15

if ip addr show cni0 >/dev/null 2>&1; then
    echo "New cni0 bridge configuration:"
    ip addr show cni0 | grep -E "inet|state"
    
    NEW_CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
    if [ -n "$NEW_CNI_IP" ]; then
        echo "New cni0 IP: $NEW_CNI_IP"
        
        if echo "$NEW_CNI_IP" | grep -q "10.244."; then
            info "✓ cni0 bridge now has correct Flannel subnet IP"
        else
            warn "cni0 bridge still has incorrect IP - may need manual intervention"
        fi
    fi
else
    warn "cni0 bridge not yet created - Flannel may still be initializing"
fi

# Step 7: Check if ContainerCreating pods can now start
info "Step 7: Checking if stuck pods can now start"

echo "Current pod status:"
kubectl get pods --all-namespaces | grep -E "(ContainerCreating|Pending)" || echo "No pods stuck in ContainerCreating/Pending"

# Try to create a test pod to verify networking
info "Testing pod creation with clean CNI bridge..."

cat <<EOF | timeout 30 kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: cni-test
  namespace: kube-system
spec:
  containers:
  - name: test
    image: busybox:1.35
    command: ['sleep', '60']
  restartPolicy: Never
EOF

# Wait and check if test pod starts successfully
sleep 10

TEST_POD_STATUS=$(timeout 30 kubectl get pod cni-test -n kube-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [ "$TEST_POD_STATUS" = "Running" ] || [ "$TEST_POD_STATUS" = "Succeeded" ]; then
    info "✓ Test pod created successfully - CNI bridge fix worked"
    
    # Get the pod IP to verify networking
    TEST_POD_IP=$(timeout 30 kubectl get pod cni-test -n kube-system -o jsonpath='{.status.podIP}' 2>/dev/null)
    if [ -n "$TEST_POD_IP" ]; then
        echo "Test pod IP: $TEST_POD_IP"
        if echo "$TEST_POD_IP" | grep -q "10.244."; then
            info "✓ Test pod received IP from correct Flannel subnet"
        fi
    fi
else
    warn "Test pod status: $TEST_POD_STATUS - CNI issues may persist"
    timeout 30 kubectl describe pod cni-test -n kube-system 2>/dev/null || true
fi

# Clean up test pod
timeout 30 kubectl delete pod cni-test -n kube-system --ignore-not-found

# Step 8: Restart CoreDNS and other stuck pods
info "Step 8: Restarting CoreDNS and other system pods"

# Restart CoreDNS deployment to clear any stuck pods
timeout 60 kubectl rollout restart deployment/coredns -n kube-system

echo "Waiting for CoreDNS to be ready..."
if timeout 120 kubectl rollout status deployment/coredns -n kube-system; then
    info "CoreDNS is ready"
else
    warn "CoreDNS rollout timed out - may still be recovering"
fi

# Final status check
echo
info "=== CNI Bridge Fix Complete ==="

echo "Final cluster status:"
timeout 30 kubectl get nodes -o wide 2>/dev/null || echo "Failed to get cluster status"

echo
echo "Final pod status (focusing on previously stuck pods):"
timeout 30 kubectl get pods --all-namespaces 2>/dev/null | grep -E "(kube-system|kube-flannel)" | grep -E "(coredns|flannel)" || echo "Failed to get pod status"

echo
echo "Any remaining ContainerCreating pods:"
timeout 30 kubectl get pods --all-namespaces 2>/dev/null | grep "ContainerCreating" || echo "✓ No pods stuck in ContainerCreating"

echo
if ip addr show cni0 >/dev/null 2>&1; then
    echo "Final cni0 bridge status:"
    ip addr show cni0 | grep -E "inet|state"
else
    warn "cni0 bridge not found - this may be normal if no pods are scheduled yet"
fi

echo
info "CNI bridge conflict fix completed!"
echo
echo "If pods are still stuck, check:"
echo "  1. Flannel logs: kubectl logs -n kube-flannel -l app=flannel"
echo "  2. Containerd logs: sudo journalctl -u containerd --since '5 minutes ago'"
echo "  3. Pod events: kubectl get events --all-namespaces --sort-by='.lastTimestamp'"
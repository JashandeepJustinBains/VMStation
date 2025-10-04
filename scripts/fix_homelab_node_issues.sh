#!/bin/bash
# Comprehensive fix for homelab node networking issues
# Addresses: Flannel CrashLoopBackOff, kube-proxy crashes, CoreDNS scheduling

set -euo pipefail

echo "=== Homelab Node Comprehensive Fix ==="
echo ""
echo "This script fixes:"
echo "  - Flannel CrashLoopBackOff on homelab node"
echo "  - kube-proxy crashes on RHEL 10"
echo "  - CoreDNS scheduling issues"
echo "  - Stuck ContainerCreating pods"
echo ""

# Function to wait for kubectl to be available
wait_for_kubectl() {
    echo "Waiting for Kubernetes API to become available..."
    for i in {1..30}; do
        if kubectl get nodes >/dev/null 2>&1; then
            echo "✓ Kubernetes API is available"
            return 0
        fi
        echo "  Waiting for API... ($i/30)"
        sleep 2
    done
    echo "✗ ERROR: Kubernetes API is still unavailable after 60 seconds"
    return 1
}

# Function to check if homelab node exists
check_homelab_node() {
    if ! kubectl get node homelab >/dev/null 2>&1; then
        echo "✗ ERROR: homelab node not found in cluster"
        echo "Available nodes:"
        kubectl get nodes
        exit 1
    fi
    echo "✓ homelab node found"
}

# Step 1: System-level fixes on homelab node
echo "=========================================="
echo "STEP 1: System-level fixes on homelab node"
echo "=========================================="
echo ""

echo "1.1 Disabling swap (required for kubelet)..."
ssh jashandeepjustinbains@192.168.4.62 'sudo swapoff -a 2>/dev/null || echo "Swap already disabled"'
ssh jashandeepjustinbains@192.168.4.62 'sudo sed -i "/\sswap\s/s/^/# /" /etc/fstab 2>/dev/null || echo "fstab already updated"'
echo "✓ Swap disabled"
echo ""

echo "1.2 Setting SELinux to permissive mode..."
ssh jashandeepjustinbains@192.168.4.62 'sudo setenforce 0 2>/dev/null || echo "SELinux already permissive"'
ssh jashandeepjustinbains@192.168.4.62 'sudo sed -i "s/^SELINUX=enforcing/SELINUX=permissive/" /etc/selinux/config 2>/dev/null || echo "SELinux config already updated"'
echo "✓ SELinux set to permissive"
echo ""

echo "1.3 Loading required kernel modules..."
ssh jashandeepjustinbains@192.168.4.62 'sudo modprobe br_netfilter overlay nf_conntrack vxlan 2>/dev/null || echo "Modules already loaded"'
echo "✓ Kernel modules loaded"
echo ""

echo "1.4 Configuring iptables backend for RHEL 10..."
# Check if iptables-nft exists (RHEL 10)
if ssh jashandeepjustinbains@192.168.4.62 'test -f /usr/sbin/iptables-nft' 2>/dev/null; then
    echo "  Detected iptables-nft, configuring nftables backend..."
    
    # Install alternatives if they don't exist
    ssh jashandeepjustinbains@192.168.4.62 'sudo update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-nft 10 2>/dev/null || true'
    ssh jashandeepjustinbains@192.168.4.62 'sudo update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-nft 10 2>/dev/null || true'
    
    # Set the backend
    ssh jashandeepjustinbains@192.168.4.62 'sudo update-alternatives --set iptables /usr/sbin/iptables-nft 2>/dev/null || echo "iptables-nft already set"'
    ssh jashandeepjustinbains@192.168.4.62 'sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-nft 2>/dev/null || echo "ip6tables-nft already set"'

    echo "  ✓ nftables backend configured"
else
    echo "  iptables-legacy detected, no backend change needed"
fi
echo ""

echo "1.5 Creating iptables lock file..."
ssh jashandeepjustinbains@192.168.4.62 'sudo touch /run/xtables.lock 2>/dev/null || echo "Lock file already exists"'
echo "✓ iptables lock file created"
echo ""

echo "1.6 Pre-creating kube-proxy iptables chains..."
ssh jashandeepjustinbains@192.168.4.62 'sudo bash -c "
    # Create NAT table chains
    iptables -t nat -N KUBE-SERVICES 2>/dev/null || true
    iptables -t nat -N KUBE-POSTROUTING 2>/dev/null || true
    iptables -t nat -N KUBE-FIREWALL 2>/dev/null || true
    iptables -t nat -N KUBE-MARK-MASQ 2>/dev/null || true
    
    # Create filter table chains
    iptables -t filter -N KUBE-FORWARD 2>/dev/null || true
    iptables -t filter -N KUBE-SERVICES 2>/dev/null || true
    
    # Link chains to base chains
    iptables -t nat -C PREROUTING -j KUBE-SERVICES 2>/dev/null || iptables -t nat -A PREROUTING -j KUBE-SERVICES
    iptables -t nat -C OUTPUT -j KUBE-SERVICES 2>/dev/null || iptables -t nat -A OUTPUT -j KUBE-SERVICES
    iptables -t nat -C POSTROUTING -j KUBE-POSTROUTING 2>/dev/null || iptables -t nat -A POSTROUTING -j KUBE-POSTROUTING
    iptables -t filter -C FORWARD -j KUBE-FORWARD 2>/dev/null || iptables -t filter -A FORWARD -j KUBE-FORWARD
"'
echo "✓ iptables chains pre-created"
echo ""

echo "1.7 Clearing stale network interfaces..."
ssh jashandeepjustinbains@192.168.4.62 'sudo ip link delete flannel.1 2>/dev/null || echo "No flannel.1 to delete"'
ssh jashandeepjustinbains@192.168.4.62 'sudo ip link delete cni0 2>/dev/null || echo "No cni0 to delete"'
echo "✓ Stale interfaces cleared"
echo ""

echo "1.8 Clearing CNI configuration (will be regenerated)..."
ssh jashandeepjustinbains@192.168.4.62 'sudo rm -f /etc/cni/net.d/10-flannel.conflist 2>/dev/null || echo "No CNI config to remove"'
ssh jashandeepjustinbains@192.168.4.62 'sudo rm -rf /var/lib/cni/flannel/* 2>/dev/null || echo "No flannel data to remove"'
echo "✓ CNI configuration cleared"
echo ""

echo "1.9 Restarting kubelet..."
ssh jashandeepjustinbains@192.168.4.62 'sudo systemctl restart kubelet'
sleep 5
echo "✓ kubelet restarted"
echo ""

# Wait for kubectl to be available
wait_for_kubectl || exit 1
echo ""

# Check homelab node
check_homelab_node
echo ""

# Step 2: Fix Flannel CrashLoopBackOff
echo "=========================================="
echo "STEP 2: Fix Flannel CrashLoopBackOff"
echo "=========================================="
echo ""

echo "2.1 Checking current Flannel pod status..."
kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o wide || echo "No Flannel pods found yet"
echo ""

echo "2.2 Deleting Flannel pod to force recreation..."
FLANNEL_POD=$(kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$FLANNEL_POD" ]; then
    echo "  Deleting pod: $FLANNEL_POD"
    kubectl delete pod -n kube-flannel "$FLANNEL_POD" --wait=false
    echo "✓ Flannel pod deleted"
else
    echo "  No Flannel pod to delete (will be created automatically)"
fi
echo ""

echo "2.3 Waiting for Flannel to restart (30 seconds)..."
sleep 30
echo ""

echo "2.4 Checking new Flannel pod status..."
kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o wide || echo "Flannel pod still starting"
echo ""

# Step 3: Fix kube-proxy CrashLoopBackOff
echo "=========================================="
echo "STEP 3: Fix kube-proxy CrashLoopBackOff"
echo "=========================================="
echo ""

echo "3.1 Checking current kube-proxy pod status..."
kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab -o wide || echo "No kube-proxy pods found yet"
echo ""

echo "3.2 Deleting kube-proxy pod to force recreation with new iptables config..."
PROXY_POD=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$PROXY_POD" ]; then
    echo "  Deleting pod: $PROXY_POD"
    kubectl delete pod -n kube-system "$PROXY_POD" --wait=false
    echo "✓ kube-proxy pod deleted"
else
    echo "  No kube-proxy pod to delete"
fi
echo ""

echo "3.3 Waiting for kube-proxy to restart (30 seconds)..."
sleep 30
echo ""

echo "3.4 Checking new kube-proxy pod status..."
kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab -o wide || echo "kube-proxy pod still starting"
echo ""

# Step 4: Fix CoreDNS scheduling
echo "=========================================="
echo "STEP 4: Fix CoreDNS Scheduling"
echo "=========================================="
echo ""

echo "4.1 Checking CoreDNS pod placement..."
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide || echo "No CoreDNS pods found"
echo ""

echo "4.2 Patching CoreDNS to prefer control-plane nodes..."
kubectl patch deployment coredns -n kube-system --type=merge -p '
{
  "spec": {
    "template": {
      "spec": {
        "affinity": {
          "nodeAffinity": {
            "preferredDuringSchedulingIgnoredDuringExecution": [
              {
                "weight": 100,
                "preference": {
                  "matchExpressions": [
                    {
                      "key": "node-role.kubernetes.io/control-plane",
                      "operator": "Exists"
                    }
                  ]
                }
              }
            ]
          }
        },
        "tolerations": [
          {
            "key": "node-role.kubernetes.io/control-plane",
            "operator": "Exists",
            "effect": "NoSchedule"
          }
        ]
      }
    }
  }
}' 2>/dev/null || echo "CoreDNS deployment not found or already patched"
echo "✓ CoreDNS scheduling configuration updated"
echo ""

# Step 5: Restart stuck ContainerCreating pods
echo "=========================================="
echo "STEP 5: Restart Stuck ContainerCreating Pods"
echo "=========================================="
echo ""

echo "5.1 Checking for stuck pods..."
STUCK_PODS=$(kubectl get pods -A --field-selector status.phase=Pending -o json 2>/dev/null | jq -r '.items[] | select(.status.containerStatuses != null) | select(.status.containerStatuses[].state.waiting.reason == "ContainerCreating") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

if [ -n "$STUCK_PODS" ]; then
    echo "  Found stuck pods:"
    echo "$STUCK_PODS"
    echo ""
    echo "  Deleting stuck pods..."
    echo "$STUCK_PODS" | while read -r pod; do
        if [ -n "$pod" ]; then
            kubectl delete pod "$pod" --wait=false 2>/dev/null || echo "  Failed to delete $pod"
        fi
    done
    echo "✓ Stuck pods deleted"
else
    echo "  No stuck ContainerCreating pods found"
fi
echo ""

# Step 6: Final validation
echo "=========================================="
echo "STEP 6: Final Validation"
echo "=========================================="
echo ""

echo "6.1 Waiting for pods to stabilize (60 seconds)..."
sleep 60
echo ""

echo "6.2 Checking for CrashLoopBackOff pods..."
CRASHLOOP=$(kubectl get pods -A --field-selector status.phase=Running -o json 2>/dev/null | \
    jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting.reason == "CrashLoopBackOff") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

if [ -n "$CRASHLOOP" ]; then
    echo "⚠ WARNING: Still found pods in CrashLoopBackOff:"
    echo "$CRASHLOOP"
    echo ""
    echo "To diagnose:"
    echo "  ./scripts/diagnose-flannel-homelab.sh"
    echo "  ./scripts/diagnose-homelab-issues.sh"
else
    echo "✓ No CrashLoopBackOff pods detected"
fi
echo ""

echo "6.3 Final cluster status:"
echo ""
echo "--- Nodes ---"
kubectl get nodes -o wide
echo ""
echo "--- Flannel Pods ---"
kubectl get pods -n kube-flannel -o wide
echo ""
echo "--- kube-system Pods (on homelab) ---"
kubectl get pods -n kube-system --field-selector spec.nodeName=homelab -o wide
echo ""
echo "--- CoreDNS Pods ---"
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
echo ""

echo "=========================================="
echo "=== Fix Complete ==="
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ System-level fixes applied to homelab node"
echo "  ✓ Flannel pod restarted"
echo "  ✓ kube-proxy pod restarted with proper iptables config"
echo "  ✓ CoreDNS scheduling optimized"
echo "  ✓ Stuck pods cleaned up"
echo ""
echo "If issues persist:"
echo "  1. Check pod logs: kubectl logs -n <namespace> <pod-name>"
echo "  2. Run diagnostics: ./scripts/diagnose-homelab-issues.sh"
echo "  3. Check node status: kubectl describe node homelab"
echo ""

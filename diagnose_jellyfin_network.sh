#!/bin/bash

# Diagnose Jellyfin Network Connectivity Issues
# This script helps identify and diagnose the "no route to host" errors
# that prevent Jellyfin health probes from working

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

echo "=== Jellyfin Network Connectivity Diagnostic ==="
echo "Timestamp: $(date)"
echo

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl is required but not found"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot connect to Kubernetes cluster"
    exit 1
fi

info "Step 1: Checking cluster network configuration"

echo "=== Cluster Nodes ==="
kubectl get nodes -o wide

echo
echo "=== CNI Configuration ==="
if [ -d "/etc/cni/net.d" ]; then
    echo "CNI configuration files:"
    ls -la /etc/cni/net.d/
    echo
    if [ -f "/etc/cni/net.d/10-flannel.conflist" ]; then
        echo "Flannel configuration:"
        cat /etc/cni/net.d/10-flannel.conflist
    fi
else
    warn "CNI configuration directory not found"
fi

echo
echo "=== CNI Bridge Status ==="
if ip addr show cni0 >/dev/null 2>&1; then
    echo "cni0 bridge exists:"
    ip addr show cni0
    
    CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
    if [ -n "$CNI_IP" ]; then
        echo "CNI bridge IP: $CNI_IP"
        
        # Check if it matches expected Flannel subnet
        if echo "$CNI_IP" | grep -q "10.244."; then
            info "✓ CNI bridge IP is in correct Flannel subnet"
        else
            error "✗ CNI bridge IP ($CNI_IP) is NOT in expected Flannel subnet (10.244.0.0/16)"
            warn "This is likely causing the 'no route to host' errors"
        fi
    fi
else
    warn "No cni0 bridge found - this may indicate CNI issues"
fi

echo
info "Step 2: Checking Flannel networking"

echo "=== Flannel Pods ==="
kubectl get pods -n kube-flannel -o wide

echo
echo "=== Flannel DaemonSet Status ==="
kubectl get daemonset -n kube-flannel

echo
if kubectl get pods -n kube-flannel -l app=flannel >/dev/null 2>&1; then
    echo "=== Flannel Logs (last 20 lines) ==="
    kubectl logs -n kube-flannel -l app=flannel --tail=20 || warn "Could not get Flannel logs"
fi

echo
info "Step 3: Checking Jellyfin pod status"

if kubectl get namespace jellyfin >/dev/null 2>&1; then
    if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
        echo "=== Jellyfin Pod Status ==="
        kubectl get pod -n jellyfin jellyfin -o wide
        
        echo
        echo "=== Jellyfin Pod Details ==="
        kubectl describe pod -n jellyfin jellyfin
        
        echo
        echo "=== Recent Jellyfin Events ==="
        kubectl get events -n jellyfin --sort-by='.lastTimestamp' | tail -10
        
        # Try to get pod IP and test connectivity
        POD_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}' 2>/dev/null)
        if [ -n "$POD_IP" ]; then
            echo
            info "Testing connectivity to Jellyfin pod IP: $POD_IP"
            
            # Test basic IP connectivity
            if ping -c 1 -W 3 "$POD_IP" >/dev/null 2>&1; then
                info "✓ Ping to pod IP successful"
            else
                warn "✗ Ping to pod IP failed"
            fi
            
            # Test HTTP connectivity
            if timeout 5 curl -s --connect-timeout 3 "http://$POD_IP:8096/" >/dev/null 2>&1; then
                info "✓ HTTP connectivity to pod:8096 successful"
            else
                warn "✗ HTTP connectivity to pod:8096 failed"
                warn "This confirms the 'no route to host' issue"
            fi
        else
            warn "Jellyfin pod has no IP assigned"
        fi
    else
        warn "No Jellyfin pod found in jellyfin namespace"
    fi
else
    warn "Jellyfin namespace does not exist"
fi

echo
info "Step 4: Checking system routes and networking"

echo "=== System Routes ==="
ip route show | grep -E "(10.244|cni0)" || echo "No routes found for pod network"

echo
echo "=== Network Interfaces ==="
ip addr show | grep -A 5 -E "(cni0|flannel|veth)" || echo "No CNI-related interfaces found"

echo
echo "=== iptables NAT rules (CNI-related) ==="
sudo iptables -t nat -L | grep -A 5 -B 5 -E "(CNI|FLANNEL|10.244)" || echo "No CNI-related iptables rules found"

echo
info "Step 5: Checking for specific issues from problem statement"

echo "=== kubectl Configuration Check ==="
# Check if kubectl works on worker nodes (simulate the problem from the statement)
if kubectl get nodes >/dev/null 2>&1; then
    info "✓ kubectl can access cluster from this node"
else
    error "✗ kubectl cannot access cluster - connection refused error detected"
    echo "This matches the problem statement issue on storage node"
    echo "Fix: Run ./scripts/fix_worker_kubectl_config.sh"
fi

echo
echo "=== kube-proxy Status Check ==="
# Check for CrashLoopBackOff specifically
CRASHLOOP_PROXY=$(kubectl get pods -n kube-system -l component=kube-proxy 2>/dev/null | grep "CrashLoopBackOff" || echo "")
if [ -n "$CRASHLOOP_PROXY" ]; then
    error "✗ Found kube-proxy pods in CrashLoopBackOff:"
    echo "$CRASHLOOP_PROXY"
    echo "This matches the problem statement issue on homelab node"
    echo "Fix: Run ./scripts/fix_remaining_pod_issues.sh"
else
    info "✓ No kube-proxy pods in CrashLoopBackOff"
fi

echo
echo "=== iptables Compatibility Check ==="
# Check for the specific nftables error from problem statement
if command -v iptables >/dev/null 2>&1; then
    IPTABLES_ERROR=$(iptables -t nat -L KUBE-SEP 2>&1 | grep "nf_tables.*incompatible" || echo "")
    if [ -n "$IPTABLES_ERROR" ]; then
        error "✗ Detected iptables/nftables incompatibility issue:"
        echo "$IPTABLES_ERROR"
        echo "This matches the problem statement iptables error"
        echo "Fix: Run ./scripts/fix_iptables_compatibility.sh"
    else
        info "✓ No iptables/nftables compatibility issues detected"
    fi
else
    warn "iptables command not available for testing"
fi

echo
echo "=== NodePort Service Test ==="
# Test NodePort 30096 specifically mentioned in problem statement
if kubectl get service -n jellyfin jellyfin-service >/dev/null 2>&1; then
    JELLYFIN_NODEPORT=$(kubectl get service -n jellyfin jellyfin-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [ "$JELLYFIN_NODEPORT" = "30096" ]; then
        info "Testing NodePort 30096 connectivity (mentioned in problem statement)"
        
        # Get node IPs
        NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
        
        for node_ip in $NODE_IPS; do
            if timeout 5 curl -s --connect-timeout 3 "http://$node_ip:30096/" >/dev/null 2>&1; then
                info "✓ NodePort 30096 accessible on $node_ip"
            else
                error "✗ NodePort 30096 connection refused on $node_ip"
                echo "This matches the problem statement curl failure"
                echo "Fix: Run ./scripts/fix_cluster_communication.sh"
            fi
        done
    fi
else
    warn "Jellyfin service not found - cannot test NodePort 30096"
fi

echo
info "Step 6: Suggested actions"

echo
echo "Based on the diagnostic results above:"
echo

if ! ip addr show cni0 >/dev/null 2>&1; then
    error "CRITICAL: No cni0 bridge found"
    echo "Actions:"
    echo "  1. Check if Flannel is running: kubectl get pods -n kube-flannel"
    echo "  2. Restart Flannel: kubectl delete pods -n kube-flannel --all"
    echo "  3. Check containerd: sudo systemctl status containerd"
elif ip addr show cni0 >/dev/null 2>&1; then
    CNI_IP=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
    if [ -n "$CNI_IP" ] && ! echo "$CNI_IP" | grep -q "10.244."; then
        error "CRITICAL: CNI bridge has wrong IP subnet"
        echo "Actions:"
        echo "  1. Run the CNI bridge fix: sudo ./scripts/fix_cni_bridge_conflict.sh"
        echo "  2. Or manually fix: sudo ip link delete cni0; sudo systemctl restart containerd"
        echo "  3. Restart Flannel: kubectl delete pods -n kube-flannel --all"
    else
        info "CNI bridge looks correct, checking other issues..."
        
        if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
            POD_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}' 2>/dev/null)
            if [ -n "$POD_IP" ] && ! timeout 3 curl -s "http://$POD_IP:8096/" >/dev/null 2>&1; then
                warn "Pod IP connectivity failed - may be seccomp or security context issue"
                echo "Actions:"
                echo "  1. Check pod security context restrictions"
                echo "  2. Remove seccompProfile if present"
                echo "  3. Increase probe timeouts and failure thresholds"
            fi
        fi
    fi
fi

echo
echo "=== Common Solutions ==="
echo "1. Complete cluster communication fix: ./scripts/fix_cluster_communication.sh"
echo "2. kubectl configuration fix: ./scripts/fix_worker_kubectl_config.sh"
echo "3. iptables compatibility fix: ./scripts/fix_iptables_compatibility.sh"
echo "4. CNI Bridge Fix: ./scripts/fix_cni_bridge_conflict.sh"
echo "5. kube-proxy and pod issues: ./scripts/fix_remaining_pod_issues.sh"
echo "6. Cluster validation: ./scripts/validate_cluster_communication.sh"
echo "7. Enhanced Jellyfin Fix: ./fix_jellyfin_readiness.sh"

echo
info "Diagnostic complete. Review the output above to identify the root cause."
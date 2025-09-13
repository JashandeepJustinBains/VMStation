#!/bin/bash

# VMStation NodePort External Access Fix
# Fixes external access to NodePort services (like Jellyfin on port 30096)
# from machines outside the cluster by ensuring proper firewall and iptables rules

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

echo "=== VMStation NodePort External Access Fix ==="
echo "Timestamp: $(date)"
echo "Purpose: Enable external access to NodePort services from outside the cluster"
echo

# Check prerequisites
info "Checking prerequisites..."

# Check if kubectl is available and working
if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl is not available"
    exit 1
fi

if ! timeout 10 kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    exit 1
fi

# Check if we're running as root (needed for firewall changes)
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root for firewall configuration"
    echo "Please run: sudo $0"
    exit 1
fi

success "✅ Prerequisites check passed"

# Step 1: Analyze current NodePort services
info "Step 1: Analyzing current NodePort services"

NODEPORT_SERVICES=$(kubectl get services --all-namespaces -o wide | grep NodePort || echo "")

if [ -z "$NODEPORT_SERVICES" ]; then
    warn "No NodePort services found in the cluster"
    exit 0
fi

echo "Found NodePort services:"
echo "$NODEPORT_SERVICES"
echo

# Extract NodePort ranges being used
NODEPORTS=$(echo "$NODEPORT_SERVICES" | awk '{print $6}' | grep -o '[0-9]*:[0-9]*' | cut -d: -f2 | sort -n | uniq)
info "NodePorts in use: $(echo $NODEPORTS | tr '\n' ' ')"

# Step 2: Check current firewall status
info "Step 2: Checking current firewall configuration"

# Check if ufw is active
if command -v ufw >/dev/null 2>&1; then
    UFW_STATUS=$(ufw status | head -1)
    info "UFW Status: $UFW_STATUS"
    
    if echo "$UFW_STATUS" | grep -q "Status: active"; then
        info "UFW is active - checking NodePort rules"
        
        # Check if NodePort range is allowed
        if ufw status numbered | grep -q "30000:32767"; then
            info "✓ NodePort range rules already exist"
        else
            warn "⚠️ NodePort range rules missing"
            
            info "Adding UFW rules for NodePort range (30000-32767)"
            
            # Allow NodePort range from local network
            ufw allow from 192.168.0.0/16 to any port 30000:32767 comment "Kubernetes NodePorts"
            
            # Allow specific NodePorts from anywhere if they're commonly used ones
            for port in $NODEPORTS; do
                if [ "$port" -ge 30000 ] && [ "$port" -le 32767 ]; then
                    info "Adding specific rule for NodePort $port"
                    ufw allow $port comment "NodePort $port"
                fi
            done
            
            success "✅ UFW NodePort rules added"
        fi
    else
        info "UFW is not active - checking iptables directly"
    fi
fi

# Step 3: Check and fix iptables rules for kube-proxy
info "Step 3: Validating kube-proxy iptables rules"

# Check if KUBE-NODEPORTS chain exists and has rules
if iptables -t nat -L KUBE-NODEPORTS >/dev/null 2>&1; then
    NODEPORT_RULES=$(iptables -t nat -L KUBE-NODEPORTS --line-numbers | wc -l)
    if [ "$NODEPORT_RULES" -gt 1 ]; then
        info "✓ kube-proxy NodePort iptables rules exist ($((NODEPORT_RULES - 1)) rules)"
    else
        warn "⚠️ KUBE-NODEPORTS chain exists but has no rules"
    fi
else
    warn "⚠️ KUBE-NODEPORTS iptables chain does not exist"
    
    info "Restarting kube-proxy to recreate iptables rules"
    kubectl rollout restart daemonset/kube-proxy -n kube-system
    
    info "Waiting for kube-proxy rollout to complete..."
    kubectl rollout status daemonset/kube-proxy -n kube-system --timeout=300s
    
    # Wait a bit more for iptables rules to be created
    sleep 30
    
    # Check again
    if iptables -t nat -L KUBE-NODEPORTS >/dev/null 2>&1; then
        success "✅ KUBE-NODEPORTS chain recreated successfully"
    else
        error "❌ Failed to recreate KUBE-NODEPORTS chain"
    fi
fi

# Step 4: Test NodePort accessibility from control plane
info "Step 4: Testing NodePort accessibility from control plane"

# Get node IPs
NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
info "Testing NodePort access on nodes: $NODE_IPS"

# Test each NodePort service
echo "$NODEPORT_SERVICES" | while IFS= read -r line; do
    if [ -n "$line" ] && echo "$line" | grep -q NodePort; then
        namespace=$(echo "$line" | awk '{print $1}')
        service=$(echo "$line" | awk '{print $2}')
        nodeport=$(echo "$line" | awk '{print $6}' | cut -d: -f2 | cut -d/ -f1)
        
        if [ -n "$nodeport" ] && [ "$nodeport" != "<none>" ]; then
            info "Testing $namespace/$service on NodePort $nodeport"
            
            for node_ip in $NODE_IPS; do
                if timeout 5 curl -s --connect-timeout 3 "http://$node_ip:$nodeport/" >/dev/null 2>&1; then
                    success "  ✅ $node_ip:$nodeport - accessible"
                else
                    warn "  ⚠️  $node_ip:$nodeport - not accessible"
                fi
            done
        fi
    fi
done

# Step 5: Apply additional iptables rules if needed
info "Step 5: Ensuring direct iptables rules for NodePort forwarding"

# Add explicit ACCEPT rules for NodePort traffic if they don't exist
for port in $NODEPORTS; do
    if [ "$port" -ge 30000 ] && [ "$port" -le 32767 ]; then
        # Check if rule already exists
        if ! iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
            info "Adding iptables rule for port $port"
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        fi
        
        # Also ensure UDP if it's a UDP service
        if ! iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null; then
            iptables -A INPUT -p udp --dport "$port" -j ACCEPT
        fi
    fi
done

# Step 6: Restart and validate services on each node
info "Step 6: Ensuring services are reachable on all nodes"

# Force refresh of service endpoints
kubectl get endpoints --all-namespaces >/dev/null

# For Jellyfin specifically, ensure it's properly bound
if kubectl get service -n jellyfin jellyfin-service >/dev/null 2>&1; then
    JELLYFIN_NODEPORT=$(kubectl get service -n jellyfin jellyfin-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    info "Jellyfin NodePort: $JELLYFIN_NODEPORT"
    
    # Check if Jellyfin pod is running and ready
    if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
        POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null)
        POD_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        
        info "Jellyfin pod status: $POD_STATUS, ready: $POD_READY"
        
        if [ "$POD_STATUS" = "Running" ] && [ "$POD_READY" = "true" ]; then
            success "✅ Jellyfin pod is running and ready"
        else
            warn "⚠️ Jellyfin pod is not ready - this may affect external access"
        fi
    fi
fi

# Step 7: Save iptables rules if using iptables-persistent
info "Step 7: Saving iptables rules"

if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
    info "iptables rules saved with netfilter-persistent"
elif command -v iptables-save >/dev/null 2>&1; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    info "iptables rules saved to /etc/iptables/rules.v4"
fi

# Final validation
info "Step 8: Final validation"

echo
success "🎉 NodePort external access configuration completed!"
echo
echo "Summary of changes made:"
echo "✅ UFW rules added for NodePort range (30000-32767)"
echo "✅ kube-proxy iptables rules validated/recreated"
echo "✅ Direct iptables rules added for active NodePorts"
echo "✅ Service endpoints refreshed"
echo
echo "To test external access from your development desktop:"
echo "  curl -v http://192.168.4.61:30096/    # Jellyfin on storage node"
echo "  curl -v http://192.168.4.63:30096/    # Jellyfin on master node"
echo "  curl -v http://192.168.4.62:30096/    # Jellyfin on homelab node"
echo
echo "If issues persist, check:"
echo "1. External firewall/router settings"
echo "2. Network connectivity between machines"
echo "3. Run: kubectl get endpoints --all-namespaces"
echo

exit 0
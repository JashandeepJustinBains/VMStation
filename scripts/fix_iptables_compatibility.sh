#!/bin/bash

# Fix iptables/nftables Compatibility Issues
# This script detects and fixes iptables/nftables compatibility problems
# that can cause kube-proxy to fail with "incompatible" errors

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

echo "=== iptables/nftables Compatibility Fix ==="
echo "Timestamp: $(date)"
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

# Function to detect iptables backend
detect_iptables_backend() {
    info "Detecting iptables backend configuration"
    
    # Check which iptables backend is being used
    if command -v update-alternatives >/dev/null 2>&1; then
        # Debian/Ubuntu systems
        local current_iptables=$(update-alternatives --query iptables 2>/dev/null | grep "Value:" | awk '{print $2}' || echo "")
        if [ -n "$current_iptables" ]; then
            echo "Current iptables alternative: $current_iptables"
            
            if echo "$current_iptables" | grep -q "nft"; then
                warn "System is using nftables backend for iptables"
                return 1  # nftables
            else
                info "System is using legacy iptables backend"
                return 0  # legacy
            fi
        fi
    fi
    
    # Check for nftables directly
    if command -v nft >/dev/null 2>&1; then
        local nft_rules=$(nft list tables 2>/dev/null | wc -l || echo "0")
        if [ "$nft_rules" -gt 0 ]; then
            warn "System has active nftables rules"
            return 1  # nftables
        fi
    fi
    
    # Default to legacy if unclear
    info "Assuming legacy iptables backend"
    return 0
}

# Function to check for compatibility issues
check_compatibility_issues() {
    info "Checking for existing iptables/nftables compatibility issues"
    
    local issues_found=false
    
    # Check iptables commands for errors
    if ! iptables -t nat -L >/dev/null 2>&1; then
        local iptables_error=$(iptables -t nat -L 2>&1 || echo "")
        if echo "$iptables_error" | grep -q "nf_tables.*incompatible"; then
            error "Detected iptables/nftables incompatibility:"
            echo "$iptables_error"
            issues_found=true
        fi
    fi
    
    # Check kube-proxy logs for compatibility errors
    if command -v kubectl >/dev/null 2>&1 && kubectl get pods -n kube-system >/dev/null 2>&1; then
        local proxy_errors=$(kubectl logs -n kube-system -l component=kube-proxy --tail=100 2>/dev/null | grep -i "nf_tables.*incompatible" || echo "")
        if [ -n "$proxy_errors" ]; then
            error "Found iptables compatibility errors in kube-proxy logs:"
            echo "$proxy_errors"
            issues_found=true
        fi
    fi
    
    if [ "$issues_found" = "true" ]; then
        return 1
    else
        info "No compatibility issues detected"
        return 0
    fi
}

# Function to fix iptables backend
fix_iptables_backend() {
    info "Switching to legacy iptables backend"
    
    # For Debian/Ubuntu systems
    if command -v update-alternatives >/dev/null 2>&1; then
        info "Configuring iptables alternatives to use legacy backend"
        
        # Set iptables to legacy
        update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || {
            warn "Failed to set iptables alternative, trying manual configuration"
        }
        
        # Set ip6tables to legacy
        update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
        
        # Set iptables-save and iptables-restore
        update-alternatives --set iptables-save /usr/sbin/iptables-legacy-save 2>/dev/null || true
        update-alternatives --set iptables-restore /usr/sbin/iptables-legacy-restore 2>/dev/null || true
        
        info "✓ Switched to legacy iptables backend"
    fi
    
    # For RHEL/CentOS systems (if using alternatives)
    if command -v alternatives >/dev/null 2>&1; then
        info "Configuring iptables alternatives for RHEL/CentOS"
        alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
        alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
    fi
    
    # Verify the change
    if iptables --version 2>/dev/null | grep -q "legacy"; then
        info "✓ Successfully switched to legacy iptables"
    else
        warn "iptables backend switch may not have been successful"
    fi
}

# Function to configure kube-proxy for iptables mode
configure_kube_proxy_iptables() {
    info "Configuring kube-proxy to use iptables mode explicitly"
    
    if ! command -v kubectl >/dev/null 2>&1; then
        warn "kubectl not available, skipping kube-proxy configuration"
        return
    fi
    
    # Check if we can access the cluster
    if ! timeout 10 kubectl get nodes >/dev/null 2>&1; then
        warn "Cannot access Kubernetes cluster, skipping kube-proxy configuration"
        return
    fi
    
    # Get current kube-proxy configmap
    if kubectl get configmap kube-proxy -n kube-system >/dev/null 2>&1; then
        info "Updating existing kube-proxy configmap"
        
        # Create a temporary file with the new configuration
        cat > /tmp/kube-proxy-config.yaml <<EOF
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "iptables"
clusterCIDR: "10.244.0.0/16"
bindAddress: 0.0.0.0
healthzBindAddress: 0.0.0.0:10256
metricsBindAddress: 127.0.0.1:10249
iptables:
  minSyncPeriod: 0s
  syncPeriod: 30s
  masqueradeAll: false
conntrack:
  maxPerCore: 32768
  min: 131072
  tcpCloseWaitTimeout: 1h0m0s
  tcpEstablishedTimeout: 24h0m0s
nodePortAddresses: null
EOF
        
        # Update the configmap
        kubectl create configmap kube-proxy-config --from-file=config.conf=/tmp/kube-proxy-config.yaml -n kube-system --dry-run=client -o yaml | \
        kubectl apply -f - || warn "Failed to update kube-proxy configmap"
        
        # Clean up temp file
        rm -f /tmp/kube-proxy-config.yaml
        
    else
        info "Creating new kube-proxy configmap"
        
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-proxy
  namespace: kube-system
data:
  config.conf: |
    apiVersion: kubeproxy.config.k8s.io/v1alpha1
    kind: KubeProxyConfiguration
    mode: "iptables"
    clusterCIDR: "10.244.0.0/16"
    bindAddress: 0.0.0.0
    healthzBindAddress: 0.0.0.0:10256
    metricsBindAddress: 127.0.0.1:10249
    iptables:
      minSyncPeriod: 0s
      syncPeriod: 30s
      masqueradeAll: false
    conntrack:
      maxPerCore: 32768
      min: 131072
      tcpCloseWaitTimeout: 1h0m0s
      tcpEstablishedTimeout: 24h0m0s
    nodePortAddresses: null
EOF
    fi
}

# Function to restart affected services
restart_services() {
    info "Restarting services to apply iptables changes"
    
    # Restart kube-proxy if kubectl is available
    if command -v kubectl >/dev/null 2>&1 && timeout 10 kubectl get nodes >/dev/null 2>&1; then
        info "Restarting kube-proxy daemonset"
        kubectl rollout restart daemonset/kube-proxy -n kube-system || warn "Failed to restart kube-proxy"
        
        # Wait for rollout
        if timeout 120 kubectl rollout status daemonset/kube-proxy -n kube-system; then
            info "✓ kube-proxy restart completed"
        else
            warn "kube-proxy restart timed out"
        fi
    fi
    
    # Restart containerd if it's running
    if systemctl is-active containerd >/dev/null 2>&1; then
        info "Restarting containerd to clear any cached iptables state"
        systemctl restart containerd
        sleep 5
        info "✓ containerd restarted"
    fi
}

# Function to validate the fix
validate_fix() {
    info "Validating iptables compatibility fix"
    
    # Test basic iptables functionality
    if iptables -t nat -L >/dev/null 2>&1; then
        info "✓ iptables NAT table accessible"
    else
        error "✗ iptables NAT table still has issues"
        return 1
    fi
    
    # Test filter table
    if iptables -t filter -L >/dev/null 2>&1; then
        info "✓ iptables filter table accessible"
    else
        warn "⚠️  iptables filter table has issues"
    fi
    
    # Check kube-proxy logs for errors
    if command -v kubectl >/dev/null 2>&1 && timeout 10 kubectl get pods -n kube-system >/dev/null 2>&1; then
        sleep 10  # Wait a moment for new logs
        
        local recent_errors=$(kubectl logs -n kube-system -l component=kube-proxy --tail=50 --since=1m 2>/dev/null | grep -i "error\|fail\|incompatible" || echo "")
        
        if [ -z "$recent_errors" ]; then
            info "✓ No recent errors in kube-proxy logs"
        else
            warn "⚠️  Still seeing errors in kube-proxy logs:"
            echo "$recent_errors"
        fi
        
        # Check if kube-proxy pods are running
        local running_proxy=$(kubectl get pods -n kube-system -l component=kube-proxy --no-headers | grep -c "Running" || echo "0")
        local total_proxy=$(kubectl get pods -n kube-system -l component=kube-proxy --no-headers | wc -l || echo "0")
        
        if [ "$running_proxy" -eq "$total_proxy" ] && [ "$total_proxy" -gt 0 ]; then
            info "✓ All kube-proxy pods are running ($running_proxy/$total_proxy)"
        else
            warn "⚠️  Some kube-proxy pods are not running ($running_proxy/$total_proxy)"
        fi
    fi
}

# Main execution
main() {
    # Check current state
    if check_compatibility_issues; then
        info "No iptables compatibility issues detected"
        
        # Still check the backend configuration
        if detect_iptables_backend; then
            info "System is already using legacy iptables backend"
        else
            warn "System is using nftables backend but no immediate issues detected"
            echo "Consider switching to legacy iptables for better Kubernetes compatibility"
        fi
        
        return 0
    fi
    
    error "iptables/nftables compatibility issues detected"
    
    # Detect current backend
    if detect_iptables_backend; then
        warn "Legacy iptables backend detected but still having issues"
    else
        info "nftables backend detected - this may be causing the compatibility issues"
    fi
    
    # Apply fixes
    info "Applying iptables compatibility fixes..."
    
    # Fix the iptables backend
    fix_iptables_backend
    
    # Configure kube-proxy
    configure_kube_proxy_iptables
    
    # Restart services
    restart_services
    
    # Validate the fix
    echo
    info "Validating the fix..."
    if validate_fix; then
        info "🎉 iptables compatibility issues have been resolved!"
    else
        warn "Some issues may still persist. Manual intervention may be required."
        
        echo
        echo "Additional steps you can try:"
        echo "1. Reboot the system to ensure all changes take effect"
        echo "2. Manually restart kube-proxy: kubectl delete pods -n kube-system -l component=kube-proxy"
        echo "3. Check system-specific iptables configuration"
        echo "4. Consider using a different CNI if issues persist"
    fi
}

# Run main function
main "$@"
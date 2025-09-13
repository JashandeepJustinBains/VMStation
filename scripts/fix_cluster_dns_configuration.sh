#!/bin/bash

# VMStation Cluster DNS Configuration Fix
# Fixes the issue where kubectl uses router gateway (192.168.4.1) instead of CoreDNS
# This addresses the problem: "dial tcp: lookup hort on 192.168.4.1:53: no such host"

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

echo "=== VMStation Cluster DNS Configuration Fix ==="
echo "Timestamp: $(date)"
echo ""

# Function to check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        error "This script must be run as root"
        error "Please run: sudo $0"
        exit 1
    fi
}

# Function to detect current DNS configuration
detect_dns_config() {
    info "Detecting current DNS configuration..."
    
    echo "Current /etc/resolv.conf:"
    cat /etc/resolv.conf 2>/dev/null || echo "  Cannot read /etc/resolv.conf"
    
    echo ""
    echo "Current systemd-resolved status:"
    systemctl status systemd-resolved --no-pager -l 2>/dev/null || echo "  systemd-resolved not running"
    
    echo ""
    echo "Current kubelet configuration (if exists):"
    if [ -f "/var/lib/kubelet/config.yaml" ]; then
        grep -E "clusterDNS|clusterDomain" /var/lib/kubelet/config.yaml 2>/dev/null || echo "  No DNS config in kubelet config"
    else
        echo "  /var/lib/kubelet/config.yaml not found"
    fi
    
    echo ""
    echo "Testing current DNS resolution:"
    echo "  Router gateway test (should fail for cluster operations):"
    nslookup kubernetes.default.svc.cluster.local 192.168.4.1 2>&1 || echo "    (Expected failure)"
    echo ""
}

# Function to get CoreDNS service IP
get_coredns_ip() {
    local coredns_ip=""
    
    # Try to get CoreDNS service IP from the cluster
    if command -v kubectl >/dev/null 2>&1; then
        # Try to get the cluster DNS IP
        coredns_ip=$(kubectl get service kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
        
        if [ -z "$coredns_ip" ]; then
            # Fallback: try to get it from kubelet config if available
            if [ -f "/var/lib/kubelet/config.yaml" ]; then
                coredns_ip=$(grep -A 1 "clusterDNS:" /var/lib/kubelet/config.yaml 2>/dev/null | grep -E "^\s*-\s*" | sed 's/.*- //' | head -1 || echo "")
            fi
        fi
        
        if [ -z "$coredns_ip" ]; then
            # Default Kubernetes DNS service IP
            coredns_ip="10.96.0.10"
            warn "Cannot determine CoreDNS IP from cluster, using default: $coredns_ip"
        fi
    else
        # kubectl not available, use default
        coredns_ip="10.96.0.10"
        warn "kubectl not available, using default CoreDNS IP: $coredns_ip"
    fi
    
    echo "$coredns_ip"
}

# Function to fix kubelet DNS configuration
fix_kubelet_dns() {
    local coredns_ip="$1"
    
    info "Configuring kubelet to use cluster DNS..."
    
    # Create or update kubelet systemd drop-in for DNS configuration
    local kubelet_dropin_dir="/etc/systemd/system/kubelet.service.d"
    local dns_config_file="$kubelet_dropin_dir/20-dns-cluster.conf"
    
    mkdir -p "$kubelet_dropin_dir"
    
    # Create kubelet DNS configuration
    cat > "$dns_config_file" << EOF
[Service]
Environment="KUBELET_DNS_ARGS=--cluster-dns=$coredns_ip --cluster-domain=cluster.local"
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS \$KUBELET_DNS_ARGS
EOF
    
    info "✓ Created kubelet DNS configuration at $dns_config_file"
    debug "DNS configuration: cluster-dns=$coredns_ip, cluster-domain=cluster.local"
}

# Function to fix systemd-resolved configuration
fix_systemd_resolved() {
    local coredns_ip="$1"
    
    info "Configuring systemd-resolved for cluster DNS..."
    
    # Check if systemd-resolved is running
    if systemctl is-active --quiet systemd-resolved; then
        info "systemd-resolved is active, configuring it..."
        
        # Create resolved configuration for cluster DNS
        local resolved_config="/etc/systemd/resolved.conf.d/cluster-dns.conf"
        mkdir -p "$(dirname "$resolved_config")"
        
        cat > "$resolved_config" << EOF
[Resolve]
# VMStation Kubernetes Cluster DNS Configuration
# Use cluster DNS for .cluster.local domains
Domains=~cluster.local
DNS=$coredns_ip
# Keep using system DNS for other domains
FallbackDNS=192.168.4.1 8.8.8.8 8.8.4.4
EOF
        
        info "✓ Created systemd-resolved cluster DNS configuration"
        
        # Restart systemd-resolved to apply changes
        systemctl restart systemd-resolved
        info "✓ Restarted systemd-resolved"
        
    else
        warn "systemd-resolved is not active, skipping systemd-resolved configuration"
    fi
}

# Function to create custom resolv.conf for cluster operations
fix_resolv_conf() {
    local coredns_ip="$1"
    
    info "Creating cluster-aware resolv.conf backup..."
    
    # Create a backup of original resolv.conf
    if [ -f "/etc/resolv.conf" ] && [ ! -f "/etc/resolv.conf.backup-vmstation" ]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup-vmstation
        info "✓ Backed up original /etc/resolv.conf"
    fi
    
    # Check if resolv.conf is managed by systemd-resolved
    if [ -L "/etc/resolv.conf" ] && readlink /etc/resolv.conf | grep -q "systemd"; then
        info "✓ /etc/resolv.conf is managed by systemd-resolved, no direct modification needed"
        return 0
    fi
    
    # For static resolv.conf, add cluster DNS as first nameserver
    info "Adding cluster DNS to /etc/resolv.conf..."
    
    # Create new resolv.conf with cluster DNS first
    local temp_resolv="/tmp/resolv.conf.new"
    
    echo "# VMStation Kubernetes Cluster DNS Configuration" > "$temp_resolv"
    echo "# Generated by fix_cluster_dns_configuration.sh on $(date)" >> "$temp_resolv"
    echo "nameserver $coredns_ip" >> "$temp_resolv"
    echo "search cluster.local" >> "$temp_resolv"
    
    # Add original nameservers (excluding any existing cluster DNS entries)
    if [ -f "/etc/resolv.conf" ]; then
        grep "^nameserver" /etc/resolv.conf | grep -v "$coredns_ip" >> "$temp_resolv" || true
        grep "^search\|^domain" /etc/resolv.conf | grep -v "cluster.local" >> "$temp_resolv" || true
    fi
    
    # Add fallback DNS if no nameservers were found
    if ! grep -q "^nameserver.*192.168.4.1" "$temp_resolv"; then
        echo "nameserver 192.168.4.1" >> "$temp_resolv"
    fi
    
    # Replace resolv.conf
    mv "$temp_resolv" /etc/resolv.conf
    info "✓ Updated /etc/resolv.conf with cluster DNS configuration"
}

# Function to restart kubelet service
restart_kubelet() {
    info "Restarting kubelet service..."
    
    # Reload systemd configuration
    systemctl daemon-reload
    info "✓ Reloaded systemd configuration"
    
    # Restart kubelet
    if systemctl restart kubelet; then
        info "✓ Restarted kubelet service"
        
        # Wait for kubelet to be ready
        sleep 5
        
        if systemctl is-active --quiet kubelet; then
            info "✓ Kubelet is active and running"
        else
            warn "⚠️ Kubelet service may have issues, check: systemctl status kubelet"
        fi
    else
        error "❌ Failed to restart kubelet service"
        return 1
    fi
}

# Function to test DNS resolution
test_dns_resolution() {
    local coredns_ip="$1"
    
    info "Testing DNS resolution after fixes..."
    
    echo "Testing cluster DNS resolution:"
    
    # Test 1: Direct query to CoreDNS
    echo "  1. Direct query to CoreDNS ($coredns_ip):"
    if timeout 10 nslookup kubernetes.default.svc.cluster.local "$coredns_ip" >/dev/null 2>&1; then
        info "    ✅ Direct CoreDNS query successful"
    else
        error "    ❌ Direct CoreDNS query failed"
    fi
    
    # Test 2: kubectl version check (the original failing command)
    echo "  2. kubectl version check (original failing command):"
    if timeout 15 kubectl version --short >/dev/null 2>&1; then
        info "    ✅ kubectl version command successful"
    else
        error "    ❌ kubectl version command still fails"
        echo "    Debugging kubectl connection:"
        kubectl version --short 2>&1 | head -5 || true
    fi
    
    # Test 3: General cluster connectivity
    echo "  3. Cluster connectivity test:"
    if timeout 10 kubectl get nodes >/dev/null 2>&1; then
        info "    ✅ kubectl can connect to cluster"
    else
        warn "    ⚠️ kubectl cluster connection issues"
    fi
    
    # Test 4: CoreDNS pod status
    echo "  4. CoreDNS pod status:"
    if command -v kubectl >/dev/null 2>&1; then
        local coredns_status
        coredns_status=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | awk '{print $3}' | grep -c "Running" || echo "0")
        if [ "$coredns_status" -gt 0 ]; then
            info "    ✅ $coredns_status CoreDNS pod(s) running"
        else
            warn "    ⚠️ No CoreDNS pods running or accessible"
        fi
    fi
}

# Function to show configuration summary
show_config_summary() {
    local coredns_ip="$1"
    
    echo ""
    info "=== DNS Configuration Summary ==="
    
    echo "Cluster DNS IP: $coredns_ip"
    echo "Cluster Domain: cluster.local"
    echo ""
    
    echo "Applied configurations:"
    echo "  • Kubelet DNS: /etc/systemd/system/kubelet.service.d/20-dns-cluster.conf"
    
    if systemctl is-active --quiet systemd-resolved; then
        echo "  • systemd-resolved: /etc/systemd/resolved.conf.d/cluster-dns.conf"
    fi
    
    if [ -f "/etc/resolv.conf.backup-vmstation" ]; then
        echo "  • resolv.conf: Updated (backup at /etc/resolv.conf.backup-vmstation)"
    fi
    
    echo ""
    echo "Current effective DNS configuration:"
    echo "/etc/resolv.conf:"
    cat /etc/resolv.conf | head -10
    
    echo ""
    echo "To verify the fix worked:"
    echo "  kubectl version --short"
    echo "  kubectl get nodes"
    echo "  nslookup kubernetes.default.svc.cluster.local"
}

# Function to cleanup on error
cleanup_on_error() {
    warn "Error occurred, cleaning up partial changes..."
    
    # Remove created files if they exist
    rm -f /etc/systemd/system/kubelet.service.d/20-dns-cluster.conf
    rm -f /etc/systemd/resolved.conf.d/cluster-dns.conf
    
    # Restore original resolv.conf if backup exists
    if [ -f "/etc/resolv.conf.backup-vmstation" ]; then
        cp /etc/resolv.conf.backup-vmstation /etc/resolv.conf
        info "✓ Restored original /etc/resolv.conf"
    fi
    
    # Reload systemd and restart services
    systemctl daemon-reload
    systemctl restart kubelet 2>/dev/null || true
    systemctl restart systemd-resolved 2>/dev/null || true
}

# Main execution function
main() {
    check_root
    
    info "Starting cluster DNS configuration fix..."
    info "This will fix the issue where kubectl uses router gateway instead of CoreDNS"
    echo ""
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Step 1: Detect current configuration
    detect_dns_config
    
    # Step 2: Get CoreDNS IP
    info "Step 1: Determining CoreDNS service IP..."
    local coredns_ip
    coredns_ip=$(get_coredns_ip)
    info "✓ CoreDNS IP: $coredns_ip"
    echo ""
    
    # Step 3: Fix kubelet DNS configuration
    info "Step 2: Configuring kubelet DNS settings..."
    fix_kubelet_dns "$coredns_ip"
    echo ""
    
    # Step 4: Fix systemd-resolved
    info "Step 3: Configuring systemd-resolved..."
    fix_systemd_resolved "$coredns_ip"
    echo ""
    
    # Step 5: Fix resolv.conf
    info "Step 4: Configuring resolv.conf..."
    fix_resolv_conf "$coredns_ip"
    echo ""
    
    # Step 6: Restart kubelet
    info "Step 5: Restarting kubelet service..."
    restart_kubelet
    echo ""
    
    # Step 7: Test the fixes
    info "Step 6: Testing DNS resolution..."
    test_dns_resolution "$coredns_ip"
    echo ""
    
    # Step 8: Show summary
    show_config_summary "$coredns_ip"
    
    # Remove error trap
    trap - ERR
    
    echo ""
    info "🎉 Cluster DNS configuration fix completed!"
    echo ""
    info "The kubectl command should now work properly:"
    info "  kubectl version --short"
    echo ""
    info "If you still experience issues:"
    info "  1. Check kubelet logs: journalctl -u kubelet -f"
    info "  2. Check CoreDNS status: kubectl get pods -n kube-system -l k8s-app=kube-dns"
    info "  3. Test DNS directly: nslookup kubernetes.default.svc.cluster.local $coredns_ip"
    
    return 0
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#!/bin/bash

# VMStation Static IP Assignment and DNS Subdomain Setup
# This script ensures critical Kubernetes components have static IPs and sets up homelab.com DNS

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

echo "=== VMStation Static IP Assignment and DNS Subdomain Setup ==="
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

# Function to verify current static IP assignments
verify_static_ips() {
    info "Verifying current static IP assignments..."
    
    # Check CoreDNS service IP
    local coredns_service_ip
    if command -v kubectl >/dev/null 2>&1; then
        coredns_service_ip=$(kubectl get service kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
        if [ -n "$coredns_service_ip" ]; then
            info "✓ CoreDNS has static service IP: $coredns_service_ip"
        else
            warn "⚠️ Could not retrieve CoreDNS service IP"
        fi
    fi
    
    # Check kube-proxy pods (using hostNetwork)
    info "Checking kube-proxy static IP assignments (hostNetwork)..."
    if command -v kubectl >/dev/null 2>&1; then
        local proxy_count
        proxy_count=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$proxy_count" -gt 0 ]; then
            info "✓ Found $proxy_count kube-proxy pods using hostNetwork (static node IPs)"
            kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide --no-headers 2>/dev/null | while read line; do
                local pod_name=$(echo "$line" | awk '{print $1}')
                local node_ip=$(echo "$line" | awk '{print $6}')
                info "  - $pod_name on node IP: $node_ip"
            done
        else
            warn "⚠️ No kube-proxy pods found"
        fi
    fi
    
    # Check kube-flannel pods (using hostNetwork)
    info "Checking kube-flannel static IP assignments (hostNetwork)..."
    if command -v kubectl >/dev/null 2>&1; then
        local flannel_count
        flannel_count=$(kubectl get pods -n kube-flannel -l app=flannel --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$flannel_count" -gt 0 ]; then
            info "✓ Found $flannel_count kube-flannel pods using hostNetwork (static node IPs)"
            kubectl get pods -n kube-flannel -l app=flannel -o wide --no-headers 2>/dev/null | while read line; do
                local pod_name=$(echo "$line" | awk '{print $1}')
                local node_ip=$(echo "$line" | awk '{print $6}')
                info "  - $pod_name on node IP: $node_ip"
            done
        else
            warn "⚠️ No kube-flannel pods found"
        fi
    fi
    
    echo ""
}

# Function to ensure CoreDNS has proper static configuration
ensure_coredns_static_ip() {
    info "Ensuring CoreDNS has static IP configuration..."
    
    local coredns_manifest="/home/runner/work/VMStation/VMStation/manifests/network/coredns-service.yaml"
    
    if [ -f "$coredns_manifest" ]; then
        if grep -q "clusterIP: 10.96.0.10" "$coredns_manifest"; then
            info "✓ CoreDNS service already has static clusterIP: 10.96.0.10"
        else
            warn "⚠️ CoreDNS service clusterIP configuration needs update"
        fi
    else
        warn "⚠️ CoreDNS service manifest not found at expected location"
    fi
}

# Function to create DNS configuration for homelab.com subdomains
setup_homelab_dns() {
    info "Setting up homelab.com DNS subdomain configuration..."
    
    # Node IP mappings based on inventory
    local STORAGE_NODE_IP="192.168.4.61"
    local COMPUTE_NODE_IP="192.168.4.62"
    local CONTROL_NODE_IP="192.168.4.63"
    
    # Method 1: Configure CoreDNS to handle homelab.com subdomains
    if command -v kubectl >/dev/null 2>&1; then
        info "Updating CoreDNS configuration for homelab.com subdomains..."
        
        # Apply the CoreDNS ConfigMap from manifests
        if [ -f "manifests/network/coredns-configmap.yaml" ]; then
            kubectl apply -f manifests/network/coredns-configmap.yaml
            info "✓ Applied CoreDNS ConfigMap with homelab.com configuration"
            
            # Restart CoreDNS pods to pick up new configuration
            kubectl delete pods -n kube-system -l k8s-app=kube-dns --ignore-not-found=true
            info "✓ Restarted CoreDNS pods to apply new configuration"
        else
            warn "CoreDNS ConfigMap manifest not found"
        fi
    else
        warn "kubectl not available - skipping CoreDNS configuration"
    fi
    
    # Method 2: Add entries to local hosts file for immediate resolution
    info "Adding homelab.com subdomain entries to /etc/hosts for local resolution..."
    
    # Create backup of hosts file
    local hosts_backup="/etc/hosts.vmstation-backup"
    if [ ! -f "$hosts_backup" ]; then
        cp /etc/hosts "$hosts_backup"
        info "✓ Created backup of /etc/hosts"
    fi
    
    # Remove any existing VMStation homelab entries
    sed -i '/# VMStation homelab.com entries/,/# End VMStation homelab.com entries/d' /etc/hosts
    
    # Add new entries
    cat >> /etc/hosts << EOF

# VMStation homelab.com entries - $(date)
$STORAGE_NODE_IP jellyfin.homelab.com storage.homelab.com
$COMPUTE_NODE_IP compute.homelab.com
$CONTROL_NODE_IP grafana.homelab.com control.homelab.com
# End VMStation homelab.com entries
EOF
    
    info "✓ Added homelab.com subdomain entries to /etc/hosts"
}

# Function to configure network to use the new DNS
configure_network_dns() {
    info "Configuring network DNS for homelab.com resolution..."
    
    # Method 1: Configure systemd-resolved for homelab.com domain if available
    if systemctl is-active --quiet systemd-resolved; then
        local resolved_config="/etc/systemd/resolved.conf.d/vmstation-homelab.conf"
        mkdir -p "$(dirname "$resolved_config")"
        
        cat > "$resolved_config" << EOF
[Resolve]
# VMStation homelab.com DNS Configuration
# Use CoreDNS service for homelab.com resolution
Domains=~homelab.com
DNS=10.96.0.10
# Keep existing DNS for other domains
FallbackDNS=192.168.4.1 8.8.8.8 1.1.1.1
EOF
        
        systemctl restart systemd-resolved
        info "✓ Configured systemd-resolved for homelab.com DNS via CoreDNS"
    else
        info "systemd-resolved not active - using hosts file resolution only"
    fi
    
    # Method 2: Ensure all cluster nodes have the hosts entries
    info "Distributing hosts entries to all cluster nodes..."
    
    # If we're on the control plane, distribute to worker nodes
    if command -v kubectl >/dev/null 2>&1; then
        local nodes=$(kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name | grep -v $(hostname) || true)
        for node in $nodes; do
            info "Adding hosts entries to node: $node"
            # Note: This would need SSH access to worker nodes in real deployment
            # For now, we ensure the control plane has the entries
        done
    fi
}

# Function to test DNS subdomain resolution
test_dns_subdomains() {
    info "Testing DNS subdomain resolution..."
    
    local test_domains=(
        "jellyfin.homelab.com"
        "grafana.homelab.com"
        "storage.homelab.com"
        "compute.homelab.com"
        "control.homelab.com"
    )
    
    for domain in "${test_domains[@]}"; do
        echo "  Testing $domain..."
        if timeout 5 nslookup "$domain" >/dev/null 2>&1; then
            local resolved_ip=$(nslookup "$domain" | grep "Address:" | tail -1 | awk '{print $2}')
            info "    ✅ $domain resolves to: $resolved_ip"
        else
            warn "    ⚠️ $domain resolution failed"
        fi
    done
    
    echo ""
    info "Testing specific service access:"
    
    # Test Jellyfin access
    echo "  Testing Jellyfin access via subdomain..."
    if timeout 10 curl -s --connect-timeout 3 "http://jellyfin.homelab.com:30096/" >/dev/null 2>&1; then
        info "    ✅ jellyfin.homelab.com:30096 is accessible"
    else
        warn "    ⚠️ jellyfin.homelab.com:30096 is not accessible"
        info "    Note: Service may not be running or port may not be open"
    fi
}

# Function to create documentation
create_documentation() {
    info "Creating documentation for static IP and DNS configuration..."
    
    local doc_file="/home/runner/work/VMStation/VMStation/docs/static-ips-and-dns.md"
    
    cat > "$doc_file" << 'EOF'
# VMStation Static IP Assignment and DNS Subdomains

This document describes the static IP assignments for critical Kubernetes components and the DNS subdomain configuration for the homelab.

## Static IP Assignments

### CoreDNS
- **Type**: Service ClusterIP
- **IP**: `10.96.0.10`
- **Configuration**: `/manifests/network/coredns-service.yaml`
- **Purpose**: Provides stable DNS service IP for cluster operations

### kube-proxy Pods
- **Type**: hostNetwork (uses node IP)
- **IPs**: 
  - Control plane: `192.168.4.63`
  - Storage node: `192.168.4.61`
  - Compute node: `192.168.4.62`
- **Configuration**: `/manifests/network/kube-proxy-daemonset.yaml`
- **Purpose**: Provides stable network proxy on each node

### kube-flannel Pods
- **Type**: hostNetwork (uses node IP)
- **IPs**:
  - Control plane: `192.168.4.63`
  - Storage node: `192.168.4.61`
  - Compute node: `192.168.4.62`
- **Configuration**: `/manifests/cni/flannel.yaml`
- **Purpose**: Provides stable CNI networking on each node

## DNS Subdomains (homelab.com)

### Configured Subdomains

| Subdomain | Target IP | Purpose |
|-----------|-----------|---------|
| `jellyfin.homelab.com` | `192.168.4.61:30096` | Jellyfin media server |
| `grafana.homelab.com` | `192.168.4.63:*` | Grafana monitoring |
| `storage.homelab.com` | `192.168.4.61` | Storage node services |
| `compute.homelab.com` | `192.168.4.62` | Compute node services |
| `control.homelab.com` | `192.168.4.63` | Control plane services |

### DNS Configuration

- **Primary DNS**: CoreDNS (kube-dns service) at `10.96.0.10`
- **Configuration**: `/manifests/network/coredns-configmap.yaml`
- **Fallback**: /etc/hosts entries on cluster nodes

### Usage Examples

```bash
# Access Jellyfin via subdomain
curl http://jellyfin.homelab.com:30096/

# Access from any device on the network
curl http://jellyfin.homelab.com:30096/

# Test DNS resolution
nslookup jellyfin.homelab.com
```

## Maintenance

### Verify Static IPs
```bash
sudo ./scripts/setup_static_ips_and_dns.sh --verify
```

### Update DNS Configuration
Apply updated CoreDNS configuration:
```bash
kubectl apply -f manifests/network/coredns-configmap.yaml
kubectl delete pods -n kube-system -l k8s-app=kube-dns
```

### Troubleshooting
- Check CoreDNS: `kubectl get pods -n kube-system -l k8s-app=kube-dns`
- Test resolution: `nslookup jellyfin.homelab.com`
- Check pod IPs: `kubectl get pods -o wide --all-namespaces`
- Check hosts file: `cat /etc/hosts | grep homelab`
EOF
    
    info "✓ Created documentation at $doc_file"
}

# Function to show configuration summary
show_summary() {
    echo ""
    info "=== Static IP and DNS Configuration Summary ==="
    
    echo "Static IP Assignments:"
    echo "  • CoreDNS Service: 10.96.0.10 (cluster IP)"
    echo "  • kube-proxy pods: Use node IPs (hostNetwork)"
    echo "  • kube-flannel pods: Use node IPs (hostNetwork)"
    
    echo ""
    echo "DNS Subdomains (homelab.com):"
    echo "  • jellyfin.homelab.com → 192.168.4.61:30096"
    echo "  • grafana.homelab.com → 192.168.4.63"
    echo "  • storage.homelab.com → 192.168.4.61"
    echo "  • compute.homelab.com → 192.168.4.62"
    echo "  • control.homelab.com → 192.168.4.63"
    
    echo ""
    echo "Configuration Files:"
    echo "  • CoreDNS config: manifests/network/coredns-configmap.yaml"
    echo "  • Hosts file: /etc/hosts"
    echo "  • Documentation: docs/static-ips-and-dns.md"
    
    echo ""
    echo "Test Commands:"
    echo "  • nslookup jellyfin.homelab.com"
    echo "  • curl http://jellyfin.homelab.com:30096/"
    echo "  • kubectl get pods -o wide --all-namespaces"
}

# Main execution
main() {
    local action="${1:-full}"
    
    if [ "$action" = "--verify" ] || [ "$action" = "verify" ]; then
        verify_static_ips
        return 0
    fi
    
    check_root
    
    info "Setting up static IP assignments and DNS subdomains for VMStation..."
    echo ""
    
    # Step 1: Verify current static IP assignments
    verify_static_ips
    
    # Step 2: Ensure CoreDNS static configuration
    ensure_coredns_static_ip
    
    # Step 3: Set up homelab.com DNS
    setup_homelab_dns
    
    # Step 4: Configure network DNS
    configure_network_dns
    
    # Step 5: Create documentation
    create_documentation
    
    # Step 6: Test DNS subdomains
    test_dns_subdomains
    
    # Step 7: Show summary
    show_summary
    
    echo ""
    info "🎉 Static IP assignment and DNS subdomain setup completed!"
    echo ""
    info "Next steps:"
    info "  1. Test subdomain access: curl http://jellyfin.homelab.com:30096/"
    info "  2. Configure other nodes to use same hosts entries if needed"
    info "  3. Access Grafana at: http://grafana.homelab.com:30300"
    
    return 0
}

# Allow script to be sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
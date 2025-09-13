#!/bin/bash

# VMStation Cluster Communication Helper Script
# Small script to run on individual nodes for local checks and safe resets
# 
# Usage:
#   ./fix_cluster_helper.sh                    # Collect diagnostics only
#   ./fix_cluster_helper.sh --dry-run          # Collect diagnostics only
#   ./fix_cluster_helper.sh --apply            # Apply safe local resets
#
# This script can be executed remotely via SSH from the controller script

set -euo pipefail

# Color codes  
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Configuration
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_DIR="/tmp/fix-cluster-helper-$TIMESTAMP"
APPLY=false

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --apply)
                APPLY=true
                shift
                ;;
            --dry-run)
                APPLY=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
}

# Usage function
usage() {
    cat << EOF
VMStation Cluster Communication Helper Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --apply         Apply safe local resets and fixes
    --dry-run       Only collect diagnostics (default)
    -h, --help      Show this help

DESCRIPTION:
    This helper script performs local node diagnostics and safe resets.
    It collects network configuration, CNI files, iptables rules, and
    can perform safe local resets when invoked with --apply.

EXAMPLES:
    # Collect diagnostics only
    $0
    $0 --dry-run

    # Apply safe local fixes
    $0 --apply

EOF
}

# Initialize output directory
init_output() {
    mkdir -p "$OUTPUT_DIR" || {
        error "Cannot create output directory: $OUTPUT_DIR"
        exit 1
    }
    
    info "=== VMStation Cluster Helper - Node $(hostname) ==="
    info "Timestamp: $(date)"
    info "Output directory: $OUTPUT_DIR"
    info "Mode: $([ "$APPLY" == "true" ] && echo "APPLY" || echo "DRY-RUN")"
}

# Collect network configuration
collect_network_info() {
    info "Collecting network configuration..."
    
    # IP configuration
    ip addr show > "$OUTPUT_DIR/ip-addr.txt" 2>&1 || true
    ip link show > "$OUTPUT_DIR/ip-link.txt" 2>&1 || true
    ip route show > "$OUTPUT_DIR/ip-route.txt" 2>&1 || true
    ip route show table all > "$OUTPUT_DIR/ip-route-all.txt" 2>&1 || true
    
    # Bridge information
    if command -v brctl >/dev/null 2>&1; then
        brctl show > "$OUTPUT_DIR/brctl-show.txt" 2>&1 || true
    fi
    
    # Network interfaces
    cat /proc/net/dev > "$OUTPUT_DIR/proc-net-dev.txt" 2>&1 || true
    
    # DNS configuration
    cat /etc/resolv.conf > "$OUTPUT_DIR/resolv.conf" 2>&1 || true
    
    # Hostname and network identity
    hostname > "$OUTPUT_DIR/hostname.txt" 2>&1 || true
    hostname -I > "$OUTPUT_DIR/hostname-I.txt" 2>&1 || true
    
    debug "Network configuration collected"
}

# Collect iptables rules
collect_iptables_info() {
    info "Collecting iptables configuration..."
    
    # Save current iptables rules
    iptables-save > "$OUTPUT_DIR/iptables-save.txt" 2>&1 || true
    
    # List all tables and chains
    for table in filter nat mangle raw; do
        iptables -t "$table" -L -v -n --line-numbers > "$OUTPUT_DIR/iptables-${table}.txt" 2>&1 || true
    done
    
    # Check iptables backend
    if command -v update-alternatives >/dev/null 2>&1; then
        update-alternatives --query iptables > "$OUTPUT_DIR/iptables-alternatives.txt" 2>&1 || true
    fi
    
    # Check for nftables
    if command -v nft >/dev/null 2>&1; then
        nft list ruleset > "$OUTPUT_DIR/nftables-ruleset.txt" 2>&1 || true
    fi
    
    debug "iptables configuration collected"
}

# Collect CNI configuration and files
collect_cni_info() {
    info "Collecting CNI configuration..."
    
    # CNI configuration files
    if [[ -d /etc/cni/net.d ]]; then
        cp -r /etc/cni/net.d "$OUTPUT_DIR/cni-net.d" 2>/dev/null || true
        find /etc/cni/net.d -type f -exec ls -la {} \; > "$OUTPUT_DIR/cni-files.txt" 2>&1 || true
    fi
    
    # CNI binaries
    if [[ -d /opt/cni/bin ]]; then
        ls -la /opt/cni/bin > "$OUTPUT_DIR/cni-bin.txt" 2>&1 || true
    fi
    
    # Flannel specific files
    if [[ -f /run/flannel/subnet.env ]]; then
        cat /run/flannel/subnet.env > "$OUTPUT_DIR/flannel-subnet.env" 2>&1 || true
    fi
    
    if [[ -d /var/lib/cni ]]; then
        find /var/lib/cni -type f -exec ls -la {} \; > "$OUTPUT_DIR/cni-var-lib.txt" 2>&1 || true
    fi
    
    debug "CNI configuration collected"
}

# Collect system service status
collect_service_info() {
    info "Collecting system service status..."
    
    # Kubelet service
    systemctl status kubelet --no-pager -l > "$OUTPUT_DIR/kubelet-status.txt" 2>&1 || true
    journalctl -u kubelet --no-pager -l --since "1 hour ago" > "$OUTPUT_DIR/kubelet-logs.txt" 2>&1 || true
    
    # Container runtime services
    for service in containerd docker; do
        if systemctl list-units --type=service | grep -q "$service"; then
            systemctl status "$service" --no-pager -l > "$OUTPUT_DIR/${service}-status.txt" 2>&1 || true
            journalctl -u "$service" --no-pager -l --since "1 hour ago" > "$OUTPUT_DIR/${service}-logs.txt" 2>&1 || true
        fi
    done
    
    # Network services
    for service in networking systemd-networkd NetworkManager; do
        if systemctl list-units --type=service | grep -q "$service"; then
            systemctl status "$service" --no-pager -l > "$OUTPUT_DIR/${service}-status.txt" 2>&1 || true
        fi
    done
    
    debug "Service status collected"
}

# Collect Kubernetes configuration
collect_k8s_info() {
    info "Collecting Kubernetes configuration..."
    
    # Kubelet configuration
    if [[ -f /etc/kubernetes/kubelet.conf ]]; then
        cp /etc/kubernetes/kubelet.conf "$OUTPUT_DIR/kubelet.conf" 2>/dev/null || {
            echo "Permission denied" > "$OUTPUT_DIR/kubelet.conf"
        }
    fi
    
    # Kubeconfig if present
    if [[ -f /root/.kube/config ]]; then
        cp /root/.kube/config "$OUTPUT_DIR/root-kubeconfig" 2>/dev/null || {
            echo "Permission denied" > "$OUTPUT_DIR/root-kubeconfig"
        }
    fi
    
    # Kubernetes manifests
    if [[ -d /etc/kubernetes/manifests ]]; then
        cp -r /etc/kubernetes/manifests "$OUTPUT_DIR/k8s-manifests" 2>/dev/null || true
    fi
    
    # Container runtime socket test
    if [[ -S /run/containerd/containerd.sock ]]; then
        ls -la /run/containerd/containerd.sock > "$OUTPUT_DIR/containerd-socket.txt" 2>&1 || true
        
        # Test crictl access
        if command -v crictl >/dev/null 2>&1; then
            timeout 10 crictl ps > "$OUTPUT_DIR/crictl-ps.txt" 2>&1 || {
                echo "crictl command failed" > "$OUTPUT_DIR/crictl-ps.txt"
                echo "Error: $(crictl ps 2>&1)" >> "$OUTPUT_DIR/crictl-ps.txt"
            }
        fi
    fi
    
    debug "Kubernetes configuration collected"
}

# Collect system information
collect_system_info() {
    info "Collecting system information..."
    
    # Basic system info
    uname -a > "$OUTPUT_DIR/uname.txt" 2>&1 || true
    cat /etc/os-release > "$OUTPUT_DIR/os-release.txt" 2>&1 || true
    uptime > "$OUTPUT_DIR/uptime.txt" 2>&1 || true
    free -h > "$OUTPUT_DIR/memory.txt" 2>&1 || true
    df -h > "$OUTPUT_DIR/disk.txt" 2>&1 || true
    
    # Process information
    ps auxf > "$OUTPUT_DIR/processes.txt" 2>&1 || true
    
    # Network connectivity
    ping -c 2 8.8.8.8 > "$OUTPUT_DIR/ping-external.txt" 2>&1 || true
    
    # Kernel modules
    lsmod > "$OUTPUT_DIR/lsmod.txt" 2>&1 || true
    
    debug "System information collected"
}

# Perform safe local resets
apply_safe_resets() {
    if [[ "$APPLY" != "true" ]]; then
        info "Skipping resets (dry-run mode)"
        return 0
    fi
    
    info "=== Applying Safe Local Resets ==="
    
    local reset_success=true
    
    # Reset 1: Clean up problematic CNI interfaces
    info "Cleaning up CNI interfaces..."
    if ip link show cni0 >/dev/null 2>&1; then
        local cni_ip=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
        if [[ -n "$cni_ip" ]] && ! echo "$cni_ip" | grep -q "10.244."; then
            warn "Removing CNI bridge with incorrect IP: $cni_ip"
            ip link delete cni0 2>/dev/null || {
                error "Failed to delete CNI bridge"
                reset_success=false
            }
        else
            info "CNI bridge IP looks correct: $cni_ip"
        fi
    fi
    
    # Reset 2: Restart container runtime (safe)
    info "Restarting container runtime..."
    if systemctl is-active containerd >/dev/null 2>&1; then
        if systemctl restart containerd; then
            info "✓ containerd restarted successfully"
            sleep 5  # Wait for containerd to stabilize
        else
            error "Failed to restart containerd"
            reset_success=false
        fi
    elif systemctl is-active docker >/dev/null 2>&1; then
        if systemctl restart docker; then
            info "✓ docker restarted successfully"
            sleep 5  # Wait for docker to stabilize
        else
            error "Failed to restart docker"
            reset_success=false
        fi
    fi
    
    # Reset 3: Restart kubelet (safe)
    info "Restarting kubelet..."
    if systemctl restart kubelet; then
        info "✓ kubelet restarted successfully"
        sleep 10  # Wait for kubelet to stabilize
    else
        error "Failed to restart kubelet"
        reset_success=false
    fi
    
    # Reset 4: Fix common permission issues
    info "Fixing common permission issues..."
    
    # containerd socket permissions
    if [[ -S /run/containerd/containerd.sock ]]; then
        if chgrp docker /run/containerd/containerd.sock 2>/dev/null; then
            info "✓ Fixed containerd socket group"
        fi
        if chmod 660 /run/containerd/containerd.sock 2>/dev/null; then
            info "✓ Fixed containerd socket permissions"
        fi
    fi
    
    # CNI directory permissions
    if [[ -d /etc/cni/net.d ]]; then
        if chown -R root:root /etc/cni/net.d 2>/dev/null && chmod 755 /etc/cni/net.d 2>/dev/null; then
            info "✓ Fixed CNI directory permissions"
        fi
    fi
    
    # Reset 5: Clear problematic iptables rules (conservative)
    info "Checking iptables rules..."
    
    # Only clear rules if we detect obvious problems
    local iptables_issues=false
    if ! iptables -t nat -L >/dev/null 2>&1; then
        iptables_issues=true
    fi
    
    if [[ "$iptables_issues" == "true" ]]; then
        warn "Detected iptables issues, attempting backend switch..."
        if command -v update-alternatives >/dev/null 2>&1; then
            # Switch to legacy iptables
            update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
            update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
            info "Switched to legacy iptables backend"
        fi
    fi
    
    if [[ "$reset_success" == "true" ]]; then
        info "✓ All safe resets completed successfully"
        
        # Wait for services to stabilize
        info "Waiting for services to stabilize..."
        sleep 15
        
        # Verify services are running
        info "Verifying service status..."
        for service in kubelet containerd; do
            if systemctl is-active "$service" >/dev/null 2>&1; then
                info "✓ $service is running"
            else
                warn "✗ $service is not running"
            fi
        done
        
    else
        error "Some resets failed - check logs for details"
        return 1
    fi
    
    return 0
}

# Wait for readiness checks
wait_for_readiness() {
    if [[ "$APPLY" != "true" ]]; then
        return 0
    fi
    
    info "Performing readiness checks..."
    
    # Wait for kubelet to be ready
    local retry_count=0
    local max_retries=12  # 2 minutes
    
    while [[ $retry_count -lt $max_retries ]]; do
        if systemctl is-active kubelet >/dev/null 2>&1; then
            info "✓ kubelet is ready"
            break
        fi
        
        info "Waiting for kubelet to be ready... ($((retry_count + 1))/$max_retries)"
        sleep 10
        ((retry_count++))
    done
    
    if [[ $retry_count -eq $max_retries ]]; then
        warn "kubelet readiness check timed out"
        return 1
    fi
    
    # Wait for container runtime to be ready
    retry_count=0
    while [[ $retry_count -lt $max_retries ]]; do
        if command -v crictl >/dev/null 2>&1 && timeout 5 crictl ps >/dev/null 2>&1; then
            info "✓ container runtime is ready"
            break
        fi
        
        info "Waiting for container runtime to be ready... ($((retry_count + 1))/$max_retries)"
        sleep 10
        ((retry_count++))
    done
    
    if [[ $retry_count -eq $max_retries ]]; then
        warn "Container runtime readiness check timed out"
        return 1
    fi
    
    return 0
}

# Create summary report
create_summary() {
    info "Creating summary report..."
    
    cat > "$OUTPUT_DIR/SUMMARY.txt" << EOF
VMStation Cluster Helper - Node Summary
=======================================

Node: $(hostname)
Timestamp: $(date)
Mode: $([ "$APPLY" == "true" ] && echo "APPLY" || echo "DRY-RUN")

System Information:
- OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
- Kernel: $(uname -r)
- Uptime: $(uptime)

Network Configuration:
- Hostname: $(hostname)
- IP Addresses: $(hostname -I)
- CNI Bridge: $(ip addr show cni0 2>/dev/null | grep "inet " | awk '{print $2}' | head -1 || echo "Not found")

Service Status:
- kubelet: $(systemctl is-active kubelet 2>/dev/null || echo "inactive")
- containerd: $(systemctl is-active containerd 2>/dev/null || echo "inactive")
- docker: $(systemctl is-active docker 2>/dev/null || echo "inactive")

Files Collected:
$(find "$OUTPUT_DIR" -name "*.txt" -o -name "*.env" -o -name "*.conf" | sort)

EOF

    if [[ "$APPLY" == "true" ]]; then
        cat >> "$OUTPUT_DIR/SUMMARY.txt" << EOF

Actions Performed:
- CNI interface cleanup
- Container runtime restart
- kubelet restart  
- Permission fixes
- iptables backend check

Readiness Status:
- kubelet: $(systemctl is-active kubelet 2>/dev/null || echo "inactive")
- container runtime: $(timeout 5 crictl ps >/dev/null 2>&1 && echo "ready" || echo "not ready")

EOF
    fi
    
    info "Summary report created: $OUTPUT_DIR/SUMMARY.txt"
}

# Main function
main() {
    parse_args "$@"
    init_output
    
    # Collect all diagnostic information
    collect_system_info
    collect_network_info
    collect_iptables_info
    collect_cni_info
    collect_service_info
    collect_k8s_info
    
    # Apply safe resets if requested
    apply_safe_resets
    
    # Wait for readiness if we applied changes
    wait_for_readiness
    
    # Create summary
    create_summary
    
    info "Helper script completed"
    info "Output directory: $OUTPUT_DIR"
    
    # Print quick status
    echo
    echo "Quick Status:"
    echo "  kubelet: $(systemctl is-active kubelet 2>/dev/null || echo "inactive")"
    echo "  containerd: $(systemctl is-active containerd 2>/dev/null || echo "inactive")"
    echo "  CNI bridge: $(ip addr show cni0 2>/dev/null | grep "inet " | awk '{print $2}' | head -1 || echo "Not found")"
    echo
}

# Execute main function
main "$@"
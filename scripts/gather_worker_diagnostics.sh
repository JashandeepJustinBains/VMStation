#!/bin/bash

# VMStation Worker Diagnostics Gathering Script
# Collects comprehensive diagnostic information from worker nodes

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

# Configuration
CONTROL_PLANE_IP="${1:-192.168.4.63}"
WORKER_NODES="${2:-192.168.4.61,192.168.4.62}"
OUTPUT_DIR="${3:-/tmp/worker-diagnostics-$(date +%Y%m%d-%H%M%S)}"
SSH_USER="${SSH_USER:-root}"
SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no"

echo "=== VMStation Worker Diagnostics Gathering ==="
echo "Timestamp: $(date)"
echo "Control plane: $CONTROL_PLANE_IP"
echo "Worker nodes: $WORKER_NODES"
echo "Output directory: $OUTPUT_DIR"
echo "SSH user: $SSH_USER"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Function to run command on remote host
run_remote() {
    local host="$1"
    local command="$2"
    local output_file="$3"
    
    info "Running on $host: $command"
    if ssh $SSH_OPTS "$SSH_USER@$host" "$command" > "$output_file" 2>&1; then
        debug "✓ Command completed successfully"
    else
        warn "Command failed or partially failed"
    fi
}

# Function to copy file from remote host
copy_remote() {
    local host="$1"
    local remote_path="$2"
    local local_path="$3"
    
    info "Copying from $host:$remote_path to $local_path"
    if scp $SSH_OPTS "$SSH_USER@$host:$remote_path" "$local_path" 2>/dev/null; then
        debug "✓ File copied successfully"
    else
        warn "File not found or copy failed: $remote_path"
        echo "File not found: $remote_path" > "$local_path"
    fi
}

# Function to gather diagnostics from a worker node
gather_worker_diagnostics() {
    local worker_ip="$1"
    local worker_dir="$OUTPUT_DIR/worker-$worker_ip"
    
    info "Gathering diagnostics from worker node: $worker_ip"
    mkdir -p "$worker_dir"
    
    # Basic system information
    info "Collecting basic system information..."
    run_remote "$worker_ip" "hostname; uname -a; uptime; free -h; df -h" "$worker_dir/system-info.txt"
    
    # Service status
    info "Collecting service status..."
    run_remote "$worker_ip" "
        echo '=== Kubelet Service ==='
        systemctl status kubelet --no-pager -l || true
        echo ''
        echo '=== Containerd Service ==='
        systemctl status containerd --no-pager -l || true
        echo ''
        echo '=== Docker Service (if present) ==='
        systemctl status docker --no-pager -l 2>/dev/null || echo 'Docker not installed'
    " "$worker_dir/service-status.txt"
    
    # Kubelet logs
    info "Collecting kubelet logs..."
    run_remote "$worker_ip" "journalctl -u kubelet --no-pager -l --since '24 hours ago'" "$worker_dir/kubelet.log"
    
    # Containerd logs
    info "Collecting containerd logs..."
    run_remote "$worker_ip" "journalctl -u containerd --no-pager -l --since '24 hours ago'" "$worker_dir/containerd.log"
    
    # Kubeadm join logs
    info "Collecting kubeadm join logs..."
    run_remote "$worker_ip" "find /tmp -name 'kubeadm-join-*.log' -type f -exec cat {} \;" "$worker_dir/kubeadm-join.log"
    
    # Manual join logs if present
    run_remote "$worker_ip" "[ -f /tmp/manual-kubeadm-join.log ] && cat /tmp/manual-kubeadm-join.log || echo 'No manual join log found'" "$worker_dir/manual-kubeadm-join.log"
    
    # Configuration files
    info "Collecting configuration files..."
    copy_remote "$worker_ip" "/etc/crictl.yaml" "$worker_dir/crictl.yaml"
    copy_remote "$worker_ip" "/etc/containerd/config.toml" "$worker_dir/containerd-config.toml"
    copy_remote "$worker_ip" "/etc/kubernetes/kubelet.conf" "$worker_dir/kubelet.conf"
    copy_remote "$worker_ip" "/var/lib/kubelet/config.yaml" "$worker_dir/kubelet-config.yaml"
    copy_remote "$worker_ip" "/var/lib/kubelet/kubeadm-flags.env" "$worker_dir/kubeadm-flags.env"
    
    # CNI configuration
    info "Collecting CNI configuration..."
    run_remote "$worker_ip" "ls -la /etc/cni/net.d/ && echo '---' && find /etc/cni/net.d/ -name '*.conflist' -o -name '*.conf' -exec echo 'File: {}' \; -exec cat {} \; -exec echo '' \;" "$worker_dir/cni-config.txt"
    
    # Runtime socket information
    info "Collecting runtime socket information..."
    run_remote "$worker_ip" "
        echo '=== Containerd Runtime Directory ==='
        ls -la /run/containerd/ 2>/dev/null || echo 'Directory not found'
        echo ''
        echo '=== Socket Permissions ==='
        if [ -S /run/containerd/containerd.sock ]; then
            stat /run/containerd/containerd.sock
            echo 'Socket owner/group:'
            ls -la /run/containerd/containerd.sock
        else
            echo 'Containerd socket not found'
        fi
        echo ''
        echo '=== Containerd Groups ==='
        getent group containerd || echo 'containerd group not found'
        echo ''
        echo '=== User Groups ==='
        groups root 2>/dev/null || echo 'Cannot check root user groups'
    " "$worker_dir/socket-info.txt"
    
    # CRI status and info
    info "Collecting CRI status..."
    run_remote "$worker_ip" "
        echo '=== Crictl Version ==='
        crictl version 2>/dev/null || echo 'crictl version failed'
        echo ''
        echo '=== CRI Info ==='
        crictl info 2>/dev/null || echo 'crictl info failed'
        echo ''
        echo '=== Container List ==='
        crictl ps -a 2>/dev/null || echo 'crictl ps failed'
        echo ''
        echo '=== Image List ==='
        crictl images 2>/dev/null || echo 'crictl images failed'
    " "$worker_dir/cri-status.txt"
    
    # Network configuration
    info "Collecting network configuration..."
    run_remote "$worker_ip" "
        echo '=== Network Interfaces ==='
        ip link show
        echo ''
        echo '=== Network Routes ==='
        ip route show
        echo ''
        echo '=== Iptables Rules (filter) ==='
        iptables -t filter -L -n -v 2>/dev/null || echo 'iptables failed'
        echo ''
        echo '=== Iptables Rules (nat) ==='
        iptables -t nat -L -n -v 2>/dev/null || echo 'iptables failed'
        echo ''
        echo '=== Kernel Modules ==='
        lsmod | grep -E 'br_netfilter|overlay|vxlan' || echo 'No relevant modules loaded'
        echo ''
        echo '=== Sysctl Network Parameters ==='
        sysctl net.bridge.bridge-nf-call-iptables 2>/dev/null || echo 'Parameter not set'
        sysctl net.bridge.bridge-nf-call-ip6tables 2>/dev/null || echo 'Parameter not set'
        sysctl net.ipv4.ip_forward 2>/dev/null || echo 'Parameter not set'
    " "$worker_dir/network-config.txt"
    
    # Filesystem information
    info "Collecting filesystem information..."
    run_remote "$worker_ip" "
        echo '=== Disk Usage ==='
        df -h
        echo ''
        echo '=== Kubernetes Directories ==='
        for dir in /var/lib/kubelet /var/lib/containerd /etc/kubernetes /opt/cni/bin /etc/cni/net.d; do
            echo \"Directory: \$dir\"
            if [ -d \"\$dir\" ]; then
                ls -la \"\$dir\" 2>/dev/null | head -20
                du -sh \"\$dir\" 2>/dev/null || echo 'Cannot calculate size'
            else
                echo 'Directory does not exist'
            fi
            echo ''
        done
        echo ''
        echo '=== CNI Plugin Binaries ==='
        ls -la /opt/cni/bin/ 2>/dev/null || echo 'CNI bin directory not found'
    " "$worker_dir/filesystem-info.txt"
    
    # Process information
    info "Collecting process information..."
    run_remote "$worker_ip" "
        echo '=== Kubernetes Processes ==='
        ps aux | grep -E 'kubelet|containerd|kube|flannel' | grep -v grep || echo 'No Kubernetes processes found'
        echo ''
        echo '=== Process Tree ==='
        pstree -p | grep -E 'kubelet|containerd' || echo 'No relevant processes in tree'
    " "$worker_dir/process-info.txt"
    
    # Recent system logs
    info "Collecting recent system logs..."
    run_remote "$worker_ip" "journalctl --no-pager -l --since '2 hours ago' | grep -E 'kubelet|containerd|kube|flannel|systemd' | tail -200" "$worker_dir/recent-system.log"
    
    info "✅ Diagnostics collection completed for worker: $worker_ip"
}

# Function to gather control plane status
gather_control_plane_status() {
    local control_plane_dir="$OUTPUT_DIR/control-plane-$CONTROL_PLANE_IP"
    
    info "Gathering control plane status from: $CONTROL_PLANE_IP"
    mkdir -p "$control_plane_dir"
    
    # Cluster status
    run_remote "$CONTROL_PLANE_IP" "
        export KUBECONFIG=/etc/kubernetes/admin.conf
        echo '=== Cluster Nodes ==='
        kubectl get nodes -o wide 2>/dev/null || echo 'kubectl get nodes failed'
        echo ''
        echo '=== Cluster Info ==='
        kubectl cluster-info 2>/dev/null || echo 'kubectl cluster-info failed'
        echo ''
        echo '=== Pod Status ==='
        kubectl get pods --all-namespaces -o wide 2>/dev/null || echo 'kubectl get pods failed'
        echo ''
        echo '=== Flannel Status ==='
        kubectl get pods -n kube-flannel -o wide 2>/dev/null || echo 'kubectl get flannel pods failed'
        echo ''
        echo '=== Active Tokens ==='
        kubeadm token list 2>/dev/null || echo 'kubeadm token list failed'
    " "$control_plane_dir/cluster-status.txt"
    
    # Control plane logs
    run_remote "$CONTROL_PLANE_IP" "journalctl -u kubelet --no-pager -l --since '24 hours ago'" "$control_plane_dir/kubelet.log"
    
    info "✅ Control plane status collection completed"
}

# Function to create summary report
create_summary_report() {
    local summary_file="$OUTPUT_DIR/DIAGNOSTIC_SUMMARY.txt"
    
    info "Creating diagnostic summary report..."
    
    cat > "$summary_file" << EOF
VMStation Worker Node Diagnostics Summary
========================================

Collection Timestamp: $(date)
Control Plane: $CONTROL_PLANE_IP
Worker Nodes: $WORKER_NODES
Output Directory: $OUTPUT_DIR

Files Collected:
===============

EOF

    # List all collected files
    find "$OUTPUT_DIR" -type f -name "*.txt" -o -name "*.log" -o -name "*.yaml" -o -name "*.toml" -o -name "*.conf" | \
    while read file; do
        local relative_path=${file#$OUTPUT_DIR/}
        local size=$(du -h "$file" | cut -f1)
        echo "  $relative_path ($size)" >> "$summary_file"
    done
    
    cat >> "$summary_file" << EOF

Analysis Recommendations:
========================

1. Check service-status.txt files for failed services
2. Review kubelet.log files for join failures or errors
3. Examine kubeadm-join.log files for join attempt details  
4. Verify socket-info.txt for containerd socket permission issues
5. Check cri-status.txt for CRI communication problems
6. Review network-config.txt for CNI and networking issues
7. Examine filesystem-info.txt for disk space or permission problems

Key Files for Troubleshooting:
=============================

Service Issues:
  - worker-*/service-status.txt
  - worker-*/kubelet.log
  - worker-*/containerd.log

Join Failures:
  - worker-*/kubeadm-join.log
  - worker-*/manual-kubeadm-join.log
  - control-plane-*/cluster-status.txt

Configuration Issues:
  - worker-*/crictl.yaml
  - worker-*/containerd-config.toml
  - worker-*/kubelet-config.yaml
  - worker-*/cni-config.txt

Runtime Issues:
  - worker-*/socket-info.txt
  - worker-*/cri-status.txt
  - worker-*/process-info.txt

Common Issues to Look For:
=========================

1. Containerd socket permission errors in socket-info.txt
2. "invalid capacity 0 on image filesystem" in kubelet.log
3. Token expiry messages in kubeadm-join.log
4. crictl communication failures in cri-status.txt
5. Missing kubelet config.yaml in filesystem-info.txt
6. Flannel network issues in control-plane cluster-status.txt

EOF
    
    info "✅ Summary report created: $summary_file"
}

# Function to create tarball for easy transfer
create_tarball() {
    local tarball_path="$OUTPUT_DIR.tar.gz"
    
    info "Creating diagnostic tarball..."
    if tar -czf "$tarball_path" -C "$(dirname "$OUTPUT_DIR")" "$(basename "$OUTPUT_DIR")"; then
        local size=$(du -h "$tarball_path" | cut -f1)
        info "✅ Diagnostic tarball created: $tarball_path ($size)"
        
        # Try to copy to control plane if possible
        if [ "$CONTROL_PLANE_IP" != "localhost" ] && [ "$CONTROL_PLANE_IP" != "127.0.0.1" ]; then
            info "Attempting to copy tarball to control plane..."
            if scp $SSH_OPTS "$tarball_path" "$SSH_USER@$CONTROL_PLANE_IP:/tmp/"; then
                info "✅ Tarball copied to control plane: $CONTROL_PLANE_IP:/tmp/$(basename "$tarball_path")"
            else
                warn "Failed to copy tarball to control plane"
            fi
        fi
    else
        error "Failed to create tarball"
    fi
}

# Main execution
main() {
    # Check if running with appropriate tools
    for tool in ssh scp; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            error "$tool is required but not found"
            exit 1
        fi
    done
    
    info "Starting worker node diagnostics collection..."
    
    # Gather control plane status first
    gather_control_plane_status
    
    # Process each worker node
    IFS=',' read -ra WORKERS <<< "$WORKER_NODES"
    for worker in "${WORKERS[@]}"; do
        worker=$(echo "$worker" | xargs)  # Trim whitespace
        if [ -n "$worker" ]; then
            gather_worker_diagnostics "$worker"
        fi
    done
    
    # Create summary report
    create_summary_report
    
    # Create tarball
    create_tarball
    
    echo ""
    info "🎉 Diagnostics collection completed!"
    info "Output directory: $OUTPUT_DIR"
    info "Review the DIAGNOSTIC_SUMMARY.txt file for analysis guidance"
    echo ""
}

# Help function
show_help() {
    cat << EOF
VMStation Worker Diagnostics Gathering Script

Usage: $0 [CONTROL_PLANE_IP] [WORKER_NODES] [OUTPUT_DIR]

Arguments:
  CONTROL_PLANE_IP  IP address of the control plane node (default: 192.168.4.63)
  WORKER_NODES      Comma-separated list of worker node IPs (default: 192.168.4.61,192.168.4.62)
  OUTPUT_DIR        Directory to store collected diagnostics (default: /tmp/worker-diagnostics-TIMESTAMP)

Environment Variables:
  SSH_USER         SSH username for connections (default: root)

Examples:
  $0                                    # Use defaults
  $0 192.168.1.10                     # Custom control plane IP
  $0 192.168.1.10 192.168.1.11,192.168.1.12  # Custom control plane and workers
  SSH_USER=ubuntu $0                   # Use ubuntu user for SSH

The script will:
1. Collect service status, logs, and configuration from all worker nodes
2. Gather control plane cluster status
3. Create a comprehensive summary report
4. Package everything in a tarball for easy sharing

EOF
}

# Check for help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
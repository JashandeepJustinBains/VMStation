#!/usr/bin/env bash
# Kubespray Cluster Diagnostics and Troubleshooting
# Collects diagnostic information for failed deployments or unhealthy clusters
#
# Usage: ./scripts/diagnose-kubespray-cluster.sh [--verbose] [--save-to DIR]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$REPO_ROOT/ansible/artifacts/diagnostics-$TIMESTAMP"
FLAG_VERBOSE=false

log_info() { echo "[INFO] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_err() { echo "[ERROR] $*" >&2; }

usage() {
    cat <<EOF
Kubespray Cluster Diagnostics and Troubleshooting

Usage: $(basename "$0") [options]

Options:
    --verbose     Show detailed output
    --save-to DIR Custom output directory
    -h, --help    Show this help message

This script collects:
1. Node status and conditions
2. Pod status across all namespaces
3. CNI/networking status
4. Control plane component health
5. System logs (kubelet, containerd)
6. Network configuration
7. File system state (/opt/cni/bin, etc.)

Output: $OUTPUT_DIR/

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose) FLAG_VERBOSE=true; shift ;;
        --save-to) OUTPUT_DIR=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) log_err "Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

log_info "=========================================="
log_info "Kubespray Cluster Diagnostics"
log_info "=========================================="
log_info "Output directory: $OUTPUT_DIR"

# Function to run command and save output
run_and_save() {
    local cmd="$1"
    local output_file="$2"
    local description="$3"
    
    log_info "Collecting: $description"
    
    if [[ "$FLAG_VERBOSE" == "true" ]]; then
        echo "$ $cmd" | tee "$OUTPUT_DIR/$output_file"
        eval "$cmd" 2>&1 | tee -a "$OUTPUT_DIR/$output_file" || true
    else
        echo "$ $cmd" > "$OUTPUT_DIR/$output_file"
        eval "$cmd" >> "$OUTPUT_DIR/$output_file" 2>&1 || true
    fi
}

# Check if kubectl is available
if ! command -v kubectl &>/dev/null; then
    log_warn "kubectl not found. Skipping cluster checks."
    KUBECTL_AVAILABLE=false
else
    KUBECTL_AVAILABLE=true
    
    # Test cluster connectivity
    if kubectl cluster-info &>/dev/null; then
        log_info "✓ Cluster is reachable"
    else
        log_warn "✗ Cluster is not reachable"
    fi
fi

# === Kubernetes Cluster Info ===
if [[ "$KUBECTL_AVAILABLE" == "true" ]]; then
    log_info ""
    log_info "=== Kubernetes Cluster Information ==="
    
    run_and_save "kubectl cluster-info" "cluster-info.txt" "Cluster info"
    run_and_save "kubectl version" "version.txt" "Kubernetes version"
    run_and_save "kubectl get nodes -o wide" "nodes.txt" "Node status"
    run_and_save "kubectl describe nodes" "nodes-describe.txt" "Node details"
    run_and_save "kubectl get pods -A -o wide" "pods-all.txt" "All pods"
    run_and_save "kubectl get pods -n kube-system -o wide" "pods-kube-system.txt" "Kube-system pods"
    run_and_save "kubectl describe pods -n kube-system" "pods-kube-system-describe.txt" "Kube-system pod details"
    
    # Check for failing pods
    log_info "Checking for failing pods..."
    kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>&1 | tee "$OUTPUT_DIR/failing-pods.txt" || true
    
    # Get logs from failing pods
    FAILING_PODS=$(kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | awk '{print $1":"$2}' || true)
    if [[ -n "$FAILING_PODS" ]]; then
        mkdir -p "$OUTPUT_DIR/pod-logs"
        while IFS= read -r pod_ref; do
            namespace=$(echo "$pod_ref" | cut -d: -f1)
            pod=$(echo "$pod_ref" | cut -d: -f2)
            log_info "  Collecting logs from $namespace/$pod"
            kubectl logs -n "$namespace" "$pod" --all-containers=true > "$OUTPUT_DIR/pod-logs/${namespace}_${pod}.log" 2>&1 || true
            kubectl logs -n "$namespace" "$pod" --all-containers=true --previous > "$OUTPUT_DIR/pod-logs/${namespace}_${pod}_previous.log" 2>&1 || true
        done <<< "$FAILING_PODS"
    fi
    
    # CNI and networking
    run_and_save "kubectl get ds -n kube-system" "daemonsets.txt" "DaemonSets"
    run_and_save "kubectl get svc -A" "services.txt" "Services"
    run_and_save "kubectl get endpoints -A" "endpoints.txt" "Endpoints"
    run_and_save "kubectl get networkpolicies -A" "network-policies.txt" "Network policies"
    
    # Control plane components
    run_and_save "kubectl get componentstatuses" "component-status.txt" "Component status"
    run_and_save "kubectl get events -A --sort-by='.lastTimestamp'" "events.txt" "Recent events"
fi

# === System-level diagnostics ===
log_info ""
log_info "=== System-level Diagnostics ==="

# Network configuration
run_and_save "ip addr show" "ip-addr.txt" "IP addresses"
run_and_save "ip route show" "ip-route.txt" "IP routes"
run_and_save "ip link show" "ip-link.txt" "Network links"
run_and_save "iptables -L -n -v" "iptables.txt" "iptables rules" || true
run_and_save "iptables -t nat -L -n -v" "iptables-nat.txt" "iptables NAT rules" || true

# Container runtime
if command -v containerd &>/dev/null; then
    run_and_save "systemctl status containerd" "containerd-status.txt" "containerd status"
    run_and_save "sudo journalctl -u containerd -n 500 --no-pager" "containerd-logs.txt" "containerd logs"
fi

# Kubelet
if command -v kubelet &>/dev/null; then
    run_and_save "systemctl status kubelet" "kubelet-status.txt" "kubelet status"
    run_and_save "sudo journalctl -u kubelet -n 500 --no-pager" "kubelet-logs.txt" "kubelet logs"
fi

# CNI binaries and configuration
run_and_save "ls -la /opt/cni/bin/" "cni-binaries.txt" "CNI binaries"
run_and_save "ls -la /etc/cni/net.d/" "cni-config.txt" "CNI configuration"

# Kernel modules
run_and_save "lsmod | grep -E 'br_netfilter|overlay|ip_vs'" "kernel-modules.txt" "Kernel modules"

# System resources
run_and_save "df -h" "disk-usage.txt" "Disk usage"
run_and_save "free -h" "memory.txt" "Memory usage"
run_and_save "uptime" "uptime.txt" "System uptime"

# Create summary
cat > "$OUTPUT_DIR/SUMMARY.txt" <<EOF
Kubespray Cluster Diagnostics Summary
======================================
Timestamp: $TIMESTAMP
Hostname: $(hostname)
Date: $(date)

Files in this directory:
$(ls -1 "$OUTPUT_DIR" | grep -v SUMMARY.txt)

Quick Checks:
-------------
EOF

if [[ "$KUBECTL_AVAILABLE" == "true" ]]; then
    echo "Nodes:" >> "$OUTPUT_DIR/SUMMARY.txt"
    kubectl get nodes --no-headers 2>/dev/null >> "$OUTPUT_DIR/SUMMARY.txt" || echo "  Failed to get nodes" >> "$OUTPUT_DIR/SUMMARY.txt"
    echo "" >> "$OUTPUT_DIR/SUMMARY.txt"
    
    echo "Failing Pods:" >> "$OUTPUT_DIR/SUMMARY.txt"
    kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null >> "$OUTPUT_DIR/SUMMARY.txt" || echo "  None or failed to check" >> "$OUTPUT_DIR/SUMMARY.txt"
    echo "" >> "$OUTPUT_DIR/SUMMARY.txt"
fi

log_info ""
log_info "=========================================="
log_info "Diagnostics Complete"
log_info "=========================================="
log_info "Output directory: $OUTPUT_DIR"
log_info ""
log_info "Review the following files:"
log_info "  - SUMMARY.txt         - Quick summary"
log_info "  - nodes.txt           - Node status"
log_info "  - pods-kube-system.txt - System pod status"
log_info "  - failing-pods.txt    - List of failing pods"
log_info "  - pod-logs/           - Logs from failing pods"
log_info "  - kubelet-logs.txt    - Kubelet system logs"
log_info "  - containerd-logs.txt - Container runtime logs"
log_info ""
log_info "To share diagnostics:"
log_info "  tar -czf diagnostics-$TIMESTAMP.tar.gz -C $(dirname "$OUTPUT_DIR") $(basename "$OUTPUT_DIR")"

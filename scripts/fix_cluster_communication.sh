#!/bin/bash

# VMStation Cluster Communication Fix Script
# Context: Mixed-Linux Kubernetes cluster (example nodes: 192.168.4.61, 192.168.4.62, 192.168.4.63)
# 
# Modes:
# - Controller mode (default): run on masternode; collects cluster-wide diagnostics with kubectl
# - Remote execution: optionally runs per-node helpers over SSH when --remote-exec and --nodes provided
#
# Usage examples:
#   # Controller mode only (collect diagnostics)
#   ./fix_cluster_communication.sh
#   
#   # Controller mode with remote execution
#   ./fix_cluster_communication.sh --remote-exec --nodes "192.168.4.61 192.168.4.62"
#   
#   # Apply fixes after diagnostics
#   ./fix_cluster_communication.sh --apply --remote-exec --nodes "192.168.4.61 192.168.4.62"
#   
#   # Force apply without confirmation
#   ./fix_cluster_communication.sh --apply --force --remote-exec --nodes "192.168.4.61 192.168.4.62"

set -euo pipefail

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Logging functions
info() { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"; }

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="/tmp/fix-cluster-${TIMESTAMP}.log"
DIAG_DIR="/tmp/fix-cluster-diag-${TIMESTAMP}"
DIAG_TARBALL="${DIAG_DIR}.tar.gz"

# Configuration variables
REMOTE_EXEC=false
NODES=""
SSH_USER="${USER}"
APPLY=false
FORCE=false
DRY_RUN=true

# Permission tracking
declare -a PERMISSION_ISSUES=()

# Usage function
usage() {
    cat << EOF
VMStation Cluster Communication Fix Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --remote-exec           Enable remote execution on worker nodes
    --nodes "ip1 ip2 ..."   Space-separated list of node IPs (requires --remote-exec)
    --ssh-user USER         SSH username (default: current user '$USER')
    --apply                 Apply fixes after diagnostics (requires confirmation unless --force)
    --force                 Skip confirmation prompts
    --dry-run               Only collect diagnostics, don't apply fixes (default)
    --delegate-perms        Print permission fix commands and exit with code 2
    -h, --help              Show this help

EXAMPLES:
    # Collect diagnostics only (controller mode)
    $0

    # Collect diagnostics and check remote nodes
    $0 --remote-exec --nodes "192.168.4.61 192.168.4.62"

    # Apply fixes with confirmation
    $0 --apply --remote-exec --nodes "192.168.4.61 192.168.4.62"

    # Force apply without confirmation  
    $0 --apply --force --remote-exec --nodes "192.168.4.61 192.168.4.62"

COPY+PASTE EXAMPLES:
    # Manual scp + remote run:
    scp scripts/fix_cluster_helper.sh root@192.168.4.61:/tmp/
    ssh root@192.168.4.61 'bash /tmp/fix_cluster_helper.sh --dry-run'

    # Run helper over SSH from masternode without copy:
    for node in 192.168.4.61 192.168.4.62; do 
        ssh root@"\$node" 'bash -s' < scripts/fix_cluster_helper.sh -- --dry-run
    done

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --remote-exec)
                REMOTE_EXEC=true
                shift
                ;;
            --nodes)
                NODES="$2"
                shift 2
                ;;
            --ssh-user)
                SSH_USER="$2"
                shift 2
                ;;
            --apply)
                APPLY=true
                DRY_RUN=false
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                APPLY=false
                shift
                ;;
            --delegate-perms)
                print_permission_commands
                exit 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validation
    if [[ "$REMOTE_EXEC" == "true" && -z "$NODES" ]]; then
        error "--remote-exec requires --nodes to be specified"
        exit 1
    fi
}

# Print permission fix commands
print_permission_commands() {
    cat << 'EOF'
PERMISSION FIX COMMANDS:

# If kubectl config issues:
sudo chown $(id -u):$(id -g) $HOME/.kube/config
sudo chmod 600 $HOME/.kube/config

# If kubeconfig directory issues:
sudo chown -R $(id -u):$(id -g) $HOME/.kube/
sudo chmod 755 $HOME/.kube/
sudo chmod 600 $HOME/.kube/config

# If containerd socket issues:
sudo chown root:docker /run/containerd/containerd.sock
sudo chmod 660 /run/containerd/containerd.sock

# If CNI config issues:
sudo chown -R root:root /etc/cni/net.d/
sudo chmod 755 /etc/cni/net.d/
sudo chmod 644 /etc/cni/net.d/*

# If kubelet issues:
sudo chown root:root /etc/kubernetes/kubelet.conf
sudo chmod 600 /etc/kubernetes/kubelet.conf

EOF
}

# Check if file/directory permissions are blocking access
check_permissions() {
    local path="$1"
    local required_op="$2"  # read, write, execute
    
    if [[ ! -e "$path" ]]; then
        return 0  # Path doesn't exist, not a permission issue
    fi
    
    case "$required_op" in
        read)
            if [[ ! -r "$path" ]]; then
                local stat_info=$(stat -c "User:%U Group:%G Mode:%a" "$path" 2>/dev/null || echo "unknown")
                PERMISSION_ISSUES+=("READ blocked: $path ($stat_info)")
                return 1
            fi
            ;;
        write)
            if [[ ! -w "$path" ]]; then
                local stat_info=$(stat -c "User:%U Group:%G Mode:%a" "$path" 2>/dev/null || echo "unknown")
                PERMISSION_ISSUES+=("WRITE blocked: $path ($stat_info)")
                return 1
            fi
            ;;
        execute)
            if [[ ! -x "$path" ]]; then
                local stat_info=$(stat -c "User:%U Group:%G Mode:%a" "$path" 2>/dev/null || echo "unknown")
                PERMISSION_ISSUES+=("EXECUTE blocked: $path ($stat_info)")
                return 1
            fi
            ;;
    esac
    return 0
}

# Initialize logging and directories
init_logging() {
    # Create log file
    touch "$LOG_FILE" || {
        error "Cannot create log file: $LOG_FILE"
        exit 1
    }
    
    # Create diagnostics directory
    mkdir -p "$DIAG_DIR" || {
        error "Cannot create diagnostics directory: $DIAG_DIR"
        exit 1
    }
    
    info "=== VMStation Cluster Communication Fix Script ==="
    info "Timestamp: $(date)"
    info "Log file: $LOG_FILE"
    info "Diagnostics directory: $DIAG_DIR"
    info "Mode: $([ "$APPLY" == "true" ] && echo "APPLY" || echo "DRY-RUN")"
    info "Remote execution: $REMOTE_EXEC"
    [[ -n "$NODES" ]] && info "Target nodes: $NODES"
    info "SSH user: $SSH_USER"
}

# Collect cluster-wide diagnostics with kubectl
collect_cluster_diagnostics() {
    info "=== Collecting Cluster-wide Diagnostics ==="
    
    # Check kubectl access
    if ! check_permissions "$HOME/.kube/config" "read"; then
        warn "kubectl config permission issues detected"
        return 1
    fi
    
    # Test kubectl connectivity
    if ! timeout 10 kubectl cluster-info &>/dev/null; then
        error "Cannot connect to Kubernetes cluster"
        kubectl cluster-info 2>&1 | tee "$DIAG_DIR/kubectl-error.txt" || true
        return 1
    fi
    
    info "Collecting node information..."
    kubectl get nodes -o wide > "$DIAG_DIR/nodes.txt" 2>&1 || true
    kubectl describe nodes > "$DIAG_DIR/nodes-describe.txt" 2>&1 || true
    
    info "Collecting pod information..."
    kubectl get pods --all-namespaces -o wide > "$DIAG_DIR/pods.txt" 2>&1 || true
    kubectl get pods --all-namespaces -o yaml > "$DIAG_DIR/pods-yaml.txt" 2>&1 || true
    
    info "Collecting service information..."
    kubectl get services --all-namespaces -o wide > "$DIAG_DIR/services.txt" 2>&1 || true
    
    info "Collecting events..."
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' > "$DIAG_DIR/events.txt" 2>&1 || true
    
    info "Collecting component logs..."
    # Collect logs from system components
    for ns in kube-system kube-flannel; do
        mkdir -p "$DIAG_DIR/logs/$ns"
        kubectl get pods -n "$ns" -o name 2>/dev/null | while read -r pod; do
            pod_name=$(echo "$pod" | sed 's#pod/##')
            kubectl logs -n "$ns" "$pod_name" --all-containers=true > "$DIAG_DIR/logs/$ns/${pod_name}.log" 2>&1 || true
            kubectl describe pod -n "$ns" "$pod_name" > "$DIAG_DIR/logs/$ns/${pod_name}-describe.txt" 2>&1 || true
        done
    done
    
    info "Cluster diagnostics collection completed"
    return 0
}

# Execute helper script on remote node
execute_remote_helper() {
    local node_ip="$1"
    local apply_flag="$2"
    
    info "Executing helper on node: $node_ip"
    
    local helper_script="$SCRIPT_DIR/fix_cluster_helper.sh"
    if [[ ! -f "$helper_script" ]]; then
        error "Helper script not found: $helper_script"
        return 1
    fi
    
    # Test SSH connectivity
    if ! timeout 10 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" 'echo "SSH test successful"' &>/dev/null; then
        warn "SSH connection failed to $node_ip"
        
        # Print manual commands for operator
        cat << EOF | tee -a "$DIAG_DIR/manual-commands-$node_ip.txt"

MANUAL EXECUTION COMMANDS FOR NODE $node_ip:

# Copy helper script to node:
scp scripts/fix_cluster_helper.sh $SSH_USER@$node_ip:/tmp/

# Execute helper script on node:
ssh $SSH_USER@$node_ip 'bash /tmp/fix_cluster_helper.sh $apply_flag'

# Alternative - run without copying:
ssh $SSH_USER@$node_ip 'bash -s' < scripts/fix_cluster_helper.sh -- $apply_flag

EOF
        
        return 1
    fi
    
    # Create remote directory for diagnostics
    local remote_dir="/tmp/fix-cluster-helper-$TIMESTAMP"
    ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" "mkdir -p $remote_dir" || {
        error "Failed to create remote directory on $node_ip"
        return 1
    }
    
    # Execute helper script remotely
    local output_file="$DIAG_DIR/remote-$node_ip.log"
    
    info "Running helper script on $node_ip..."
    if ssh -o ConnectTimeout=30 -o StrictHostKeyChecking=no "$SSH_USER@$node_ip" 'bash -s' < "$helper_script" -- $apply_flag > "$output_file" 2>&1; then
        info "Helper script completed successfully on $node_ip"
        
        # Try to copy back remote diagnostics
        scp -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$node_ip:$remote_dir/*" "$DIAG_DIR/" 2>/dev/null || {
            warn "Could not copy diagnostics from $node_ip"
        }
        
        return 0
    else
        warn "Helper script failed on $node_ip (check $output_file)"
        
        # Try to get sudo command if permission issues
        if grep -q -i "permission\|denied\|sudo" "$output_file"; then
            info "Permission issues detected on $node_ip"
            cat << EOF | tee -a "$DIAG_DIR/manual-commands-$node_ip.txt"

PERMISSION FIX COMMANDS FOR NODE $node_ip:

# Execute with sudo:
ssh $SSH_USER@$node_ip 'sudo bash /tmp/fix_cluster_helper.sh $apply_flag'

# Or run individual commands with sudo (see helper script output)

EOF
        fi
        
        return 1
    fi
}

# Process remote nodes if specified
process_remote_nodes() {
    if [[ "$REMOTE_EXEC" != "true" || -z "$NODES" ]]; then
        return 0
    fi
    
    info "=== Processing Remote Nodes ==="
    
    local apply_flag=""
    [[ "$APPLY" == "true" ]] && apply_flag="--apply"
    [[ "$DRY_RUN" == "true" ]] && apply_flag="--dry-run"
    
    local failed_nodes=()
    
    for node_ip in $NODES; do
        info "Processing node: $node_ip"
        
        if ! execute_remote_helper "$node_ip" "$apply_flag"; then
            failed_nodes+=("$node_ip")
            warn "Failed to process node: $node_ip"
        fi
    done
    
    if [[ ${#failed_nodes[@]} -gt 0 ]]; then
        warn "Failed to process nodes: ${failed_nodes[*]}"
        info "Manual commands have been saved to $DIAG_DIR/manual-commands-*.txt"
        return 1
    fi
    
    info "All remote nodes processed successfully"
    return 0
}

# Perform verification commands after apply
perform_verification() {
    if [[ "$APPLY" != "true" ]]; then
        info "Skipping verification (dry-run mode)"
        return 0
    fi
    
    info "=== Performing Post-Apply Verification ==="
    
    # Wait for system to stabilize
    info "Waiting for system to stabilize..."
    sleep 30
    
    local verification_failed=false
    
    # Test 1: Pod-to-pod ping
    info "Testing pod-to-pod connectivity..."
    if ! test_pod_to_pod_connectivity; then
        error "Pod-to-pod connectivity test failed"
        verification_failed=true
    fi
    
    # Test 2: DNS resolution
    info "Testing DNS resolution..."
    if ! test_dns_resolution; then
        error "DNS resolution test failed"
        verification_failed=true
    fi
    
    # Test 3: NodePort accessibility
    info "Testing NodePort accessibility..."
    if ! test_nodeport_access; then
        error "NodePort accessibility test failed"
        verification_failed=true
    fi
    
    if [[ "$verification_failed" == "true" ]]; then
        error "Verification failed - some issues persist"
        return 1
    else
        info "All verification tests passed"
        return 0
    fi
}

# Test pod-to-pod connectivity
test_pod_to_pod_connectivity() {
    info "Creating test pods for connectivity testing..."
    
    # Clean up any existing test pods
    kubectl delete pod ping-test-source ping-test-target --ignore-not-found=true --timeout=30s >/dev/null 2>&1 || true
    
    # Create test pods
    cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: ping-test-source
  namespace: default
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot:latest
    command: ["sleep", "300"]
  restartPolicy: Never
---
apiVersion: v1
kind: Pod
metadata:
  name: ping-test-target
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:alpine
  restartPolicy: Never
EOF
    
    # Wait for pods to be ready
    if ! kubectl wait --for=condition=Ready pod/ping-test-source pod/ping-test-target --timeout=120s >/dev/null 2>&1; then
        warn "Test pods failed to become ready"
        kubectl delete pod ping-test-source ping-test-target --ignore-not-found=true --timeout=30s >/dev/null 2>&1 || true
        return 1
    fi
    
    # Get pod IPs
    local source_ip target_ip
    source_ip=$(kubectl get pod ping-test-source -o jsonpath='{.status.podIP}')
    target_ip=$(kubectl get pod ping-test-target -o jsonpath='{.status.podIP}')
    
    if [[ -z "$source_ip" || -z "$target_ip" ]]; then
        warn "Could not get pod IPs"
        kubectl delete pod ping-test-source ping-test-target --ignore-not-found=true --timeout=30s >/dev/null 2>&1 || true
        return 1
    fi
    
    info "Testing ping from $source_ip to $target_ip"
    
    # Test ping (this addresses: '2 packets transmitted, 0 received, 100% packet loss')
    if kubectl exec ping-test-source -- ping -c 2 -W 5 "$target_ip" >/dev/null 2>&1; then
        info "✓ Pod-to-pod ping successful"
        local result=0
    else
        warn "✗ Pod-to-pod ping failed (100% packet loss)"
        local result=1
    fi
    
    # Test HTTP connectivity
    if kubectl exec ping-test-source -- timeout 10 curl -s --max-time 5 "http://$target_ip/" >/dev/null 2>&1; then
        info "✓ Pod-to-pod HTTP successful"
    else
        warn "✗ Pod-to-pod HTTP failed"
        result=1
    fi
    
    # Clean up
    kubectl delete pod ping-test-source ping-test-target --ignore-not-found=true --timeout=30s >/dev/null 2>&1 || true
    
    return $result
}

# Test DNS resolution
test_dns_resolution() {
    # Create test pod for DNS testing
    kubectl run dns-test --image=busybox:1.35 --rm -i --restart=Never --timeout=60s -- \
        nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1 && {
        info "✓ DNS resolution successful"
        return 0
    } || {
        warn "✗ DNS resolution failed ('FAIL: DNS resolution of kubernetes service')"
        return 1
    }
}

# Test NodePort access on all specified nodes
test_nodeport_access() {
    if [[ -z "$NODES" ]]; then
        info "No nodes specified, skipping NodePort test"
        return 0
    fi
    
    # Find a NodePort service to test
    local nodeport_service nodeport_port
    nodeport_service=$(kubectl get services --all-namespaces -o jsonpath='{.items[?(@.spec.type=="NodePort")].metadata.name}' | head -1)
    
    if [[ -z "$nodeport_service" ]]; then
        info "No NodePort services found, skipping test"
        return 0
    fi
    
    nodeport_port=$(kubectl get service "$nodeport_service" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    
    if [[ -z "$nodeport_port" ]]; then
        warn "Could not determine NodePort for service $nodeport_service"
        return 1
    fi
    
    info "Testing NodePort $nodeport_port on all nodes..."
    
    local failed_nodes=()
    for node_ip in $NODES; do
        if timeout 10 nc -zv "$node_ip" "$nodeport_port" >/dev/null 2>&1; then
            info "✓ NodePort $nodeport_port accessible on $node_ip"
        else
            warn "✗ NodePort $nodeport_port not accessible on $node_ip"
            failed_nodes+=("$node_ip")
        fi
    done
    
    if [[ ${#failed_nodes[@]} -gt 0 ]]; then
        warn "NodePort not accessible on nodes: ${failed_nodes[*]}"
        return 1
    fi
    
    return 0
}

# Create final output tarball
create_output_tarball() {
    info "Creating diagnostics tarball..."
    
    # Add summary file
    cat > "$DIAG_DIR/SUMMARY.txt" << EOF
VMStation Cluster Communication Fix - Diagnostic Summary
========================================================

Timestamp: $(date)
Log file: $LOG_FILE
Mode: $([ "$APPLY" == "true" ] && echo "APPLY" || echo "DRY-RUN")
Remote execution: $REMOTE_EXEC
Nodes: $NODES
SSH user: $SSH_USER

Permission Issues Detected:
$(printf '%s\n' "${PERMISSION_ISSUES[@]}" || echo "None")

Files in this diagnostic package:
$(find "$DIAG_DIR" -type f | sort)

EOF
    
    # Create tarball
    if tar -czf "$DIAG_TARBALL" -C "$(dirname "$DIAG_DIR")" "$(basename "$DIAG_DIR")" 2>/dev/null; then
        info "Diagnostics tarball created: $DIAG_TARBALL"
        info "Tarball size: $(du -h "$DIAG_TARBALL" | cut -f1)"
    else
        error "Failed to create diagnostics tarball"
        return 1
    fi
}

# Print final summary and commands
print_final_summary() {
    echo
    info "=== Final Summary ==="
    info "Log file: $LOG_FILE"
    info "Diagnostics tarball: $DIAG_TARBALL"
    
    if [[ ${#PERMISSION_ISSUES[@]} -gt 0 ]]; then
        warn "Permission issues detected:"
        printf '%s\n' "${PERMISSION_ISSUES[@]}"
        echo
        warn "To fix permission issues, run:"
        echo "  $0 --delegate-perms"
        echo
    fi
    
    if [[ "$APPLY" != "true" ]]; then
        info "To apply fixes, run with --apply flag:"
        echo "  $0 --apply --remote-exec --nodes \"$NODES\""
        echo
    fi
    
    echo "Manual command examples:"
    echo "  # Copy and run helper manually:"
    for node_ip in $NODES; do
        echo "  scp scripts/fix_cluster_helper.sh $SSH_USER@$node_ip:/tmp/"
        echo "  ssh $SSH_USER@$node_ip 'bash /tmp/fix_cluster_helper.sh --dry-run'"
    done
    echo
    echo "  # Run helper without copying:"
    echo "  for node in $NODES; do"
    echo "    ssh $SSH_USER@\"\$node\" 'bash -s' < scripts/fix_cluster_helper.sh -- --dry-run"
    echo "  done"
}

# Safety confirmation
confirm_apply() {
    if [[ "$APPLY" != "true" || "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo
    warn "You are about to apply cluster communication fixes."
    warn "This will modify system configurations and restart services."
    echo
    read -p "Do you want to proceed? (y/N): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Operation cancelled by user"
        exit 0
    fi
}

# Main function
main() {
    parse_args "$@"
    init_logging
    
    # Safety confirmation
    confirm_apply
    
    # Collect cluster diagnostics
    if ! collect_cluster_diagnostics; then
        error "Failed to collect cluster diagnostics"
        if [[ ${#PERMISSION_ISSUES[@]} -gt 0 ]]; then
            error "Diagnostics marked as permission-blocked"
        fi
    fi
    
    # Process remote nodes if specified
    process_remote_nodes
    
    # Perform verification if applying fixes
    if [[ "$APPLY" == "true" ]]; then
        perform_verification
    fi
    
    # Create output files
    create_output_tarball
    
    # Print final summary
    print_final_summary
    
    info "Script completed successfully"
}

# Execute main function
main "$@"
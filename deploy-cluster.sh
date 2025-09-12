#!/bin/bash

# VMStation Kubernetes Cluster Deployment Script
# Wrapper for the complete cluster bootstrap process

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Configuration
INVENTORY_FILE="ansible/inventory/hosts.yml"
PLAYBOOK_DIR="ansible/playbooks"
VERIFICATION_PLAYBOOK="$PLAYBOOK_DIR/verify-cluster.yml"
MAIN_BOOTSTRAP="$PLAYBOOK_DIR/cluster-bootstrap.yml"
SIMPLE_BOOTSTRAP="$PLAYBOOK_DIR/cluster-bootstrap/simple-bootstrap.yml"

# Default settings
MODE="full"
SKIP_VERIFICATION=false
FORCE_RESET=false
DRY_RUN=false

usage() {
    cat << EOF
VMStation Kubernetes Cluster Deployment Script

Usage: $0 [OPTIONS] [COMMAND]

Commands:
    deploy      Deploy complete cluster (default)
    verify      Run cluster verification only
    reset       Reset cluster and redeploy
    smoke-test  Run quick smoke test

Options:
    --simple            Use simple bootstrap (without existing setup-cluster.yaml)
    --skip-verification Skip post-deployment verification
    --dry-run          Show what would be done without executing
    --force            Force operations without confirmation
    --help             Show this help message

Examples:
    $0 deploy                    # Full deployment with verification
    $0 --simple deploy           # Simple deployment only
    $0 verify                    # Verification only
    $0 --dry-run deploy          # Preview deployment steps
    $0 reset                     # Reset and redeploy cluster

Environment Variables:
    ANSIBLE_INVENTORY    Override inventory file (default: $INVENTORY_FILE)
    ANSIBLE_VERBOSITY    Set verbosity level (0-4)

EOF
}

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if ansible is installed
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        error "ansible-playbook not found. Please install Ansible."
        exit 1
    fi
    
    # Check if inventory file exists
    if [ ! -f "$INVENTORY_FILE" ]; then
        error "Inventory file not found: $INVENTORY_FILE"
        exit 1
    fi
    
    # Check if kubernetes.core collection is available
    if ! ansible-galaxy collection list kubernetes.core >/dev/null 2>&1; then
        warn "kubernetes.core collection not found. Installing..."
        ansible-galaxy collection install kubernetes.core
    fi
    
    success "Prerequisites check passed"
}

deploy_cluster() {
    local playbook_file
    
    if [ "$MODE" = "simple" ]; then
        playbook_file="$SIMPLE_BOOTSTRAP"
        info "Using simple bootstrap playbook: $playbook_file"
    else
        playbook_file="$MAIN_BOOTSTRAP"
        info "Using full bootstrap playbook: $playbook_file"
    fi
    
    if [ ! -f "$playbook_file" ]; then
        error "Playbook not found: $playbook_file"
        exit 1
    fi
    
    local ansible_opts=()
    
    if [ "$DRY_RUN" = true ]; then
        ansible_opts+=("--check" "--diff")
        info "DRY RUN MODE: Showing what would be done"
    fi
    
    if [ -n "$ANSIBLE_VERBOSITY" ] && [ "$ANSIBLE_VERBOSITY" -gt 0 ]; then
        local verbosity_flag=""
        for ((i=1; i<=ANSIBLE_VERBOSITY; i++)); do
            verbosity_flag="${verbosity_flag}v"
        done
        ansible_opts+=("-${verbosity_flag}")
    fi
    
    info "Starting cluster deployment..."
    echo "Playbook: $playbook_file"
    echo "Inventory: $INVENTORY_FILE"
    echo "Options: ${ansible_opts[*]}"
    echo ""
    
    if ansible-playbook -i "$INVENTORY_FILE" "${ansible_opts[@]}" "$playbook_file"; then
        success "✅ Cluster deployment completed successfully!"
        
        if [ "$SKIP_VERIFICATION" = false ] && [ "$DRY_RUN" = false ]; then
            info "Running post-deployment verification..."
            verify_cluster
            
            # Run post-deployment fixes for common issues
            info "Running post-deployment fixes for known issues..."
            run_post_deployment_fixes
        fi
    else
        error "❌ Cluster deployment failed!"
        info "Check the output above for errors. Common issues:"
        info "- SSH connectivity to nodes"
        info "- Insufficient privileges"
        info "- Network connectivity between nodes"
        info "- Package repository issues"
        exit 1
    fi
}

verify_cluster() {
    info "Running cluster verification..."
    
    if [ ! -f "$VERIFICATION_PLAYBOOK" ]; then
        error "Verification playbook not found: $VERIFICATION_PLAYBOOK"
        exit 1
    fi
    
    local ansible_opts=()
    
    if [ "$DRY_RUN" = true ]; then
        ansible_opts+=("--check")
    fi
    
    if ansible-playbook -i "$INVENTORY_FILE" "${ansible_opts[@]}" "$VERIFICATION_PLAYBOOK"; then
        success "✅ Cluster verification passed!"
    else
        error "❌ Cluster verification failed!"
        info "Run smoke test for quick diagnosis: $0 smoke-test"
        exit 1
    fi
}

run_post_deployment_fixes() {
    info "Running post-deployment fixes for common pod issues..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would run post-deployment fixes on control plane"
        return 0
    fi
    
    # Check if fix scripts exist
    local fix_scripts=(
        "scripts/fix_homelab_node_issues.sh"
        "scripts/fix_remaining_pod_issues.sh"
    )
    
    local control_plane_ip="192.168.4.63"
    
    # Check if we're already running on the control plane
    if is_running_on_control_plane; then
        info "Running post-deployment fixes locally (already on control plane)..."
        
        # Clean up any existing PVC resources that might conflict with hostPath
        info "Cleaning up any conflicting PVC resources for Jellyfin..."
        kubectl delete pvc -n jellyfin --all --ignore-not-found=true || true
        kubectl delete pv jellyfin-config-pv jellyfin-media-pv --ignore-not-found=true || true
        
        for script in "${fix_scripts[@]}"; do
            if [ -f "$script" ]; then
                info "Running fix script: $script"
                if chmod +x "$script" && "$script"; then
                    success "✅ Fix script $script completed successfully"
                else
                    warn "⚠️ Fix script $script encountered issues (non-critical)"
                fi
            else
                warn "Fix script not found: $script"
            fi
        done
    else
        info "Copying fix scripts to control plane and running them..."
        
        # Copy scripts to control plane
        local temp_dir="/tmp/vmstation-fixes"
        
        # First clean up any conflicting PVCs
        info "Cleaning up any conflicting PVC resources for Jellyfin on remote control plane..."
        ssh root@$control_plane_ip "kubectl delete pvc -n jellyfin --all --ignore-not-found=true || true" || true
        ssh root@$control_plane_ip "kubectl delete pv jellyfin-config-pv jellyfin-media-pv --ignore-not-found=true || true" || true
        
        for script in "${fix_scripts[@]}"; do
            if [ -f "$script" ]; then
                info "Copying and running: $script"
                if scp "$script" root@$control_plane_ip:/tmp/; then
                    local script_name=$(basename "$script")
                    if ssh root@$control_plane_ip "chmod +x /tmp/$script_name && /tmp/$script_name"; then
                        success "✅ Remote fix script $script_name completed successfully"
                    else
                        warn "⚠️ Remote fix script $script_name encountered issues (non-critical)"
                    fi
                    # Clean up
                    ssh root@$control_plane_ip "rm -f /tmp/$script_name" || true
                else
                    warn "Failed to copy fix script $script to control plane"
                fi
            fi
        done
    fi
    
    info "Post-deployment fixes completed"
}

is_running_on_control_plane() {
    local control_plane_ip="192.168.4.63"
    local current_ip
    
    # Get current machine IP addresses
    current_ip=$(hostname -I 2>/dev/null || ip route get 1 2>/dev/null | awk '{print $7; exit}' || echo "")
    
    # Check if any of the current IPs match the control plane IP
    if echo "$current_ip" | grep -q "$control_plane_ip"; then
        return 0
    fi
    
    # Also check if we're the control plane by checking for kubeconfig
    if [ -f "/etc/kubernetes/admin.conf" ]; then
        return 0
    fi
    
    return 1
}

run_smoke_test() {
    info "Running smoke test..."
    
    # Check if smoke test script exists
    if [ ! -f "scripts/smoke-test.sh" ]; then
        error "Smoke test script not found: scripts/smoke-test.sh"
        exit 1
    fi
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would execute smoke test on control plane"
        return 0
    fi
    
    # Run smoke test on control plane node
    local control_plane_ip="192.168.4.63"
    
    # Check if we're already running on the control plane
    if is_running_on_control_plane; then
        info "Running smoke test locally (already on control plane)..."
        if chmod +x scripts/smoke-test.sh && scripts/smoke-test.sh; then
            success "✅ Smoke test passed!"
        else
            error "❌ Smoke test failed!"
            exit 1
        fi
    else
        info "Copying smoke test script to control plane..."
        if scp scripts/smoke-test.sh root@$control_plane_ip:/tmp/; then
            info "Running smoke test on control plane ($control_plane_ip)..."
            if ssh root@$control_plane_ip "chmod +x /tmp/smoke-test.sh && /tmp/smoke-test.sh"; then
                success "✅ Smoke test passed!"
            else
                error "❌ Smoke test failed!"
                exit 1
            fi
        else
            error "Failed to copy smoke test script to control plane"
            info "Make sure SSH access to $control_plane_ip is configured"
            exit 1
        fi
    fi
}

reset_cluster() {
    warn "This will completely reset the Kubernetes cluster!"
    
    if [ "$FORCE_RESET" = false ]; then
        echo -n "Are you sure you want to proceed? (yes/no): "
        read -r confirmation
        if [ "$confirmation" != "yes" ]; then
            info "Reset cancelled."
            exit 0
        fi
    fi
    
    info "Resetting cluster..."
    
    # Reset all nodes
    local reset_commands=(
        "kubeadm reset --force"
        "systemctl stop kubelet containerd"
        "rm -rf /etc/kubernetes/"
        "rm -rf /var/lib/kubelet/"
        "rm -rf /etc/cni/net.d/"
        "iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X"
        "systemctl start containerd"
    )
    
    for cmd in "${reset_commands[@]}"; do
        info "Executing on all nodes: $cmd"
        if [ "$DRY_RUN" = false ]; then
            ansible all -i "$INVENTORY_FILE" -b -m shell -a "$cmd" || true
        fi
    done
    
    if [ "$DRY_RUN" = false ]; then
        success "Cluster reset completed. Deploying fresh cluster..."
        deploy_cluster
    else
        info "DRY RUN: Would reset cluster and redeploy"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --simple)
            MODE="simple"
            shift
            ;;
        --skip-verification)
            SKIP_VERIFICATION=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_RESET=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        deploy)
            COMMAND="deploy"
            shift
            ;;
        verify)
            COMMAND="verify"
            shift
            ;;
        reset)
            COMMAND="reset"
            shift
            ;;
        smoke-test)
            COMMAND="smoke-test"
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Default command
COMMAND=${COMMAND:-deploy}

# Main execution
echo "=== VMStation Kubernetes Cluster Deployment ==="
echo "Command: $COMMAND"
echo "Mode: $MODE"
echo "Timestamp: $(date)"
echo ""

check_prerequisites

case $COMMAND in
    deploy)
        deploy_cluster
        ;;
    verify)
        verify_cluster
        ;;
    reset)
        reset_cluster
        ;;
    smoke-test)
        run_smoke_test
        ;;
    *)
        error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac

success "🎉 Operation completed successfully!"
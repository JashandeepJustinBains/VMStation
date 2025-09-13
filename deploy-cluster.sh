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
CONFIRM_RESET=false

usage() {
    cat << EOF
VMStation Kubernetes Cluster Deployment Script

Usage: $0 [OPTIONS] [COMMAND]

Commands:
    deploy      Deploy complete cluster (default)
    verify      Run cluster verification only
    reset       Reset cluster and redeploy
    net-reset   Reset only kube-proxy and CoreDNS (network control plane)
    smoke-test  Run quick smoke test

Options:
    --simple            Use simple bootstrap (without existing setup-cluster.yaml)
    --skip-verification Skip post-deployment verification
    --dry-run          Show what would be done without executing
    --force            Force operations without confirmation
    --confirm          Confirm destructive operations (for net-reset)
    --help             Show this help message

Examples:
    $0 deploy                    # Full deployment with verification
    $0 --simple deploy           # Simple deployment only
    $0 verify                    # Verification only
    $0 --dry-run deploy          # Preview deployment steps
    $0 reset                     # Reset and redeploy cluster
    $0 net-reset --confirm       # Reset only network control plane
    $0 --dry-run net-reset       # Preview network reset steps

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
        "scripts/fix_cluster_dns_configuration.sh"
        "scripts/fix_homelab_node_issues.sh"
        "scripts/fix_remaining_pod_issues.sh"
    )
    
    local control_plane_ip="192.168.4.63"
    
    # Check if we're already running on the control plane
    if is_running_on_control_plane; then
        info "Running post-deployment fixes locally (already on control plane)..."
        
        # Clean up any existing Jellyfin resources that might conflict
        info "Cleaning up any conflicting Jellyfin resources..."
        kubectl delete pvc -n jellyfin --all --ignore-not-found=true || true
        kubectl delete pv jellyfin-config-pv jellyfin-media-pv --ignore-not-found=true || true
        # Clean up existing services and deployments to prevent port conflicts
        kubectl delete service -n jellyfin jellyfin-service --ignore-not-found=true || true
        kubectl delete service -n jellyfin jellyfin --ignore-not-found=true || true
        kubectl delete deployment -n jellyfin jellyfin --ignore-not-found=true || true
        kubectl delete pod -n jellyfin jellyfin --ignore-not-found=true || true
        
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
        
        # First clean up any conflicting Jellyfin resources
        info "Cleaning up any conflicting Jellyfin resources on remote control plane..."
        ssh root@$control_plane_ip "kubectl delete pvc -n jellyfin --all --ignore-not-found=true || true" || true
        ssh root@$control_plane_ip "kubectl delete pv jellyfin-config-pv jellyfin-media-pv --ignore-not-found=true || true" || true
        # Clean up existing services and deployments to prevent port conflicts
        ssh root@$control_plane_ip "kubectl delete service -n jellyfin jellyfin-service --ignore-not-found=true || true" || true
        ssh root@$control_plane_ip "kubectl delete service -n jellyfin jellyfin --ignore-not-found=true || true" || true
        ssh root@$control_plane_ip "kubectl delete deployment -n jellyfin jellyfin --ignore-not-found=true || true" || true
        ssh root@$control_plane_ip "kubectl delete pod -n jellyfin jellyfin --ignore-not-found=true || true" || true
        
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

# Function to perform node discovery
node_discovery() {
    info "Performing node discovery..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local log_file="ansible/artifacts/arc-network-diagnosis/node-discovery-${timestamp}.log"
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$log_file")"
    
    {
        echo "=== VMStation Node Discovery ==="
        echo "Timestamp: $(date)"
        echo ""
        
        if command -v kubectl >/dev/null 2>&1; then
            echo "### Cluster Version Information ###"
            kubectl version --short 2>/dev/null || echo "Failed to get version info"
            echo ""
            
            echo "### Node Information ###"
            kubectl get nodes -o wide 2>/dev/null || echo "Failed to get node info"
            echo ""
            
            echo "### Node Summary ###"
            kubectl get nodes --no-headers 2>/dev/null | while read -r line; do
                if [ -n "$line" ]; then
                    node_name=$(echo "$line" | awk '{print $1}')
                    node_status=$(echo "$line" | awk '{print $2}')
                    node_roles=$(echo "$line" | awk '{print $3}')
                    node_age=$(echo "$line" | awk '{print $4}')
                    node_version=$(echo "$line" | awk '{print $5}')
                    node_ip=$(echo "$line" | awk '{print $6}')
                    echo "Node: $node_name | Status: $node_status | Roles: $node_roles | IP: $node_ip | Version: $node_version"
                fi
            done
        else
            echo "kubectl not available - node discovery requires running on master node"
        fi
    } | tee "$log_file"
    
    info "Node discovery logged to: $log_file"
}

# Function to create timestamped backup directory
create_backup_directory() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_dir="ansible/artifacts/arc-network-diagnosis/backup-${timestamp}"
    
    mkdir -p "$backup_dir"
    echo "$backup_dir"
}

# Function to collect network diagnostics and backups
collect_network_backups() {
    local backup_dir="$1"
    
    info "Collecting network backups and diagnostics to: $backup_dir"
    
    if ! command -v kubectl >/dev/null 2>&1; then
        warn "kubectl not available - backup collection requires running on master node"
        return 1
    fi
    
    # Save current manifests and objects
    info "Backing up current kube-proxy configuration..."
    kubectl get daemonset kube-proxy -n kube-system -o yaml > "$backup_dir/kube-proxy-daemonset.yaml" 2>/dev/null || warn "Failed to backup kube-proxy daemonset"
    kubectl get cm kube-proxy -n kube-system -o yaml > "$backup_dir/kube-proxy-configmap.yaml" 2>/dev/null || warn "Failed to backup kube-proxy configmap"
    
    info "Backing up current CoreDNS configuration..."
    kubectl get deployment coredns -n kube-system -o yaml > "$backup_dir/coredns-deployment.yaml" 2>/dev/null || warn "Failed to backup coredns deployment"
    kubectl get configmap coredns -n kube-system -o yaml > "$backup_dir/coredns-configmap.yaml" 2>/dev/null || warn "Failed to backup coredns configmap"
    kubectl get service kube-dns -n kube-system -o yaml > "$backup_dir/coredns-service.yaml" 2>/dev/null || warn "Failed to backup coredns service"
    
    # Collect logs
    info "Collecting current logs..."
    kubectl -n kube-system logs -l k8s-app=kube-dns --tail=500 > "$backup_dir/coredns-logs.txt" 2>/dev/null || warn "Failed to collect CoreDNS logs"
    kubectl -n kube-system logs -l k8s-app=kube-proxy --tail=500 > "$backup_dir/kube-proxy-logs.txt" 2>/dev/null || warn "Failed to collect kube-proxy logs"
    
    # System state snapshots
    info "Collecting system state snapshots..."
    if command -v iptables-save >/dev/null 2>&1; then
        sudo iptables-save > "$backup_dir/iptables-save.txt" 2>/dev/null || warn "Failed to save iptables rules"
    fi
    
    # Network interface information
    ip -d link show > "$backup_dir/links.txt" 2>/dev/null || warn "Failed to collect network links"
    
    # CNI configuration backup
    if [ -d "/etc/cni/net.d" ]; then
        cp -r /etc/cni/net.d "$backup_dir/cni-net.d" 2>/dev/null || warn "Failed to backup CNI config"
    fi
    
    if [ -d "/opt/cni/bin" ]; then
        ls -la /opt/cni/bin > "$backup_dir/cni-bin-list.txt" 2>/dev/null || warn "Failed to list CNI binaries"
    fi
    
    success "Backup collection completed in: $backup_dir"
}

# Function to reset network control plane (kube-proxy and CoreDNS)
reset_network_control_plane() {
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local log_file="ansible/artifacts/arc-network-diagnosis/reset-${timestamp}.log"
    
    # Create log directory
    mkdir -p "$(dirname "$log_file")"
    
    {
        echo "=== VMStation Network Control Plane Reset ==="
        echo "Timestamp: $(date)"
        echo "Target: kube-proxy and CoreDNS only"
        echo ""
        
        if [ "$CONFIRM_RESET" = false ]; then
            echo "ERROR: Network reset requires explicit confirmation"
            echo "Use --confirm flag to proceed with destructive operations"
            echo ""
            echo "This operation will:"
            echo "  - Delete existing kube-proxy DaemonSet"
            echo "  - Delete existing CoreDNS Deployment and Service"
            echo "  - Apply fresh canonical manifests"
            echo ""
            echo "Backups will be created before any destructive operations."
            return 1
        fi
        
        if [ "$DRY_RUN" = true ]; then
            echo "DRY RUN MODE: Would perform network reset operations"
            echo ""
            echo "Operations that would be performed:"
            echo "  1. Create timestamped backup directory"
            echo "  2. Backup current kube-proxy and CoreDNS configurations"
            echo "  3. Collect diagnostic logs and system state"
            echo "  4. Delete kube-proxy DaemonSet"
            echo "  5. Delete CoreDNS Deployment and Service"
            echo "  6. Apply fresh manifests from manifests/network/"
            echo "  7. Wait for readiness and verify functionality"
            return 0
        fi
        
        if ! command -v kubectl >/dev/null 2>&1; then
            echo "ERROR: kubectl not available - network reset requires running on master node"
            return 1
        fi
        
        # Step 1: Create backup directory
        echo "Step 1: Creating backup directory..."
        local backup_dir
        backup_dir=$(create_backup_directory)
        echo "Backup directory: $backup_dir"
        
        # Step 2: Collect backups and diagnostics
        echo ""
        echo "Step 2: Collecting backups and diagnostics..."
        if ! collect_network_backups "$backup_dir"; then
            echo "ERROR: Failed to collect backups"
            return 1
        fi
        
        # Step 3: Delete existing resources
        echo ""
        echo "Step 3: Removing existing network control plane resources..."
        
        echo "Deleting kube-proxy DaemonSet..."
        kubectl -n kube-system delete daemonset kube-proxy --ignore-not-found 2>/dev/null || warn "Failed to delete kube-proxy daemonset"
        
        echo "Deleting CoreDNS resources..."
        kubectl -n kube-system delete deployment coredns --ignore-not-found 2>/dev/null || warn "Failed to delete coredns deployment"
        kubectl -n kube-system delete svc kube-dns --ignore-not-found 2>/dev/null || warn "Failed to delete kube-dns service"
        
        # Step 4: Apply fresh manifests
        echo ""
        echo "Step 4: Applying fresh canonical manifests..."
        
        if [ ! -d "manifests/network" ]; then
            echo "ERROR: Network manifests directory not found: manifests/network"
            return 1
        fi
        
        # Apply manifests in order
        local manifests=(
            "manifests/network/kube-proxy-configmap.yaml"
            "manifests/network/kube-proxy-daemonset.yaml"
            "manifests/network/coredns-configmap.yaml"
            "manifests/network/coredns-service.yaml"
            "manifests/network/coredns-deployment.yaml"
        )
        
        for manifest in "${manifests[@]}"; do
            if [ -f "$manifest" ]; then
                echo "Applying: $manifest"
                if kubectl apply -f "$manifest"; then
                    echo "✓ Successfully applied $manifest"
                else
                    echo "✗ Failed to apply $manifest"
                    return 1
                fi
            else
                echo "WARNING: Manifest not found: $manifest"
            fi
        done
        
        # Step 5: Wait for readiness
        echo ""
        echo "Step 5: Waiting for network control plane readiness..."
        
        echo "Waiting for kube-proxy DaemonSet to be ready..."
        if timeout 120 kubectl rollout status daemonset/kube-proxy -n kube-system; then
            echo "✓ kube-proxy DaemonSet is ready"
        else
            echo "⚠️ kube-proxy DaemonSet readiness timeout"
        fi
        
        echo "Waiting for CoreDNS Deployment to be ready..."
        if timeout 120 kubectl rollout status deployment/coredns -n kube-system; then
            echo "✓ CoreDNS Deployment is ready"
        else
            echo "⚠️ CoreDNS Deployment readiness timeout"
        fi
        
        # Step 6: Verify endpoints
        echo ""
        echo "Step 6: Verifying DNS service endpoints..."
        kubectl get endpoints kube-dns -n kube-system || warn "Failed to get kube-dns endpoints"
        
        echo ""
        echo "Network control plane reset completed successfully!"
        echo "Backup location: $backup_dir"
        echo "Log location: $log_file"
        
        # Step 7: Run verification
        echo ""
        echo "Step 7: Running post-reset verification..."
        if verify_network_functionality; then
            echo "✓ Network functionality verification passed"
        else
            echo "⚠️ Network functionality verification failed"
            echo ""
            echo "Attempting automatic rollback..."
            if rollback_network_reset "$backup_dir"; then
                echo "✓ Rollback completed successfully"
                echo "Please investigate the issue before attempting reset again"
            else
                echo "✗ Rollback failed"
                echo "Manual intervention required - restore from backup: $backup_dir"
            fi
            return 1
        fi
        
    } | tee "$log_file"
    
    local exit_code=${PIPESTATUS[0]}
    if [ $exit_code -eq 0 ]; then
        success "Network reset completed successfully"
    else
        error "Network reset failed - check log: $log_file"
        return $exit_code
    fi
}

# Function to verify network functionality after reset
verify_network_functionality() {
    info "Verifying network functionality..."
    
    if ! command -v kubectl >/dev/null 2>&1; then
        warn "kubectl not available - verification requires running on master node"
        return 1
    fi
    
    local success=true
    
    # Check kube-proxy DaemonSet status
    info "Checking kube-proxy DaemonSet status..."
    local proxy_desired proxy_ready
    proxy_desired=$(kubectl get daemonset kube-proxy -n kube-system -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    proxy_ready=$(kubectl get daemonset kube-proxy -n kube-system -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    
    if [ "$proxy_desired" = "$proxy_ready" ] && [ "$proxy_ready" -gt 0 ]; then
        success "✓ kube-proxy DaemonSet: $proxy_ready/$proxy_desired ready"
    else
        error "✗ kube-proxy DaemonSet: $proxy_ready/$proxy_desired ready"
        success=false
    fi
    
    # Check CoreDNS Deployment status
    info "Checking CoreDNS Deployment status..."
    local dns_desired dns_ready
    dns_desired=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    dns_ready=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [ "$dns_desired" = "$dns_ready" ] && [ "$dns_ready" -gt 0 ]; then
        success "✓ CoreDNS Deployment: $dns_ready/$dns_desired ready"
    else
        error "✗ CoreDNS Deployment: $dns_ready/$dns_ready ready"
        success=false
    fi
    
    # Check DNS service endpoints
    info "Checking DNS service endpoints..."
    local endpoints
    endpoints=$(kubectl get endpoints kube-dns -n kube-system -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
    
    if [ -n "$endpoints" ]; then
        success "✓ DNS service has endpoints: $endpoints"
    else
        error "✗ DNS service has no endpoints"
        success=false
    fi
    
    # Check iptables rules for KUBE-SERVICES
    info "Checking iptables NAT rules..."
    if command -v iptables >/dev/null 2>&1; then
        if sudo iptables -t nat -L KUBE-SERVICES >/dev/null 2>&1; then
            success "✓ KUBE-SERVICES iptables chain exists"
        else
            error "✗ KUBE-SERVICES iptables chain missing"
            success=false
        fi
        
        if sudo iptables -t nat -L POSTROUTING | grep -q KUBE-POSTROUTING; then
            success "✓ KUBE-POSTROUTING masquerade rules found"
        else
            warn "⚠️ KUBE-POSTROUTING rules not found (may be normal)"
        fi
    else
        warn "⚠️ iptables not available for rule verification"
    fi
    
    if [ "$success" = true ]; then
        success "Network functionality verification passed"
        return 0
    else
        error "Network functionality verification failed"
        return 1
    fi
}

# Function to rollback network reset using backups
rollback_network_reset() {
    local backup_dir="$1"
    
    if [ ! -d "$backup_dir" ]; then
        error "Backup directory not found: $backup_dir"
        return 1
    fi
    
    warn "Rolling back network reset using backups from: $backup_dir"
    
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not available - rollback requires running on master node"
        return 1
    fi
    
    # Restore kube-proxy
    if [ -f "$backup_dir/kube-proxy-configmap.yaml" ]; then
        info "Restoring kube-proxy ConfigMap..."
        kubectl apply -f "$backup_dir/kube-proxy-configmap.yaml" || warn "Failed to restore kube-proxy configmap"
    fi
    
    if [ -f "$backup_dir/kube-proxy-daemonset.yaml" ]; then
        info "Restoring kube-proxy DaemonSet..."
        kubectl apply -f "$backup_dir/kube-proxy-daemonset.yaml" || warn "Failed to restore kube-proxy daemonset"
    fi
    
    # Restore CoreDNS
    if [ -f "$backup_dir/coredns-configmap.yaml" ]; then
        info "Restoring CoreDNS ConfigMap..."
        kubectl apply -f "$backup_dir/coredns-configmap.yaml" || warn "Failed to restore coredns configmap"
    fi
    
    if [ -f "$backup_dir/coredns-service.yaml" ]; then
        info "Restoring CoreDNS Service..."
        kubectl apply -f "$backup_dir/coredns-service.yaml" || warn "Failed to restore coredns service"
    fi
    
    if [ -f "$backup_dir/coredns-deployment.yaml" ]; then
        info "Restoring CoreDNS Deployment..."
        kubectl apply -f "$backup_dir/coredns-deployment.yaml" || warn "Failed to restore coredns deployment"
    fi
    
    info "Rollback completed. Waiting for pods to be ready..."
    sleep 30
    
    # Wait for rollback to complete
    kubectl rollout status daemonset/kube-proxy -n kube-system --timeout=120s || warn "kube-proxy rollback timeout"
    kubectl rollout status deployment/coredns -n kube-system --timeout=120s || warn "coredns rollback timeout"
    
    success "Network reset rollback completed"
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
        --confirm)
            CONFIRM_RESET=true
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
        net-reset)
            COMMAND="net-reset"
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
    net-reset)
        node_discovery
        reset_network_control_plane
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
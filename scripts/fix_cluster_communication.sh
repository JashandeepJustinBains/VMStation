#!/bin/bash

# Master Cluster Communication Fix Script
# This script addresses all the issues identified in the problem statement:
# 1. kubectl configuration on worker nodes
# 2. kube-proxy CrashLoopBackOff issues
# 3. iptables/nftables compatibility
# 4. NodePort service connectivity
# 5. CNI/Flannel networking problems

set -e

# CLI flags
NON_INTERACTIVE=false
COLLECT_LOGS=true

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --non-interactive|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        --no-collect-logs)
            COLLECT_LOGS=false
            shift
            ;;
        *)
            shift
            ;;
    esac
done

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

echo "=== VMStation Cluster Communication Master Fix ==="
echo "Timestamp: $(date)"
echo "This script will fix the following issues:"
echo "  - kubectl connection refused errors on worker nodes"
echo "  - kube-proxy CrashLoopBackOff problems"  
echo "  - iptables/nftables compatibility issues"
echo "  - NodePort service connectivity failures"
echo "  - CNI bridge conflicts"
echo

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to run a script and handle errors
run_fix_script() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"
    local description="$2"
    
    if [ -f "$script_path" ]; then
        info "Running: $description"
        echo "Script: $script_name"
        
        if bash "$script_path" "${@:3}"; then
            success "✅ $description completed successfully"
            return 0
        else
            warn "⚠️  $description completed with warnings or errors"
            return 1
        fi
    else
        error "Script not found: $script_path"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
    
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl is required but not found"
        echo "Please install kubectl first"
        exit 1
    fi
    
    success "✅ Prerequisites check passed"
}

# Function to perform initial diagnosis
initial_diagnosis() {
    info "=== Initial Problem Diagnosis ==="
    
    # Check if we can access the cluster
    local can_access_cluster=false
    if timeout 10 kubectl get nodes >/dev/null 2>&1; then
        can_access_cluster=true
        info "✅ kubectl can access the cluster"
        
        echo "Current cluster status:"
        kubectl get nodes -o wide
        
        echo
        echo "Current pod issues:"
        kubectl get pods --all-namespaces | grep -E "(CrashLoopBackOff|ContainerCreating|Pending)" || echo "No problematic pods found"
        
    else
        warn "⚠️  kubectl cannot access cluster - this will be fixed"
    fi
    
    # Check for iptables issues
    echo
    info "Checking for iptables compatibility issues..."
    if iptables -t nat -L >/dev/null 2>&1; then
        info "✅ iptables NAT table accessible"
    else
        local iptables_error=$(iptables -t nat -L 2>&1 || echo "")
        if echo "$iptables_error" | grep -q "nf_tables.*incompatible"; then
            warn "⚠️  iptables/nftables compatibility issue detected"
        else
            warn "⚠️  iptables has other issues"
        fi
        echo "Error: $iptables_error"
    fi
    
    # Check CNI bridge
    echo
    info "Checking CNI bridge configuration..."
    if ip addr show cni0 >/dev/null 2>&1; then
        local cni_ip=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
        if [ -n "$cni_ip" ]; then
            if echo "$cni_ip" | grep -q "10.244."; then
                info "✅ CNI bridge IP is correct: $cni_ip"
            else
                warn "⚠️  CNI bridge IP may be incorrect: $cni_ip"
            fi
        fi
    else
        warn "⚠️  No CNI bridge found"
    fi
    
    echo
    if [ "$NON_INTERACTIVE" = false ]; then
        read -p "Press Enter to continue with fixes, or Ctrl+C to abort..."
    else
        info "Non-interactive mode: continuing without user prompt"
    fi
}

# Collect diagnostics (kubectl output + pod logs) to a timestamped directory
collect_diagnostics() {
    if [ "$COLLECT_LOGS" != true ]; then
        warn "Skipping diagnostics collection (disabled)"
        return
    fi

    local outdir="/tmp/fix-cluster-diag-$(date +%s)"
    mkdir -p "$outdir"
    info "Collecting diagnostics to $outdir"

    kubectl get nodes -o wide > "$outdir"/nodes.txt 2>&1 || true
    kubectl get pods --all-namespaces -o wide > "$outdir"/pods.txt 2>&1 || true
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' > "$outdir"/events.txt 2>&1 || true

    # collect logs and describe for known system components that often fail
    for ns in kube-system kube-flannel kube-system monitoring jellyfin; do
        kubectl -n "$ns" get pods -o name 2>/dev/null | while read -r p; do
            name=$(echo "$p" | sed 's#pod/##')
            kubectl -n "$ns" describe pod "$name" > "$outdir/${ns}-${name}-describe.txt" 2>&1 || true
            kubectl -n "$ns" logs "$name" --all-containers=true > "$outdir/${ns}-${name}-logs.txt" 2>&1 || true
        done
    done

    info "Diagnostics collected. Tarball: ${outdir}.tar.gz"
    tar -czf "${outdir}.tar.gz" -C "$(dirname "$outdir")" "$(basename "$outdir")" || true
}

# Main execution
main() {
    local overall_success=true
    
    # Check prerequisites
    check_prerequisites
    
    # Initial diagnosis
    initial_diagnosis
    
    echo
    info "=== Starting Cluster Communication Fixes ==="
    
    # Fix 1: iptables/nftables compatibility (run first as it affects other components)
    echo
    info "Step 1: Fixing iptables/nftables compatibility issues"
    if ! run_fix_script "fix_iptables_compatibility.sh" "iptables/nftables compatibility fix"; then
        warn "iptables compatibility fix had issues, attempting diagnostics and retries"
        overall_success=false
        collect_diagnostics
    fi
    
    # Fix 2: CNI bridge conflicts (run before pod fixes)
    echo
    info "Step 2: Fixing CNI bridge conflicts"
    if ! run_fix_script "fix_cni_bridge_conflict.sh" "CNI bridge conflict fix"; then
        warn "CNI bridge fix had issues, attempting diagnostics and retrying flannel daemonset restart"
        overall_success=false
        collect_diagnostics
        kubectl -n kube-flannel rollout restart daemonset kube-flannel-ds 2>/dev/null || kubectl -n kube-system rollout restart daemonset kube-flannel-ds 2>/dev/null || true
        sleep 8
    fi
    
    # Fix 2b: Worker node specific CNI issues (addresses pod-to-pod communication failures)
    echo
    info "Step 2b: Fixing worker node CNI communication issues"
    if ! run_fix_script "fix_worker_node_cni.sh" "Worker node CNI communication fix" "--node" "storagenodet3500"; then
        warn "Worker node CNI fix had issues, collecting diagnostics"
        overall_success=false
        collect_diagnostics
    fi
    
    # Fix 2c: Flannel mixed-OS configuration issues
    echo
    info "Step 2c: Fixing Flannel configuration for mixed OS environment"
    if ! run_fix_script "fix_flannel_mixed_os.sh" "Flannel mixed-OS configuration fix"; then
        warn "Flannel configuration fix had issues, collecting diagnostics"
        overall_success=false
        collect_diagnostics
    fi
    
    # Fix 3: kube-proxy and remaining pod issues
    echo
    info "Step 3: Fixing kube-proxy and pod issues"
    if ! run_fix_script "fix_remaining_pod_issues.sh" "kube-proxy and pod issues fix"; then
        warn "Pod issues fix had issues, attempting diagnostics and daemonset restarts"
        overall_success=false
        collect_diagnostics
        # Try restarting kube-proxy and flannel daemonsets as a remediation attempt
        kubectl -n kube-system rollout restart daemonset kube-proxy || true
        kubectl -n kube-flannel rollout restart daemonset kube-flannel-ds 2>/dev/null || kubectl -n kube-system rollout restart daemonset kube-flannel-ds 2>/dev/null || true
        info "Requested daemonset restarts; waiting briefly for pods to come up"
        sleep 12
    fi
    
    # Fix 4: kubectl configuration on worker nodes
    echo
    info "Step 4: Fixing kubectl configuration on worker nodes"
    if ! run_fix_script "fix_worker_kubectl_config.sh" "kubectl worker node configuration"; then
        warn "kubectl configuration had issues, collecting diagnostics"
        overall_success=false
        collect_diagnostics
    fi
    
    # Wait for services to stabilize
    echo
    info "Waiting for services to stabilize..."
    sleep 30
    
    # Validation
    echo
    info "=== Final Validation ==="
    if ! run_fix_script "validate_cluster_communication.sh" "cluster communication validation"; then
        warn "Validation found remaining issues, collecting diagnostics"
        overall_success=false
        collect_diagnostics
    fi
    
    # Additional pod-to-pod connectivity validation (addresses specific problem statement scenario)
    echo
    info "=== Pod-to-Pod Connectivity Validation ==="
    if ! run_fix_script "validate_pod_connectivity.sh" "pod-to-pod connectivity validation"; then
        warn "Pod connectivity validation found issues - may need worker node CNI fix"
        overall_success=false
        collect_diagnostics
    fi
    
    # Final summary
    echo
    info "=== Fix Summary ==="
    
    if [ "$overall_success" = "true" ]; then
        success "🎉 All fixes completed successfully!"
        echo
        echo "Cluster communication should now be working correctly:"
        echo "✅ kubectl configured on all nodes"
        echo "✅ kube-proxy running correctly"
        echo "✅ iptables compatibility issues resolved"
        echo "✅ CNI networking functional"
        echo "✅ NodePort services accessible"
        
        echo
        echo "You can now test NodePort access with:"
        echo "  curl http://<node-ip>:30096/  # For Jellyfin service"
        
    else
        warn "⚠️  Some fixes completed with warnings or errors"
        echo
        echo "Common remaining issues and solutions:"
        echo "1. If kubectl still fails: manually copy kubeconfig from control plane"
        echo "2. If NodePort not accessible: check firewall settings"
        echo "3. If pods still crash: check pod logs for specific errors"
        echo "4. If networking fails: consider cluster restart"
        
        echo
        echo "For detailed diagnostics, run:"
        echo "  ./scripts/validate_cluster_communication.sh"
        echo "  kubectl get pods --all-namespaces"
        echo "  kubectl get events --all-namespaces --sort-by='.lastTimestamp'"
    fi
    
    echo
    echo "=== Master Fix Complete ==="
    echo "Timestamp: $(date)"
}

# Run main function
main "$@"
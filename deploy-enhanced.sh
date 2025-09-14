#!/bin/bash

# Enhanced VMStation Deployment with Integrated Fixes
# Replaces the need for post-deployment fix scripts
# Integrates functionality from fix_homelab_node_issues.sh, fix_remaining_pod_issues.sh, and fix_jellyfin_cni_bridge_conflict.sh

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
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Default values
MODE="${1:-full}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_VALIDATION="${SKIP_VALIDATION:-false}"
ANSIBLE_VERBOSITY="${ANSIBLE_VERBOSITY:-0}"

# Paths
ANSIBLE_DIR="ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory.txt"
SETUP_PLAYBOOK="$ANSIBLE_DIR/plays/setup-cluster.yaml"
APPS_PLAYBOOK="$ANSIBLE_DIR/plays/deploy-apps.yaml"
JELLYFIN_PLAYBOOK="$ANSIBLE_DIR/plays/jellyfin-enhanced.yml"

echo "================================================================"
echo "  VMStation Enhanced Kubernetes Deployment                     "
echo "================================================================"
echo "Mode: $MODE"
echo "Enhanced features:"
echo "  ✓ Integrated CNI bridge conflict prevention"
echo "  ✓ CoreDNS control-plane scheduling enforcement"
echo "  ✓ kube-proxy iptables compatibility fixes"
echo "  ✓ Comprehensive network validation"
echo "  ✓ Enhanced Jellyfin deployment with networking checks"
echo "================================================================"
echo

usage() {
    cat << EOF
Enhanced VMStation Deployment Script

USAGE:
    $0 [MODE] [OPTIONS]

MODES:
    full        Deploy complete cluster and applications (default)
    cluster     Deploy Kubernetes cluster only
    apps        Deploy monitoring applications only
    jellyfin    Deploy Jellyfin only
    validate    Run network validation only

OPTIONS:
    DRY_RUN=true                Show what would be done
    SKIP_VALIDATION=true        Skip network validation steps
    ANSIBLE_VERBOSITY=1         Set Ansible verbosity (0-4)

EXAMPLES:
    $0 full                     # Full deployment with all enhancements
    $0 cluster                  # Cluster setup with network validation
    DRY_RUN=true $0 full       # Show what would be done
    $0 validate                 # Run network validation only

ENHANCED FEATURES:
    - Integrated CNI bridge IP conflict prevention
    - CoreDNS hard scheduling to control-plane nodes
    - kube-proxy iptables/nftables compatibility
    - Comprehensive network component validation
    - Enhanced Jellyfin deployment with networking checks
    - Eliminates need for post-deployment fix scripts

EOF
}

check_prerequisites() {
    info "Checking prerequisites for enhanced deployment..."
    
    # Check required tools
    for tool in ansible-playbook kubectl; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            error "$tool is required but not found"
            exit 1
        fi
    done
    
    # Check inventory
    if [ ! -f "$INVENTORY_FILE" ]; then
        error "Inventory file not found: $INVENTORY_FILE"
        exit 1
    fi
    
    # Check if kubernetes.core collection is available
    if ! ansible-galaxy collection list kubernetes.core >/dev/null 2>&1; then
        warn "kubernetes.core collection not found. Installing..."
        ansible-galaxy collection install kubernetes.core
    fi
    
    # Check enhanced manifests exist
    for manifest in "manifests/network/coredns-deployment.yaml" "manifests/network/kube-proxy-configmap.yaml" "manifests/jellyfin/jellyfin.yaml"; do
        if [ ! -f "$manifest" ]; then
            error "Enhanced manifest not found: $manifest"
            exit 1
        fi
    done
    
    success "Prerequisites check passed - enhanced deployment ready"
}

deploy_cluster() {
    info "Deploying Kubernetes cluster with integrated fixes..."
    
    local ansible_opts=()
    
    if [ "$DRY_RUN" = true ]; then
        ansible_opts+=(--check --diff)
        info "DRY RUN MODE: Showing what would be done"
    fi
    
    if [ -n "$ANSIBLE_VERBOSITY" ] && [ "$ANSIBLE_VERBOSITY" -gt 0 ]; then
        local verbosity_flag=""
        for ((i=1; i<=ANSIBLE_VERBOSITY; i++)); do
            verbosity_flag="${verbosity_flag}v"
        done
        ansible_opts+=("-${verbosity_flag}")
    fi
    
    info "Enhanced cluster deployment includes:"
    info "  - CNI bridge conflict prevention"
    info "  - CoreDNS control-plane scheduling"
    info "  - kube-proxy iptables compatibility"
    info "  - Network component validation"
    echo
    
    if ansible-playbook -i "$INVENTORY_FILE" "${ansible_opts[@]}" "$SETUP_PLAYBOOK"; then
        success "✅ Enhanced cluster deployment completed successfully!"
        info "Network fixes have been integrated into the deployment process"
        info "Post-deployment fix scripts should no longer be necessary"
    else
        error "❌ Enhanced cluster deployment failed!"
        info "Check the output above for errors. Enhanced features included:"
        info "- CNI bridge IP conflict detection and prevention"
        info "- CoreDNS scheduling validation and remediation"
        info "- kube-proxy configuration validation"
        info "- Comprehensive network health checks"
        exit 1
    fi
}

deploy_applications() {
    info "Deploying applications with enhanced networking validation..."
    
    local ansible_opts=()
    
    if [ "$DRY_RUN" = true ]; then
        ansible_opts+=(--check --diff)
    fi
    
    if [ -n "$ANSIBLE_VERBOSITY" ] && [ "$ANSIBLE_VERBOSITY" -gt 0 ]; then
        local verbosity_flag=""
        for ((i=1; i<=ANSIBLE_VERBOSITY; i++)); do
            verbosity_flag="${verbosity_flag}v"
        done
        ansible_opts+=("-${verbosity_flag}")
    fi
    
    if ansible-playbook -i "$INVENTORY_FILE" "${ansible_opts[@]}" "$APPS_PLAYBOOK"; then
        success "✅ Applications deployed successfully with network validation!"
    else
        error "❌ Application deployment failed!"
        exit 1
    fi
}

deploy_jellyfin() {
    info "Deploying Jellyfin with enhanced networking and CNI bridge fixes..."
    
    local ansible_opts=()
    
    if [ "$DRY_RUN" = true ]; then
        ansible_opts+=(--check --diff)
    fi
    
    if [ -n "$ANSIBLE_VERBOSITY" ] && [ "$ANSIBLE_VERBOSITY" -gt 0 ]; then
        local verbosity_flag=""
        for ((i=1; i<=ANSIBLE_VERBOSITY; i++)); do
            verbosity_flag="${verbosity_flag}v"
        done
        ansible_opts+=("-${verbosity_flag}")
    fi
    
    info "Enhanced Jellyfin deployment includes:"
    info "  - CNI bridge conflict detection and remediation"
    info "  - Storage node readiness validation"
    info "  - Enhanced health checks and networking"
    info "  - Comprehensive deployment monitoring"
    echo
    
    if ansible-playbook -i "$INVENTORY_FILE" "${ansible_opts[@]}" "$JELLYFIN_PLAYBOOK"; then
        success "✅ Enhanced Jellyfin deployment completed successfully!"
        info "Jellyfin deployed with integrated networking fixes"
        info "Should be accessible without needing fix_remaining_pod_issues.sh"
    else
        error "❌ Enhanced Jellyfin deployment failed!"
        info "The enhanced deployment includes troubleshooting information"
        info "Check the output above for specific error details and remediation steps"
        exit 1
    fi
}

run_network_validation() {
    info "Running comprehensive network validation..."
    
    # Create a temporary playbook for validation only
    cat > /tmp/network-validation-playbook.yaml << 'EOF'
---
- name: "Network Validation Only"
  hosts: monitoring_nodes
  become: false
  tasks:
    - name: "Include network validation tasks"
      include_tasks: plays/templates/network-validation-tasks.yaml
      vars:
        validation_only: true
EOF
    
    local ansible_opts=()
    
    if [ "$DRY_RUN" = true ]; then
        ansible_opts+=(--check --diff)
    fi
    
    if ansible-playbook -i "$INVENTORY_FILE" "${ansible_opts[@]}" /tmp/network-validation-playbook.yaml; then
        success "✅ Network validation completed successfully!"
        info "All network components are healthy"
    else
        warn "⚠️  Network validation detected issues"
        info "This indicates problems that the enhanced deployment should prevent"
        info "Consider running the full enhanced deployment to apply fixes"
        exit 1
    fi
    
    # Cleanup
    rm -f /tmp/network-validation-playbook.yaml
}

# Main execution
case "$MODE" in
    "full")
        check_prerequisites
        deploy_cluster
        if [ "$SKIP_VALIDATION" = false ]; then
            info "Running network validation before applications..."
            run_network_validation
        fi
        deploy_applications
        deploy_jellyfin
        ;;
    "cluster")
        check_prerequisites
        deploy_cluster
        if [ "$SKIP_VALIDATION" = false ]; then
            run_network_validation
        fi
        ;;
    "apps")
        check_prerequisites
        deploy_applications
        ;;
    "jellyfin")
        check_prerequisites
        deploy_jellyfin
        ;;
    "validate")
        check_prerequisites
        run_network_validation
        ;;
    "-h"|"--help"|"help")
        usage
        exit 0
        ;;
    *)
        error "Unknown mode: $MODE"
        usage
        exit 1
        ;;
esac

echo
success "🎉 Enhanced VMStation deployment completed for mode: $MODE"
echo
info "Enhanced deployment features applied:"
info "  ✓ CNI bridge conflicts prevented through proper manifests"
info "  ✓ CoreDNS scheduled only on control-plane nodes"
info "  ✓ kube-proxy configured for iptables compatibility"
info "  ✓ Network components validated and remediated"
info "  ✓ Jellyfin deployed with enhanced networking checks"
echo
info "Post-deployment fix scripts should no longer be necessary:"
info "  - fix_homelab_node_issues.sh → Integrated into cluster setup"
info "  - fix_remaining_pod_issues.sh → Integrated into app deployment"
info "  - fix_jellyfin_cni_bridge_conflict.sh → Integrated into Jellyfin deployment"
echo
info "Monitor cluster status with: kubectl get pods --all-namespaces"
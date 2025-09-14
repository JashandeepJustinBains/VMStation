#!/bin/bash

# VMStation Single-Command Kubernetes Deployment
# Fixes CNI bridge issues and deploys working cluster with minimal manifests

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFESTS_DIR="$PROJECT_ROOT/manifests"
ANSIBLE_DIR="$PROJECT_ROOT/ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory/hosts.yml"

# Deployment mode
DEPLOY_MODE="full"  # full, network-only, apps-only
DRY_RUN=false
SKIP_CNI_RESET=false

usage() {
    cat << EOF
VMStation Single-Command Deployment

Usage: $0 [OPTIONS] [COMMAND]

Commands:
    deploy          Deploy complete cluster (default)
    network-only    Deploy only network components (flannel, coredns, kube-proxy)
    apps-only       Deploy only applications (assumes network is working)
    reset-cni       Reset CNI bridge only
    verify          Verify deployment

Options:
    --dry-run       Show what would be done without executing
    --skip-cni      Skip CNI bridge reset (if you know it's not needed)
    --help          Show this help

Examples:
    $0 deploy                    # Full deployment with CNI reset
    $0 --skip-cni deploy         # Deploy without CNI reset
    $0 network-only              # Deploy only network components
    $0 reset-cni                 # Reset CNI bridge only
    $0 verify                    # Verify current deployment

EOF
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if we're on the control plane
    if [ ! -f "/etc/kubernetes/admin.conf" ]; then
        error "This script must be run on the Kubernetes control plane node"
        exit 1
    fi
    
    # Check if kubectl works
    if ! kubectl get nodes >/dev/null 2>&1; then
        error "kubectl not working. Is the cluster initialized?"
        exit 1
    fi
    
    # Check if ansible inventory exists
    if [ ! -f "$INVENTORY_FILE" ]; then
        error "Ansible inventory not found: $INVENTORY_FILE"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Reset CNI bridge on all nodes
reset_cni_bridge() {
    info "=== Resetting CNI Bridge on All Nodes ==="
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would reset CNI bridge on all nodes"
        return 0
    fi
    
    local reset_script="$PROJECT_ROOT/scripts/reset_cni_bridge_minimal.sh"
    
    if [ ! -f "$reset_script" ]; then
        error "CNI reset script not found: $reset_script"
        exit 1
    fi
    
    info "Running CNI bridge reset script..."
    chmod +x "$reset_script"
    
    if sudo "$reset_script"; then
        success "CNI bridge reset completed successfully"
        sleep 30  # Allow time for network stabilization
    else
        error "CNI bridge reset failed"
        exit 1
    fi
}

# Deploy network components
deploy_network() {
    info "=== Deploying Network Components ==="
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would deploy network components"
        return 0
    fi
    
    # Delete existing network components first
    info "Cleaning up existing network components..."
    kubectl delete -f "$MANIFESTS_DIR/cni/flannel.yaml" --ignore-not-found=true || true
    kubectl delete -f "$MANIFESTS_DIR/network/coredns-deployment.yaml" --ignore-not-found=true || true
    kubectl delete -f "$MANIFESTS_DIR/network/coredns-configmap.yaml" --ignore-not-found=true || true
    kubectl delete -f "$MANIFESTS_DIR/network/coredns-service.yaml" --ignore-not-found=true || true
    kubectl delete -f "$MANIFESTS_DIR/network/kube-proxy-daemonset.yaml" --ignore-not-found=true || true
    kubectl delete -f "$MANIFESTS_DIR/network/kube-proxy-configmap.yaml" --ignore-not-found=true || true
    
    # Wait for cleanup
    sleep 30
    
    # Apply minimal network manifests in order
    local network_manifests=(
        "$MANIFESTS_DIR/cni/flannel-minimal.yaml"
        "$MANIFESTS_DIR/network/kube-proxy-minimal.yaml"
        "$MANIFESTS_DIR/network/coredns-minimal.yaml"
    )
    
    for manifest in "${network_manifests[@]}"; do
        if [ -f "$manifest" ]; then
            info "Applying: $(basename "$manifest")"
            kubectl apply -f "$manifest"
            sleep 10
        else
            error "Manifest not found: $manifest"
            exit 1
        fi
    done
    
    # Wait for network components to be ready
    info "Waiting for network components to be ready..."
    
    info "Waiting for flannel DaemonSet..."
    kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel --timeout=300s || warn "Flannel rollout timeout"
    
    info "Waiting for kube-proxy DaemonSet..."
    kubectl rollout status daemonset/kube-proxy -n kube-system --timeout=300s || warn "kube-proxy rollout timeout"
    
    info "Waiting for CoreDNS Deployment..."
    kubectl rollout status deployment/coredns -n kube-system --timeout=300s || warn "CoreDNS rollout timeout"
    
    success "Network components deployed successfully"
}

# Deploy applications
deploy_applications() {
    info "=== Deploying Applications ==="
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would deploy applications"
        return 0
    fi
    
    # Deploy monitoring stack using ansible
    if [ -f "$ANSIBLE_DIR/plays/deploy-apps.yaml" ]; then
        info "Deploying monitoring stack..."
        ansible-playbook -i "$INVENTORY_FILE" "$ANSIBLE_DIR/plays/deploy-apps.yaml" || warn "Monitoring deployment had issues"
    fi
    
    # Deploy Jellyfin with minimal manifest
    info "Deploying Jellyfin..."
    kubectl delete -f "$MANIFESTS_DIR/jellyfin/jellyfin.yaml" --ignore-not-found=true || true
    sleep 10
    kubectl apply -f "$MANIFESTS_DIR/jellyfin/jellyfin-minimal.yaml"
    
    # Wait for Jellyfin pod
    info "Waiting for Jellyfin pod to be ready..."
    timeout 300 kubectl wait --for=condition=Ready pod/jellyfin -n jellyfin || warn "Jellyfin pod timeout"
    
    success "Applications deployed successfully"
}

# Verify deployment
verify_deployment() {
    info "=== Verifying Deployment ==="
    
    # Check nodes
    info "Checking node status..."
    kubectl get nodes -o wide
    
    # Check network pods
    info "Checking network pod status..."
    kubectl get pods -n kube-flannel
    kubectl get pods -n kube-system | grep -E "(coredns|kube-proxy)"
    
    # Check application pods
    info "Checking application pods..."
    kubectl get pods -n monitoring || warn "No monitoring namespace"
    kubectl get pods -n jellyfin || warn "No jellyfin namespace"
    
    # Check for stuck pods
    info "Checking for stuck pods..."
    local stuck_pods=$(kubectl get pods --all-namespaces | grep -E "(ContainerCreating|Pending|CrashLoopBackOff)" | wc -l)
    
    if [ "$stuck_pods" -eq 0 ]; then
        success "No stuck pods found"
    else
        warn "Found $stuck_pods stuck pods"
        kubectl get pods --all-namespaces | grep -E "(ContainerCreating|Pending|CrashLoopBackOff)"
    fi
    
    # Check CNI bridge status
    info "Checking CNI bridge status..."
    if ip addr show cni0 >/dev/null 2>&1; then
        local cni_ip=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
        if echo "$cni_ip" | grep -q "10.244."; then
            success "CNI bridge has correct IP: $cni_ip"
        else
            error "CNI bridge has wrong IP: $cni_ip"
        fi
    else
        warn "CNI bridge not found (may be normal if flannel not ready)"
    fi
    
    # Check recent CNI errors
    info "Checking for recent CNI bridge errors..."
    local recent_errors=$(kubectl get events --all-namespaces --field-selector reason=FailedCreatePodSandBox 2>/dev/null | grep "failed to set bridge addr.*already has an IP address different" | wc -l || echo "0")
    
    if [ "$recent_errors" -eq 0 ]; then
        success "No recent CNI bridge errors"
    else
        error "Found $recent_errors recent CNI bridge errors"
    fi
    
    # Display access URLs
    info "=== Access URLs ==="
    local master_ip="192.168.4.63"
    local storage_ip="192.168.4.61"
    
    echo "• Grafana: http://$master_ip:30300"
    echo "• Prometheus: http://$master_ip:30090"
    echo "• Jellyfin: http://$storage_ip:30096"
    
    success "Deployment verification completed"
}

# Main deployment function
deploy_full() {
    info "=== VMStation Full Deployment ==="
    echo "Timestamp: $(date)"
    echo "Mode: $DEPLOY_MODE"
    echo "Dry Run: $DRY_RUN"
    echo "Skip CNI Reset: $SKIP_CNI_RESET"
    echo ""
    
    check_prerequisites
    
    if [ "$SKIP_CNI_RESET" = false ]; then
        reset_cni_bridge
    else
        info "Skipping CNI bridge reset"
    fi
    
    deploy_network
    deploy_applications
    verify_deployment
    
    success "🎉 VMStation deployment completed successfully!"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-cni)
            SKIP_CNI_RESET=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        deploy)
            DEPLOY_MODE="full"
            shift
            ;;
        network-only)
            DEPLOY_MODE="network-only"
            shift
            ;;
        apps-only)
            DEPLOY_MODE="apps-only"
            shift
            ;;
        reset-cni)
            DEPLOY_MODE="reset-cni"
            shift
            ;;
        verify)
            DEPLOY_MODE="verify"
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution
case $DEPLOY_MODE in
    full)
        deploy_full
        ;;
    network-only)
        check_prerequisites
        if [ "$SKIP_CNI_RESET" = false ]; then
            reset_cni_bridge
        fi
        deploy_network
        verify_deployment
        ;;
    apps-only)
        check_prerequisites
        deploy_applications
        verify_deployment
        ;;
    reset-cni)
        check_prerequisites
        reset_cni_bridge
        ;;
    verify)
        check_prerequisites
        verify_deployment
        ;;
    *)
        error "Unknown deployment mode: $DEPLOY_MODE"
        usage
        exit 1
        ;;
esac
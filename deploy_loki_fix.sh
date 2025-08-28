#!/bin/bash

# Quick deployment script for Loki Stack CrashLoopBackOff fix
# Choose between different deployment methods

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    if ! command -v kubectl &> /dev/null; then
        missing+=("kubectl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing+=("helm")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing dependencies: ${missing[*]}"
        echo "Please install the missing tools before proceeding."
        exit 1
    fi
    
    info "All dependencies available"
}

# Show deployment options
show_options() {
    echo -e "${BLUE}=== VMStation Loki Stack Fix Deployment ===${NC}"
    echo ""
    echo "Select deployment method:"
    echo ""
    echo "1) Quick Helm Fix - Apply fix directly with Helm (fastest)"
    echo "2) Ansible Playbook - Deploy via updated Ansible playbook"
    echo "3) Verify Only - Check current status without changes"
    echo "4) Show Help - Display detailed instructions"
    echo ""
    echo -n "Enter your choice (1-4): "
}

# Deploy via Helm
deploy_helm() {
    info "Deploying Loki stack fix via Helm..."
    
    # Check if loki-stack-values.yaml exists
    if [[ ! -f "loki-stack-values.yaml" ]]; then
        error "loki-stack-values.yaml not found in current directory"
        exit 1
    fi
    
    # Add Grafana repo
    info "Adding Grafana Helm repository..."
    helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
    helm repo update
    
    # Apply the fix
    info "Upgrading loki-stack with improved configuration..."
    helm upgrade loki-stack grafana/loki-stack \
        --namespace monitoring \
        --values loki-stack-values.yaml \
        --timeout 10m \
        --wait
    
    info "Helm deployment completed successfully"
}

# Deploy via Ansible
deploy_ansible() {
    info "Deploying Loki stack fix via Ansible..."
    
    # Check if inventory exists
    if [[ ! -f "ansible/inventory.txt" ]]; then
        warn "ansible/inventory.txt not found"
        echo "Please ensure your inventory file is configured properly"
        exit 1
    fi
    
    # Deploy monitoring stack
    info "Running Ansible playbook..."
    ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml
    
    info "Ansible deployment completed successfully"
}

# Verify deployment
verify_deployment() {
    info "Verifying Loki stack status..."
    
    if [[ -f "verify_loki_stack_fix.sh" ]]; then
        ./verify_loki_stack_fix.sh
    else
        warn "Verification script not found, running basic checks..."
        echo ""
        echo "=== Pod Status ==="
        kubectl get pods -n monitoring -l app=loki
        kubectl get pods -n monitoring -l app=promtail
        echo ""
        echo "=== Working Pods Check ==="
        kubectl get pods -n jellyfin 2>/dev/null || echo "No jellyfin namespace found"
    fi
}

# Show help
show_help() {
    cat << 'EOF'
=== VMStation Loki Stack CrashLoopBackOff Fix Help ===

This script provides multiple ways to fix the Loki stack CrashLoopBackOff issues:

METHOD 1: Quick Helm Fix (Recommended)
--------------------------------------
Uses the standalone loki-stack-values.yaml file to apply fixes directly.

Prerequisites:
- kubectl configured for your cluster
- helm installed
- loki-stack-values.yaml in current directory

Commands:
  ./deploy_loki_fix.sh  # Select option 1

METHOD 2: Ansible Playbook
---------------------------
Uses the updated deploy_monitoring.yaml playbook with embedded fixes.

Prerequisites:
- Ansible installed
- ansible/inventory.txt configured
- Access to monitoring nodes

Commands:
  ./deploy_loki_fix.sh  # Select option 2

METHOD 3: Manual Helm Deployment
---------------------------------
If you prefer manual control:

  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo update
  helm upgrade loki-stack grafana/loki-stack \
    --namespace monitoring \
    --values loki-stack-values.yaml \
    --timeout 10m \
    --wait

VERIFICATION:
-------------
After deployment, verify the fix:

  ./verify_loki_stack_fix.sh

Or manually check:
  kubectl get pods -n monitoring -l app=loki
  kubectl get pods -n monitoring -l app=promtail

TROUBLESHOOTING:
----------------
If issues persist:
1. Check pod logs: kubectl logs -n monitoring -l app=loki
2. Check events: kubectl get events -n monitoring
3. Review documentation: LOKI_STACK_CRASHLOOP_FIX.md

ROLLBACK:
---------
If needed, rollback the Helm release:
  helm rollback loki-stack -n monitoring

EOF
}

# Main function
main() {
    check_dependencies
    
    if [[ $# -eq 1 ]]; then
        case $1 in
            "helm"|"1")
                deploy_helm
                verify_deployment
                ;;
            "ansible"|"2")
                deploy_ansible
                verify_deployment
                ;;
            "verify"|"3")
                verify_deployment
                ;;
            "help"|"4")
                show_help
                ;;
            *)
                echo "Invalid option: $1"
                show_help
                exit 1
                ;;
        esac
        return
    fi
    
    while true; do
        show_options
        read -r choice
        
        case $choice in
            1)
                deploy_helm
                verify_deployment
                break
                ;;
            2)
                deploy_ansible
                verify_deployment
                break
                ;;
            3)
                verify_deployment
                break
                ;;
            4)
                show_help
                ;;
            *)
                warn "Invalid choice. Please select 1-4."
                ;;
        esac
        echo ""
    done
    
    echo ""
    info "Deployment completed. Monitor the pods to ensure stability:"
    info "kubectl get pods -n monitoring -w"
}

# Run main function
main "$@"
#!/bin/bash

# VMStation Update and Deploy Script
# Fetches latest changes and deploys infrastructure using selectable modular playbooks

set -e

echo "=== VMStation Update and Deploy ==="
echo "Timestamp: $(date)"
echo ""

# Ensure we run git commands from the repository root.
# This makes the script resilient if invoked from another cwd or across mount boundaries.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"

if [ -d "$REPO_ROOT/.git" ]; then
    cd "$REPO_ROOT"
else
    # Try to find git top-level from current environment; fall back to REPO_ROOT
    if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        cd "$git_root"
    else
        echo "Warning: .git not found from script path; continuing from $REPO_ROOT"
        cd "$REPO_ROOT"
    fi
fi

# Fetch latest changes from remote
echo "Fetching latest changes..."
git fetch --all
git pull --ff-only

# Make deploy scripts executable
chmod +x ./ansible/deploy.sh
chmod +x ./deploy_kubernetes.sh 2>/dev/null || true

# === CONFIGURATION SETUP ===
# Ensure configuration file exists before deployment
if [ ! -f "ansible/group_vars/all.yml" ]; then
    if [ -f "ansible/group_vars/all.yml.template" ]; then
        echo "Configuration file not found. Creating from template..."
        cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml
        echo "✓ Created ansible/group_vars/all.yml from template"
        echo "  You may customize it if needed, but defaults should work for most setups"
    else
        echo "ERROR: No configuration template found at ansible/group_vars/all.yml.template"
        exit 1
    fi
fi

# === PREREQUISITE SETUP ===
# Check and fix Kubernetes service enablement before deployment
if [ -f "scripts/fix_kubernetes_service_enablement.sh" ]; then
    echo "Checking Kubernetes service enablement (kubelet, containerd)..."
    chmod +x scripts/fix_kubernetes_service_enablement.sh
    if sudo -n true 2>/dev/null; then
        echo "Running Kubernetes service enablement check..."
        if ./scripts/fix_kubernetes_service_enablement.sh; then
            echo "✓ Kubernetes services are properly enabled"
        else
            echo "⚠ Some Kubernetes services may need manual intervention"
            echo "Check the output above for specific issues"
        fi
    else
        echo "WARNING: Cannot run service commands automatically."
        echo "You may need to run this manually before deployment:"
        echo "  sudo ./scripts/fix_kubernetes_service_enablement.sh"
        echo ""
        echo "Continuing with deployment - kubelet/containerd issues may cause failures..."
    fi
    echo ""
else
    echo "INFO: Service enablement script not found - assuming services are properly configured"
fi

# Run monitoring permission setup before deployment to prevent hanging
if [ -f "scripts/fix_monitoring_permissions.sh" ]; then
    echo "Setting up monitoring directories and permissions..."
    chmod +x scripts/fix_monitoring_permissions.sh
    if sudo -n true 2>/dev/null; then
        echo "Running monitoring permission setup with sudo..."
        sudo ./scripts/fix_monitoring_permissions.sh
    else
        echo "WARNING: Cannot run sudo commands automatically."
        echo "You may need to run this manually before deployment:"
        echo "  sudo ./scripts/fix_monitoring_permissions.sh"
        echo ""
        echo "Continuing with deployment - some monitoring components may fail without proper permissions..."
    fi
else
    echo "WARNING: Monitoring permission script not found at scripts/fix_monitoring_permissions.sh"
fi

# Setup monitoring node labels for proper scheduling (if kubectl is available)
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    if [ -f "scripts/setup_monitoring_node_labels.sh" ]; then
        echo "Setting up monitoring node labels for proper scheduling..."
        chmod +x scripts/setup_monitoring_node_labels.sh
        if ./scripts/setup_monitoring_node_labels.sh; then
            echo "✓ Monitoring node labels configured successfully"
        else
            echo "WARNING: Failed to setup monitoring node labels"
            echo "You may need to run this manually before deployment:"
            echo "  ./scripts/setup_monitoring_node_labels.sh"
        fi
    else
        echo "WARNING: Monitoring node label script not found at scripts/setup_monitoring_node_labels.sh"
    fi
else
    echo "INFO: Skipping node labeling setup (kubectl not available or cluster not accessible)"
    echo "      If deploying monitoring, run manually: ./scripts/setup_monitoring_node_labels.sh"
fi

# === KUBERNETES CONNECTIVITY CHECK ===
# Check if kubectl can connect to cluster before running Kubernetes-dependent playbooks
echo ""
echo "=== Kubernetes Connectivity Check ==="

# Set kubectl timeout environment variables to prevent hanging
export KUBECTL_TIMEOUT=10s
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}

KUBECTL_AVAILABLE=false
CLUSTER_ACCESSIBLE=false

# Check if kubectl is available
if command -v kubectl >/dev/null 2>&1; then
    echo "✓ kubectl command found"
    KUBECTL_AVAILABLE=true
    
    # Test cluster connectivity with timeout
    echo "Testing Kubernetes cluster connectivity..."
    if timeout 15s kubectl cluster-info >/dev/null 2>&1; then
        echo "✓ Kubernetes cluster is accessible"
        CLUSTER_ACCESSIBLE=true
        
        # Show basic cluster info
        echo "Cluster context: $(kubectl config current-context 2>/dev/null || echo 'unknown')"
        echo "Server version: $(kubectl version --short --client=false 2>/dev/null | grep 'Server Version' || echo 'unavailable')"
    else
        echo "⚠ Kubernetes cluster is not accessible or timed out"
        echo "  This may be due to:"
        echo "  - Cluster not running on the expected node (192.168.4.63:6443)"
        echo "  - Network connectivity issues"
        echo "  - Incorrect kubeconfig configuration"
        echo "  - Firewall blocking access to API server"
    fi
else
    echo "⚠ kubectl command not found"
    echo "  Kubernetes-dependent operations will be skipped"
fi

# Skip Kubernetes-dependent playbooks if cluster is not accessible
SKIP_K8S_PLAYBOOKS=false
if [ "$CLUSTER_ACCESSIBLE" = false ]; then
    echo ""
    echo "WARNING: Kubernetes cluster is not accessible!"
    echo "The following playbooks will be filtered to avoid hanging:"
    echo "  - ansible/site.yaml (contains Kubernetes operations)"
    echo "  - ansible/plays/kubernetes_stack.yaml"
    echo "  - Any playbooks that use kubernetes.core modules"
    echo ""
    echo "To fix this:"
    echo "  1. Ensure Kubernetes cluster is running: systemctl status kubelet"
    echo "  2. Check kubeconfig: kubectl config view"
    echo "  3. Test connectivity: kubectl cluster-info"
    echo "  4. Check firewall: firewall-cmd --list-ports"
    echo ""
    echo "Set FORCE_K8S_DEPLOYMENT=true to override this check (not recommended)"
    
    if [ "${FORCE_K8S_DEPLOYMENT:-false}" != "true" ]; then
        SKIP_K8S_PLAYBOOKS=true
    fi
fi

# === MODULAR PLAYBOOKS CONFIGURATION ===
# Edit the PLAYBOOKS array below to select which playbooks to run.
# Uncomment entries you want to execute. By default, all entries are commented out for safety.
#
# Recommended order:
# 1. 01-checks.yaml    - Verify SSH, become access, firewall, ports
# 2. 02-certs.yaml     - Generate and distribute TLS certificates  
# 3. 03-monitoring.yaml - Deploy monitoring stack (Prometheus, Grafana, Loki)
# 4. 04-jellyfin.yaml  - Jellyfin deployment pre-checks and storage validation
# 5. site.yaml         - Full site orchestrator (includes kubernetes_stack.yaml)
#
# You can also run individual deployment playbooks:
# - ansible/plays/kubernetes_stack.yaml (main Kubernetes stack)
# - ansible/plays/jellyfin.yml (Jellyfin media server)

PLAYBOOKS=(
    # === Modular Subsites (Recommended) ===
    # "ansible/subsites/01-checks.yaml"        # SSH connectivity, become access, firewall checks
    # "ansible/subsites/02-certs.yaml"         # TLS certificate generation & distribution
    # "ansible/subsites/03-monitoring.yaml"    # Monitoring stack pre-checks and deployment
    # "ansible/subsites/04-jellyfin.yaml"      # Jellyfin deployment pre-checks and storage validation
    # "apply_drone_secrets.yml"
    # "ansible/subsites/05-extra_apps.yaml"   # Extra Apps Orchestrator: runs all individual app playbooks
    
    # === Individual Extra Apps (Modular) ===
    # "ansible/subsites/06-kubernetes-dashboard.yaml"  # Kubernetes Dashboard only
    # "ansible/subsites/07-drone-ci.yaml"              # Drone CI only
    # "ansible/subsites/08-mongodb.yaml"               # MongoDB only
    
    # Work-in-progress subsites (wip_*) - exercise caution; these are flagged for review

    # "ansible/plays/kubernetes_stack.yaml"    # Core Kubernetes infrastructure only

    # === Full Deployment ===
    "ansible/site.yaml"                      # Complete site orchestrator (includes all subsites + kubernetes)

    # === Individual Components ===  
    # "ansible/plays/kubernetes_stack.yaml"    # Core Kubernetes infrastructure only
    # "ansible/plays/jellyfin.yml"             # Jellyfin media server deployment
    # "ansible/plays/kubernetes/deploy_monitoring.yaml"  # Legacy monitoring deployment
)

# Check if any playbooks are selected
if [ ${#PLAYBOOKS[@]} -eq 0 ]; then
    echo "ERROR: No playbooks selected in PLAYBOOKS array."
    echo ""
    echo "To run deployments:"
    echo "1. Edit this script: $0"
    echo "2. Uncomment desired entries in the PLAYBOOKS array"
    echo "3. Run this script again"
    echo ""
    echo "Available options:"
    echo "  - ansible/subsites/01-checks.yaml (preflight checks)"
    echo "  - ansible/subsites/02-certs.yaml (certificate management)"  
    echo "  - ansible/subsites/03-monitoring.yaml (monitoring stack)"
    echo "  - ansible/subsites/04-jellyfin.yaml (jellyfin pre-checks)"
    echo "  - ansible/subsites/05-extra_apps.yaml (extra apps: dashboard, drone, mongodb)"
    echo "  - ansible/site.yaml (complete deployment)"
    echo ""
    echo "Example: Uncomment '# \"ansible/subsites/01-checks.yaml\"' to enable checks."
    echo ""
    echo "TROUBLESHOOTING: If drone deployment is causing issues:"
    echo "  Set SKIP_DRONE=true to skip drone and deploy other components:"
    echo "  SKIP_DRONE=true ./update_and_deploy.sh"
    echo ""
    echo "  Or configure drone secrets first:"
    echo "  ./scripts/setup_drone_secrets.sh"
    exit 0
fi

# Run selected playbooks with syntax checking first
FAILED_PLAYBOOKS=()
SKIPPED_PLAYBOOKS=()
INVENTORY_ARG="-i ansible/inventory.txt"

# List of playbooks that require Kubernetes connectivity
K8S_DEPENDENT_PLAYBOOKS=(
    "ansible/site.yaml"
    "ansible/plays/kubernetes_stack.yaml"
    "ansible/plays/kubernetes/deploy_monitoring.yaml"
    "ansible/subsites/05-extra_apps.yaml"
)

for pb in "${PLAYBOOKS[@]}"; do
    if [ -z "$pb" ]; then
        continue
    fi
    
    if [ ! -f "$pb" ]; then
        echo "ERROR: Playbook $pb not found, skipping"
        FAILED_PLAYBOOKS+=("$pb (not found)")
        continue
    fi
    
    # Check if this playbook requires Kubernetes and if cluster is accessible
    REQUIRES_K8S=false
    for k8s_pb in "${K8S_DEPENDENT_PLAYBOOKS[@]}"; do
        if [[ "$pb" == "$k8s_pb" ]]; then
            REQUIRES_K8S=true
            break
        fi
    done
    
    if [ "$REQUIRES_K8S" = true ] && [ "$SKIP_K8S_PLAYBOOKS" = true ]; then
        echo ""
        echo "=== SKIPPING: $pb ==="
        echo "⚠ Skipping Kubernetes-dependent playbook (cluster not accessible)"
        echo "  To force execution: FORCE_K8S_DEPLOYMENT=true ./update_and_deploy.sh"
        SKIPPED_PLAYBOOKS+=("$pb (cluster not accessible)")
        continue
    fi
    
    echo ""
    echo "=== Syntax Check: $pb ==="
    if ! ansible-playbook $INVENTORY_ARG "$pb" --syntax-check; then
        echo "ERROR: Syntax check failed for $pb"
        FAILED_PLAYBOOKS+=("$pb (syntax error)")
        continue
    fi
    
    echo ""
    echo "=== Running: $pb ==="
    
    # Set timeouts for Kubernetes operations
    if [ "$REQUIRES_K8S" = true ]; then
        echo "Setting Kubernetes operation timeouts..."
        export K8S_WAIT_TIMEOUT=30
        export ANSIBLE_TIMEOUT=45
    fi
    
    if ! timeout 1800 ansible-playbook $INVENTORY_ARG "$pb"; then
        echo "ERROR: Playbook execution failed for $pb"
        FAILED_PLAYBOOKS+=("$pb (execution failed)")
        continue
    fi
    
    echo "SUCCESS: $pb completed"
done

# Report results
echo ""
echo "=== Deployment Summary ==="

# Report skipped playbooks
if [ ${#SKIPPED_PLAYBOOKS[@]} -gt 0 ]; then
    echo "⚠ Playbooks skipped due to Kubernetes connectivity issues:"
    for skipped in "${SKIPPED_PLAYBOOKS[@]}"; do
        echo "   - $skipped"
    done
    echo ""
fi

# Report failed playbooks
if [ ${#FAILED_PLAYBOOKS[@]} -eq 0 ]; then
    if [ ${#SKIPPED_PLAYBOOKS[@]} -eq 0 ]; then
        echo "✅ All selected playbooks completed successfully"
    else
        echo "✅ All executable playbooks completed successfully"
        echo "⚠ Some playbooks were skipped due to missing Kubernetes connectivity"
    fi
else
    echo "❌ Some playbooks failed:"
    for failed in "${FAILED_PLAYBOOKS[@]}"; do
        echo "   - $failed"
    done
    echo ""
    echo "To troubleshoot:"
    echo "- Check syntax: ansible-playbook --syntax-check <playbook>"
    echo "- Run in check mode: ansible-playbook --check <playbook>"
    echo "- Increase verbosity: ansible-playbook -vv <playbook>"
    
    if [ ${#SKIPPED_PLAYBOOKS[@]} -gt 0 ]; then
        echo ""
        echo "For Kubernetes connectivity issues:"
        echo "- Check service enablement: ./scripts/fix_kubernetes_service_enablement.sh"
        echo "- Check cluster status: systemctl status kubelet"
        echo "- Test connectivity: kubectl cluster-info"
        echo "- Verify kubeconfig: kubectl config view"
        echo "- Check API server: netstat -tlnp | grep :6443"
    fi
    exit 1
fi

echo ""
if [ "$CLUSTER_ACCESSIBLE" = true ]; then
    echo "🎉 VMStation deployment completed successfully!"
    echo "Check service status with: kubectl get pods --all-namespaces"
else
    echo "🎉 VMStation deployment completed (non-Kubernetes components)!"
    echo "To complete Kubernetes deployment:"
    echo "1. Fix Kubernetes cluster connectivity"
    echo "2. Re-run with: FORCE_K8S_DEPLOYMENT=true ./update_and_deploy.sh"
    echo "3. Or run individual playbooks: ansible-playbook -i ansible/inventory.txt ansible/site.yaml"
fi

#########################################
# Post-deployment remediation (run known fix scripts if present)
# This section will run a small set of helper scripts that attempt to
# fix common post-deploy issues (permissions, dashboard RBAC/CSRF, monitoring pods).
#########################################

echo ""
echo "=== Post-deployment remediation scripts ==="
if [ "$CLUSTER_ACCESSIBLE" = true ]; then
    # Only run Kubernetes-dependent remediation here; host-level permission fixes
    # are performed earlier (see pre-deploy section). Keep post-deploy focused on
    # scripts that require a reachable cluster.
    POST_SCRIPTS=(
        "scripts/fix_monitoring_scheduling.sh"
        "scripts/fix_k8s_dashboard_permissions.sh"
        "scripts/fix_k8s_monitoring_pods.sh"
    )

    for s in "${POST_SCRIPTS[@]}"; do
        if [ -f "$s" ]; then
            echo "Found $s - ensuring executable"
            chmod +x "$s" || true

            # Decide args: dashboard and monitoring_pods accept --auto-approve; others run without args
            case "$(basename "$s")" in
                fix_k8s_dashboard_permissions.sh|fix_k8s_monitoring_pods.sh)
                    ARGS="--auto-approve"
                    ;;
                fix_monitoring_scheduling.sh)
                    ARGS=""  # No args needed for scheduling fix
                    ;;
                *)
                    ARGS=""
                    ;;
            esac

            if sudo -n true 2>/dev/null; then
                echo "Running $s $ARGS with sudo (may prompt for password if required)..."
                sudo "$s" $ARGS || echo "WARNING: $s exited with code $?"
            else
                echo "No passwordless sudo available - running $s $ARGS unprivileged (may require manual sudo)"
                "$s" $ARGS || echo "WARNING: $s exited with code $?"
            fi
        else
            echo "Skipping missing script: $s"
        fi
    done
else
    echo "Cluster not accessible - skipping post-deployment Kubernetes remediation scripts"
    echo "To run post-deploy fixes later, execute:" \
         "scripts/fix_monitoring_permissions.sh && scripts/fix_monitoring_scheduling.sh && scripts/fix_k8s_dashboard_permissions.sh --auto-approve && scripts/fix_k8s_monitoring_pods.sh --auto-approve"
fi

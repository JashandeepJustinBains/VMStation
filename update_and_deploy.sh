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
    "apply_drone_secrets.yml"
    "ansible/subsites/05-extra_apps.yaml"   # Extra Apps: Kubernetes Dashboard, Drone, MongoDB
    # Work-in-progress subsites (wip_*) - exercise caution; these are flagged for review

    # === Full Deployment ===
    # "ansible/site.yaml"                      # Complete site orchestrator (includes all subsites + kubernetes)

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
    exit 0
fi

# Run selected playbooks with syntax checking first
FAILED_PLAYBOOKS=()
INVENTORY_ARG="-i ansible/inventory.txt"

for pb in "${PLAYBOOKS[@]}"; do
    if [ -z "$pb" ]; then
        continue
    fi
    
    if [ ! -f "$pb" ]; then
        echo "ERROR: Playbook $pb not found, skipping"
        FAILED_PLAYBOOKS+=("$pb (not found)")
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
    if ! ansible-playbook $INVENTORY_ARG "$pb"; then
        echo "ERROR: Playbook execution failed for $pb"
        FAILED_PLAYBOOKS+=("$pb (execution failed)")
        continue
    fi
    
    echo "SUCCESS: $pb completed"
done

# Report results
echo ""
echo "=== Deployment Summary ==="
if [ ${#FAILED_PLAYBOOKS[@]} -eq 0 ]; then
    echo "✅ All selected playbooks completed successfully"
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
    exit 1
fi

echo ""
echo "🎉 VMStation deployment completed successfully!"
echo "Check service status with: kubectl get pods --all-namespaces"

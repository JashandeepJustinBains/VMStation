#!/bin/bash

# VMStation Update and Deploy Script
# Fetches latest changes and deploys infrastructure

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

# Check for infrastructure mode
# Selectable playbooks mechanism
# Edit the PLAYBOOKS array below and uncomment the entries you want to run.
PLAYBOOKS=(
    # "ansible/site.yaml"                       # run the full site orchestrator
    # "ansible/subsites/01-checks.yaml"        # preflight checks
    # "ansible/subsites/02-certs.yaml"         # cert generation & distribution
    # "ansible/subsites/03-monitoring.yaml"    # monitoring stack deploy
    # "ansible/plays/kubernetes/deploy_monitoring.yaml" # older deploy path
)

if [ ${#PLAYBOOKS[@]} -eq 0 ]; then
    echo "No playbooks selected in PLAYBOOKS array. Edit update_and_deploy.sh to enable entries. Exiting."
    exit 0
fi

for pb in "${PLAYBOOKS[@]}"; do
    if [ -z "$pb" ]; then
        continue
    fi
    if [ ! -f "$pb" ]; then
        echo "Playbook $pb not found, skipping"
        continue
    fi
    echo "Running playbook: $pb"
    ansible-playbook -i ansible/inventory.txt "$pb"
done

#!/bin/bash

# VMStation Update and Deploy Script
# Fetches latest changes and deploys infrastructure

set -e

echo "=== VMStation Update and Deploy ==="
echo "Timestamp: $(date)"
echo ""

# Fetch latest changes from remote
echo "Fetching latest changes..."
git fetch --all
git pull --ff-only

# Make deploy scripts executable
chmod +x ./ansible/deploy.sh
chmod +x ./deploy_kubernetes.sh 2>/dev/null || true

# Check for infrastructure mode
if [ -f "ansible/group_vars/all.yml" ]; then
    if grep -q "infrastructure_mode:.*kubernetes" ansible/group_vars/all.yml; then
        echo "Using Kubernetes deployment mode..."
        ./deploy_kubernetes.sh
    elif grep -q "infrastructure_mode:.*podman" ansible/group_vars/all.yml; then
        echo "Using legacy Podman deployment mode..."
        ./ansible/deploy.sh
    else
        echo "Infrastructure mode not specified, using Kubernetes..."
        ./deploy_kubernetes.sh
    fi
else
    echo "No configuration found, using Kubernetes deployment..."
    ./deploy_kubernetes.sh
fi

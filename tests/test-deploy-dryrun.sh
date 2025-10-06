#!/usr/bin/env bash
# Test script: Dry-run deployment to verify playbook execution without changes
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "========================================="
echo "VMStation Dry-Run Deployment Test"
echo "========================================="
echo ""

# Test 1: Dry-run Debian deployment
echo "[1/2] Dry-run: Debian cluster deployment..."
if ansible-playbook -i ansible/inventory/hosts.yml \
    ansible/playbooks/deploy-cluster.yaml \
    --check \
    2>&1 | tee /tmp/dryrun-debian.log; then
    echo "  ✅ Debian deployment dry-run completed"
else
    echo "  ❌ Debian deployment dry-run FAILED"
    echo "  Check /tmp/dryrun-debian.log for details"
    exit 1
fi

echo ""

# Test 2: Dry-run RKE2 deployment (if vault password available)
echo "[2/2] Dry-run: RKE2 deployment..."
if [ -f ansible/inventory/group_vars/secrets.yml ]; then
    echo "  Vault file found, attempting dry-run..."
    echo "  (This will prompt for vault password if encrypted)"
    
    if ansible-playbook -i ansible/inventory/hosts.yml \
        ansible/playbooks/install-rke2-homelab.yml \
        --check \
        --ask-vault-pass \
        2>&1 | tee /tmp/dryrun-rke2.log; then
        echo "  ✅ RKE2 deployment dry-run completed"
    else
        echo "  ❌ RKE2 deployment dry-run FAILED"
        echo "  Check /tmp/dryrun-rke2.log for details"
        exit 1
    fi
else
    echo "  ⚠️  Vault file not found, skipping RKE2 dry-run"
    echo "  Create ansible/inventory/group_vars/secrets.yml to enable"
fi

echo ""
echo "========================================="
echo "✅ All dry-run tests PASSED"
echo "========================================="
echo ""
echo "Note: Dry-run shows what WOULD change, but doesn't execute."
echo "Run actual deployment with: ./deploy.sh all --with-rke2"

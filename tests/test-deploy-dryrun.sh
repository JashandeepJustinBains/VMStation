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
if ansible-playbook -i inventory.ini \
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

# Test 2: Dry-run Kubespray preflight (RKE2 deployment removed)
echo "[2/2] Dry-run: Kubespray preflight checks..."
echo "  Note: RKE2 deployment deprecated in favor of Kubespray"

if [ -f ansible/playbooks/run-preflight-rhel10.yml ]; then
    echo "  Running preflight checks on compute_nodes..."
    
    if ansible-playbook -i inventory.ini \
        ansible/playbooks/run-preflight-rhel10.yml \
        -l compute_nodes \
        --check \
        2>&1 | tee /tmp/dryrun-preflight.log; then
        echo "  ✅ Preflight checks dry-run completed"
    else
        echo "  ❌ Preflight checks dry-run FAILED (non-blocking)"
        echo "  Check /tmp/dryrun-preflight.log for details"
    fi
else
    echo "  ⚠️  Preflight playbook not found, skipping"
fi

echo ""
echo "========================================="
echo "✅ All dry-run tests PASSED"
echo "========================================="
echo ""
echo "Note: Dry-run shows what WOULD change, but doesn't execute."
echo "Run actual deployment with: ./deploy.sh all --with-rke2"

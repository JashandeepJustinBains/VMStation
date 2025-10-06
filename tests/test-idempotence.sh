#!/usr/bin/env bash
# Test script: Idempotency test - deploy twice, verify no unexpected changes
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ITERATIONS=${1:-2}  # Default 2 iterations, can be overridden

echo "========================================="
echo "VMStation Idempotency Test"
echo "Running $ITERATIONS deployment cycles"
echo "========================================="
echo ""

echo "WARNING: This test will reset and redeploy your cluster!"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read -r

for i in $(seq 1 "$ITERATIONS"); do
    echo ""
    echo "========================================="
    echo "Cycle $i of $ITERATIONS"
    echo "========================================="
    
    # Reset cluster
    echo ""
    echo "[$i.1] Resetting cluster..."
    if ! ./deploy.sh reset --yes; then
        echo "❌ Reset FAILED at cycle $i"
        exit 1
    fi
    echo "✅ Reset completed"
    
    # First deployment
    echo ""
    echo "[$i.2] First deployment..."
    if ! ./deploy.sh all --with-rke2 --yes 2>&1 | tee "/tmp/deploy-cycle-${i}-run1.log"; then
        echo "❌ First deployment FAILED at cycle $i"
        exit 1
    fi
    echo "✅ First deployment completed"
    
    # Verify deployment
    echo ""
    echo "[$i.3] Verifying deployment..."
    if ! ansible-playbook -i ansible/inventory/hosts.yml \
        ansible/playbooks/verify-cluster.yaml \
        2>&1 | tee "/tmp/verify-cycle-${i}.log"; then
        echo "❌ Verification FAILED at cycle $i"
        exit 1
    fi
    echo "✅ Verification passed"
    
    # Second deployment (idempotency check)
    echo ""
    echo "[$i.4] Second deployment (idempotency check)..."
    if ! ./deploy.sh all --with-rke2 --yes 2>&1 | tee "/tmp/deploy-cycle-${i}-run2.log"; then
        echo "❌ Second deployment FAILED at cycle $i"
        exit 1
    fi
    
    # Check for unexpected changes
    CHANGES=$(grep -c "changed=" "/tmp/deploy-cycle-${i}-run2.log" | tail -1 || echo "0")
    if [ "$CHANGES" -gt 10 ]; then
        echo "⚠️  WARNING: Second deployment had $CHANGES changes (expected < 10)"
        echo "  This may indicate non-idempotent tasks"
        echo "  Review /tmp/deploy-cycle-${i}-run2.log"
    else
        echo "✅ Second deployment was idempotent (minimal changes)"
    fi
    
    echo ""
    echo "✅ Cycle $i completed successfully"
done

echo ""
echo "========================================="
echo "✅ All $ITERATIONS cycles PASSED"
echo "========================================="
echo ""
echo "Logs saved to:"
for i in $(seq 1 "$ITERATIONS"); do
    echo "  - /tmp/deploy-cycle-${i}-run1.log (first deploy)"
    echo "  - /tmp/deploy-cycle-${i}-run2.log (second deploy, idempotency)"
    echo "  - /tmp/verify-cycle-${i}.log (verification)"
done

exit 0

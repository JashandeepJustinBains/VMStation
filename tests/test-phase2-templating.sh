#!/usr/bin/env bash
# Test script: Validate Phase 2 control plane validation has no Jinja2 conflicts
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "========================================="
echo "Phase 2 Templating Validation Test"
echo "========================================="
echo ""

FAILED=0

# Test 1: Verify no arithmetic expansion remains in deploy-cluster.yaml
echo "[1/5] Checking for arithmetic expansion in deploy-cluster.yaml..."
if grep -q '\$((count' ansible/playbooks/deploy-cluster.yaml; then
    echo "  ❌ FAILED: Found arithmetic expansion that could cause Jinja2 conflicts"
    grep -n '\$((count' ansible/playbooks/deploy-cluster.yaml
    FAILED=`expr $FAILED + 1`
else
    echo "  ✅ PASS: No arithmetic expansion found"
fi

# Test 2: Verify crictl is used instead of docker
echo "[2/5] Checking for crictl usage in Phase 2..."
if grep -A30 "Verify control plane components are running" ansible/playbooks/deploy-cluster.yaml | grep -q "crictl ps"; then
    echo "  ✅ PASS: crictl is used for container checks"
else
    echo "  ❌ FAILED: crictl not found in Phase 2"
    FAILED=`expr $FAILED + 1`
fi

# Test 3: Verify expr is used for arithmetic
echo "[3/5] Checking for expr usage in Phase 2..."
if grep -A20 "Verify control plane components are running" ansible/playbooks/deploy-cluster.yaml | grep -q 'expr $count + 1'; then
    echo "  ✅ PASS: expr arithmetic is used"
else
    echo "  ❌ FAILED: expr arithmetic not found in Phase 2"
    FAILED=`expr $FAILED + 1`
fi

# Test 4: Verify error suppression with 2>/dev/null
echo "[4/5] Checking for error suppression in crictl commands..."
if grep -A20 "Verify control plane components are running" ansible/playbooks/deploy-cluster.yaml | grep -q 'crictl ps 2>/dev/null'; then
    echo "  ✅ PASS: Error suppression is in place"
else
    echo "  ❌ FAILED: Error suppression not found"
    FAILED=`expr $FAILED + 1`
fi

# Test 5: Verify playbook syntax is valid
echo "[5/5] Checking playbook syntax..."
if ansible-playbook --syntax-check ansible/playbooks/deploy-cluster.yaml > /dev/null 2>&1; then
    echo "  ✅ PASS: Playbook syntax is valid"
else
    echo "  ❌ FAILED: Playbook syntax check failed"
    FAILED=`expr $FAILED + 1`
fi

echo ""
echo "========================================="
if [ $FAILED -eq 0 ]; then
    echo "✅ All Phase 2 templating tests PASSED"
    echo "========================================="
    echo ""
    echo "Phase 2 is ready for deployment:"
    echo "  - No Jinja2 templating conflicts"
    echo "  - Uses crictl for container runtime checks"
    echo "  - Uses expr for arithmetic (avoids double parentheses)"
    echo "  - Proper error suppression in place"
    exit 0
else
    echo "❌ $FAILED test(s) FAILED"
    echo "========================================="
    exit 1
fi

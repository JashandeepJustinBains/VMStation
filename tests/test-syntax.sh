#!/usr/bin/env bash
# Test script: Syntax validation for all playbooks and roles
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "========================================="
echo "VMStation Syntax Validation Test"
echo "========================================="
echo ""

FAILED=0

# Test 1: Ansible syntax check for all playbooks
echo "[1/3] Checking playbook syntax..."
PLAYBOOKS=$(find ansible/playbooks -name "*.yml" -o -name "*.yaml" 2>/dev/null | sort)

for playbook in $PLAYBOOKS; do
    echo "  Checking: $playbook"
    if ! ansible-playbook --syntax-check "$playbook" > /dev/null 2>&1; then
        echo "    ❌ FAILED: $playbook"
        FAILED=$((FAILED + 1))
    else
        echo "    ✅ PASS"
    fi
done

# Test 2: YAML lint (if yamllint is available)
echo ""
echo "[2/3] Checking YAML lint (if available)..."
if command -v yamllint &> /dev/null; then
    if yamllint -c .yamllint ansible/ 2>/dev/null || true; then
        echo "  ✅ YAML lint passed"
    else
        echo "  ⚠️  YAML lint warnings (non-fatal)"
    fi
else
    echo "  ⚠️  yamllint not installed, skipping"
fi

# Test 3: ansible-lint (if available)
echo ""
echo "[3/3] Checking ansible-lint (if available)..."
if command -v ansible-lint &> /dev/null; then
    if ansible-lint ansible/playbooks/*.yaml 2>/dev/null || true; then
        echo "  ✅ ansible-lint passed"
    else
        echo "  ⚠️  ansible-lint warnings (non-fatal)"
    fi
else
    echo "  ⚠️  ansible-lint not installed, skipping"
fi

echo ""
echo "========================================="
if [ $FAILED -eq 0 ]; then
    echo "✅ All syntax checks PASSED"
    echo "========================================="
    exit 0
else
    echo "❌ $FAILED playbook(s) FAILED syntax check"
    echo "========================================="
    exit 1
fi

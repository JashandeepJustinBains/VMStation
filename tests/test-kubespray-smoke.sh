#!/usr/bin/env bash
# Smoke test for VMStation kubespray integration
# Tests that new components are properly installed without breaking existing functionality

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASSED=0
FAILED=0

log_pass() {
  echo "✅ PASS: $*"
  PASSED=$((PASSED + 1))
}

log_fail() {
  echo "❌ FAIL: $*"
  FAILED=$((FAILED + 1))
}

log_info() {
  echo "ℹ️  INFO: $*"
}

echo "========================================="
echo "VMStation Kubespray Integration Smoke Test"
echo "========================================="
echo ""

# Test 1: Check deploy.sh still works
echo "[1/12] Testing deploy.sh help..."
if ./deploy.sh help >/dev/null 2>&1; then
  log_pass "deploy.sh help works"
else
  log_fail "deploy.sh help failed"
fi

# Test 2: Check kubespray wrapper exists and is executable
echo "[2/12] Checking kubespray wrapper..."
if [[ -x scripts/run-kubespray.sh ]]; then
  log_pass "scripts/run-kubespray.sh exists and is executable"
else
  log_fail "scripts/run-kubespray.sh not found or not executable"
fi

# Test 3: Check kubespray wrapper syntax
echo "[3/12] Checking kubespray wrapper syntax..."
if bash -n scripts/run-kubespray.sh; then
  log_pass "scripts/run-kubespray.sh syntax valid"
else
  log_fail "scripts/run-kubespray.sh syntax error"
fi

# Test 4: Check preflight role exists
echo "[4/12] Checking preflight-rhel10 role..."
if [[ -d ansible/roles/preflight-rhel10 ]]; then
  log_pass "ansible/roles/preflight-rhel10 exists"
else
  log_fail "ansible/roles/preflight-rhel10 not found"
fi

# Test 5: Check preflight playbook exists
echo "[5/12] Checking preflight playbook..."
if [[ -f ansible/playbooks/run-preflight-rhel10.yml ]]; then
  log_pass "ansible/playbooks/run-preflight-rhel10.yml exists"
else
  log_fail "ansible/playbooks/run-preflight-rhel10.yml not found"
fi

# Test 6: Validate preflight playbook syntax
echo "[6/12] Validating preflight playbook syntax..."
if ansible-playbook --syntax-check ansible/playbooks/run-preflight-rhel10.yml >/dev/null 2>&1; then
  log_pass "Preflight playbook syntax valid"
else
  log_fail "Preflight playbook syntax error"
fi

# Test 7: Check new documentation exists
echo "[7/12] Checking new documentation..."
docs_found=0
[[ -f docs/ARCHITECTURE.md ]] && ((docs_found++)) || true
[[ -f docs/TROUBLESHOOTING.md ]] && ((docs_found++)) || true
[[ -f docs/USAGE.md ]] && ((docs_found++)) || true
[[ -f README.md ]] && ((docs_found++)) || true
if [[ $docs_found -eq 4 ]]; then
  log_pass "All new documentation files exist"
else
  log_fail "Missing documentation files ($docs_found/4 found)"
fi

# Test 8: Check old docs archived
echo "[8/12] Checking archived documentation..."
if [[ -f docs/archive/architecture.md ]] && [[ -f docs/archive/troubleshooting.md ]]; then
  log_pass "Old documentation properly archived"
else
  log_fail "Old documentation not found in archive"
fi

# Test 9: Check .gitignore updated
echo "[9/12] Checking .gitignore..."
if grep -q ".cache/" .gitignore; then
  log_pass ".gitignore includes .cache/ directory"
else
  log_fail ".gitignore missing .cache/ entry"
fi

# Test 10: Check existing test scripts still work
echo "[10/12] Checking test scripts syntax..."
test_ok=true
for script in tests/test-complete-validation.sh tests/test-sleep-wake-cycle.sh scripts/validate-monitoring-stack.sh; do
  if ! bash -n "$script" 2>/dev/null; then
    test_ok=false
    break
  fi
done
if $test_ok; then
  log_pass "Existing test scripts syntax valid"
else
  log_fail "Test script syntax errors found"
fi

# Test 11: Verify no syntax errors in deploy.sh
echo "[11/12] Checking deploy.sh syntax..."
if bash -n deploy.sh; then
  log_pass "deploy.sh syntax valid"
else
  log_fail "deploy.sh has syntax errors"
fi

# Test 12: Check YAML linting
echo "[12/12] Running YAML lint on new files..."
if yamllint ansible/playbooks/run-preflight-rhel10.yml ansible/roles/preflight-rhel10/ >/dev/null 2>&1; then
  log_pass "YAML files pass linting"
else
  log_fail "YAML linting errors found"
fi

echo ""
echo "========================================="
echo "Smoke Test Results"
echo "========================================="
echo "Passed: $PASSED/12"
echo "Failed: $FAILED/12"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo "✅ All smoke tests passed!"
  echo ""
  echo "Next steps:"
  echo "  1. Review the new documentation in docs/"
  echo "  2. Try the kubespray wrapper: ./scripts/run-kubespray.sh --help || ./scripts/run-kubespray.sh"
  echo "  3. Run preflight checks: ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/run-preflight-rhel10.yml --check"
  echo "  4. Test existing workflows: ./deploy.sh --help"
  exit 0
else
  echo "❌ Some smoke tests failed."
  echo ""
  echo "Please review the failures above and fix before proceeding."
  exit 1
fi

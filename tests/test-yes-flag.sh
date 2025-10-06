#!/usr/bin/env bash
# Test script to verify --yes flag behavior in deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

info(){ echo "[TEST-INFO] $*" >&2; }
pass(){ echo "[TEST-PASS] ✓ $*" >&2; }
fail(){ echo "[TEST-FAIL] ✗ $*" >&2; exit 1; }

cd "$REPO_ROOT"

info "Testing deploy.sh --yes flag behavior"
info ""

# Test 1: debian command with --yes should include skip_ansible_confirm
info "Test 1: debian --yes includes skip_ansible_confirm"
output=$(./deploy.sh debian --check --yes 2>&1)
if echo "$output" | grep -q "skip_ansible_confirm=true"; then
  pass "debian --yes includes skip_ansible_confirm parameter"
else
  fail "debian --yes does not include skip_ansible_confirm parameter"
fi

# Test 2: debian without --yes should NOT include skip_ansible_confirm
info ""
info "Test 2: debian without --yes excludes skip_ansible_confirm"
output=$(./deploy.sh debian --check 2>&1)
if ! echo "$output" | grep -q "skip_ansible_confirm=true"; then
  pass "debian without --yes excludes skip_ansible_confirm parameter"
else
  fail "debian without --yes incorrectly includes skip_ansible_confirm parameter"
fi

# Test 3: rke2 command with --yes should include skip_ansible_confirm
info ""
info "Test 3: rke2 --yes includes skip_ansible_confirm"
output=$(./deploy.sh rke2 --check --yes 2>&1)
if echo "$output" | grep -q "skip_ansible_confirm=true"; then
  pass "rke2 --yes includes skip_ansible_confirm parameter"
else
  fail "rke2 --yes does not include skip_ansible_confirm parameter"
fi

# Test 4: reset command with --yes should include skip_ansible_confirm
info ""
info "Test 4: reset --yes includes skip_ansible_confirm"
output=$(./deploy.sh reset --check --yes 2>&1)
if echo "$output" | grep -q "skip_ansible_confirm=true"; then
  pass "reset --yes includes skip_ansible_confirm parameter"
else
  fail "reset --yes does not include skip_ansible_confirm parameter"
fi

# Test 5: all command with --with-rke2 should work without prompts
info ""
info "Test 5: all --with-rke2 includes both phases"
output=$(./deploy.sh all --check --with-rke2 2>&1)
if echo "$output" | grep -q "PHASE 1" && echo "$output" | grep -q "PHASE 2"; then
  pass "all --with-rke2 includes both phases without prompting"
else
  fail "all --with-rke2 does not include both phases"
fi

# Test 6: Verify ANSIBLE_FORCE_COLOR would be set (can't test directly in dry-run)
info ""
info "Test 6: Checking that colored output is enabled"
# This is hard to test in dry-run mode, but we can verify the script has ANSIBLE_FORCE_COLOR
if grep -q "ANSIBLE_FORCE_COLOR=true" "$REPO_ROOT/deploy.sh"; then
  pass "deploy.sh sets ANSIBLE_FORCE_COLOR=true for colored output"
else
  fail "deploy.sh does not set ANSIBLE_FORCE_COLOR for colored output"
fi

info ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info " ALL --yes FLAG TESTS PASSED"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info ""

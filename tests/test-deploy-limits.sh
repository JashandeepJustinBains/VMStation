#!/usr/bin/env bash
# Test script to verify deploy.sh uses correct --limit flags

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

info(){ echo "[TEST-INFO] $*" >&2; }
pass(){ echo "[TEST-PASS] ✓ $*" >&2; }
fail(){ echo "[TEST-FAIL] ✗ $*" >&2; exit 1; }

cd "$REPO_ROOT"

info "Testing deploy.sh --limit behavior"
info ""

# Test 1: debian command should use --limit monitoring_nodes,storage_nodes
info "Test 1: debian command uses correct --limit"
output=$(./deploy.sh debian --check 2>&1)
if echo "$output" | grep -q "monitoring_nodes,storage_nodes"; then
  pass "debian command includes monitoring_nodes,storage_nodes"
else
  fail "debian command does not include correct --limit"
fi

if ! echo "$output" | grep -q "homelab"; then
  pass "debian command does not target homelab (compute_nodes)"
else
  fail "debian command incorrectly includes homelab"
fi

# Test 2: rke2 command should target homelab only
info ""
info "Test 2: rke2 command targets homelab playbook"
output=$(./deploy.sh rke2 --check --yes 2>&1)
if echo "$output" | grep -q "install-rke2-homelab.yml"; then
  pass "rke2 command uses install-rke2-homelab.yml playbook"
else
  fail "rke2 command does not use correct playbook"
fi

# Test 3: reset command should handle both
info ""
info "Test 3: reset command handles both Debian and RKE2"
output=$(./deploy.sh reset --check --yes 2>&1)
if echo "$output" | grep -q "reset-cluster.yaml" && echo "$output" | grep -q "uninstall-rke2-homelab.yml"; then
  pass "reset command includes both Debian and RKE2 playbooks"
else
  fail "reset command does not include both playbooks"
fi

# Test 4: all command should run both phases
info ""
info "Test 4: all command includes both phases"
output=$(./deploy.sh all --check --with-rke2 2>&1)
if echo "$output" | grep -q "PHASE 1" && echo "$output" | grep -q "PHASE 2"; then
  pass "all command includes both phases"
else
  fail "all command does not include both phases"
fi

info ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info " ALL TESTS PASSED"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info ""

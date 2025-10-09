#!/usr/bin/env bash
# Test script to verify modular deployment commands in deploy.sh
# Tests the new 'monitoring' and 'infrastructure' commands

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

info(){ echo "[TEST-INFO] $*" >&2; }
pass(){ echo "[TEST-PASS] ✓ $*" >&2; }
fail(){ echo "[TEST-FAIL] ✗ $*" >&2; exit 1; }

cd "$REPO_ROOT"

info "Testing deploy.sh modular deployment commands"
info ""

# Test 1: monitoring command should use deploy-monitoring-stack.yaml
info "Test 1: monitoring command uses correct playbook"
output=$(./deploy.sh monitoring --check 2>&1)
if echo "$output" | grep -q "deploy-monitoring-stack.yaml"; then
  pass "monitoring command uses deploy-monitoring-stack.yaml"
else
  fail "monitoring command does not use correct playbook"
fi

if echo "$output" | grep -q "Deploy Monitoring Stack"; then
  pass "monitoring command shows correct banner"
else
  fail "monitoring command does not show correct banner"
fi

# Test 2: infrastructure command should use deploy-infrastructure-services.yaml
info ""
info "Test 2: infrastructure command uses correct playbook"
output=$(./deploy.sh infrastructure --check 2>&1)
if echo "$output" | grep -q "deploy-infrastructure-services.yaml"; then
  pass "infrastructure command uses deploy-infrastructure-services.yaml"
else
  fail "infrastructure command does not use correct playbook"
fi

if echo "$output" | grep -q "Deploy Infrastructure Services"; then
  pass "infrastructure command shows correct banner"
else
  fail "infrastructure command does not show correct banner"
fi

# Test 3: monitoring command supports --yes flag
info ""
info "Test 3: monitoring command supports --yes flag"
output=$(./deploy.sh monitoring --check --yes 2>&1)
if echo "$output" | grep -q "skip_ansible_confirm=true"; then
  pass "monitoring command supports --yes flag"
else
  fail "monitoring command does not support --yes flag"
fi

# Test 4: infrastructure command supports --yes flag
info ""
info "Test 4: infrastructure command supports --yes flag"
output=$(./deploy.sh infrastructure --check --yes 2>&1)
if echo "$output" | grep -q "skip_ansible_confirm=true"; then
  pass "infrastructure command supports --yes flag"
else
  fail "infrastructure command does not support --yes flag"
fi

# Test 5: help should include new commands
info ""
info "Test 5: help includes new commands"
output=$(./deploy.sh help 2>&1)
if echo "$output" | grep -q "monitoring.*Deploy monitoring stack"; then
  pass "help includes monitoring command"
else
  fail "help does not include monitoring command"
fi

if echo "$output" | grep -q "infrastructure.*Deploy infrastructure services"; then
  pass "help includes infrastructure command"
else
  fail "help does not include infrastructure command"
fi

# Test 6: help should show recommended workflow
info ""
info "Test 6: help shows recommended workflow"
if echo "$output" | grep -q "Recommended Workflow"; then
  pass "help shows recommended workflow section"
else
  fail "help does not show recommended workflow section"
fi

if echo "$output" | grep -q "./deploy.sh monitoring"; then
  pass "recommended workflow includes monitoring command"
else
  fail "recommended workflow does not include monitoring command"
fi

if echo "$output" | grep -q "./deploy.sh infrastructure"; then
  pass "recommended workflow includes infrastructure command"
else
  fail "recommended workflow does not include infrastructure command"
fi

# Test 7: verify playbook files exist
info ""
info "Test 7: verify playbook files exist"
if [ -f "ansible/playbooks/deploy-monitoring-stack.yaml" ]; then
  pass "deploy-monitoring-stack.yaml exists"
else
  fail "deploy-monitoring-stack.yaml does not exist"
fi

if [ -f "ansible/playbooks/deploy-infrastructure-services.yaml" ]; then
  pass "deploy-infrastructure-services.yaml exists"
else
  fail "deploy-infrastructure-services.yaml does not exist"
fi

# Test 8: verify log paths are correct
info ""
info "Test 8: verify log paths are correct"
output=$(./deploy.sh monitoring --check 2>&1)
if echo "$output" | grep -q "deploy-monitoring-stack.log"; then
  pass "monitoring command uses correct log file name"
else
  fail "monitoring command does not use correct log file name"
fi

output=$(./deploy.sh infrastructure --check 2>&1)
if echo "$output" | grep -q "deploy-infrastructure-services.log"; then
  pass "infrastructure command uses correct log file name"
else
  fail "infrastructure command does not use correct log file name"
fi

# Test 9: verify existing commands still work
info ""
info "Test 9: verify existing commands still work"
output=$(./deploy.sh debian --check 2>&1)
if echo "$output" | grep -q "deploy-cluster.yaml"; then
  pass "debian command still works"
else
  fail "debian command broken"
fi

# Note: setup command doesn't have --check mode, just verify it exists
output=$(./deploy.sh help 2>&1)
if echo "$output" | grep -q "setup.*Setup auto-sleep monitoring"; then
  pass "setup command documented in help"
else
  fail "setup command not documented in help"
fi

# Test 10: verify monitoring command targets monitoring_nodes
info ""
info "Test 10: verify monitoring command targets monitoring_nodes"
output=$(./deploy.sh monitoring --check 2>&1)
if echo "$output" | grep -q "monitoring_nodes"; then
  pass "monitoring command targets monitoring_nodes"
else
  fail "monitoring command does not target monitoring_nodes"
fi

# Test 11: verify infrastructure command targets monitoring_nodes
info ""
info "Test 11: verify infrastructure command targets monitoring_nodes"
output=$(./deploy.sh infrastructure --check 2>&1)
if echo "$output" | grep -q "monitoring_nodes"; then
  pass "infrastructure command targets monitoring_nodes"
else
  fail "infrastructure command does not target monitoring_nodes"
fi

# Test 12: DEPLOYMENT_RUNBOOK.md is updated
info ""
info "Test 12: DEPLOYMENT_RUNBOOK.md is updated with new commands"
if [ -f "docs/DEPLOYMENT_RUNBOOK.md" ]; then
  if grep -q "./deploy.sh monitoring" "docs/DEPLOYMENT_RUNBOOK.md" && \
     grep -q "./deploy.sh infrastructure" "docs/DEPLOYMENT_RUNBOOK.md"; then
    pass "DEPLOYMENT_RUNBOOK.md includes new commands"
  else
    fail "DEPLOYMENT_RUNBOOK.md does not include new commands"
  fi
else
  fail "DEPLOYMENT_RUNBOOK.md does not exist"
fi

# Test 13: memory.instruction.md is updated
info ""
info "Test 13: memory.instruction.md is updated with new commands"
if [ -f ".github/instructions/memory.instruction.md" ]; then
  if grep -q "./deploy.sh monitoring" ".github/instructions/memory.instruction.md" && \
     grep -q "./deploy.sh infrastructure" ".github/instructions/memory.instruction.md"; then
    pass "memory.instruction.md includes new commands"
  else
    fail "memory.instruction.md does not include new commands"
  fi
else
  fail "memory.instruction.md does not exist"
fi

info ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info " ALL TESTS PASSED (13/13)"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info ""
info "Summary:"
info "  ✓ New 'monitoring' command works correctly"
info "  ✓ New 'infrastructure' command works correctly"
info "  ✓ Both commands support --check and --yes flags"
info "  ✓ Help documentation is updated"
info "  ✓ Playbook files exist and are referenced correctly"
info "  ✓ Log file paths are correct"
info "  ✓ Existing commands remain functional"
info "  ✓ Documentation is updated"
info ""

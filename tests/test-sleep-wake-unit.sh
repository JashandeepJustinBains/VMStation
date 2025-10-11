#!/usr/bin/env bash
# Unit tests for sleep/wake cycle changes
# These tests validate the logic without requiring actual cluster access

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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
echo "Sleep/Wake Cycle Unit Tests"
echo "========================================="
echo ""

# Test 1: Verify vmstation-event-wake.sh has tcpdump monitoring
echo "[1/6] Checking vmstation-event-wake.sh has tcpdump monitoring..."
if grep -q "tcpdump.*tcp port.*tcp\[tcpflags\]" "$REPO_ROOT/scripts/vmstation-event-wake.sh"; then
  log_pass "Event-wake script uses tcpdump for traffic monitoring"
else
  log_fail "Event-wake script missing tcpdump monitoring"
fi

# Test 2: Verify IP filtering is implemented
echo "[2/6] Checking internal IP filtering..."
if grep -q '192.*168.*4.*(61.*62.*63)' "$REPO_ROOT/scripts/vmstation-event-wake.sh" && \
   grep -q "node-to-node traffic.*ignore" "$REPO_ROOT/scripts/vmstation-event-wake.sh"; then
  log_pass "Internal IP filtering is implemented"
else
  log_fail "Internal IP filtering not found"
fi

# Test 3: Verify uncordon_node function exists
echo "[3/6] Checking for uncordon_node function..."
if grep -q "^uncordon_node()" "$REPO_ROOT/scripts/vmstation-event-wake.sh" && \
   grep -q "KUBECTL uncordon" "$REPO_ROOT/scripts/vmstation-event-wake.sh"; then
  log_pass "uncordon_node function exists with kubectl uncordon"
else
  log_fail "uncordon_node function not found or incomplete"
fi

# Test 4: Verify sleep script has actual suspend
echo "[4/6] Checking sleep script suspends nodes..."
if grep -q "systemctl suspend" "$REPO_ROOT/ansible/playbooks/setup-autosleep.yaml"; then
  log_pass "Sleep script includes systemctl suspend command"
else
  log_fail "Sleep script missing systemctl suspend"
fi

# Test 5: Verify state tracking is implemented
echo "[5/6] Checking state tracking..."
if grep -q "suspended:\$(date +%s)" "$REPO_ROOT/ansible/playbooks/setup-autosleep.yaml" && \
   grep -q "awake:\$(date +%s)" "$REPO_ROOT/scripts/vmstation-event-wake.sh"; then
  log_pass "State tracking implemented for suspend/wake"
else
  log_fail "State tracking not found"
fi

# Test 6: Verify log collection script exists and is executable
echo "[6/6] Checking log collection script..."
if [[ -f "$REPO_ROOT/scripts/vmstation-collect-wake-logs.sh" ]] && \
   [[ -x "$REPO_ROOT/scripts/vmstation-collect-wake-logs.sh" ]]; then
  log_pass "Log collection script exists and is executable"
else
  log_fail "Log collection script missing or not executable"
fi

echo ""
echo "========================================="
echo "Unit Test Results"
echo "========================================="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo "✅ All unit tests passed!"
  exit 0
else
  echo "❌ Some unit tests failed."
  exit 1
fi

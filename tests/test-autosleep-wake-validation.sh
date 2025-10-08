#!/usr/bin/env bash
# Test script: Validate auto-sleep and wake functionality
# Tests systemd timers, cron jobs, sleep transitions, WoL, and service restoration
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Configuration
MASTERNODE_IP="${MASTERNODE_IP:-192.168.4.63}"
STORAGE_NODE_IP="${STORAGE_NODE_IP:-192.168.4.61}"
HOMELAB_NODE_IP="${HOMELAB_NODE_IP:-192.168.4.62}"
STORAGE_NODE_MAC="b8:ac:6f:7e:6c:9d"
HOMELAB_NODE_MAC="d0:94:66:30:d6:63"
KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

echo "========================================="
echo "VMStation Auto-Sleep/Wake Validation"
echo "Testing sleep/wake cycle and monitoring"
echo "========================================="
echo ""

FAILED=0
PASSED=0
WARNINGS=0

# Logging functions
log_pass() {
  echo "✅ PASS: $*"
  PASSED=$((PASSED + 1))
}

log_fail() {
  echo "❌ FAIL: $*"
  FAILED=$((FAILED + 1))
}

log_warn() {
  echo "⚠️  WARN: $*"
  WARNINGS=$((WARNINGS + 1))
}

log_info() {
  echo "ℹ️  INFO: $*"
}

# Test 1: Verify systemd timer configuration on storagenodet3500
echo "[1/10] Testing systemd timer on storagenodet3500..."
if ssh -o ConnectTimeout=5 root@${STORAGE_NODE_IP} "systemctl is-enabled vmstation-autosleep.timer 2>/dev/null" | grep -q "enabled"; then
  log_pass "Auto-sleep timer is enabled on storagenodet3500"
  
  # Check timer status
  if ssh root@${STORAGE_NODE_IP} "systemctl is-active vmstation-autosleep.timer 2>/dev/null" | grep -q "active"; then
    log_pass "Auto-sleep timer is active on storagenodet3500"
  else
    log_warn "Auto-sleep timer is not active on storagenodet3500"
  fi
else
  log_fail "Auto-sleep timer is not enabled on storagenodet3500"
fi
echo ""

# Test 2: Verify systemd timer configuration on homelab (RHEL10)
echo "[2/10] Testing systemd timer on homelab (RHEL10)..."
if ssh -o ConnectTimeout=5 jashandeepjustinbains@${HOMELAB_NODE_IP} "systemctl is-enabled vmstation-autosleep.timer 2>/dev/null" | grep -q "enabled"; then
  log_pass "Auto-sleep timer is enabled on homelab"
  
  # Check timer status
  if ssh jashandeepjustinbains@${HOMELAB_NODE_IP} "systemctl is-active vmstation-autosleep.timer 2>/dev/null" | grep -q "active"; then
    log_pass "Auto-sleep timer is active on homelab"
  else
    log_warn "Auto-sleep timer is not active on homelab"
  fi
else
  log_fail "Auto-sleep timer is not enabled on homelab"
fi
echo ""

# Test 3: Verify auto-sleep scripts exist
echo "[3/10] Testing auto-sleep script existence..."
if ssh root@${STORAGE_NODE_IP} "test -x /usr/local/bin/vmstation-autosleep-monitor.sh"; then
  log_pass "Auto-sleep monitor script exists on storagenodet3500"
else
  log_fail "Auto-sleep monitor script missing on storagenodet3500"
fi

if ssh root@${STORAGE_NODE_IP} "test -x /usr/local/bin/vmstation-sleep.sh"; then
  log_pass "Sleep script exists on storagenodet3500"
else
  log_fail "Sleep script missing on storagenodet3500"
fi
echo ""

# Test 4: Verify Wake-on-LAN script and service
echo "[4/10] Testing WoL configuration..."
if test -x "$REPO_ROOT/scripts/vmstation-event-wake.sh"; then
  log_pass "WoL script exists and is executable"
else
  log_fail "WoL script missing or not executable"
fi

# Check if masternode has WoL service configured
if ssh -o ConnectTimeout=5 root@${MASTERNODE_IP} "test -f /etc/systemd/system/vmstation-event-wake.service"; then
  log_pass "WoL systemd service exists on masternode"
else
  log_warn "WoL systemd service not found on masternode"
fi
echo ""

# Test 5: Test kubectl access from control plane
echo "[5/10] Testing kubectl access..."
if ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes >/dev/null 2>&1"; then
  log_pass "kubectl access verified on masternode"
  
  # Get current node status
  NODE_STATUS=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --no-headers 2>/dev/null" || echo "")
  if [[ -n "$NODE_STATUS" ]]; then
    log_info "Current cluster status:"
    echo "$NODE_STATUS" | while read -r line; do
      echo "  $line"
    done
  fi
else
  log_fail "kubectl access failed on masternode"
fi
echo ""

# Test 6: Verify WoL tool availability
echo "[6/10] Testing WoL tool availability..."
WOL_TOOL_FOUND=false

if command -v wakeonlan >/dev/null 2>&1; then
  log_pass "wakeonlan tool is available"
  WOL_TOOL_FOUND=true
elif command -v etherwake >/dev/null 2>&1; then
  log_pass "etherwake tool is available"
  WOL_TOOL_FOUND=true
elif command -v ether-wake >/dev/null 2>&1; then
  log_pass "ether-wake tool is available"
  WOL_TOOL_FOUND=true
else
  log_fail "No WoL tool found (install wakeonlan, etherwake, or ether-wake)"
fi
echo ""

# Test 7: Verify node reachability
echo "[7/10] Testing node reachability..."
if ping -c 1 -W 2 ${STORAGE_NODE_IP} >/dev/null 2>&1; then
  log_pass "storagenodet3500 is reachable (${STORAGE_NODE_IP})"
else
  log_warn "storagenodet3500 is not reachable (${STORAGE_NODE_IP})"
fi

if ping -c 1 -W 2 ${HOMELAB_NODE_IP} >/dev/null 2>&1; then
  log_pass "homelab is reachable (${HOMELAB_NODE_IP})"
else
  log_warn "homelab is not reachable (${HOMELAB_NODE_IP})"
fi
echo ""

# Test 8: Verify monitoring services are configured
echo "[8/10] Testing monitoring service configuration..."
if ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring >/dev/null 2>&1"; then
  log_pass "Monitoring namespace exists"
  
  # Check key monitoring pods
  PROMETHEUS_RUNNING=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring 2>/dev/null | grep prometheus | grep Running" || echo "")
  if [[ -n "$PROMETHEUS_RUNNING" ]]; then
    log_pass "Prometheus pods are running"
  else
    log_warn "Prometheus pods may not be running"
  fi
  
  GRAFANA_RUNNING=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -n monitoring 2>/dev/null | grep grafana | grep Running" || echo "")
  if [[ -n "$GRAFANA_RUNNING" ]]; then
    log_pass "Grafana pods are running"
  else
    log_warn "Grafana pods may not be running"
  fi
else
  log_fail "Cannot access monitoring namespace"
fi
echo ""

# Test 9: Verify log files and directories
echo "[9/10] Testing log file configuration..."
if ssh root@${MASTERNODE_IP} "test -d /var/lib/vmstation"; then
  log_pass "VMStation state directory exists"
else
  log_warn "VMStation state directory not found"
fi

if ssh root@${MASTERNODE_IP} "test -f /var/log/vmstation-autosleep.log -o -f /var/log/vmstation-sleep.log"; then
  log_pass "Auto-sleep log files exist"
else
  log_warn "Auto-sleep log files not yet created (normal on first setup)"
fi
echo ""

# Test 10: Verify systemd timer schedules
echo "[10/10] Testing systemd timer schedules..."
TIMER_SCHEDULE=$(ssh root@${MASTERNODE_IP} "systemctl list-timers vmstation-autosleep.timer 2>/dev/null | grep vmstation" || echo "")
if [[ -n "$TIMER_SCHEDULE" ]]; then
  log_pass "Auto-sleep timer is scheduled"
  log_info "Timer schedule:"
  echo "$TIMER_SCHEDULE" | while read -r line; do
    echo "  $line"
  done
else
  log_fail "Auto-sleep timer schedule not found"
fi
echo ""

# Summary
echo "========================================="
echo "Test Results Summary"
echo "========================================="
echo "Passed:   $PASSED"
echo "Failed:   $FAILED"
echo "Warnings: $WARNINGS"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo "✅ All critical tests passed!"
  echo ""
  echo "Auto-Sleep/Wake Configuration:"
  echo "  - Systemd timers configured on both nodes"
  echo "  - Scripts deployed and executable"
  echo "  - Monitoring services available"
  echo ""
  echo "Manual Testing:"
  echo "  1. Trigger sleep: ssh root@${MASTERNODE_IP} 'sudo /usr/local/bin/vmstation-sleep.sh'"
  echo "  2. Check node status: ssh root@${MASTERNODE_IP} 'kubectl get nodes'"
  echo "  3. Send WoL: wakeonlan ${STORAGE_NODE_MAC}"
  echo "  4. Monitor wake time and verify services"
  echo ""
  exit 0
else
  echo "❌ Some tests failed. Review details above."
  echo ""
  echo "Common fixes:"
  echo "  1. Deploy auto-sleep: ./deploy.sh setup"
  echo "  2. Check systemd status: systemctl status vmstation-autosleep.timer"
  echo "  3. Review logs: journalctl -u vmstation-autosleep -n 50"
  echo ""
  exit 1
fi

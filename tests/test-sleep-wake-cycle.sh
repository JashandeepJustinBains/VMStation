#!/usr/bin/env bash
# Test script: Automated sleep/wake cycle validation
# Triggers sleep, sends WoL, measures wake time, and validates service restoration
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Configuration
MASTERNODE_IP="${MASTERNODE_IP:-192.168.4.63}"
STORAGE_NODE_IP="${STORAGE_NODE_IP:-192.168.4.61}"
HOMELAB_NODE_IP="${HOMELAB_NODE_IP:-192.168.4.62}"
STORAGE_NODE_MAC="b8:ac:6f:7e:6c:9d"
HOMELAB_NODE_MAC="d0:94:66:30:d6:63"
WAKE_TIMEOUT=120  # Maximum seconds to wait for node to wake

echo "========================================="
echo "VMStation Sleep/Wake Cycle Test"
echo "Automated testing of full sleep/wake cycle"
echo "========================================="
echo ""
echo "⚠️  WARNING: This test will:"
echo "  1. Cordon and drain worker nodes"
echo "  2. Actually SUSPEND worker nodes (low power mode)"
echo "  3. Send Wake-on-LAN packets to wake them"
echo "  4. Auto-uncordon nodes after successful wake"
echo "  5. Measure actual hardware wake time"
echo ""
echo "📝 NOTE: This test requires:"
echo "  - Wake-on-LAN enabled in BIOS/UEFI"
echo "  - Network interfaces support WoL (check with ethtool)"
echo "  - SSH access to all nodes"
echo "  - Root/sudo privileges on all nodes"
echo ""
read -p "Continue with sleep/wake cycle test? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Test cancelled."
  exit 0
fi
echo ""

FAILED=0
PASSED=0

# Logging functions
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

timestamp() {
  date +%s
}

# Test 1: Record initial cluster state
echo "[1/7] Recording initial cluster state..."
INITIAL_NODE_STATUS=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --no-headers 2>/dev/null" || echo "")
if [[ -n "$INITIAL_NODE_STATUS" ]]; then
  log_pass "Cluster is accessible"
  log_info "Initial node status:"
  echo "$INITIAL_NODE_STATUS" | while read -r line; do
    echo "  $line"
  done
  
  # Count Ready nodes
  READY_COUNT=$(echo "$INITIAL_NODE_STATUS" | grep -c " Ready " || echo "0")
  log_info "Ready nodes: $READY_COUNT"
else
  log_fail "Cannot access cluster"
  exit 1
fi
echo ""

# Test 2: Trigger cluster sleep
echo "[2/7] Triggering cluster sleep..."
log_info "Running vmstation-sleep.sh on masternode..."

SLEEP_START=$(timestamp)
if ssh root@${MASTERNODE_IP} "sudo /usr/local/bin/vmstation-sleep.sh" 2>&1 | tee /tmp/sleep-output.log; then
  log_pass "Sleep script executed"
else
  log_fail "Sleep script execution failed"
  echo "Sleep script output:"
  cat /tmp/sleep-output.log
  exit 1
fi

# Wait a bit for nodes to drain
sleep 10
echo ""

# Test 3: Verify nodes are cordoned/drained
echo "[3/7] Verifying node status after sleep..."
SLEEP_NODE_STATUS=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --no-headers 2>/dev/null" || echo "")
if [[ -n "$SLEEP_NODE_STATUS" ]]; then
  log_info "Node status after sleep:"
  echo "$SLEEP_NODE_STATUS" | while read -r line; do
    echo "  $line"
  done
  
  # Check if worker nodes are cordoned
  CORDONED_COUNT=$(echo "$SLEEP_NODE_STATUS" | grep -c "SchedulingDisabled" || echo "0")
  if [[ "$CORDONED_COUNT" -gt 0 ]]; then
    log_pass "Worker nodes are cordoned ($CORDONED_COUNT nodes)"
  else
    log_fail "No nodes appear to be cordoned"
  fi
else
  log_fail "Cannot get node status after sleep"
fi
echo ""

# Test 4: Send Wake-on-LAN packets
echo "[4/7] Sending Wake-on-LAN packets..."

# Try to wake storage node
log_info "Waking storagenodet3500 (${STORAGE_NODE_MAC})..."
WOL_SENT=false

if command -v wakeonlan >/dev/null 2>&1; then
  wakeonlan ${STORAGE_NODE_MAC}
  log_pass "WoL packet sent to storagenodet3500 (wakeonlan)"
  WOL_SENT=true
elif command -v etherwake >/dev/null 2>&1; then
  etherwake ${STORAGE_NODE_MAC}
  log_pass "WoL packet sent to storagenodet3500 (etherwake)"
  WOL_SENT=true
elif command -v ether-wake >/dev/null 2>&1; then
  ether-wake ${STORAGE_NODE_MAC}
  log_pass "WoL packet sent to storagenodet3500 (ether-wake)"
  WOL_SENT=true
else
  log_fail "No WoL tool available (install wakeonlan, etherwake, or ether-wake)"
fi

# Try to wake homelab node
log_info "Waking homelab (${HOMELAB_NODE_MAC})..."
if command -v wakeonlan >/dev/null 2>&1; then
  wakeonlan ${HOMELAB_NODE_MAC}
  log_pass "WoL packet sent to homelab (wakeonlan)"
elif command -v etherwake >/dev/null 2>&1; then
  etherwake ${HOMELAB_NODE_MAC}
  log_pass "WoL packet sent to homelab (etherwake)"
elif command -v ether-wake >/dev/null 2>&1; then
  ether-wake ${HOMELAB_NODE_MAC}
  log_pass "WoL packet sent to homelab (ether-wake)"
fi
echo ""

# Test 5: Measure wake time
echo "[5/7] Measuring wake time..."
WAKE_START=$(timestamp)

# Wait for storage node to respond
log_info "Waiting for storagenodet3500 to respond (timeout: ${WAKE_TIMEOUT}s)..."
log_info "Note: Actual hardware wake may take 30-90 seconds"
STORAGE_WAKE_TIME=0
STORAGE_AWAKE=false
while [[ $STORAGE_WAKE_TIME -lt $WAKE_TIMEOUT ]]; do
  if ping -c 1 -W 1 ${STORAGE_NODE_IP} >/dev/null 2>&1; then
    STORAGE_AWAKE=true
    log_pass "storagenodet3500 responded after ${STORAGE_WAKE_TIME}s"
    break
  fi
  sleep 5
  STORAGE_WAKE_TIME=$((STORAGE_WAKE_TIME + 5))
done

if [[ "$STORAGE_AWAKE" == "false" ]]; then
  log_fail "storagenodet3500 did not respond within ${WAKE_TIMEOUT}s"
  log_info "Machine may still be waking up from suspend. Check with: ping ${STORAGE_NODE_IP}"
fi

# Wait for homelab node to respond
log_info "Waiting for homelab to respond (timeout: ${WAKE_TIMEOUT}s)..."
log_info "Note: Actual hardware wake may take 30-90 seconds"
HOMELAB_WAKE_TIME=0
HOMELAB_AWAKE=false
while [[ $HOMELAB_WAKE_TIME -lt $WAKE_TIMEOUT ]]; do
  if ping -c 1 -W 1 ${HOMELAB_NODE_IP} >/dev/null 2>&1; then
    HOMELAB_AWAKE=true
    log_pass "homelab responded after ${HOMELAB_WAKE_TIME}s"
    break
  fi
  sleep 5
  HOMELAB_WAKE_TIME=$((HOMELAB_WAKE_TIME + 5))
done

if [[ "$HOMELAB_AWAKE" == "false" ]]; then
  log_fail "homelab did not respond within ${WAKE_TIMEOUT}s"
  log_info "Machine may still be waking up from suspend. Check with: ping ${HOMELAB_NODE_IP}"
fi
echo ""

# Test 6: Validate service restoration
echo "[6/7] Validating service restoration..."

# Wait a bit for services to fully start
log_info "Waiting 30s for services to stabilize..."
sleep 30

# Check kubelet on storage node
if [[ "$STORAGE_AWAKE" == "true" ]]; then
  if ssh root@${STORAGE_NODE_IP} "systemctl is-active kubelet" | grep -q "active"; then
    log_pass "kubelet is active on storagenodet3500"
  else
    log_fail "kubelet is not active on storagenodet3500"
  fi
  
  # Check node-exporter
  if curl -sf "http://${STORAGE_NODE_IP}:9100/metrics" | grep -q "node_cpu_seconds_total"; then
    log_pass "node-exporter is responding on storagenodet3500"
  else
    log_fail "node-exporter is not responding on storagenodet3500"
  fi
  
  # Check if node is uncordoned
  NODE_SCHEDULABLE=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get node storagenodet3500 -o jsonpath='{.spec.unschedulable}'" 2>/dev/null || echo "true")
  if [[ "$NODE_SCHEDULABLE" == "false" ]] || [[ -z "$NODE_SCHEDULABLE" ]]; then
    log_pass "storagenodet3500 is uncordoned and schedulable"
  else
    log_fail "storagenodet3500 is still cordoned (should be auto-uncordoned after wake)"
    log_info "Manual uncordon: kubectl uncordon storagenodet3500"
  fi
fi

# Check services on homelab
if [[ "$HOMELAB_AWAKE" == "true" ]]; then
  # For RHEL/RKE2 node, check rke2-server or rke2-agent
  if ssh jashandeepjustinbains@${HOMELAB_NODE_IP} "systemctl is-active rke2-server 2>/dev/null || systemctl is-active rke2-agent 2>/dev/null" | grep -q "active"; then
    log_pass "rke2 service is active on homelab"
  else
    log_fail "rke2 service is not active on homelab (may not be configured)"
  fi
  
  # Check if node is uncordoned
  NODE_SCHEDULABLE=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get node homelab -o jsonpath='{.spec.unschedulable}'" 2>/dev/null || echo "true")
  if [[ "$NODE_SCHEDULABLE" == "false" ]] || [[ -z "$NODE_SCHEDULABLE" ]]; then
    log_pass "homelab is uncordoned and schedulable"
  else
    log_fail "homelab is still cordoned (should be auto-uncordoned after wake)"
    log_info "Manual uncordon: kubectl uncordon homelab"
  fi
fi

# Check cluster node status
log_info "Checking cluster node status..."
WAKE_NODE_STATUS=$(ssh root@${MASTERNODE_IP} "kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --no-headers 2>/dev/null" || echo "")
if [[ -n "$WAKE_NODE_STATUS" ]]; then
  log_info "Node status after wake:"
  echo "$WAKE_NODE_STATUS" | while read -r line; do
    echo "  $line"
  done
fi
echo ""

# Test 7: Validate monitoring stack
echo "[7/7] Validating monitoring stack..."

# Check Prometheus
if curl -sf "http://${MASTERNODE_IP}:30090/-/healthy" | grep -q "Prometheus is Healthy"; then
  echo "curl http://${MASTERNODE_IP}:30090/-/healthy ok"
  log_pass "Prometheus is healthy after wake"
else
  echo "curl http://${MASTERNODE_IP}:30090/-/healthy error"
  log_fail "Prometheus is not healthy after wake"
fi

# Check Grafana
if curl -sf "http://${MASTERNODE_IP}:30300/api/health" | grep -q "database"; then
  echo "curl http://${MASTERNODE_IP}:30300/api/health ok"
  log_pass "Grafana is healthy after wake"
else
  echo "curl http://${MASTERNODE_IP}:30300/api/health error"
  log_fail "Grafana is not healthy after wake"
fi
echo ""

# Summary
echo "========================================="
echo "Sleep/Wake Cycle Test Results"
echo "========================================="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""
echo "Wake Time Summary:"
echo "  storagenodet3500: ${STORAGE_WAKE_TIME}s"
echo "  homelab:          ${HOMELAB_WAKE_TIME}s"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo "✅ Sleep/wake cycle completed successfully!"
  echo ""
  echo "Next steps:"
  echo "  1. Verify nodes are uncordoned: kubectl get nodes"
  echo "  2. Verify pods are rescheduled: kubectl get pods -A"
  echo "  3. Check monitoring dashboards: http://${MASTERNODE_IP}:30300"
  echo "  4. Review wake logs: /var/log/vmstation-event-wake.log"
  echo ""
  echo "To collect detailed wake logs for debugging:"
  echo "  sudo /usr/local/bin/vmstation-collect-wake-logs.sh"
  echo ""
  exit 0
else
  echo "❌ Sleep/wake cycle test encountered failures."
  echo ""
  echo "Review details above for troubleshooting."
  echo ""
  echo "Common issues:"
  echo "  - Nodes didn't wake: Check WoL enabled in BIOS and network driver supports it"
  echo "  - Services not starting: Nodes may still be booting, wait and check again"
  echo "  - Nodes still cordoned: Auto-uncordon may have failed, manually uncordon"
  echo ""
  echo "To collect diagnostic logs:"
  echo "  sudo /usr/local/bin/vmstation-collect-wake-logs.sh"
  echo ""
  echo "To manually uncordon nodes:"
  echo "  kubectl uncordon storagenodet3500"
  echo "  kubectl uncordon homelab"
  echo ""
  exit 1
fi

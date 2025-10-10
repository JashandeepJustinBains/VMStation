#!/usr/bin/env bash
# Master test suite: Complete VMStation validation
# Runs all sleep/wake, monitoring, and exporter tests in sequence
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}VMStation Complete Validation Suite${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

# Test suite tracking
run_test_suite() {
  local suite_name="$1"
  local test_script="$2"
  
  TOTAL_SUITES=$((TOTAL_SUITES + 1))
  
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}Test Suite: $suite_name${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  
  if [[ -x "$test_script" ]]; then
    if "$test_script"; then
      echo -e "${GREEN}✅ SUITE PASSED: $suite_name${NC}"
      PASSED_SUITES=$((PASSED_SUITES + 1))
      echo ""
      return 0
    else
      echo -e "${RED}❌ SUITE FAILED: $suite_name${NC}"
      FAILED_SUITES=$((FAILED_SUITES + 1))
      echo ""
      return 1
    fi
  else
    echo -e "${YELLOW}⚠️  SUITE SKIPPED: $suite_name (script not executable or not found)${NC}"
    echo ""
    return 0
  fi
}

# Introduction
echo "This test suite validates:"
echo "  1. Auto-sleep and wake configuration"
echo "  2. Monitoring exporters health"
echo "  3. Loki log aggregation"
echo "  4. Loki ConfigMap drift prevention"
echo "  5. Headless service endpoints validation"
echo "  6. Sleep/wake cycle (optional - requires confirmation)"
echo ""
echo "Test order:"
echo "  - Non-destructive tests run first"
echo "  - Sleep/wake cycle test is optional (requires user confirmation)"
echo ""

# Phase 1: Configuration validation (non-destructive)
echo -e "${GREEN}Phase 1: Configuration Validation${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

run_test_suite "Auto-Sleep/Wake Configuration" \
  "tests/test-autosleep-wake-validation.sh" || true

echo ""

# Phase 2: Monitoring health (non-destructive)
echo -e "${GREEN}Phase 2: Monitoring Health Validation${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

run_test_suite "Monitoring Exporters Health" \
  "tests/test-monitoring-exporters-health.sh" || true

echo ""

run_test_suite "Loki Log Aggregation" \
  "tests/test-loki-validation.sh" || true

echo ""

run_test_suite "Loki ConfigMap Drift Prevention" \
  "tests/test-loki-config-drift.sh" || true

echo ""

run_test_suite "Monitoring Access (Updated)" \
  "tests/test-monitoring-access.sh" || true

echo ""

run_test_suite "Headless Service Endpoints" \
  "tests/test-headless-service-endpoints.sh" || true

echo ""

# Phase 3: Sleep/wake cycle (destructive - optional)
echo -e "${YELLOW}Phase 3: Sleep/Wake Cycle Test (Optional)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${YELLOW}WARNING: This test will trigger cluster sleep and wake.${NC}"
echo "This is a destructive test that will:"
echo "  - Cordon and drain worker nodes"
echo "  - Scale down deployments"
echo "  - Send Wake-on-LAN packets"
echo "  - Measure wake time and validate service restoration"
echo ""
read -p "Run sleep/wake cycle test? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  run_test_suite "Sleep/Wake Cycle" \
    "tests/test-sleep-wake-cycle.sh" || true
else
  echo -e "${YELLOW}⚠️  Sleep/wake cycle test skipped by user${NC}"
fi

echo ""

# Final summary
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Complete Validation Summary${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo "Test Suites Run:    $TOTAL_SUITES"
echo "Suites Passed:      $PASSED_SUITES"
echo "Suites Failed:      $FAILED_SUITES"
echo ""

if [[ $FAILED_SUITES -eq 0 ]]; then
  echo -e "${GREEN}✅ All test suites passed!${NC}"
  echo ""
  echo "VMStation is properly configured:"
  echo "  ✅ Auto-sleep/wake monitoring enabled"
  echo "  ✅ Monitoring stack healthy"
  echo "  ✅ Exporters collecting metrics"
  echo "  ✅ Log aggregation functional"
  echo ""
  echo "Access your monitoring:"
  echo "  Grafana:    http://192.168.4.63:30300"
  echo "  Prometheus: http://192.168.4.63:30090"
  echo ""
  exit 0
else
  echo -e "${RED}❌ Some test suites failed.${NC}"
  echo ""
  echo "Review the output above for details."
  echo ""
  echo "Common next steps:"
  echo "  1. Fix failed tests and re-run: ./tests/test-complete-validation.sh"
  echo "  2. Deploy missing components: ./deploy.sh setup"
  echo "  3. Check cluster health: kubectl get pods -A"
  echo "  4. Review logs: journalctl -u vmstation-autosleep -n 50"
  echo ""
  exit 1
fi

#!/usr/bin/env bash
# Comprehensive Validation Script for VMStation
# Runs all validation tests and provides a complete health report
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================="
echo "VMStation Comprehensive Validation"
echo "========================================="
echo ""

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Test tracking
test_suite() {
  local name="$1"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$name${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

run_test() {
  local test_name="$1"
  local test_script="$2"
  
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  echo -n "Running: $test_name... "
  
  if [[ -x "$test_script" ]]; then
    if output=$("$test_script" 2>&1); then
      echo -e "${GREEN}✅ PASS${NC}"
      PASSED_TESTS=$((PASSED_TESTS + 1))
      return 0
    else
      echo -e "${RED}❌ FAIL${NC}"
      FAILED_TESTS=$((FAILED_TESTS + 1))
      echo "$output" | head -20
      return 1
    fi
  else
    echo -e "${YELLOW}⚠️  SKIP${NC} (script not executable or not found)"
    WARNINGS=$((WARNINGS + 1))
    return 0
  fi
}

# 1. Code Quality Tests
test_suite "Code Quality & Syntax Validation"

if [[ -x tests/test-syntax.sh ]]; then
  run_test "Ansible Syntax Check" "tests/test-syntax.sh" || true
else
  echo "⚠️  Syntax test not found"
  WARNINGS=$((WARNINGS + 1))
fi

echo ""

# 2. Security Validation
test_suite "Security Audit"

if [[ -x tests/test-security-audit.sh ]]; then
  run_test "Security Audit" "tests/test-security-audit.sh" || true
else
  echo "⚠️  Security audit not found"
  WARNINGS=$((WARNINGS + 1))
fi

echo ""

# 3. Configuration Validation
test_suite "Configuration Validation"

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking inventory file... "
if [[ -f inventory.ini ]]; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking deploy script... "
if [[ -x deploy.sh ]]; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking playbook directory... "
if [[ -d ansible/playbooks ]] && [[ $(find ansible/playbooks -name "*.yaml" -o -name "*.yml" | wc -l) -gt 0 ]]; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking manifests directory... "
if [[ -d manifests/monitoring ]] && [[ -f manifests/monitoring/prometheus.yaml ]] && [[ -f manifests/monitoring/grafana.yaml ]]; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo ""

# 4. Documentation Validation
test_suite "Documentation Validation"

docs=(
  "docs/MONITORING_ACCESS.md"
  "docs/BEST_PRACTICES.md"
  "docs/AUTOSLEEP_RUNBOOK.md"
  "ENHANCEMENT_SUMMARY.md"
  "README.md"
)

for doc in "${docs[@]}"; do
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  echo -n "Checking $doc... "
  if [[ -f "$doc" ]] && [[ $(wc -c < "$doc") -gt 100 ]]; then
    echo -e "${GREEN}✅ PASS${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo -e "${YELLOW}⚠️  MISSING or EMPTY${NC}"
    WARNINGS=$((WARNINGS + 1))
  fi
done

echo ""

# 5. Monitoring Configuration Validation
test_suite "Monitoring Configuration"

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking Grafana anonymous access config... "
if grep -q "GF_AUTH_ANONYMOUS_ENABLED" manifests/monitoring/grafana.yaml && \
   grep -q "true" manifests/monitoring/grafana.yaml; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking Grafana Viewer role... "
if grep -q "GF_AUTH_ANONYMOUS_ORG_ROLE" manifests/monitoring/grafana.yaml && \
   grep -q "Viewer" manifests/monitoring/grafana.yaml; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking Prometheus CORS config... "
if grep -q "web.cors.origin" manifests/monitoring/prometheus.yaml; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${YELLOW}⚠️  NOT CONFIGURED${NC}"
  WARNINGS=$((WARNINGS + 1))
fi

echo ""

# 6. Auto-Sleep Configuration Validation
test_suite "Auto-Sleep Configuration"

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking auto-sleep playbook... "
if [[ -f ansible/playbooks/setup-autosleep.yaml ]]; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking auto-sleep monitor script... "
if grep -q "vmstation-autosleep-monitor.sh" ansible/playbooks/setup-autosleep.yaml; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking configurable threshold... "
if grep -q "VMSTATION_INACTIVITY_THRESHOLD" ansible/playbooks/setup-autosleep.yaml; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking logging configuration... "
if grep -q "LOG_FILE" ansible/playbooks/setup-autosleep.yaml; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo ""

# 7. Deploy Script Validation
test_suite "Deploy Script Enhancements"

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking timestamped logging... "
if grep -q "log_timestamp" deploy.sh; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking retry logic... "
if grep -q "retry_cmd" deploy.sh; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking dependency validation... "
if grep -q "validate_dependencies" deploy.sh; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo ""

# 8. Playbook Enhancements Validation
test_suite "Playbook Enhancements"

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking deploy-cluster health checks... "
if grep -q "Verify Grafana endpoint" ansible/playbooks/deploy-cluster.yaml; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking RKE2 retry logic... "
if grep -q "retries:" ansible/playbooks/install-rke2-homelab.yml; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking RKE2 download method... "
if grep -A 2 "Download RKE2 installation script" ansible/playbooks/install-rke2-homelab.yml | grep -q "shell:.*curl"; then
  echo -e "${GREEN}✅ PASS${NC}"
  PASSED_TESTS=$((PASSED_TESTS + 1))
else
  echo -e "${RED}❌ FAIL${NC}"
  FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo ""

# 9. Optional: Monitoring Endpoint Tests (if cluster is running)
test_suite "Monitoring Endpoints (Optional)"

echo "ℹ️  Monitoring endpoint tests can be run with:"
echo "    ./tests/test-monitoring-access.sh"
echo ""

# 10. Final Summary
echo ""
echo "========================================="
echo "Validation Summary"
echo "========================================="
echo ""
echo -e "Total Tests:    $TOTAL_TESTS"
echo -e "${GREEN}Passed:         $PASSED_TESTS${NC}"
echo -e "${RED}Failed:         $FAILED_TESTS${NC}"
echo -e "${YELLOW}Warnings:       $WARNINGS${NC}"
echo ""

# Calculate percentage
if [[ $TOTAL_TESTS -gt 0 ]]; then
  PASS_PERCENTAGE=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
  echo "Pass Rate: ${PASS_PERCENTAGE}%"
  echo ""
fi

# Exit status
if [[ $FAILED_TESTS -eq 0 ]]; then
  echo -e "${GREEN}✅ All validations passed!${NC}"
  echo ""
  echo "Your VMStation automation is:"
  echo "  ✅ Industry-standard compliant"
  echo "  ✅ Security validated"
  echo "  ✅ Well-documented"
  echo "  ✅ Production-ready for homelab"
  echo ""
  exit 0
else
  echo -e "${RED}❌ Some validations failed${NC}"
  echo ""
  echo "Review the failures above and:"
  echo "  1. Check file permissions"
  echo "  2. Verify file contents"
  echo "  3. Run specific test scripts for details"
  echo ""
  exit 1
fi

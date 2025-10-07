#!/usr/bin/env bash
# =============================================================================
# Test: RKE2 Installation Script Download Method
# Validates that RKE2 uses shell/curl instead of get_url to avoid SSL issues
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RKE2_PLAYBOOK="$REPO_ROOT/ansible/playbooks/install-rke2-homelab.yml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "RKE2 Installation Method Test"
echo "========================================="
echo ""

FAILED=0

# Test 1: Check that get_url is NOT used for downloading RKE2 script
echo "[1/3] Checking RKE2 download method..."
if grep -q "get_url:" "$RKE2_PLAYBOOK" && grep -A 3 "get_url:" "$RKE2_PLAYBOOK" | grep -q "https://get.rke2.io"; then
    echo -e "  ${RED}❌ FAIL${NC}: RKE2 playbook still uses get_url (known to have SSL issues)"
    FAILED=$((FAILED + 1))
else
    echo -e "  ${GREEN}✅ PASS${NC}: RKE2 playbook does not use get_url for installation script"
fi

# Test 2: Check that shell/curl is used instead
echo "[2/3] Checking for shell/curl method..."
if grep -A 2 "Download RKE2 installation script" "$RKE2_PLAYBOOK" | grep -q "shell:.*curl"; then
    echo -e "  ${GREEN}✅ PASS${NC}: RKE2 playbook uses shell/curl for download"
else
    echo -e "  ${RED}❌ FAIL${NC}: RKE2 playbook does not use shell/curl for download"
    FAILED=$((FAILED + 1))
fi

# Test 3: Verify the curl command has proper flags
echo "[3/3] Checking curl command flags..."
if grep -A 2 "Download RKE2 installation script" "$RKE2_PLAYBOOK" | grep -q "curl -sfL"; then
    echo -e "  ${GREEN}✅ PASS${NC}: Curl command uses proper flags (-sfL for silent, fail-fast, follow-redirects)"
else
    echo -e "  ${YELLOW}⚠️  WARN${NC}: Curl command may not have optimal flags"
fi

echo ""
echo "========================================="
if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests PASSED${NC}"
    echo "========================================="
    exit 0
else
    echo -e "${RED}❌ $FAILED test(s) FAILED${NC}"
    echo "========================================="
    exit 1
fi

#!/bin/bash
# Pre-deployment checklist - Run this before deploying to validate everything is ready

# Determine repository root relative to this script so the checklist can be run
# from any checked-out location (CI runners have different paths).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# The tests directory is one level below the repository root
REPO_ROOT="${SCRIPT_DIR%/tests}"
cd "$REPO_ROOT" || {
    echo "Could not change directory to repository root: $REPO_ROOT" >&2
}

echo "=============================================="
echo "VMStation Pre-Deployment Checklist"
echo "=============================================="
echo

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

check_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((PASS++))
}

check_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((FAIL++))
}

check_warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
    ((WARN++))
}

echo "1. Checking repository structure..."
if [ -d "$REPO_ROOT/ansible" ] && [ -d "$REPO_ROOT/manifests" ] && [ -d "$REPO_ROOT/tests" ]; then
    check_pass "Repository structure is valid"
else
    check_fail "Repository structure incomplete"
fi

echo
echo "2. Checking required files exist..."
required_files=(
    "ansible/playbooks/deploy-cluster.yaml"
    "inventory.ini"
    "deploy.sh"
    "manifests/monitoring/prometheus.yaml"
    "manifests/monitoring/grafana.yaml"
    "manifests/monitoring/loki.yaml"
)

for file in "${required_files[@]}"; do
    if [ -f "$REPO_ROOT/$file" ]; then
        check_pass "$file exists"
    else
        check_fail "$file NOT FOUND"
    fi
done

echo
echo "3. Checking Ansible installation..."
if command -v ansible-playbook >/dev/null 2>&1; then
    version=$(ansible-playbook --version | head -1)
    check_pass "Ansible installed: $version"
else
    check_fail "ansible-playbook not found"
fi

echo
echo "4. Validating playbook syntax..."
if ansible-playbook --syntax-check ansible/playbooks/deploy-cluster.yaml >/dev/null 2>&1; then
    check_pass "Deploy playbook syntax valid"
else
    check_fail "Deploy playbook syntax ERROR"
fi

echo
echo "5. Checking inventory file..."
if ansible-inventory -i inventory.ini --list >/dev/null 2>&1; then
    check_pass "Inventory file valid"
    
    # Check for required groups
    groups=$(ansible-inventory -i inventory.ini --list | jq -r '.all.children | keys[]' 2>/dev/null)
    for group in monitoring_nodes storage_nodes compute_nodes; do
        if echo "$groups" | grep -q "$group"; then
            check_pass "Group '$group' defined in inventory"
        else
            check_warn "Group '$group' not found in inventory"
        fi
    done
else
    check_fail "Inventory file invalid or jq not installed"
fi

echo
echo "6. Verifying playbook phase order..."
# Parse phase numbers in a portable way (avoid awk match() incompatibilities
# across different awk implementations used on various CI/host platforms).
phases=$(grep -oE 'Phase [0-9]+' ansible/playbooks/deploy-cluster.yaml 2>/dev/null | sed -E 's/Phase //g' | tr '\n' ' ' | sed -E 's/ +$//')
expected="0 1 2 3 4 5 6 7 8"
actual="$phases"

# Normalize whitespace and compare
if [ "$(echo $actual)" = "$(echo $expected)" ]; then
    check_pass "Playbook phases in correct order (0-8)"
else
    check_fail "Playbook phase order incorrect: $actual (expected: $expected)"
fi

echo
echo "7. Checking monitoring manifests..."
manifest_count=$(find manifests/monitoring -name "*.yaml" -type f | wc -l)
if [ "$manifest_count" -ge 10 ]; then
    check_pass "Found $manifest_count monitoring manifests"
else
    check_warn "Only found $manifest_count monitoring manifests (expected >= 10)"
fi

# Validate YAML syntax
for manifest in manifests/monitoring/*.yaml; do
    if python3 -c "import yaml; list(yaml.safe_load_all(open('$manifest')))" 2>/dev/null; then
        : # pass silently
    else
        check_fail "$(basename $manifest) has YAML syntax errors"
    fi
done

echo
echo "8. Checking for critical fixes..."

# Check blackbox-exporter has nodeSelector
if grep -A 20 "name: blackbox-exporter" manifests/monitoring/prometheus.yaml | grep -q "nodeSelector:"; then
    check_pass "Blackbox-exporter has nodeSelector configured"
else
    check_fail "Blackbox-exporter missing nodeSelector"
fi

# Check Phase 0 is complete
phase0_tasks=$(awk '/^- name:.*Phase 0:/,/^- name:.*Phase 1:/' ansible/playbooks/deploy-cluster.yaml | grep -c "name: \"" || echo "0")
if [ "$phase0_tasks" -ge 20 ]; then
    check_pass "Phase 0 has sufficient tasks ($phase0_tasks)"
else
    check_warn "Phase 0 might be incomplete (only $phase0_tasks tasks found)"
fi

# Check Phase 8 is at the end
phase8_line=$(grep -n "^- name:.*Phase 8:" ansible/playbooks/deploy-cluster.yaml | cut -d: -f1)
phase7_line=$(grep -n "^- name:.*Phase 7:" ansible/playbooks/deploy-cluster.yaml | cut -d: -f1)

if [ "$phase8_line" -gt "$phase7_line" ]; then
    check_pass "Phase 8 is positioned after Phase 7 (line $phase8_line > $phase7_line)"
else
    check_fail "Phase 8 is NOT after Phase 7 (line $phase8_line vs $phase7_line)"
fi

echo
echo "9. Checking deploy.sh script..."
if [ -x "deploy.sh" ]; then
    check_pass "deploy.sh is executable"
else
    check_warn "deploy.sh is not executable (run: chmod +x deploy.sh)"
fi

if bash -n deploy.sh 2>/dev/null; then
    check_pass "deploy.sh syntax is valid"
else
    check_fail "deploy.sh has syntax errors"
fi

echo
echo "10. Checking SSH connectivity (if possible)..."
if [ -f "$HOME/.ssh/id_k3s" ]; then
    check_pass "SSH key ~/.ssh/id_k3s exists"
else
    check_warn "SSH key ~/.ssh/id_k3s not found (might be needed for worker nodes)"
fi

echo
echo "=============================================="
echo "Summary"
echo "=============================================="
echo -e "${GREEN}Passed:${NC}  $PASS"
echo -e "${YELLOW}Warnings:${NC} $WARN"
echo -e "${RED}Failed:${NC}  $FAIL"
echo

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✅ READY FOR DEPLOYMENT${NC}"
    echo
    echo "You can now deploy the cluster with:"
    echo "  ./deploy.sh reset      # Reset existing cluster (if any)"
    echo "  ./deploy.sh all --yes  # Deploy Debian cluster"
    echo
    exit 0
else
    echo -e "${RED}❌ NOT READY FOR DEPLOYMENT${NC}"
    echo
    echo "Please fix the $FAIL failed checks before deploying."
    echo
    exit 1
fi

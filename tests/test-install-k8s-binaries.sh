#!/usr/bin/env bash
# Test script to verify install-k8s-binaries role integration
# Tests that the role is properly structured and integrated into deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

info(){ echo "[TEST-INFO] $*" >&2; }
pass(){ echo "[TEST-PASS] ✓ $*" >&2; }
fail(){ echo "[TEST-FAIL] ✗ $*" >&2; exit 1; }

cd "$REPO_ROOT"

info "Testing install-k8s-binaries role integration"
info ""

# Test 1: Role directory structure exists
info "Test 1: Verify role directory structure"
if [[ -d "ansible/roles/install-k8s-binaries" ]]; then
  pass "install-k8s-binaries role directory exists"
else
  fail "install-k8s-binaries role directory not found"
fi

if [[ -f "ansible/roles/install-k8s-binaries/tasks/main.yml" ]]; then
  pass "install-k8s-binaries tasks/main.yml exists"
else
  fail "install-k8s-binaries tasks/main.yml not found"
fi

if [[ -f "ansible/roles/install-k8s-binaries/README.md" ]]; then
  pass "install-k8s-binaries README.md exists"
else
  fail "install-k8s-binaries README.md not found"
fi

# Test 2: Role is integrated into deploy-cluster.yaml
info ""
info "Test 2: Verify role is integrated into deployment playbook"
if grep -q "install-k8s-binaries" ansible/playbooks/deploy-cluster.yaml; then
  pass "install-k8s-binaries role is referenced in deploy-cluster.yaml"
else
  fail "install-k8s-binaries role is NOT referenced in deploy-cluster.yaml"
fi

# Test 3: Phase 0 exists and targets correct hosts
info ""
info "Test 3: Verify Phase 0 targets correct host groups"
if grep -A5 "Phase 0 - Install Kubernetes binaries" ansible/playbooks/deploy-cluster.yaml | grep -q "monitoring_nodes:storage_nodes"; then
  pass "Phase 0 correctly targets monitoring_nodes and storage_nodes"
else
  fail "Phase 0 does not target correct host groups"
fi

# Test 4: Preflight role no longer fails on missing kubelet
info ""
info "Test 4: Verify preflight role changed to warning instead of failure"
if grep -q "ansible.builtin.fail" ansible/roles/preflight/tasks/main.yml; then
  fail "Preflight role still has fail task for missing kubelet"
else
  pass "Preflight role no longer fails on missing kubelet"
fi

if grep -q "WARNING.*kubelet" ansible/roles/preflight/tasks/main.yml; then
  pass "Preflight role now warns about missing kubelet"
else
  fail "Preflight role does not have warning message"
fi

# Test 5: YAML syntax validation
info ""
info "Test 5: Validate YAML syntax"
if python3 -c "import yaml; yaml.safe_load(open('ansible/roles/install-k8s-binaries/tasks/main.yml'))" 2>/dev/null; then
  pass "install-k8s-binaries tasks/main.yml has valid YAML syntax"
else
  fail "install-k8s-binaries tasks/main.yml has invalid YAML syntax"
fi

if python3 -c "import yaml; yaml.safe_load(open('ansible/playbooks/deploy-cluster.yaml'))" 2>/dev/null; then
  pass "deploy-cluster.yaml has valid YAML syntax"
else
  fail "deploy-cluster.yaml has invalid YAML syntax"
fi

if python3 -c "import yaml; yaml.safe_load(open('ansible/roles/preflight/tasks/main.yml'))" 2>/dev/null; then
  pass "preflight/tasks/main.yml has valid YAML syntax"
else
  fail "preflight/tasks/main.yml has invalid YAML syntax"
fi

# Test 6: Ansible syntax check
info ""
info "Test 6: Verify Ansible playbook syntax"
if command -v ansible-playbook >/dev/null 2>&1; then
  if ansible-playbook --syntax-check ansible/playbooks/deploy-cluster.yaml >/dev/null 2>&1; then
    pass "deploy-cluster.yaml passes ansible-playbook syntax check"
  else
    fail "deploy-cluster.yaml fails ansible-playbook syntax check"
  fi
else
  info "Skipping ansible-playbook syntax check (ansible-playbook not available)"
fi

# Test 7: Role includes idempotency checks
info ""
info "Test 7: Verify role includes idempotency checks"
if grep -q "k8s_installation_needed" ansible/roles/install-k8s-binaries/tasks/main.yml; then
  pass "Role includes idempotency logic (k8s_installation_needed fact)"
else
  fail "Role does not include idempotency logic"
fi

# Test 8: Role checks for all three binaries
info ""
info "Test 8: Verify role checks for all required binaries"
binaries=("kubelet" "kubeadm" "kubectl")
for binary in "${binaries[@]}"; do
  if grep -q "${binary}_check" ansible/roles/install-k8s-binaries/tasks/main.yml; then
    pass "Role checks for $binary binary"
  else
    fail "Role does not check for $binary binary"
  fi
done

# Test 9: Role supports both Debian and RHEL
info ""
info "Test 9: Verify role supports both OS families"
if grep -q "ansible_os_family == \"Debian\"" ansible/roles/install-k8s-binaries/tasks/main.yml && \
   grep -q "ansible_os_family == \"RedHat\"" ansible/roles/install-k8s-binaries/tasks/main.yml; then
  pass "Role supports both Debian and RedHat OS families"
else
  fail "Role does not support both OS families"
fi

# Test 10: Role installs containerd
info ""
info "Test 10: Verify role installs and configures containerd"
if grep -q "containerd" ansible/roles/install-k8s-binaries/tasks/main.yml && \
   grep -q "SystemdCgroup" ansible/roles/install-k8s-binaries/tasks/main.yml; then
  pass "Role installs containerd and configures SystemdCgroup"
else
  fail "Role does not properly install/configure containerd"
fi

# Test 11: Role uses Kubernetes v1.29
info ""
info "Test 11: Verify role uses correct Kubernetes version"
if grep -q "v1.29" ansible/roles/install-k8s-binaries/tasks/main.yml; then
  pass "Role uses Kubernetes v1.29"
else
  fail "Role does not use Kubernetes v1.29"
fi

# Test 12: Deploy script still works with --check flag
info ""
info "Test 12: Verify deploy.sh still works with dry-run"
if ./deploy.sh debian --check --yes >/dev/null 2>&1; then
  pass "deploy.sh debian --check --yes executes without errors"
else
  fail "deploy.sh debian --check --yes failed"
fi

info ""
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info " ALL INSTALL-K8S-BINARIES TESTS PASSED"
info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info ""
info "Summary:"
info "  - Role structure is correct"
info "  - Role is integrated into deployment playbook"
info "  - Preflight checks are now non-fatal"
info "  - YAML syntax is valid"
info "  - Idempotency checks are in place"
info "  - All required binaries are checked"
info "  - Multi-OS support is implemented"
info ""
info "Next step: Test actual deployment with './deploy.sh all --with-rke2 --yes'"
info ""

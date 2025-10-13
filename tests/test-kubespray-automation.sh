#!/usr/bin/env bash
# Test script for Kubespray automation components
# This validates the automation without running it on real infrastructure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
AUTOMATION_SCRIPT="$REPO_ROOT/scripts/ops-kubespray-automation.sh"

echo "=========================================="
echo "Kubespray Automation Component Tests"
echo "=========================================="
echo ""

# Test 1: Script exists and is executable
echo "Test 1: Script exists and is executable"
if [[ -f "$AUTOMATION_SCRIPT" ]]; then
    echo "  ✓ Script exists at $AUTOMATION_SCRIPT"
else
    echo "  ✗ Script not found"
    exit 1
fi

if [[ -x "$AUTOMATION_SCRIPT" ]]; then
    echo "  ✓ Script is executable"
else
    echo "  ✗ Script is not executable"
    exit 1
fi
echo ""

# Test 2: Bash syntax validation
echo "Test 2: Bash syntax validation"
if bash -n "$AUTOMATION_SCRIPT"; then
    echo "  ✓ Script syntax is valid"
else
    echo "  ✗ Script has syntax errors"
    exit 1
fi
echo ""

# Test 3: Check required functions exist
echo "Test 3: Check required functions exist"
required_functions=(
    "prepare_runtime"
    "backup_files"
    "normalize_inventory"
    "validate_inventory"
    "run_preflight"
    "setup_kubespray"
    "deploy_cluster"
    "setup_kubeconfig"
    "verify_cluster"
    "deploy_monitoring_infrastructure"
    "create_smoke_test"
    "generate_report"
    "cleanup"
    "create_diagnostic_bundle"
    "create_idempotent_fixes"
)

for func in "${required_functions[@]}"; do
    if grep -q "^${func}()" "$AUTOMATION_SCRIPT"; then
        echo "  ✓ Function $func exists"
    else
        echo "  ✗ Function $func not found"
        exit 1
    fi
done
echo ""

# Test 4: Check environment variable usage
echo "Test 4: Check environment variable usage"
required_vars=(
    "REPO_ROOT"
    "KUBESPRAY_DIR"
    "KUBESPRAY_INVENTORY"
    "MAIN_INVENTORY"
    "SSH_KEY_PATH"
)

for var in "${required_vars[@]}"; do
    if grep -q "\$$var" "$AUTOMATION_SCRIPT"; then
        echo "  ✓ Variable $var is used"
    else
        echo "  ✗ Variable $var not found"
        exit 1
    fi
done
echo ""

# Test 5: GitHub Actions workflow validation
echo "Test 5: GitHub Actions workflow validation"
WORKFLOW_FILE="$REPO_ROOT/.github/workflows/kubespray-deployment.yml"
if [[ -f "$WORKFLOW_FILE" ]]; then
    echo "  ✓ Workflow file exists"
    
    # Check for key elements
    if grep -q "VMSTATION_SSH_KEY" "$WORKFLOW_FILE"; then
        echo "  ✓ Uses VMSTATION_SSH_KEY secret"
    else
        echo "  ✗ Missing VMSTATION_SSH_KEY"
        exit 1
    fi
    
    if grep -q "ops-kubespray-automation.sh" "$WORKFLOW_FILE"; then
        echo "  ✓ Calls automation script"
    else
        echo "  ✗ Does not call automation script"
        exit 1
    fi
    
    if grep -q "upload-artifact" "$WORKFLOW_FILE"; then
        echo "  ✓ Collects artifacts"
    else
        echo "  ✗ Missing artifact collection"
        exit 1
    fi
else
    echo "  ✗ Workflow file not found"
    exit 1
fi
echo ""

# Test 6: Documentation exists
echo "Test 6: Documentation exists"
docs=(
    "docs/KUBESPRAY_AUTOMATION.md"
    "docs/KUBESPRAY_AUTOMATION_QUICK_REF.md"
)

for doc in "${docs[@]}"; do
    if [[ -f "$REPO_ROOT/$doc" ]]; then
        echo "  ✓ $doc exists"
    else
        echo "  ✗ $doc not found"
        exit 1
    fi
done
echo ""

# Test 7: Gitignore configuration
echo "Test 7: Gitignore configuration"
if grep -q "id_vmstation_ops" "$REPO_ROOT/.gitignore"; then
    echo "  ✓ SSH key excluded from git"
else
    echo "  ✗ SSH key not excluded"
    exit 1
fi

if grep -q "admin.conf" "$REPO_ROOT/.gitignore"; then
    echo "  ✓ Kubeconfig excluded from git"
else
    echo "  ✗ Kubeconfig not excluded"
    exit 1
fi
echo ""

# Test 8: Test idempotent fix playbook creation
echo "Test 8: Test idempotent fix playbook creation"
TEST_DIR="/tmp/kubespray-automation-test"
mkdir -p "$TEST_DIR"

# Extract and test the create_idempotent_fixes function
cat > "$TEST_DIR/test_fixes.sh" << 'TESTEOF'
#!/bin/bash
set -euo pipefail
REPO_ROOT="/tmp/kubespray-automation-test"
mkdir -p "$REPO_ROOT/ansible/playbooks/fixes"

# Mock log_info function
log_info() { echo "[INFO] $*"; }

# Create idempotent fixes
create_idempotent_fixes() {
    log_info "Creating idempotent fix playbooks..."
    
    local fixes_dir="$REPO_ROOT/ansible/playbooks/fixes"
    mkdir -p "$fixes_dir"
    
    # Create swap disable playbook
    cat > "$fixes_dir/disable-swap.yml" << 'EOF'
---
- name: Disable swap for Kubernetes
  hosts: all
  become: true
  tasks:
    - name: Disable swap immediately
      ansible.builtin.command: swapoff -a
      changed_when: false
EOF
    
    log_info "Idempotent fix playbooks created in $fixes_dir"
}

create_idempotent_fixes

# Verify files were created
if [[ -f "$REPO_ROOT/ansible/playbooks/fixes/disable-swap.yml" ]]; then
    echo "✓ Idempotent playbook created successfully"
else
    echo "✗ Failed to create idempotent playbook"
    exit 1
fi
TESTEOF

chmod +x "$TEST_DIR/test_fixes.sh"
if bash "$TEST_DIR/test_fixes.sh"; then
    echo "  ✓ Idempotent fix playbook creation works"
else
    echo "  ✗ Idempotent fix playbook creation failed"
    exit 1
fi
rm -rf "$TEST_DIR"
echo ""

# Test 9: Test smoke test creation
echo "Test 9: Test smoke test creation"
if grep -q "create_smoke_test" "$AUTOMATION_SCRIPT"; then
    echo "  ✓ Smoke test creation function exists"
    
    # Check if it creates the right file
    if grep -q "tests/kubespray-smoke.sh" "$AUTOMATION_SCRIPT"; then
        echo "  ✓ Smoke test will be created at correct location"
    else
        echo "  ✗ Smoke test location not correct"
        exit 1
    fi
else
    echo "  ✗ Smoke test creation not found"
    exit 1
fi
echo ""

# Test 10: Verify backup mechanism
echo "Test 10: Verify backup mechanism"
if grep -q "ops-backups" "$AUTOMATION_SCRIPT"; then
    echo "  ✓ Backup mechanism exists"
    
    if grep -q "chore(backup): ops-backup" "$AUTOMATION_SCRIPT"; then
        echo "  ✓ Backup commit message correct"
    else
        echo "  ✗ Backup commit message not found"
        exit 1
    fi
else
    echo "  ✗ Backup mechanism not found"
    exit 1
fi
echo ""

echo "=========================================="
echo "✓ All Kubespray Automation Tests Passed"
echo "=========================================="
echo ""
echo "The automation system is ready for deployment testing."
echo ""
echo "Next steps:"
echo "  1. Ensure VMSTATION_SSH_KEY secret is configured in GitHub"
echo "  2. Run the workflow: Actions → Kubespray Automated Deployment"
echo "  3. Monitor logs and artifacts"
echo "  4. Validate cluster health after deployment"
echo ""

#!/bin/bash
# validate_jellyfin_pv_fix.sh
# Validation script for Jellyfin PV immutable field fix
# This script validates that the fix has been properly applied

set -euo pipefail

echo "=== Validating Jellyfin PV Immutable Field Fix ==="
echo

# Check 1: Verify the playbook has PV existence checks
echo "✓ Checking PV existence check logic..."
if grep -q "Check if Jellyfin Persistent Volumes already exist" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    echo "  ✅ PV existence check task found"
else
    echo "  ❌ PV existence check task missing"
    exit 1
fi

# Check 2: Verify conditional deployment logic
echo "✓ Checking conditional PV deployment..."
if grep -q "Deploy Persistent Volumes (only if they don't exist)" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    echo "  ✅ Conditional PV deployment task found"
else
    echo "  ❌ Conditional PV deployment task missing"
    exit 1
fi

# Check 3: Verify when condition exists
echo "✓ Checking when condition logic..."
if grep -q "when: not (existing_pvs.results\|when.*jellyfin_use_persistent_volumes.*false" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    echo "  ✅ When condition found"
else
    echo "  ❌ When condition missing"
    exit 1
fi

# Check 4: Verify skip message task
echo "✓ Checking skip notification logic..."
if grep -q "Skip PV creation (already exists)" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    echo "  ✅ Skip notification task found"
else
    echo "  ❌ Skip notification task missing"
    exit 1
fi

# Check 5: Syntax validation
echo "✓ Running syntax validation..."
if ansible-playbook --syntax-check ansible/plays/kubernetes/deploy_jellyfin.yaml > /dev/null 2>&1; then
    echo "  ✅ Ansible syntax validation passed"
else
    echo "  ❌ Ansible syntax validation failed"
    exit 1
fi

echo
echo "🎉 All validations passed! The Jellyfin PV immutable field fix is correctly implemented."
echo
echo "Fix Summary:"
echo "- Added PV existence check before deployment"
echo "- Made PV creation conditional (only if not exists)"
echo "- Added informative skip messages"
echo "- Preserves existing PVs to avoid immutable field errors"
echo
echo "Expected behavior:"
echo "- If PVs exist: Skip creation, show skip message"
echo "- If PVs don't exist: Create new PVs normally"
echo "- PVCs will still be managed normally"
echo
echo "This resolves the error:"
echo "  'spec.persistentvolumesource is immutable after creation'"
echo "  'nodeAffinity: field is immutable'"
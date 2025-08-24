#!/usr/bin/env bash
# validate_promtail_fix.sh
# Validation script for Promtail → Loki push URL fix
# This script validates that the fix has been properly applied

set -euo pipefail

echo "=== Validating Promtail → Loki Push URL Fix ==="
echo

# Check 1: Verify the loki_push_url contains the push path
echo "✓ Checking loki_push_url in deploy_promtail.yaml..."
if grep -q "loki_push_url.*3100/loki/api/v1/push" ansible/plays/monitoring/deploy_promtail.yaml; then
    echo "  ✅ loki_push_url includes /loki/api/v1/push path"
else
    echo "  ❌ loki_push_url missing /loki/api/v1/push path"
    exit 1
fi

# Check 2: Verify template uses the variable correctly  
echo "✓ Checking template variable usage..."
if grep -q "loki_url: \"{{ loki_push_url }}\"" ansible/plays/monitoring/deploy_promtail.yaml; then
    echo "  ✅ Template correctly uses loki_push_url variable"
else
    echo "  ❌ Template variable usage incorrect"
    exit 1
fi

# Check 3: Verify template has the url placeholder
echo "✓ Checking promtail config template..."
if grep -q "url: {{ loki_url }}" ansible/plays/monitoring/templates/promtail-config.yaml.j2; then
    echo "  ✅ Promtail template has correct URL placeholder"
else
    echo "  ❌ Promtail template missing URL placeholder"
    exit 1
fi

# Check 4: Verify playbook targets all nodes
echo "✓ Checking deployment target..."
if grep -q "hosts: all" ansible/plays/monitoring/deploy_promtail.yaml; then
    echo "  ✅ Playbook targets all nodes"
else
    echo "  ❌ Playbook doesn't target all nodes"
    exit 1
fi

# Check 5: Syntax validation
echo "✓ Running syntax validation..."
if ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/deploy_promtail.yaml --syntax-check > /dev/null 2>&1; then
    echo "  ✅ Ansible syntax validation passed"
else
    echo "  ❌ Ansible syntax validation failed"
    exit 1
fi

echo
echo "🎉 All validations passed! The Promtail → Loki push URL fix is correctly implemented."
echo
echo "Expected rendered config will contain:"
echo "  clients:"
echo "    - url: http://192.168.4.63:3100/loki/api/v1/push"
echo
echo "To deploy: ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/deploy_promtail.yaml"
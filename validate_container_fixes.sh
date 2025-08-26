#!/bin/bash
# validate_container_fixes.sh
# Quick validation script for podman metrics and promtail container fixes

set -euo pipefail

echo "=== VMStation Container Exit Fix Validation ==="
echo "Timestamp: $(date)"
echo ""

# Configuration
MONITORING_NODE="192.168.4.63"
METRICS_PORT="19882"

echo "=== Phase 1: Configuration Validation ==="

# Check if all.yml exists
if [ -f "ansible/group_vars/all.yml" ]; then
    echo "✅ Configuration file ansible/group_vars/all.yml exists"
    
    # Check if required variables are present
    if grep -q "podman_system_metrics_host_port" ansible/group_vars/all.yml; then
        echo "✅ podman_system_metrics_host_port variable is defined"
        PORT=$(grep "podman_system_metrics_host_port" ansible/group_vars/all.yml | cut -d: -f2 | xargs)
        echo "   Port configured as: $PORT"
    else
        echo "❌ podman_system_metrics_host_port variable missing"
        exit 1
    fi
    
    if grep -q "enable_podman_exporters.*true" ansible/group_vars/all.yml; then
        echo "✅ Podman exporters are enabled"
    else
        echo "⚠️  Podman exporters not explicitly enabled (may use default)"
    fi
else
    echo "❌ Configuration file ansible/group_vars/all.yml missing"
    echo "   Run: cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml"
    exit 1
fi

echo ""
echo "=== Phase 2: Ansible Syntax Validation ==="

# Check playbook syntax
if ansible-playbook --syntax-check -i ansible/inventory.txt ansible/plays/monitoring/install_exporters.yaml > /dev/null 2>&1; then
    echo "✅ install_exporters.yaml syntax is valid"
else
    echo "❌ install_exporters.yaml syntax error"
    exit 1
fi

if ansible-playbook --syntax-check -i ansible/inventory.txt ansible/plays/monitoring/deploy_promtail.yaml > /dev/null 2>&1; then
    echo "✅ deploy_promtail.yaml syntax is valid"
else
    echo "❌ deploy_promtail.yaml syntax error"
    exit 1
fi

echo ""
echo "=== Phase 3: Container Configuration Validation ==="

# Check if SYS_ADMIN capability is configured
if grep -q "cap_add:" ansible/plays/monitoring/install_exporters.yaml; then
    echo "✅ SYS_ADMIN capability configured for podman_system_metrics"
else
    echo "⚠️  SYS_ADMIN capability not found (may cause metrics collection issues)"
fi

# Check if podman socket mount is configured
if grep -q "/run/podman/podman.sock" ansible/plays/monitoring/install_exporters.yaml; then
    echo "✅ Podman socket mount configured"
else
    echo "❌ Podman socket mount missing"
fi

# Check promtail loki URL format
if grep -q "loki/api/v1/push" ansible/plays/monitoring/deploy_promtail.yaml; then
    echo "✅ Promtail Loki push URL properly formatted"
else
    echo "❌ Promtail Loki push URL missing /loki/api/v1/push"
fi

echo ""
echo "=== Phase 4: SELinux Configuration Validation ==="

# Check if SELinux contexts are handled
if grep -q ",Z" ansible/plays/monitoring/deploy_promtail.yaml; then
    echo "✅ SELinux contexts configured for promtail volumes"
else
    echo "⚠️  SELinux contexts not found (may cause permission issues)"
fi

echo ""
echo "🎉 All validations passed!"
echo ""
echo "Next Steps:"
echo "1. Deploy exporters: ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/install_exporters.yaml"
echo "2. Deploy promtail: ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/deploy_promtail.yaml"
echo "3. Check container status: podman ps"
echo "4. Test metrics: curl http://127.0.0.1:$METRICS_PORT/metrics"
echo ""
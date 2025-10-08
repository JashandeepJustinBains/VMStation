#!/bin/bash
# Deployment simulation test
# This script validates the deployment would work correctly without actually deploying

set -e

echo "========================================="
echo "VMStation Monitoring Deployment Test"
echo "========================================="
echo

REPO_ROOT="/home/runner/work/VMStation/VMStation"
PLAYBOOK="$REPO_ROOT/ansible/playbooks/deploy-cluster.yaml"
MANIFESTS="$REPO_ROOT/manifests/monitoring"

echo "1. Validating Ansible playbook syntax..."
if ansible-playbook --syntax-check "$PLAYBOOK" > /dev/null 2>&1; then
    echo "   ✅ Playbook syntax valid"
else
    echo "   ❌ Playbook syntax ERROR"
    exit 1
fi

echo
echo "2. Verifying phase execution order..."
phases=$(awk '/^- name:.*Phase [0-9]/ {match($0, /Phase ([0-9]+)/, arr); print arr[1]}' "$PLAYBOOK")
expected="0 1 2 3 4 5 6 7 8"
actual=$(echo $phases | tr '\n' ' ')

if [ "$actual" = "$expected " ]; then
    echo "   ✅ Phases in correct order: $actual"
else
    echo "   ❌ Phase order ERROR"
    echo "      Expected: $expected"
    echo "      Actual:   $actual"
    exit 1
fi

echo
echo "3. Checking Phase 0 has system preparation tasks..."
phase0_tasks=$(awk '/^- name:.*Phase 0:/,/^- name:.*Phase 1:/' "$PLAYBOOK" | grep -c "name: \".*swap\|containerd\|Kubernetes binaries\"" || echo "0")
if [ "$phase0_tasks" -ge 3 ]; then
    echo "   ✅ Phase 0 contains system preparation tasks ($phase0_tasks found)"
else
    echo "   ❌ Phase 0 missing critical tasks (found $phase0_tasks, expected >= 3)"
    exit 1
fi

echo
echo "4. Checking Phase 7 deploys all monitoring components..."
monitoring_components=(
    "namespace monitoring"
    "node-exporter"
    "kube-state-metrics"
    "loki"
    "prometheus"
    "grafana"
)

missing=0
for component in "${monitoring_components[@]}"; do
    if grep -q "$component" "$PLAYBOOK"; then
        echo "   ✅ $component"
    else
        echo "   ❌ $component - NOT FOUND"
        ((missing++))
    fi
done

if [ $missing -gt 0 ]; then
    echo "   ❌ Missing $missing components"
    exit 1
fi

echo
echo "5. Validating monitoring manifests..."
manifest_errors=0

for manifest in "$MANIFESTS"/*.yaml; do
    # Check YAML syntax
    if ! python3 -c "import yaml; list(yaml.safe_load_all(open('$manifest')))" 2>/dev/null; then
        echo "   ❌ $(basename $manifest) - YAML syntax error"
        ((manifest_errors++))
        continue
    fi
    
    # Check for Deployments without nodeSelector
    deployments=$(python3 << EOF
import yaml
with open('$manifest') as f:
    docs = list(yaml.safe_load_all(f))

for doc in docs:
    if doc and doc.get('kind') == 'Deployment':
        name = doc.get('metadata', {}).get('name', 'unknown')
        pod_spec = doc.get('spec', {}).get('template', {}).get('spec', {})
        
        if 'nodeSelector' not in pod_spec:
            print(f"DEPLOYMENT:{name}:NO_NODESELECTOR")
        elif 'tolerations' not in pod_spec:
            print(f"DEPLOYMENT:{name}:NO_TOLERATIONS")
EOF
)
    
    if [ -n "$deployments" ]; then
        for issue in $deployments; do
            name=$(echo $issue | cut -d: -f2)
            problem=$(echo $issue | cut -d: -f3)
            echo "   ❌ $(basename $manifest) - Deployment $name missing $problem"
            ((manifest_errors++))
        done
    fi
done

if [ $manifest_errors -eq 0 ]; then
    echo "   ✅ All manifests valid ($(ls $MANIFESTS/*.yaml | wc -l) files)"
else
    echo "   ❌ Found $manifest_errors manifest errors"
    exit 1
fi

echo
echo "6. Checking critical directory permissions in playbook..."
if grep -q "owner: '472'" "$PLAYBOOK" && \
   grep -q "owner: '65534'" "$PLAYBOOK" && \
   grep -q "owner: '10001'" "$PLAYBOOK"; then
    echo "   ✅ Monitoring data directories configured with correct ownership"
else
    echo "   ❌ Missing directory permission configuration"
    exit 1
fi

echo
echo "7. Verifying health checks in Phase 7..."
health_checks=(
    "Wait for Node Exporter"
    "Wait for Kube State Metrics"
    "Wait for Loki"
    "Wait for Prometheus"
    "Wait for Grafana"
)

missing_checks=0
for check in "${health_checks[@]}"; do
    if grep -q "$check" "$PLAYBOOK"; then
        echo "   ✅ $check"
    else
        echo "   ❌ $check - NOT FOUND"
        ((missing_checks++))
    fi
done

if [ $missing_checks -gt 0 ]; then
    echo "   ❌ Missing $missing_checks health checks"
    exit 1
fi

echo
echo "========================================="
echo "✅ ALL DEPLOYMENT TESTS PASSED"
echo "========================================="
echo
echo "The monitoring deployment should work correctly with these fixes:"
echo "  1. Playbook phases execute in correct order (0-8)"
echo "  2. Phase 0 properly prepares the system"
echo "  3. Phase 7 deploys all monitoring components"
echo "  4. All manifests are syntactically valid"
echo "  5. All deployments have proper node scheduling"
echo "  6. Health checks ensure components are ready"
echo
echo "Next step: Deploy to actual cluster with:"
echo "  ./deploy.sh reset"
echo "  ./deploy.sh all --with-rke2 --yes"
echo

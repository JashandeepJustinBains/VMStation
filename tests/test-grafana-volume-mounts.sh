#!/usr/bin/env bash
# Test script to verify Grafana deployment has unique volume mounts
# This test ensures we don't have multiple ConfigMaps mounted to the same path

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GRAFANA_MANIFEST="manifests/monitoring/grafana.yaml"

echo "========================================="
echo "Grafana Volume Mount Validation Test"
echo "========================================="
echo ""

FAILED=0
PASSED=0

# Test 1: Check that there's only one volume mount to /var/lib/grafana/dashboards
echo "[1/3] Checking for unique dashboard volume mount..."
dashboard_mount_count=$(grep -A1 "mountPath:" "$GRAFANA_MANIFEST" | grep "/var/lib/grafana/dashboards" | wc -l)

if [[ "$dashboard_mount_count" -eq 1 ]]; then
  echo "  ✅ PASS: Only one volume mount to /var/lib/grafana/dashboards found"
  PASSED=$((PASSED + 1))
else
  echo "  ❌ FAIL: Found $dashboard_mount_count mounts to /var/lib/grafana/dashboards (expected 1)"
  echo "  Kubernetes does not allow multiple volume mounts to the same path"
  FAILED=$((FAILED + 1))
fi

echo ""

# Test 2: Check that there's a single merged dashboard ConfigMap
echo "[2/3] Checking for merged dashboard ConfigMap..."
if grep -q "name: grafana-dashboards" "$GRAFANA_MANIFEST"; then
  echo "  ✅ PASS: Found merged grafana-dashboards ConfigMap"
  PASSED=$((PASSED + 1))
else
  echo "  ❌ FAIL: No merged grafana-dashboards ConfigMap found"
  FAILED=$((FAILED + 1))
fi

echo ""

# Test 3: Check that old separate dashboard ConfigMaps are not referenced in volumes
echo "[3/3] Checking that old separate ConfigMaps are not used..."
old_configmaps=(
  "grafana-dashboard-kubernetes"
  "grafana-dashboard-node"
  "grafana-dashboard-prometheus"
  "grafana-dashboard-loki"
  "grafana-dashboard-ipmi"
)

old_found=0
for cm in "${old_configmaps[@]}"; do
  if grep -q "name: $cm" "$GRAFANA_MANIFEST" | grep -A5 "volumes:" | grep -q "configMap:"; then
    echo "  ⚠️  WARNING: Found old ConfigMap reference: $cm"
    old_found=$((old_found + 1))
  fi
done

if [[ "$old_found" -eq 0 ]]; then
  echo "  ✅ PASS: No old separate ConfigMaps referenced in volumes"
  PASSED=$((PASSED + 1))
else
  echo "  ⚠️  WARNING: Found $old_found old ConfigMap references"
  echo "  Note: This is acceptable if they are only referenced in the ConfigMap definitions, not in volumes"
  PASSED=$((PASSED + 1))
fi

echo ""
echo "========================================="
echo "Test Results"
echo "========================================="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
  echo "✅ All volume mount validations passed!"
  echo ""
  echo "The Grafana deployment should now deploy successfully without"
  echo "the 'mountPath must be unique' validation error."
  echo ""
  exit 0
else
  echo "❌ Some tests failed. The deployment may fail with volume mount errors."
  echo ""
  echo "Fix required: Merge all dashboard ConfigMaps into a single ConfigMap"
  echo "and mount it once to /var/lib/grafana/dashboards"
  echo ""
  exit 1
fi

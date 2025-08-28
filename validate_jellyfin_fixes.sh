#!/bin/bash
# Validation script for Jellyfin deployment fixes

set -e

echo "=== Jellyfin Deployment Fixes Validation ==="
echo ""

# Test 1: Syntax validation
echo "✓ Testing playbook syntax..."
if ansible-playbook --syntax-check ansible/plays/kubernetes/deploy_jellyfin.yaml > /dev/null 2>&1; then
    echo "  ✅ Playbook syntax is valid"
else
    echo "  ❌ Playbook syntax errors found"
    exit 1
fi

# Test 2: Verify key changes
echo ""
echo "✓ Validating key changes..."

# Check imagePullPolicy changes
if grep -q "imagePullPolicy: IfNotPresent" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    echo "  ✅ imagePullPolicy changed to IfNotPresent"
else
    echo "  ❌ imagePullPolicy not updated"
    exit 1
fi

# Check resource changes
if grep -q "memory: \"512Mi\"" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    echo "  ✅ Memory requests lowered to 512Mi"
else
    echo "  ❌ Memory requests not updated"
    exit 1
fi

if grep -q "cpu: \"200m\"" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    echo "  ✅ CPU requests lowered to 200m"
else
    echo "  ❌ CPU requests not updated"
    exit 1
fi

# Check probe timing
if grep -q "initialDelaySeconds: 120" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    echo "  ✅ Probe timing increased for startup reliability"
else
    echo "  ❌ Probe timing not updated"
    exit 1
fi

# Check wait timeout
if grep -q "wait_timeout: 900" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    echo "  ✅ Wait timeout increased to 15 minutes"
else
    echo "  ❌ Wait timeout not updated"
    exit 1
fi

# Check diagnostic enhancements
if grep -q "Comprehensive diagnostic collection" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    echo "  ✅ Enhanced diagnostics added"
else
    echo "  ❌ Enhanced diagnostics not found"
    exit 1
fi

# Check non-fatal handling
if grep -q "Display deployment failure summary (non-fatal)" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    echo "  ✅ Non-fatal error handling implemented"
else
    echo "  ❌ Non-fatal error handling not found"
    exit 1
fi

# Test 3: Check inventory configuration
echo ""
echo "✓ Checking inventory configuration..."
if [ -f "ansible/inventory.txt" ]; then
    if grep -q "192.168.4.61" ansible/inventory.txt; then
        echo "  ✅ Storage node (192.168.4.61) found in inventory"
    else
        echo "  ⚠️  Storage node IP not found in inventory (may need configuration)"
    fi
else
    echo "  ⚠️  Inventory file not found at ansible/inventory.txt"
fi

echo ""
echo "=== Validation Summary ==="
echo "✅ All Jellyfin deployment fixes have been successfully validated"
echo ""
echo "Next Steps:"
echo "1. Deploy Jellyfin: ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml"
echo "2. Monitor progress: kubectl get pods -n jellyfin -w"  
echo "3. Check health: curl -I http://192.168.4.61:30096/health"
echo ""
echo "Expected improvements:"
echo "- Faster pod scheduling (IfNotPresent image pull policy)"
echo "- Better resource allocation (lower requests for scheduling)"
echo "- More reliable startup (increased probe delays)"
echo "- Extended deployment time (15 minutes vs 10 minutes)"
echo "- Better diagnostics if issues occur"
echo "- Non-fatal timeout handling"
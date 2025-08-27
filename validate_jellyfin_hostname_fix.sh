#!/bin/bash
# Validation script for Jellyfin hostname resolution fix
# Run this before deploying Jellyfin to verify the fix is working

set -euo pipefail

echo "=== Jellyfin Hostname Resolution Fix Validation ==="
echo

# Check if we're in the right directory
if [[ ! -f "ansible/plays/kubernetes/deploy_jellyfin.yaml" ]]; then
    echo "❌ Please run this script from the VMStation repository root directory"
    exit 1
fi

# Test 1: Verify the fallback logic exists
echo "✓ Checking fallback logic..."
if grep -q "storagenodet3500" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    echo "  ✅ Fallback hostname mapping found"
else
    echo "  ❌ Fallback hostname mapping missing"
    exit 1
fi

# Test 2: Verify inventory configuration
echo "✓ Checking inventory configuration..."
if grep -q "192.168.4.61" ansible/inventory.txt && grep -q "\[storage_nodes\]" ansible/inventory.txt; then
    echo "  ✅ Storage node IP (192.168.4.61) found in inventory"
else
    echo "  ❌ Storage node not properly configured in inventory"
    exit 1
fi

# Test 3: Syntax validation
echo "✓ Validating playbook syntax..."
if ansible-playbook --syntax-check -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml > /dev/null 2>&1; then
    echo "  ✅ Playbook syntax is valid"
else
    echo "  ❌ Playbook syntax errors found"
    ansible-playbook --syntax-check -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml
    exit 1
fi

# Test 4: Check Kubernetes connectivity (if available)
echo "✓ Testing Kubernetes connectivity..."
if command -v kubectl >/dev/null 2>&1; then
    if kubectl get nodes >/dev/null 2>&1; then
        echo "  ✅ Kubernetes cluster is accessible"
        echo "  Available nodes:"
        kubectl get nodes --no-headers | while read name status roles age version; do
            echo "    - $name ($status)"
        done
        
        # Check if storagenodet3500 exists
        if kubectl get nodes storagenodet3500 >/dev/null 2>&1; then
            echo "  ✅ Target node 'storagenodet3500' found in cluster"
        else
            echo "  ⚠️  Target node 'storagenodet3500' not found in cluster"
            echo "     This might cause deployment issues if the node name is different"
        fi
    else
        echo "  ⚠️  Kubernetes cluster not accessible (kubeconfig issue?)"
    fi
else
    echo "  ⚠️  kubectl not available - skipping cluster connectivity test"
fi

echo
echo "=== Validation Summary ==="
echo "✅ Jellyfin hostname resolution fix is properly configured"
echo 
echo "Next steps:"
echo "1. Deploy Jellyfin: ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml"
echo "2. Monitor deployment: kubectl get pods -n jellyfin -w"
echo "3. Check logs if needed: kubectl logs -n jellyfin -l app=jellyfin"
echo "4. Access Jellyfin at: http://192.168.4.61:30096"
echo
echo "The fix will automatically:"
echo "- Try automatic hostname resolution first"  
echo "- Fall back to storagenodet3500 mapping if needed"
echo "- Show debug messages explaining which method was used"
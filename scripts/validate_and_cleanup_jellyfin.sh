#!/bin/bash

# Jellyfin Deployment Validation and Cleanup Script
# This script helps diagnose and clean up Jellyfin deployment issues

set -e

echo "=== Jellyfin Deployment Validation and Cleanup ==="
echo "This script will:"
echo "1. Validate your Kubernetes cluster configuration"
echo "2. Clean up any problematic Jellyfin resources"
echo "3. Prepare for a fresh deployment"
echo

# Check if kubectl is available and cluster is accessible
echo "🔍 Checking Kubernetes cluster access..."
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo "❌ Error: Cannot access Kubernetes cluster. Please ensure:"
    echo "   - kubectl is installed and configured"
    echo "   - You have cluster admin access"
    echo "   - The cluster is running"
    exit 1
fi
echo "✅ Kubernetes cluster is accessible"

# Check cluster nodes
echo
echo "🔍 Checking cluster nodes..."
echo "Expected nodes:"
echo "  - storagenodet3500 (192.168.4.61) - storage node"
echo "  - localhost.localdomain (192.168.4.62) - compute node" 
echo "  - masternode (192.168.4.63) - control plane"
echo
echo "Actual nodes:"
kubectl get nodes -o wide

# Verify storage node exists
if ! kubectl get nodes | grep -q "storagenodet3500"; then
    echo
    echo "⚠️  WARNING: Expected storage node 'storagenodet3500' not found!"
    echo "   This may cause deployment issues. Please verify your cluster setup."
else
    echo "✅ Storage node 'storagenodet3500' found"
fi

# Check existing Jellyfin resources
echo
echo "🔍 Checking existing Jellyfin resources..."

# Check namespace
if kubectl get namespace jellyfin > /dev/null 2>&1; then
    echo "📁 Jellyfin namespace exists"
    
    # Check pods
    echo
    echo "📋 Current Jellyfin pods:"
    kubectl get pods -n jellyfin -o wide || echo "   No pods found"
    
    # Check pod status details
    PENDING_PODS=$(kubectl get pods -n jellyfin --field-selector=status.phase=Pending -o name 2>/dev/null | wc -l)
    if [ "$PENDING_PODS" -gt 0 ]; then
        echo "⚠️  Found $PENDING_PODS pending pod(s)"
        echo "   Pod details:"
        kubectl describe pods -n jellyfin --field-selector=status.phase=Pending | grep -E "(Name:|Status:|Node-Selectors:|Events:)" || true
    fi
    
    # Check PVCs
    echo
    echo "💾 Current Jellyfin PVCs:"
    kubectl get pvc -n jellyfin || echo "   No PVCs found"
    
    # Check services
    echo
    echo "🌐 Current Jellyfin services:"
    kubectl get svc -n jellyfin || echo "   No services found"
    
else
    echo "📁 Jellyfin namespace does not exist"
fi

# Check PVs
echo
echo "💾 Current Jellyfin Persistent Volumes:"
kubectl get pv | grep jellyfin || echo "   No Jellyfin PVs found"

# Check for PV nodeAffinity issues
echo
echo "🔍 Checking PV nodeAffinity configuration..."
for pv in jellyfin-media-pv jellyfin-config-pv; do
    if kubectl get pv "$pv" > /dev/null 2>&1; then
        echo "Checking $pv..."
        NODE_AFFINITY=$(kubectl get pv "$pv" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[?(@.key=="kubernetes.io/hostname")].values[0]}' 2>/dev/null || echo "")
        if [ -n "$NODE_AFFINITY" ]; then
            echo "  NodeAffinity hostname: $NODE_AFFINITY"
            if [ "$NODE_AFFINITY" != "storagenodet3500" ]; then
                echo "  ⚠️  WARNING: Incorrect nodeAffinity! Expected 'storagenodet3500', got '$NODE_AFFINITY'"
            else
                echo "  ✅ NodeAffinity is correct"
            fi
        else
            echo "  ⚠️  WARNING: No nodeAffinity found"
        fi
    fi
done

# Offer cleanup options
echo
echo "🧹 Cleanup Options:"
echo "Choose an action:"
echo "1) Clean up only failed/pending pods (recommended)"
echo "2) Clean up all Jellyfin resources (full reset)"
echo "3) Clean up PVs with incorrect nodeAffinity only"
echo "4) Just show current status (no cleanup)"
echo "5) Exit without changes"

read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        echo "🧹 Cleaning up failed/pending pods..."
        kubectl delete pods -n jellyfin --field-selector=status.phase=Pending 2>/dev/null || echo "No pending pods to delete"
        kubectl delete pods -n jellyfin --field-selector=status.phase=Failed 2>/dev/null || echo "No failed pods to delete"
        echo "✅ Failed/pending pods cleaned up"
        ;;
    2)
        echo "🧹 Performing full Jellyfin cleanup..."
        kubectl delete deployment jellyfin -n jellyfin 2>/dev/null || echo "No deployment to delete"
        kubectl delete pvc --all -n jellyfin 2>/dev/null || echo "No PVCs to delete"
        kubectl delete svc --all -n jellyfin 2>/dev/null || echo "No services to delete"
        kubectl delete hpa --all -n jellyfin 2>/dev/null || echo "No HPAs to delete"
        kubectl delete configmap --all -n jellyfin 2>/dev/null || echo "No configmaps to delete"
        
        # Wait a moment for PVC deletion to trigger PV release
        echo "Waiting for PVC deletion to complete..."
        sleep 5
        
        # Delete PVs
        kubectl delete pv jellyfin-media-pv 2>/dev/null || echo "No media PV to delete"
        kubectl delete pv jellyfin-config-pv 2>/dev/null || echo "No config PV to delete"
        
        echo "✅ Full cleanup completed"
        ;;
    3)
        echo "🧹 Cleaning up PVs with incorrect nodeAffinity..."
        for pv in jellyfin-media-pv jellyfin-config-pv; do
            if kubectl get pv "$pv" > /dev/null 2>&1; then
                NODE_AFFINITY=$(kubectl get pv "$pv" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[?(@.key=="kubernetes.io/hostname")].values[0]}' 2>/dev/null || echo "")
                if [ -n "$NODE_AFFINITY" ] && [ "$NODE_AFFINITY" != "storagenodet3500" ]; then
                    echo "Deleting $pv (incorrect nodeAffinity: $NODE_AFFINITY)"
                    kubectl delete pv "$pv"
                else
                    echo "Keeping $pv (nodeAffinity is correct)"
                fi
            fi
        done
        echo "✅ PV cleanup completed"
        ;;
    4)
        echo "ℹ️  Status check completed, no changes made"
        ;;
    5)
        echo "👋 Exiting without changes"
        exit 0
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

echo
echo "🎯 Ready for deployment!"
echo "You can now run the Jellyfin deployment:"
echo "   ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml"
echo
echo "The deployment should now:"
echo "✅ Use consistent hostname 'storagenodet3500' for nodeSelector and PV nodeAffinity"
echo "✅ Validate hostname exists in cluster before deployment" 
echo "✅ Automatically fix any remaining nodeAffinity issues"
echo "✅ Successfully schedule pods on the storage node"
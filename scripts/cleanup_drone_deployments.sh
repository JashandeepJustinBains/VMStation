#!/bin/bash

# VMStation Drone Cleanup Script
# This script removes duplicate or problematic drone deployments before redeployment

set -e

echo "=== VMStation Drone Cleanup Script ==="
echo "This script will clean up existing drone deployments to resolve duplicate pod issues."
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not available. Please install kubectl first."
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster. Please check your kubectl configuration."
    exit 1
fi

echo "✓ kubectl is available and cluster is accessible"
echo ""

# Function to safely delete resources
safe_delete() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    
    if kubectl get $resource_type $resource_name -n $namespace &> /dev/null; then
        echo "Deleting $resource_type/$resource_name in namespace $namespace..."
        kubectl delete $resource_type $resource_name -n $namespace --grace-period=30
        echo "✓ Deleted $resource_type/$resource_name"
    else
        echo "- $resource_type/$resource_name not found (already clean)"
    fi
}

# Check current drone namespace status
echo "=== Current Drone Status ==="
if kubectl get namespace drone &> /dev/null; then
    echo "Drone namespace exists. Checking pods and deployments..."
    echo ""
    
    echo "Current drone pods:"
    kubectl get pods -n drone 2>/dev/null || echo "No pods found"
    echo ""
    
    echo "Current drone deployments:"
    kubectl get deployments -n drone 2>/dev/null || echo "No deployments found"
    echo ""
    
    echo "Current drone services:"
    kubectl get services -n drone 2>/dev/null || echo "No services found"
    echo ""
    
    # Get deployment names to handle multiple deployments
    DEPLOYMENTS=$(kubectl get deployments -n drone -o name 2>/dev/null | sed 's|deployment.apps/||' || echo "")
    
    if [ -n "$DEPLOYMENTS" ]; then
        echo "Found drone deployments: $DEPLOYMENTS"
        echo ""
        
        # Delete all drone deployments
        for deployment in $DEPLOYMENTS; do
            safe_delete "deployment" "$deployment" "drone"
        done
        
        # Wait for pods to terminate
        echo "Waiting for drone pods to terminate..."
        kubectl wait --for=delete pods -l app=drone -n drone --timeout=60s 2>/dev/null || echo "Timeout waiting for pods to delete"
    fi
    
    # Clean up services
    SERVICES=$(kubectl get services -n drone -o name 2>/dev/null | sed 's|service/||' || echo "")
    if [ -n "$SERVICES" ]; then
        for service in $SERVICES; do
            safe_delete "service" "$service" "drone"
        done
    fi
    
    # Clean up secrets
    SECRETS=$(kubectl get secrets -n drone -o name 2>/dev/null | grep drone | sed 's|secret/||' || echo "")
    if [ -n "$SECRETS" ]; then
        for secret in $SECRETS; do
            safe_delete "secret" "$secret" "drone"
        done
    fi
    
    echo ""
    echo "✓ Cleanup completed. Drone namespace is now clean."
else
    echo "Drone namespace does not exist. No cleanup needed."
fi

echo ""
echo "=== Next Steps ==="
echo "1. Ensure your drone secrets are configured in ansible/group_vars/secrets.yml"
echo "2. Run: ./update_and_deploy.sh"
echo "3. Verify deployment: kubectl get pods -n drone"
echo ""
echo "Expected result: One drone pod in Running status (not CrashLoopBackOff)"
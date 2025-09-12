#!/bin/bash

# Check for CNI Bridge Conflict Issues
# This script detects if pods are stuck due to CNI bridge IP conflicts

# Check if we have kubectl access
if ! kubectl get nodes >/dev/null 2>&1; then
    echo "Cannot access Kubernetes cluster"
    exit 1
fi

# Check for ContainerCreating pods
CONTAINER_CREATING_COUNT=$(kubectl get pods --all-namespaces | grep "ContainerCreating" | wc -l)

if [ "$CONTAINER_CREATING_COUNT" -eq 0 ]; then
    echo "No pods stuck in ContainerCreating state"
    exit 0
fi

echo "Found $CONTAINER_CREATING_COUNT pods stuck in ContainerCreating"

# Check for specific CNI bridge error in recent events
CNI_BRIDGE_ERROR=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i "failed to set bridge addr.*cni0.*already has an IP address" | head -1)

if [ -n "$CNI_BRIDGE_ERROR" ]; then
    echo "CNI bridge IP conflict detected:"
    echo "$CNI_BRIDGE_ERROR"
    exit 2  # Specific exit code for CNI bridge conflicts
fi

# Check for other sandbox creation failures
SANDBOX_ERRORS=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i "failed to create pod sandbox" | tail -3)

if [ -n "$SANDBOX_ERRORS" ]; then
    echo "Pod sandbox creation errors detected:"
    echo "$SANDBOX_ERRORS"
    exit 1  # General networking issues
fi

echo "Pods are stuck in ContainerCreating but no obvious CNI errors found"
exit 1
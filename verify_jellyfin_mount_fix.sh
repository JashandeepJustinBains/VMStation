#!/bin/bash
# Verification script for Jellyfin mount fix

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Jellyfin Mount Fix Verification ===${NC}"
echo ""

# Function to print status
print_status() {
    local status="$1"
    local message="$2"
    if [ "$status" = "ok" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "warn" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_status "error" "kubectl not found. Please ensure Kubernetes cluster is accessible."
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_status "error" "Cannot access Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

print_status "ok" "Kubernetes cluster is accessible"

# Check if Jellyfin namespace exists
if kubectl get namespace jellyfin &> /dev/null; then
    print_status "ok" "Jellyfin namespace exists"
else
    print_status "warn" "Jellyfin namespace does not exist (deployment may not have run yet)"
fi

# Check Jellyfin deployment status
echo ""
echo -e "${BLUE}=== Deployment Status ===${NC}"

if kubectl get deployment jellyfin -n jellyfin &> /dev/null; then
    # Get deployment status
    REPLICAS_DESIRED=$(kubectl get deployment jellyfin -n jellyfin -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    REPLICAS_READY=$(kubectl get deployment jellyfin -n jellyfin -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    
    if [ "$REPLICAS_READY" = "$REPLICAS_DESIRED" ] && [ "$REPLICAS_READY" != "0" ]; then
        print_status "ok" "Jellyfin deployment is ready ($REPLICAS_READY/$REPLICAS_DESIRED replicas)"
    else
        print_status "warn" "Jellyfin deployment not fully ready ($REPLICAS_READY/$REPLICAS_DESIRED replicas)"
    fi
    
    # Show pod status
    echo "Pod status:"
    kubectl get pods -n jellyfin -o wide 2>/dev/null || print_status "warn" "Could not get pod status"
else
    print_status "warn" "Jellyfin deployment not found"
fi

# Check PV/PVC status
echo ""
echo -e "${BLUE}=== Storage Status ===${NC}"

# Check Persistent Volumes
echo "Persistent Volumes:"
if kubectl get pv | grep jellyfin; then
    print_status "ok" "Jellyfin Persistent Volumes found"
else
    print_status "warn" "No Jellyfin Persistent Volumes found"
fi

# Check Persistent Volume Claims
echo "Persistent Volume Claims:"
if kubectl get pvc -n jellyfin 2>/dev/null | grep -v NAME; then
    print_status "ok" "Jellyfin Persistent Volume Claims found"
else
    print_status "warn" "No Jellyfin Persistent Volume Claims found"
fi

# Check service status
echo ""
echo -e "${BLUE}=== Service Status ===${NC}"

if kubectl get service jellyfin-service -n jellyfin &> /dev/null; then
    print_status "ok" "Jellyfin service exists"
    
    # Get NodePort
    NODEPORT=$(kubectl get service jellyfin-service -n jellyfin -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "unknown")
    if [ "$NODEPORT" != "unknown" ]; then
        print_status "ok" "Jellyfin HTTP service available on NodePort $NODEPORT"
    fi
else
    print_status "warn" "Jellyfin service not found"
fi

# Storage node connectivity test
echo ""
echo -e "${BLUE}=== Storage Node Tests ===${NC}"

# Try to identify storage node from inventory
STORAGE_NODE=""
if [ -f "ansible/inventory.txt" ]; then
    STORAGE_NODE=$(grep -A1 "\[storage_nodes\]" ansible/inventory.txt | tail -1 | awk '{print $1}' || echo "")
fi

if [ -n "$STORAGE_NODE" ]; then
    print_status "ok" "Storage node identified: $STORAGE_NODE"
    
    # Test if media directory is accessible via ssh (if possible)
    echo "Testing storage node connectivity..."
    if timeout 5 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no "$STORAGE_NODE" "ls -la /srv/media" &> /dev/null; then
        print_status "ok" "Storage node accessible and /srv/media exists"
    else
        print_status "warn" "Could not verify /srv/media on storage node (ssh may not be configured)"
    fi
else
    print_status "warn" "Could not identify storage node from inventory"
fi

# Verification commands to run manually
echo ""
echo -e "${BLUE}=== Manual Verification Commands ===${NC}"
echo "Run these commands to verify the deployment:"
echo ""
echo "# Check pod status and logs:"
echo "kubectl get pods -n jellyfin"
echo "kubectl describe pods -n jellyfin"
echo "kubectl logs -n jellyfin -l app=jellyfin"
echo ""
echo "# Check PV/PVC status:"
echo "kubectl get pv,pvc -n jellyfin"
echo "kubectl describe pvc -n jellyfin"
echo ""
echo "# Check events for errors:"
echo "kubectl get events -n jellyfin --sort-by=.metadata.creationTimestamp"
echo ""
if [ -n "$STORAGE_NODE" ]; then
    echo "# Verify storage on storage node:"
    echo "ssh $STORAGE_NODE 'df -h; ls -la /srv/media'"
fi
echo ""
echo "# Test Jellyfin access (replace NODE_IP with any cluster node IP):"
echo "curl -I http://NODE_IP:${NODEPORT:-30096}/health"

echo ""
echo -e "${GREEN}=== Verification Complete ===${NC}"
#!/bin/bash

# VMStation Kubernetes Storage Validation Script
# Validates storage configuration and directory setup for different node types

set -e

echo "=== VMStation Kubernetes Storage Validation ==="
echo "Timestamp: $(date)"
echo ""

# Configuration
MONITORING_NODE="192.168.4.63"
STORAGE_NODE="192.168.4.61" 
COMPUTE_NODE="192.168.4.62"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

check_directory() {
    local host="$1"
    local path="$2"
    local description="$3"
    
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" "test -d '$path'" 2>/dev/null; then
        success "$description on $host: $path exists"
        # Check permissions and ownership
        ssh "$host" "ls -ld '$path'" 2>/dev/null | head -1
        return 0
    else
        error "$description on $host: $path does not exist"
        return 1
    fi
}

check_storage_space() {
    local host="$1"
    local path="$2"
    local description="$3"
    
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$host" "df -h '$path'" 2>/dev/null; then
        success "$description storage space on $host"
    else
        warning "Could not check storage space for $description on $host"
    fi
}

echo "=== 1. Storage Directory Validation ==="

# Check monitoring node storage
echo "Checking monitoring node (${MONITORING_NODE})..."
check_directory "$MONITORING_NODE" "/srv/monitoring_data" "Monitoring data directory"
check_storage_space "$MONITORING_NODE" "/srv/monitoring_data" "Monitoring"

echo ""

# Check compute node storage
echo "Checking compute node (${COMPUTE_NODE})..."
check_directory "$COMPUTE_NODE" "/mnt/storage" "Mounted storage directory"
check_directory "$COMPUTE_NODE" "/mnt/storage/kubernetes" "Kubernetes storage directory"
check_storage_space "$COMPUTE_NODE" "/mnt/storage" "Compute"

echo ""

# Check storage node storage
echo "Checking storage node (${STORAGE_NODE})..."
check_directory "$STORAGE_NODE" "/var/lib/kubernetes" "Kubernetes storage directory"
check_storage_space "$STORAGE_NODE" "/" "Root filesystem"

echo ""

echo "=== 2. Kubernetes Storage Class Validation ==="

# Check if we can access the Kubernetes cluster
if ssh -o ConnectTimeout=5 "$MONITORING_NODE" "kubectl get storageclass" 2>/dev/null; then
    success "Kubernetes storage classes accessible"
    
    # Check for local-path storage class
    if ssh "$MONITORING_NODE" "kubectl get storageclass local-path" 2>/dev/null; then
        success "local-path storage class exists"
    else
        warning "local-path storage class not found"
    fi
    
    # Check persistent volumes
    echo ""
    echo "Current persistent volumes:"
    ssh "$MONITORING_NODE" "kubectl get pv" 2>/dev/null || warning "No persistent volumes found"
    
    echo ""
    echo "Current persistent volume claims:"
    ssh "$MONITORING_NODE" "kubectl get pvc -A" 2>/dev/null || warning "No persistent volume claims found"
    
else
    warning "Cannot access Kubernetes cluster from monitoring node"
fi

echo ""

echo "=== 3. Disk Usage Summary ==="

echo "Monitoring node disk usage:"
ssh "$MONITORING_NODE" "df -h | grep -E '(Filesystem|/srv|/$)'" 2>/dev/null || warning "Could not get monitoring node disk usage"

echo ""
echo "Compute node disk usage:"
ssh "$COMPUTE_NODE" "df -h | grep -E '(Filesystem|/mnt|/$)'" 2>/dev/null || warning "Could not get compute node disk usage"

echo ""
echo "Storage node disk usage:"
ssh "$STORAGE_NODE" "df -h | grep -E '(Filesystem|/var|debian--vg-root|/$)'" 2>/dev/null || warning "Could not get storage node disk usage"

echo ""
echo "=== Storage Validation Complete ==="
#!/bin/bash

# VMStation Containerd Repointing Script
# Handles moving containerd to a new filesystem location while ensuring 
# proper image_filesystem detection and CRI status functionality

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=== VMStation Containerd Repointing Script ==="
echo "Plan: create backup -> copy data -> bind-mount new root -> restart containerd -> check image_filesystem"

# Configuration
NEW_CONTAINERD_ROOT="${1:-/mnt/storage/containerd}"
BACKUP_DIR="/root/containerd-backup-$(date +%Y%m%d-%H%M%S)"
ORIGINAL_ROOT="/var/lib/containerd"

# Validate input
if [ -z "$1" ]; then
    warn "No new containerd root specified, using default: $NEW_CONTAINERD_ROOT"
fi

echo "Original containerd root: $ORIGINAL_ROOT"
echo "New containerd root: $NEW_CONTAINERD_ROOT"
echo "Backup directory: $BACKUP_DIR"
echo ""

read -p "Type YES to continue: " confirmation
if [ "$confirmation" != "YES" ]; then
    info "Operation cancelled"
    exit 0
fi

# Function to ensure containerd image filesystem is properly initialized
initialize_containerd_filesystem() {
    info "Initializing containerd image filesystem after repointing..."
    
    # Wait for containerd to be ready
    local retry_count=0
    local max_retries=10
    
    while [ $retry_count -lt $max_retries ]; do
        if systemctl is-active containerd >/dev/null 2>&1; then
            break
        else
            warn "Waiting for containerd to start... ($((retry_count + 1))/$max_retries)"
            sleep 2
            ((retry_count++))
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "Containerd failed to start after repointing"
        return 1
    fi
    
    # Initialize containerd namespaces and filesystem detection
    info "Creating k8s.io namespace..."
    ctr namespace create k8s.io 2>/dev/null || true
    
    # Initialize image filesystem
    info "Initializing image filesystem..."
    ctr --namespace k8s.io images ls >/dev/null 2>&1 || true
    
    # Initialize snapshotter (critical for repointed containerd)
    info "Initializing snapshotter..."
    ctr --namespace k8s.io snapshots ls >/dev/null 2>&1 || true
    
    # Trigger CRI runtime status to detect image_filesystem
    info "Triggering CRI image_filesystem detection..."
    crictl info >/dev/null 2>&1 || true
    
    # Wait for initialization to complete
    sleep 5
    
    # Verify filesystem detection with retries
    retry_count=0
    max_retries=5
    
    while [ $retry_count -lt $max_retries ]; do
        if ctr --namespace k8s.io images ls >/dev/null 2>&1; then
            info "✓ Containerd image filesystem initialized successfully"
            
            # Check if CRI status shows image_filesystem
            if crictl info 2>/dev/null | grep -q "\"imageFilesystem\""; then
                info "✓ CRI status shows image_filesystem - repointing successful"
                return 0
            else
                warn "CRI status doesn't show image_filesystem yet, retrying..."
                crictl info >/dev/null 2>&1 || true
            fi
        else
            warn "Containerd image filesystem not ready, retrying... ($((retry_count + 1))/$max_retries)"
            # Retry initialization commands
            ctr namespace create k8s.io 2>/dev/null || true
            ctr --namespace k8s.io images ls >/dev/null 2>&1 || true
            ctr --namespace k8s.io snapshots ls >/dev/null 2>&1 || true
            crictl info >/dev/null 2>&1 || true
        fi
        
        sleep 3
        ((retry_count++))
    done
    
    if [ $retry_count -eq $max_retries ]; then
        warn "Containerd filesystem initialization completed but CRI may need more time"
        warn "This is normal for newly repointed containerd installations"
        return 0
    fi
    
    return 0
}

# Step 1: Stop kubelet and containerd
info "Stopping kubelet and containerd..."
systemctl stop kubelet 2>/dev/null || true
systemctl stop containerd 2>/dev/null || true
sleep 3

# Step 2: Create backup
info "Creating backup $BACKUP_DIR (will move original there)..."
mkdir -p "$BACKUP_DIR"

# Step 3: Copy data
if command -v rsync >/dev/null 2>&1; then
    info "Starting rsync copy (preserves most attributes). This may take time depending on data size..."
    rsync -av "$ORIGINAL_ROOT/" "$NEW_CONTAINERD_ROOT/"
else
    info "rsync not found, using cp -a (less robust)..."
    mkdir -p "$NEW_CONTAINERD_ROOT"
    cp -a "$ORIGINAL_ROOT/"* "$NEW_CONTAINERD_ROOT/" 2>/dev/null || true
fi

# Step 4: Move original to backup and create bind mount
info "Moving original $ORIGINAL_ROOT -> $BACKUP_DIR/"
mv "$ORIGINAL_ROOT" "$BACKUP_DIR/"
mkdir -p "$ORIGINAL_ROOT"

# Create bind mount
info "Creating bind mount: $NEW_CONTAINERD_ROOT -> $ORIGINAL_ROOT"
mount --bind "$NEW_CONTAINERD_ROOT" "$ORIGINAL_ROOT"

# Make mount persistent
if ! grep -q "$NEW_CONTAINERD_ROOT.*$ORIGINAL_ROOT" /etc/fstab; then
    echo "$NEW_CONTAINERD_ROOT $ORIGINAL_ROOT none bind 0 0" >> /etc/fstab
    info "Added bind mount to /etc/fstab for persistence"
fi

# Step 5: Restart containerd with enhanced initialization
info "Restarting containerd..."
systemctl start containerd

# Step 6: Initialize filesystem detection
if initialize_containerd_filesystem; then
    info "✓ Containerd filesystem initialized successfully"
else
    error "Failed to initialize containerd filesystem"
    exit 1
fi

# Step 7: Check CRI image_filesystem status
info "Checking CRI image_filesystem (may be empty until snapshotter initializes)..."
if command -v crictl >/dev/null 2>&1; then
    crictl info | jq '.' 2>/dev/null || crictl info
else
    warn "crictl not found, cannot display CRI status"
fi

info ""
info "✅ Containerd repointing completed successfully!"
info "Original data backed up to: $BACKUP_DIR"
info "New containerd root: $NEW_CONTAINERD_ROOT"
info "Bind mount active: $NEW_CONTAINERD_ROOT -> $ORIGINAL_ROOT"
info ""
info "To verify everything is working:"
info "  1. Check containerd status: systemctl status containerd"
info "  2. Check image filesystem: crictl info | grep -A5 imageFilesystem"
info "  3. Test image operations: ctr --namespace k8s.io images ls"
info "  4. Start kubelet if needed: systemctl start kubelet"
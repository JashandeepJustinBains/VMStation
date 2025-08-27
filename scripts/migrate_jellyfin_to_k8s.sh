#!/bin/bash

# Jellyfin Migration Script - Podman to Kubernetes
# Helps migrate existing Jellyfin Podman setup to Kubernetes deployment

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

header() {
    echo -e "${BLUE}[MIGRATION]${NC} $1"
}

# Configuration
STORAGE_NODE="192.168.4.61"
JELLYFIN_CONTAINER="jellyfin"
CONFIG_BACKUP_DIR="/tmp/jellyfin-migration-backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== Jellyfin Migration: Podman to Kubernetes ==="
echo "Timestamp: $(date)"
echo ""

header "Pre-Migration Checks"

# Check if running on storage node
if [[ "$(hostname -I | grep -o '192.168.4.61')" == "192.168.4.61" ]]; then
    info "Running on storage node (192.168.4.61)"
else
    warn "Not running on storage node. Some operations may require SSH."
fi

# Check if Podman container exists
info "Checking for existing Jellyfin Podman container..."
if podman ps -a --format "{{.Names}}" | grep -q "^${JELLYFIN_CONTAINER}$"; then
    CONTAINER_STATUS=$(podman ps --format "{{.Status}}" --filter "name=${JELLYFIN_CONTAINER}")
    info "Found Jellyfin container: $CONTAINER_STATUS"
    MIGRATION_NEEDED=true
else
    info "No existing Jellyfin Podman container found"
    MIGRATION_NEEDED=false
fi

# Check existing configuration
if [[ -d "/mnt/jellyfin-config" ]]; then
    CONFIG_SIZE=$(du -sh /mnt/jellyfin-config | cut -f1)
    info "Found Jellyfin config directory: /mnt/jellyfin-config ($CONFIG_SIZE)"
elif [[ -d "/mnt/media/jellyfin-config" ]]; then
    CONFIG_SIZE=$(du -sh /mnt/media/jellyfin-config | cut -f1)
    info "Found Jellyfin config directory: /mnt/media/jellyfin-config ($CONFIG_SIZE)"
else
    warn "No existing Jellyfin config directory found"
fi

# Check media directory
if [[ -d "/srv/media" ]]; then
    MEDIA_SIZE=$(du -sh /srv/media | cut -f1)
    info "Found media directory: /srv/media ($MEDIA_SIZE)"
else
    error "Media directory /srv/media not found!"
    exit 1
fi

header "Migration Options"
echo ""
echo "Select migration approach:"
echo "1. Full migration (backup config, stop Podman, deploy Kubernetes)"
echo "2. Parallel deployment (keep Podman running, deploy Kubernetes)"
echo "3. Backup only (backup existing configuration without deployment)"
echo "4. Deploy Kubernetes only (assume backup already done)"
echo "5. Rollback to Podman (stop Kubernetes, restore Podman)"
echo ""
read -p "Enter choice (1-5): " choice

case $choice in
    1)
        MIGRATION_MODE="full"
        ;;
    2)
        MIGRATION_MODE="parallel"
        ;;
    3)
        MIGRATION_MODE="backup"
        ;;
    4)
        MIGRATION_MODE="deploy"
        ;;
    5)
        MIGRATION_MODE="rollback"
        ;;
    *)
        error "Invalid choice"
        exit 1
        ;;
esac

header "Migration Mode: $MIGRATION_MODE"

# Create backup directory
mkdir -p "$CONFIG_BACKUP_DIR"

if [[ "$MIGRATION_MODE" == "full" || "$MIGRATION_MODE" == "backup" || "$MIGRATION_MODE" == "parallel" ]]; then
    header "Backing up Jellyfin Configuration"
    
    # Backup config directory
    if [[ -d "/mnt/jellyfin-config" ]]; then
        info "Backing up /mnt/jellyfin-config..."
        tar czf "${CONFIG_BACKUP_DIR}/jellyfin-config-${TIMESTAMP}.tar.gz" -C /mnt jellyfin-config
        info "Config backup saved: ${CONFIG_BACKUP_DIR}/jellyfin-config-${TIMESTAMP}.tar.gz"
    elif [[ -d "/mnt/media/jellyfin-config" ]]; then
        info "Backing up /mnt/media/jellyfin-config..."
        tar czf "${CONFIG_BACKUP_DIR}/jellyfin-config-${TIMESTAMP}.tar.gz" -C /mnt/media jellyfin-config
        info "Config backup saved: ${CONFIG_BACKUP_DIR}/jellyfin-config-${TIMESTAMP}.tar.gz"
    fi
    
    # Export Podman container config
    if [[ "$MIGRATION_NEEDED" == "true" ]]; then
        info "Exporting Podman container configuration..."
        podman inspect $JELLYFIN_CONTAINER > "${CONFIG_BACKUP_DIR}/podman-inspect-${TIMESTAMP}.json"
        
        # Get container volumes and ports
        podman inspect $JELLYFIN_CONTAINER --format '{{.Mounts}}' > "${CONFIG_BACKUP_DIR}/container-mounts-${TIMESTAMP}.txt"
        podman inspect $JELLYFIN_CONTAINER --format '{{.NetworkSettings.Ports}}' > "${CONFIG_BACKUP_DIR}/container-ports-${TIMESTAMP}.txt"
        
        info "Podman configuration exported"
    fi
    
    # Create migration summary
    cat > "${CONFIG_BACKUP_DIR}/migration-summary-${TIMESTAMP}.txt" << EOF
Jellyfin Migration Summary
=========================
Date: $(date)
Migration Mode: $MIGRATION_MODE
Storage Node: $STORAGE_NODE

Pre-Migration State:
- Podman Container: ${MIGRATION_NEEDED}
- Config Directory: $(find /mnt -name "jellyfin-config" -type d 2>/dev/null | head -1)
- Media Directory: /srv/media ($MEDIA_SIZE)

Backup Files:
- Config: jellyfin-config-${TIMESTAMP}.tar.gz
$(if [[ "$MIGRATION_NEEDED" == "true" ]]; then
echo "- Podman Inspect: podman-inspect-${TIMESTAMP}.json"
echo "- Container Mounts: container-mounts-${TIMESTAMP}.txt"
echo "- Container Ports: container-ports-${TIMESTAMP}.txt"
fi)

Next Steps:
1. Deploy Kubernetes Jellyfin
2. Verify configuration migration
3. Test media library access
4. Stop Podman container (if desired)
EOF
    
    info "Migration summary: ${CONFIG_BACKUP_DIR}/migration-summary-${TIMESTAMP}.txt"
fi

if [[ "$MIGRATION_MODE" == "backup" ]]; then
    info "Backup complete. Exiting."
    exit 0
fi

if [[ "$MIGRATION_MODE" == "full" ]]; then
    header "Stopping Podman Container"
    
    if [[ "$MIGRATION_NEEDED" == "true" ]]; then
        warn "This will stop the current Jellyfin service"
        read -p "Continue? (y/N): " confirm
        if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            info "Migration cancelled"
            exit 0
        fi
        
        info "Stopping Jellyfin Podman container..."
        podman stop $JELLYFIN_CONTAINER || warn "Container may already be stopped"
        
        info "Podman container stopped"
    fi
fi

if [[ "$MIGRATION_MODE" == "full" || "$MIGRATION_MODE" == "deploy" || "$MIGRATION_MODE" == "parallel" ]]; then
    header "Preparing Kubernetes Deployment"
    
    # Ensure config directory is in the right location
    if [[ -d "/mnt/jellyfin-config" && ! -d "/mnt/media/jellyfin-config" ]]; then
        info "Moving config directory to standard location..."
        mkdir -p /mnt/media
        mv /mnt/jellyfin-config /mnt/media/jellyfin-config
        info "Config moved to /mnt/media/jellyfin-config"
    fi
    
    # Set proper permissions
    info "Setting permissions on config directory..."
    chown -R 1000:1000 /mnt/media/jellyfin-config 2>/dev/null || warn "Could not set ownership"
    chmod -R 755 /mnt/media/jellyfin-config
    
    # Ensure media directory has proper NFS exports
    info "Verifying NFS exports..."
    if ! grep -q "/srv/media" /etc/exports; then
        warn "NFS export for /srv/media not found in /etc/exports"
        echo "Add this line to /etc/exports:"
        echo "/srv/media 192.168.4.0/24(rw,sync,no_subtree_check,no_root_squash,all_squash,anonuid=1001,anongid=1001)"
    fi
    
    header "Deploying Kubernetes Jellyfin"
    
    # Check if we're on monitoring node for kubectl access
    if [[ "$(hostname -I | grep -o '192.168.4.63')" == "192.168.4.63" ]]; then
        info "Running Kubernetes deployment from monitoring node..."
        
        # Run the Jellyfin deployment playbook
        if [[ -f "/home/runner/work/VMStation/VMStation/ansible/plays/kubernetes/deploy_jellyfin.yaml" ]]; then
            cd /home/runner/work/VMStation/VMStation
            ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml
        else
            error "Jellyfin deployment playbook not found"
            exit 1
        fi
    else
        info "Deployment must be run from monitoring node (192.168.4.63)"
        info "Run this command on monitoring node:"
        echo ""
        echo "ssh 192.168.4.63 'cd /home/runner/work/VMStation/VMStation && ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml'"
        echo ""
    fi
fi

if [[ "$MIGRATION_MODE" == "rollback" ]]; then
    header "Rolling Back to Podman"
    
    warn "This will stop Kubernetes Jellyfin and restore Podman container"
    read -p "Continue with rollback? (y/N): " confirm
    if [[ ! "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        info "Rollback cancelled"
        exit 0
    fi
    
    # Stop Kubernetes Jellyfin
    if [[ "$(hostname -I | grep -o '192.168.4.63')" == "192.168.4.63" ]]; then
        info "Stopping Kubernetes Jellyfin deployment..."
        kubectl delete namespace jellyfin --ignore-not-found=true
        info "Kubernetes Jellyfin stopped"
    else
        warn "Cannot stop Kubernetes deployment from this node"
        info "Run this command on monitoring node (192.168.4.63):"
        echo "kubectl delete namespace jellyfin"
    fi
    
    # Restore Podman container
    if [[ "$MIGRATION_NEEDED" == "true" ]]; then
        info "Starting Podman Jellyfin container..."
        podman start $JELLYFIN_CONTAINER || warn "Could not start container"
        info "Podman container restored"
    else
        warn "No Podman container to restore"
        info "You may need to run the original Jellyfin setup playbook:"
        echo "ansible-playbook -i ansible/inventory.txt ansible/plays/jellyfin_setup.yaml"
    fi
fi

header "Migration Complete"

if [[ "$MIGRATION_MODE" == "full" || "$MIGRATION_MODE" == "deploy" || "$MIGRATION_MODE" == "parallel" ]]; then
    echo ""
    info "Jellyfin Kubernetes deployment initiated"
    echo ""
    info "Next steps:"
    info "1. Verify deployment: ./scripts/validate_jellyfin_k8s.sh"
    info "2. Access Jellyfin: http://192.168.4.61:30096"
    info "3. Configure media libraries (should be preserved)"
    info "4. Test 4K streaming functionality"
    echo ""
    if [[ "$MIGRATION_MODE" == "parallel" ]]; then
        warn "Podman container is still running. Stop it manually when satisfied with Kubernetes deployment:"
        echo "podman stop $JELLYFIN_CONTAINER"
    fi
fi

echo ""
info "Backup location: $CONFIG_BACKUP_DIR"
info "Migration complete!"
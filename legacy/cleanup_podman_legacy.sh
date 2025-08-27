#!/bin/bash

# VMStation Podman Cleanup Script
# Removes legacy Podman-based monitoring infrastructure

set -e

echo "=== VMStation Podman Infrastructure Cleanup ==="
echo "Timestamp: $(date)"
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# Safety check
warn "This script will remove ALL Podman containers and volumes for VMStation monitoring"
warn "Make sure you have migrated to Kubernetes and verified it's working!"
warn ""
warn "Continue with cleanup? (y/N)"
read -r response
if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    info "Cleanup cancelled"
    exit 0
fi

echo ""
info "Starting Podman infrastructure cleanup..."

# Stop and remove monitoring containers
info "Stopping monitoring containers..."
CONTAINERS=(
    "prometheus"
    "grafana"
    "loki"
    "promtail_local"
    "local_registry"
    "node_exporter"
    "podman_exporter"
    "podman_system_metrics"
    "monitoring_pod"
)

for container in "${CONTAINERS[@]}"; do
    if podman ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
        info "Stopping and removing container: $container"
        podman stop "$container" 2>/dev/null || warn "Failed to stop $container"
        podman rm "$container" 2>/dev/null || warn "Failed to remove $container"
    else
        info "Container $container not found (already removed)"
    fi
done

# Remove monitoring pod
if podman pod exists monitoring_pod 2>/dev/null; then
    info "Removing monitoring pod..."
    podman pod rm -f monitoring_pod
else
    info "Monitoring pod not found (already removed)"
fi

# Clean up volumes and data
info "Cleaning up monitoring data..."
BACKUP_DIR="/tmp/vmstation_podman_backup_$(date +%Y%m%d_%H%M%S)"

if [ -d "/srv/monitoring_data" ]; then
    warn "Backing up monitoring data to $BACKUP_DIR"
    sudo mkdir -p "$BACKUP_DIR"
    sudo cp -r /srv/monitoring_data "$BACKUP_DIR/"
    
    warn "Removing monitoring data directory..."
    sudo rm -rf /srv/monitoring_data
    info "Backup created at: $BACKUP_DIR"
else
    info "No monitoring data directory found"
fi

# Clean up Podman system
info "Cleaning up unused Podman images and volumes..."
podman system prune -a -f

# Remove Podman-specific configuration files
info "Cleaning up Podman registry configuration..."
if [ -f "/etc/containers/registries.conf.d/local-registry.conf" ]; then
    sudo rm -f /etc/containers/registries.conf.d/local-registry.conf
    info "Removed local registry configuration"
fi

# Cleanup systemd services (if any)
info "Checking for Podman systemd services..."
SYSTEMD_SERVICES=(
    "podman-monitoring"
    "podman-prometheus"
    "podman-grafana"
    "podman-loki"
)

for service in "${SYSTEMD_SERVICES[@]}"; do
    if systemctl is-enabled "$service" &>/dev/null; then
        info "Stopping and disabling systemd service: $service"
        sudo systemctl stop "$service"
        sudo systemctl disable "$service"
        sudo rm -f "/etc/systemd/system/${service}.service"
    fi
done

# Reload systemd if we removed any services
if [[ $(sudo find /etc/systemd/system -name "podman-*.service" 2>/dev/null | wc -l) -eq 0 ]]; then
    sudo systemctl daemon-reload
fi

# Archive legacy scripts
info "Archiving legacy Podman scripts..."
LEGACY_SCRIPTS_DIR="/tmp/vmstation_legacy_scripts"
mkdir -p "$LEGACY_SCRIPTS_DIR"

LEGACY_SCRIPTS=(
    "scripts/fix_podman_metrics.sh"
    "scripts/podman_metrics_diagnostic.sh"
    "scripts/validate_monitoring.sh"
    "scripts/validate_container_fixes.sh"
    "scripts/fix_container_restarts.sh"
)

for script in "${LEGACY_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        cp "$script" "$LEGACY_SCRIPTS_DIR/"
        info "Archived: $script"
    fi
done

# Clean up legacy playbooks (optional)
info "Legacy monitoring playbooks will be kept for reference"
info "To remove them manually: rm -rf ansible/plays/monitoring/"

# Clean up legacy documentation
info "Archiving legacy troubleshooting documentation..."
LEGACY_DOCS=(
    "docs/monitoring/troubleshooting_podman_metrics.md"
    "PODMAN_METRICS_SOLUTION.md"
    "SOLUTION_SUMMARY.md"
    "CONTAINER_EXIT_FIXES.md"
    "CONTAINER_RESTART_FIX.md"
)

for doc in "${LEGACY_DOCS[@]}"; do
    if [ -f "$doc" ]; then
        cp "$doc" "$LEGACY_SCRIPTS_DIR/"
        info "Archived: $doc"
    fi
done

echo ""
info "Podman infrastructure cleanup completed!"
echo ""
info "Summary:"
info "- All monitoring containers stopped and removed"
info "- Monitoring data backed up to: $BACKUP_DIR"
info "- Legacy scripts archived to: $LEGACY_SCRIPTS_DIR"
info "- Podman system cleaned up"
info "- Registry configuration removed"
echo ""
warn "Important notes:"
warn "- Backup data is preserved in $BACKUP_DIR"
warn "- Legacy scripts are archived in $LEGACY_SCRIPTS_DIR"
warn "- Podman itself is still installed (in case you need it)"
warn "- Legacy Ansible playbooks are kept for reference"
echo ""
info "To complete the cleanup:"
info "1. Verify Kubernetes monitoring is working: ./scripts/validate_k8s_monitoring.sh"
info "2. Remove backup data when no longer needed: sudo rm -rf $BACKUP_DIR"
info "3. Optionally uninstall Podman: sudo apt remove podman"
echo ""
info "Cleanup complete!"
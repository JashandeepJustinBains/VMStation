#!/bin/bash

# Monitoring Stack Permission Fix Script
# Fixes file permissions and SELinux contexts for Grafana, Loki, and monitoring components

set -e

echo "=== VMStation Monitoring Permission Fix ==="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MONITORING_ROOT="/srv/monitoring_data"
ANSIBLE_INVENTORY="/home/runner/work/VMStation/VMStation/ansible/inventory.txt"

# Critical directories and their required permissions
declare -A DIRECTORIES=(
    ["/srv/monitoring_data"]="755"
    ["/srv/monitoring_data/grafana"]="755"
    ["/srv/monitoring_data/prometheus"]="755"
    ["/srv/monitoring_data/loki"]="755"
    ["/srv/monitoring_data/promtail"]="755"
    ["/var/log"]="755"
    ["/var/promtail"]="755"
    ["/opt/promtail"]="755"
)

# Function to create directory with proper permissions
create_directory() {
    local dir=$1
    local perms=$2
    
    if [ ! -d "$dir" ]; then
        echo "Creating directory: $dir"
        mkdir -p "$dir"
        chmod "$perms" "$dir"
        echo -e "  ${GREEN}✓ Created with permissions $perms${NC}"
    else
        echo "Directory exists: $dir"
        current_perms=$(stat -c "%a" "$dir")
        if [ "$current_perms" != "$perms" ]; then
            echo "  Updating permissions from $current_perms to $perms"
            chmod "$perms" "$dir"
            echo -e "  ${GREEN}✓ Permissions updated${NC}"
        else
            echo -e "  ${GREEN}✓ Permissions correct ($perms)${NC}"
        fi
    fi
}

# Function to set proper ownership for monitoring directories
set_ownership() {
    local dir=$1
    
    if [ -d "$dir" ]; then
        echo "Setting ownership for: $dir"
        
        # For Kubernetes, we typically want root ownership with proper group access
        # For Podman, we might need specific user ownership
        if command -v kubectl >/dev/null 2>&1; then
            # Kubernetes mode - ensure readable by all
            chown -R root:root "$dir" 2>/dev/null || {
                echo -e "  ${YELLOW}⚠ Could not change ownership (may not have permissions)${NC}"
                return 1
            }
        else
            # Legacy Podman mode - try to use current user
            chown -R "$(whoami):$(id -gn)" "$dir" 2>/dev/null || {
                echo -e "  ${YELLOW}⚠ Could not change ownership (may not have permissions)${NC}"
                return 1
            }
        fi
        echo -e "  ${GREEN}✓ Ownership set${NC}"
    fi
}

# Function to check and fix SELinux contexts
fix_selinux_contexts() {
    local dir=$1
    
    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status=$(getenforce)
        if [ "$selinux_status" = "Enforcing" ] || [ "$selinux_status" = "Permissive" ]; then
            echo "Fixing SELinux context for: $dir"
            
            if [ -d "$dir" ]; then
                # Set the context to allow container access
                chcon -R -t container_file_t "$dir" 2>/dev/null || {
                    echo -e "  ${YELLOW}⚠ Could not set SELinux context (may need sudo)${NC}"
                    return 1
                }
                echo -e "  ${GREEN}✓ SELinux context set to container_file_t${NC}"
            else
                echo -e "  ${YELLOW}⚠ Directory does not exist${NC}"
                return 1
            fi
        else
            echo "SELinux not enforcing, skipping context fix for: $dir"
        fi
    else
        echo "SELinux tools not available, skipping context fix for: $dir"
    fi
}

# Function to set SELinux booleans for container access
set_selinux_booleans() {
    if command -v setsebool >/dev/null 2>&1; then
        local selinux_status=$(getenforce 2>/dev/null || echo "Disabled")
        if [ "$selinux_status" = "Enforcing" ] || [ "$selinux_status" = "Permissive" ]; then
            echo "Setting SELinux booleans for container access..."
            
            setsebool -P container_use_cephfs 1 2>/dev/null || echo -e "  ${YELLOW}⚠ Could not set container_use_cephfs${NC}"
            setsebool -P container_manage_cgroup 1 2>/dev/null || echo -e "  ${YELLOW}⚠ Could not set container_manage_cgroup${NC}"
            
            echo -e "  ${GREEN}✓ SELinux booleans configured${NC}"
        fi
    fi
}

echo "=== Phase 1: Pre-flight Checks ==="
echo "Current user: $(whoami)"
echo "Current groups: $(groups)"

if [ "$EUID" -eq 0 ]; then
    echo -e "${GREEN}✓ Running as root - full permissions available${NC}"
else
    echo -e "${YELLOW}⚠ Running as non-root user - some operations may fail${NC}"
    echo "  Consider running with sudo for full functionality"
fi

if command -v getenforce >/dev/null 2>&1; then
    selinux_status=$(getenforce)
    echo "SELinux status: $selinux_status"
else
    echo "SELinux: Not available"
fi
echo ""

echo "=== Phase 2: Create and Fix Directory Permissions ==="
for dir in "${!DIRECTORIES[@]}"; do
    perms="${DIRECTORIES[$dir]}"
    create_directory "$dir" "$perms"
done
echo ""

echo "=== Phase 3: Set Directory Ownership ==="
for dir in "${!DIRECTORIES[@]}"; do
    set_ownership "$dir"
done
echo ""

echo "=== Phase 4: Fix SELinux Contexts ==="
for dir in "${!DIRECTORIES[@]}"; do
    fix_selinux_contexts "$dir"
done

set_selinux_booleans
echo ""

echo "=== Phase 5: Create Required Subdirectories ==="
# Create specific subdirectories that monitoring components need
monitoring_subdirs=(
    "$MONITORING_ROOT/grafana/dashboards"
    "$MONITORING_ROOT/grafana/datasources"
    "$MONITORING_ROOT/grafana/data"
    "$MONITORING_ROOT/prometheus/data"
    "$MONITORING_ROOT/loki/chunks"
    "$MONITORING_ROOT/loki/index"
    "$MONITORING_ROOT/promtail/data"
)

for subdir in "${monitoring_subdirs[@]}"; do
    create_directory "$subdir" "755"
done
echo ""

echo "=== Phase 6: Verification ==="
echo "Verifying directory access..."
all_good=true

for dir in "${!DIRECTORIES[@]}"; do
    if [ -d "$dir" ] && [ -r "$dir" ] && [ -w "$dir" ]; then
        echo -e "${GREEN}✓${NC} $dir - accessible"
    else
        echo -e "${RED}✗${NC} $dir - access issues"
        all_good=false
    fi
done

if [ "$all_good" = true ]; then
    echo ""
    echo -e "${GREEN}✓ All directories have proper permissions${NC}"
else
    echo ""
    echo -e "${RED}✗ Some directories still have permission issues${NC}"
fi
echo ""

echo "=== Phase 7: Next Steps ==="
if [ "$all_good" = true ]; then
    echo "Permission fixes applied successfully!"
    echo ""
    echo "To complete the monitoring stack setup:"
    echo "1. Restart any failed monitoring pods:"
    echo "   kubectl delete pods -n monitoring --field-selector=status.phase=Pending"
    echo ""
    echo "2. Or redeploy the monitoring stack:"
    echo "   ./update_and_deploy.sh"
    echo ""
    echo "3. Verify monitoring services:"
    echo "   ./scripts/validate_monitoring.sh"
else
    echo "Some permission issues remain. Try running this script with sudo:"
    echo "  sudo ./scripts/fix_monitoring_permissions.sh"
    echo ""
    echo "Or manually fix permissions for the following directories:"
    for dir in "${!DIRECTORIES[@]}"; do
        echo "  sudo chmod 755 $dir"
        echo "  sudo chown -R root:root $dir"
        echo "  sudo chcon -R -t container_file_t $dir  # If SELinux is enabled"
    done
fi

echo ""
echo "=== Fix Complete ==="
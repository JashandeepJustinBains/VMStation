#!/bin/bash

# Fix script for podman container restart and SELinux issues
# Addresses loki, promtail, and other monitoring container crashes

set -e

echo "=== VMStation Container Restart & SELinux Fix ===" 
echo "Timestamp: $(date)"
echo ""

# Configuration
MONITORING_NODE="192.168.4.63"
ANSIBLE_INVENTORY="ansible/inventory.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Phase 1: Check Current Container Status ==="
echo "Checking for failing containers..."

# Function to check container status
check_container_status() {
    local container_name=$1
    if podman ps --filter name="$container_name" --format "{{.Status}}" | grep -q "Up"; then
        echo -e "${GREEN}✓${NC} $container_name is running"
        return 0
    elif podman ps -a --filter name="$container_name" --format "{{.Status}}" | grep -q "Exited"; then
        echo -e "${RED}✗${NC} $container_name has exited"
        echo "  Last logs:"
        podman logs --tail 5 "$container_name" 2>/dev/null || echo "  No logs available"
        return 1
    else
        echo -e "${YELLOW}⚠${NC} $container_name not found"
        return 2
    fi
}

# Check key containers
containers=("loki" "promtail" "promtail_local" "grafana" "prometheus")
failed_containers=()

for container in "${containers[@]}"; do
    if ! check_container_status "$container"; then
        failed_containers+=("$container")
    fi
done

echo ""
echo "=== Phase 2: Check SELinux Status ==="

if command -v getenforce >/dev/null 2>&1; then
    selinux_status=$(getenforce)
    echo "SELinux status: $selinux_status"
    
    if [ "$selinux_status" = "Enforcing" ] || [ "$selinux_status" = "Permissive" ]; then
        echo -e "${YELLOW}⚠${NC} SELinux is active - applying SELinux fixes"
        selinux_active=true
    else
        echo -e "${GREEN}✓${NC} SELinux is not enforcing"
        selinux_active=false
    fi
else
    echo -e "${GREEN}✓${NC} SELinux tools not found - assuming not active"
    selinux_active=false
fi

echo ""
echo "=== Phase 3: Apply SELinux Context Fixes ==="

if [ "$selinux_active" = true ]; then
    echo "Applying SELinux context fixes..."
    
    # Run the SELinux fix playbook
    if [ -f "$ANSIBLE_INVENTORY" ]; then
        echo "Running SELinux context fix playbook..."
        ansible-playbook -i "$ANSIBLE_INVENTORY" ansible/plays/monitoring/fix_selinux_contexts.yaml --limit all
    else
        echo -e "${YELLOW}⚠${NC} Ansible inventory not found, applying manual SELinux fixes..."
        
        # Manual SELinux fixes
        echo "Setting SELinux contexts manually..."
        
        # Fix /var/log context
        if [ -d /var/log ]; then
            echo "Fixing /var/log SELinux context..."
            chcon -R -t container_file_t /var/log 2>/dev/null || echo "Could not set context for /var/log"
        fi
        
        # Fix monitoring data context
        if [ -d /srv/monitoring_data ]; then
            echo "Fixing /srv/monitoring_data SELinux context..."
            chcon -R -t container_file_t /srv/monitoring_data 2>/dev/null || echo "Could not set context for /srv/monitoring_data"
        fi
        
        # Fix promtail directories
        if [ -d /var/promtail ]; then
            echo "Fixing /var/promtail SELinux context..."
            chcon -R -t container_file_t /var/promtail 2>/dev/null || echo "Could not set context for /var/promtail"
        fi
        
        if [ -d /opt/promtail ]; then
            echo "Fixing /opt/promtail SELinux context..."
            chcon -R -t container_file_t /opt/promtail 2>/dev/null || echo "Could not set context for /opt/promtail"
        fi
        
        # Set SELinux booleans for container access
        echo "Setting SELinux booleans for containers..."
        setsebool -P container_use_cephfs 1 2>/dev/null || echo "Could not set container_use_cephfs boolean"
        setsebool -P container_manage_cgroup 1 2>/dev/null || echo "Could not set container_manage_cgroup boolean"
    fi
else
    echo "SELinux not active, skipping SELinux fixes"
fi

echo ""
echo "=== Phase 4: Fix Container Volume Mounts ==="

echo "Stopping failed containers..."
for container in "${failed_containers[@]}"; do
    echo "Stopping and removing $container..."
    podman stop "$container" 2>/dev/null || true
    podman rm "$container" 2>/dev/null || true
done

echo ""
echo "=== Phase 5: Recreate Failed Containers with Proper Mounts ==="

# Function to recreate containers with proper SELinux contexts
recreate_container() {
    local container_name=$1
    local image=$2
    local ports=$3
    local volumes=$4
    local command_args=$5
    local pod_args=$6
    
    echo "Recreating $container_name..."
    
    # Build volume arguments with SELinux context
    volume_args=()
    IFS=',' read -ra VOLUMES <<< "$volumes"
    for volume in "${VOLUMES[@]}"; do
        if [ "$selinux_active" = true ]; then
            # Add :Z for SELinux context if not already present
            if [[ "$volume" != *":Z" ]] && [[ "$volume" != *":z" ]]; then
                volume="${volume%:*}:${volume##*:},Z"
            fi
        fi
        volume_args+=("-v" "$volume")
    done
    
    # Create container
    podman run -d \
        --name "$container_name" \
        --restart always \
        $pod_args \
        $ports \
        "${volume_args[@]}" \
        "$image" \
        $command_args
}

# Check if monitoring pod exists
if ! podman pod exists monitoring_pod 2>/dev/null; then
    echo "Creating monitoring pod..."
    podman pod create --name monitoring_pod \
        -p 3000:3000 \
        -p 3100:3100 \
        -p 9090:9090 \
        -p 5000:5000
fi

# Recreate failed containers
if [[ " ${failed_containers[@]} " =~ " loki " ]]; then
    recreate_container "loki" \
        "docker.io/grafana/loki:2.8.2" \
        "" \
        "/srv/monitoring_data/loki/local-config.yaml:/etc/loki/local-config.yaml:ro,/srv/monitoring_data/loki/chunks:/loki/chunks,/srv/monitoring_data/loki/index:/loki/index" \
        "-config.file=/etc/loki/local-config.yaml" \
        "--pod monitoring_pod"
fi

if [[ " ${failed_containers[@]} " =~ " promtail_local " ]]; then
    recreate_container "promtail_local" \
        "docker.io/grafana/promtail:2.8.2" \
        "" \
        "/var/log:/var/log:ro,/srv/monitoring_data/promtail/promtail-config.yaml:/etc/promtail/promtail-config.yaml:ro,/srv/monitoring_data/promtail/data:/var/promtail" \
        "-config.file=/etc/promtail/promtail-config.yaml" \
        "--pod monitoring_pod"
fi

if [[ " ${failed_containers[@]} " =~ " promtail " ]]; then
    recreate_container "promtail" \
        "docker.io/grafana/promtail:2.8.2" \
        "" \
        "/var/log:/var/log:ro,/opt/promtail/promtail-config.yaml:/etc/promtail/promtail-config.yaml:ro,/var/promtail:/var/promtail" \
        "-config.file=/etc/promtail/promtail-config.yaml" \
        ""
fi

echo ""
echo "=== Phase 6: Verify Fixes ==="

sleep 5

echo "Checking container status after fixes..."
all_good=true
for container in "${containers[@]}"; do
    if ! check_container_status "$container"; then
        all_good=false
    fi
done

echo ""
if [ "$all_good" = true ]; then
    echo -e "${GREEN}✓ All containers are now running successfully${NC}"
else
    echo -e "${RED}✗ Some containers are still failing${NC}"
    echo "Check logs with: podman logs <container_name>"
fi

echo ""
echo "=== Phase 7: Additional Verification ==="

# Test log access
echo "Testing log file access..."
if [ -r /var/log/messages ] || [ -r /var/log/syslog ]; then
    echo -e "${GREEN}✓${NC} Log files are accessible"
else
    echo -e "${YELLOW}⚠${NC} Log files may not be accessible"
fi

# Test SELinux contexts
if [ "$selinux_active" = true ]; then
    echo "Checking SELinux contexts..."
    if ls -Z /var/log 2>/dev/null | grep -q container_file_t; then
        echo -e "${GREEN}✓${NC} /var/log has proper SELinux context"
    else
        echo -e "${YELLOW}⚠${NC} /var/log may not have proper SELinux context"
    fi
fi

echo ""
echo "=== Fix Complete ==="
echo "If containers are still failing, check:"
echo "1. Container logs: podman logs <container_name>"
echo "2. SELinux audit logs: ausearch -m avc"
echo "3. Directory permissions: ls -la /var/log /srv/monitoring_data"
echo ""

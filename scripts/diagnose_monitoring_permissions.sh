#!/bin/bash

# Monitoring Stack Permission Diagnostic Script
# Identifies specific file permission and SELinux issues affecting Grafana, Loki, and other monitoring pods

set -e

echo "=== VMStation Monitoring Permission Diagnostic ==="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Critical directories for monitoring stack
CRITICAL_DIRS=(
    "/srv/monitoring_data"
    "/var/log" 
    "/var/promtail"
    "/opt/promtail"
)

# Function to check directory permissions
check_directory_permissions() {
    local dir=$1
    local required_perms=$2
    local required_owner=$3
    
    echo -n "  Checking $dir... "
    
    if [ ! -d "$dir" ]; then
        echo -e "${RED}MISSING${NC} - Directory does not exist"
        return 1
    fi
    
    local perms=$(stat -c "%a" "$dir" 2>/dev/null)
    local owner=$(stat -c "%U:%G" "$dir" 2>/dev/null)
    local readable=$([ -r "$dir" ] && echo "yes" || echo "no")
    local writable=$([ -w "$dir" ] && echo "yes" || echo "no")
    
    echo -e "${BLUE}EXISTS${NC}"
    echo "    Permissions: $perms"
    echo "    Owner: $owner"
    echo "    Readable: $readable"
    echo "    Writable: $writable"
    
    if [ "$readable" = "no" ]; then
        echo -e "    ${RED}ISSUE: Directory not readable${NC}"
        return 1
    fi
    
    return 0
}

# Function to check SELinux context
check_selinux_context() {
    local dir=$1
    
    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status=$(getenforce)
        if [ "$selinux_status" = "Enforcing" ] || [ "$selinux_status" = "Permissive" ]; then
            echo "  SELinux Status: $selinux_status"
            if [ -d "$dir" ]; then
                local context=$(ls -Zd "$dir" 2>/dev/null | awk '{print $1}')
                echo "    Context: $context"
                if echo "$context" | grep -q "container_file_t"; then
                    echo -e "    ${GREEN}✓ Proper container context${NC}"
                    return 0
                else
                    echo -e "    ${YELLOW}⚠ May need container_file_t context${NC}"
                    return 1
                fi
            fi
        else
            echo "  SELinux Status: $selinux_status (OK)"
            return 0
        fi
    else
        echo "  SELinux: Not available"
        return 0
    fi
}

echo "=== 1. System Information ==="
echo "User: $(whoami)"
echo "Groups: $(groups)"
if command -v getenforce >/dev/null 2>&1; then
    echo "SELinux: $(getenforce)"
else
    echo "SELinux: Not available"
fi
echo ""

echo "=== 2. Critical Directory Analysis ==="
permission_issues=0

for dir in "${CRITICAL_DIRS[@]}"; do
    echo "Analyzing: $dir"
    if ! check_directory_permissions "$dir"; then
        ((permission_issues++))
    fi
    check_selinux_context "$dir"
    echo ""
done

echo "=== 3. Kubernetes Pod Status Check ==="
if command -v kubectl >/dev/null 2>&1; then
    echo "Checking monitoring pods..."
    kubectl get pods -n monitoring 2>/dev/null || echo "No monitoring namespace or pods found"
    echo ""
    
    echo "Checking for pending pods..."
    pending_pods=$(kubectl get pods -A --field-selector=status.phase=Pending 2>/dev/null | wc -l)
    if [ "$pending_pods" -gt 1 ]; then
        echo -e "${YELLOW}Found $((pending_pods-1)) pending pods:${NC}"
        kubectl get pods -A --field-selector=status.phase=Pending 2>/dev/null | tail -n +2
    else
        echo "No pending pods found"
    fi
else
    echo "kubectl not available - cannot check pod status"
fi
echo ""

echo "=== 4. Container Runtime Check ==="
if command -v podman >/dev/null 2>&1; then
    echo "Podman containers:"
    podman ps --filter label=monitoring --format "table {{.Names}}\t{{.Status}}\t{{.Mounts}}" 2>/dev/null || echo "No monitoring containers found"
elif command -v docker >/dev/null 2>&1; then
    echo "Docker containers:"
    docker ps --filter label=monitoring --format "table {{.Names}}\t{{.Status}}\t{{.Mounts}}" 2>/dev/null || echo "No monitoring containers found"
else
    echo "No container runtime found"
fi
echo ""

echo "=== 5. Storage and Mount Analysis ==="
echo "Checking filesystem types and mount options..."
for dir in "${CRITICAL_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "  $dir:"
        mount_info=$(df -T "$dir" 2>/dev/null | tail -n 1)
        echo "    Mount: $mount_info"
        
        # Check if it's an NFS mount or special filesystem
        if echo "$mount_info" | grep -q "nfs"; then
            echo -e "    ${YELLOW}⚠ NFS mount detected - may need special permissions${NC}"
        fi
    fi
done
echo ""

echo "=== 6. Process Analysis ==="
echo "Checking for monitoring processes..."
if pgrep -f "grafana\|prometheus\|loki\|promtail" >/dev/null; then
    echo "Monitoring processes found:"
    ps aux | grep -E "(grafana|prometheus|loki|promtail)" | grep -v grep
else
    echo "No monitoring processes running"
fi
echo ""

echo "=== 7. Summary and Recommendations ==="
echo "Permission Issues Found: $permission_issues"
echo ""

if [ $permission_issues -gt 0 ]; then
    echo -e "${RED}ISSUES DETECTED${NC}"
    echo "Recommendations:"
    echo "1. Run the permission fix script: ./scripts/fix_monitoring_permissions.sh"
    echo "2. For manual fixes, ensure these directories have proper permissions:"
    
    for dir in "${CRITICAL_DIRS[@]}"; do
        echo "   - $dir (read/write access for containers)"
    done
    
    echo ""
    echo "3. If SELinux is enabled, set container contexts:"
    echo "   sudo chcon -R -t container_file_t /srv/monitoring_data"
    echo "   sudo chcon -R -t container_file_t /var/log"
    echo "   sudo chcon -R -t container_file_t /var/promtail"
    echo "   sudo chcon -R -t container_file_t /opt/promtail"
    echo ""
    echo "4. Restart monitoring stack after fixing permissions"
else
    echo -e "${GREEN}NO CRITICAL PERMISSION ISSUES DETECTED${NC}"
    echo "If pods are still failing, check:"
    echo "1. Resource constraints (CPU/Memory)"
    echo "2. Node scheduling issues"
    echo "3. Container logs: kubectl logs -n monitoring <pod-name>"
fi

echo ""
echo "=== Diagnostic Complete ==="
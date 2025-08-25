#!/bin/bash

# Verification script for container restart fixes
# Checks if the fixes have been properly applied

echo "=== VMStation Container Restart Fix Verification ==="
echo "Timestamp: $(date)"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root/sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Note: Some checks require root privileges${NC}"
    echo ""
fi

echo "=== 1. Container Status Check ==="
if command -v podman >/dev/null 2>&1; then
    echo "Checking podman containers..."
    
    containers=("loki" "promtail" "promtail_local" "grafana" "prometheus" "local_registry")
    all_running=true
    
    for container in "${containers[@]}"; do
        if podman ps --filter name="$container" --format "{{.Status}}" | grep -q "Up"; then
            echo -e "${GREEN}✓${NC} $container is running"
        else
            echo -e "${RED}✗${NC} $container is not running"
            all_running=false
            # Show last few log lines if container exists
            if podman ps -a --filter name="$container" --format "{{.Names}}" | grep -q "$container"; then
                echo "  Last logs:"
                podman logs --tail 3 "$container" 2>/dev/null | sed 's/^/    /'
            fi
        fi
    done
    
    if [ "$all_running" = true ]; then
        echo -e "${GREEN}✓ All expected containers are running${NC}"
    else
        echo -e "${RED}✗ Some containers are not running${NC}"
    fi
else
    echo -e "${YELLOW}⚠ podman not found - skipping container check${NC}"
fi

echo ""
echo "=== 2. SELinux Status Check ==="
if command -v getenforce >/dev/null 2>&1; then
    selinux_status=$(getenforce)
    echo "SELinux status: $selinux_status"
    
    if [ "$selinux_status" = "Enforcing" ] || [ "$selinux_status" = "Permissive" ]; then
        echo "Checking SELinux contexts..."
        
        # Check key directories
        directories=("/var/log" "/srv/monitoring_data" "/var/promtail" "/opt/promtail")
        for dir in "${directories[@]}"; do
            if [ -d "$dir" ]; then
                context=$(ls -Zd "$dir" 2>/dev/null | awk '{print $1}')
                if echo "$context" | grep -q "container_file_t"; then
                    echo -e "${GREEN}✓${NC} $dir has proper SELinux context: $context"
                else
                    echo -e "${YELLOW}⚠${NC} $dir context: $context (may need container_file_t)"
                fi
            else
                echo -e "${YELLOW}⚠${NC} $dir does not exist"
            fi
        done
    else
        echo -e "${GREEN}✓${NC} SELinux not enforcing - no context issues expected"
    fi
else
    echo -e "${GREEN}✓${NC} SELinux not available"
fi

echo ""
echo "=== 3. File Access Check ==="

# Check if log files are accessible
echo "Checking log file access..."
if [ -r /var/log/messages ] || [ -r /var/log/syslog ] || [ -r /var/log/kern.log ]; then
    echo -e "${GREEN}✓${NC} Log files are readable"
else
    echo -e "${YELLOW}⚠${NC} Standard log files not found or not readable"
fi

# Check monitoring directories
if [ -d /srv/monitoring_data ]; then
    echo -e "${GREEN}✓${NC} Monitoring data directory exists"
    
    # Check if we can read inside
    if [ -r /srv/monitoring_data ]; then
        echo -e "${GREEN}✓${NC} Monitoring data directory is readable"
    else
        echo -e "${RED}✗${NC} Monitoring data directory is not readable"
    fi
else
    echo -e "${YELLOW}⚠${NC} Monitoring data directory does not exist"
fi

echo ""
echo "=== 4. Network Connectivity Check ==="

# Check if monitoring ports are accessible
ports=("3000" "3100" "9090" "5000")
for port in "${ports[@]}"; do
    if nc -z localhost "$port" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Port $port is accessible"
    else
        echo -e "${YELLOW}⚠${NC} Port $port is not accessible (service may not be running)"
    fi
done

echo ""
echo "=== 5. Service Functionality Check ==="

# Test Loki if accessible
if nc -z localhost 3100 2>/dev/null; then
    echo "Testing Loki API..."
    if curl -s http://localhost:3100/ready | grep -q "ready"; then
        echo -e "${GREEN}✓${NC} Loki is ready and responding"
    else
        echo -e "${YELLOW}⚠${NC} Loki API test failed"
    fi
else
    echo -e "${YELLOW}⚠${NC} Loki not accessible for testing"
fi

# Test Grafana if accessible
if nc -z localhost 3000 2>/dev/null; then
    echo "Testing Grafana..."
    if curl -s http://localhost:3000/api/health | grep -q "ok"; then
        echo -e "${GREEN}✓${NC} Grafana is healthy and responding"
    else
        echo -e "${YELLOW}⚠${NC} Grafana health check failed"
    fi
else
    echo -e "${YELLOW}⚠${NC} Grafana not accessible for testing"
fi

# Test Prometheus if accessible
if nc -z localhost 9090 2>/dev/null; then
    echo "Testing Prometheus..."
    if curl -s http://localhost:9090/-/ready | grep -q "Prometheus"; then
        echo -e "${GREEN}✓${NC} Prometheus is ready and responding"
    else
        echo -e "${YELLOW}⚠${NC} Prometheus readiness check failed"
    fi
else
    echo -e "${YELLOW}⚠${NC} Prometheus not accessible for testing"
fi

echo ""
echo "=== 6. Recent Error Check ==="

# Check for recent container restart errors in journal
if command -v journalctl >/dev/null 2>&1; then
    echo "Checking for recent container errors..."
    recent_errors=$(journalctl --since "10 minutes ago" -u podman* 2>/dev/null | grep -i error | wc -l)
    if [ "$recent_errors" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} No recent container errors in journal"
    else
        echo -e "${YELLOW}⚠${NC} Found $recent_errors recent container error(s) in journal"
    fi
else
    echo -e "${YELLOW}⚠${NC} journalctl not available for error checking"
fi

echo ""
echo "=== Verification Summary ==="

# Overall assessment
echo "Quick recommendations:"
echo "1. If containers are not running: run ./scripts/fix_container_restarts.sh"
echo "2. If SELinux contexts are wrong: run ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/fix_selinux_contexts.yaml"
echo "3. If services are not responding: check 'podman logs <container_name>'"
echo "4. If still having issues: check /var/log/containers/ or 'journalctl -u podman*'"

echo ""
echo "Verification complete at $(date)"
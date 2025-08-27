#!/bin/bash

# Comprehensive diagnostic script for podman_system_metrics issues
# This script helps diagnose why podman_system_metrics exits immediately and port 19882 refuses connections

set -e

echo "=== VMStation Podman System Metrics Diagnostic ==="
echo "Timestamp: $(date)"
echo ""

# Variables
PORT=19882
CONTAINER_NAME="podman_system_metrics"
IMAGE_NAME="192.168.4.63:5000/podman-system-metrics:latest"

echo "=== 1. System Information ==="
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo "Podman version: $(podman --version 2>/dev/null || echo 'Podman not found')"
echo ""

echo "=== 2. Network and Port Status ==="
echo "Checking if port $PORT is in use:"
# Check multiple ways to detect port usage
if command -v lsof >/dev/null 2>&1; then
    echo "lsof check:"
    lsof -i :$PORT 2>/dev/null || echo "Port $PORT not in use (lsof)"
fi

if command -v ss >/dev/null 2>&1; then
    echo "ss check:"
    ss -tlnp | grep ":$PORT " || echo "Port $PORT not in use (ss)"
fi

if command -v netstat >/dev/null 2>&1; then
    echo "netstat check:"
    netstat -tlnp 2>/dev/null | grep ":$PORT " || echo "Port $PORT not in use (netstat)"
fi

echo ""

echo "=== 3. Container Status ==="
echo "All podman containers:"
podman ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Created}}" 2>/dev/null || echo "Failed to list containers"
echo ""

echo "Specific container '$CONTAINER_NAME':"
podman ps -a --filter name="^${CONTAINER_NAME}$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}\t{{.Command}}" 2>/dev/null || echo "Container not found"
echo ""

echo "=== 4. Container Logs ==="
echo "Recent logs for '$CONTAINER_NAME':"
podman logs --tail 50 "$CONTAINER_NAME" 2>/dev/null || echo "No logs available or container doesn't exist"
echo ""

echo "=== 5. Image Availability ==="
echo "Checking image '$IMAGE_NAME':"
podman images | grep "podman-system-metrics" || echo "Image not found locally"
echo ""

echo "Local registry connectivity test:"
curl -s http://192.168.4.63:5000/v2/_catalog 2>/dev/null | jq -r '.repositories[]' 2>/dev/null | grep podman || echo "Cannot reach local registry or podman images not found"
echo ""

echo "=== 6. Podman System State ==="
echo "Podman system info:"
podman system info --format json 2>/dev/null | jq -r '.host.remoteSocket' 2>/dev/null || echo "Cannot get podman system info"
echo ""

echo "Podman API socket status:"
if [ -S /run/podman/podman.sock ]; then
    echo "Podman socket exists: /run/podman/podman.sock"
    ls -la /run/podman/podman.sock
else
    echo "Podman socket not found at /run/podman/podman.sock"
fi
echo ""

echo "=== 7. Testing Container Start ==="
echo "Attempting to start container manually for debugging:"

# Remove existing container if it exists
podman rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "Starting container with debug output:"
set +e  # Don't exit on error for this test
podman run --name "${CONTAINER_NAME}_test" \
           --rm \
           -p "127.0.0.1:$PORT:9882" \
           "$IMAGE_NAME" &
CONTAINER_PID=$!

echo "Container started with PID: $CONTAINER_PID"
echo "Waiting 5 seconds..."
sleep 5

echo "Checking if container is still running:"
if kill -0 $CONTAINER_PID 2>/dev/null; then
    echo "Container is running"
    echo "Testing metrics endpoint:"
    curl -s "http://127.0.0.1:$PORT/metrics" | head -10 2>/dev/null || echo "Failed to reach metrics endpoint"
    
    echo "Stopping test container..."
    kill $CONTAINER_PID 2>/dev/null || true
    wait $CONTAINER_PID 2>/dev/null || true
else
    echo "Container exited immediately"
    echo "Getting exit code and logs:"
    wait $CONTAINER_PID
    EXIT_CODE=$?
    echo "Exit code: $EXIT_CODE"
fi

set -e

echo ""
echo "=== 8. Firewall Status ==="
echo "UFW status:"
ufw status 2>/dev/null || echo "UFW not available or not installed"
echo ""

echo "=== 9. Recommended Actions ==="
echo "Based on the diagnostic results above:"
echo ""
echo "1. If the image is missing:"
echo "   - Check local registry: curl http://192.168.4.63:5000/v2/_catalog"
echo "   - Rebuild/push image to registry"
echo ""
echo "2. If port is in use:"
echo "   - Stop conflicting process: sudo kill <pid>"
echo "   - Or use different port in ansible/group_vars/all.yml"
echo ""
echo "3. If container exits immediately:"
echo "   - Check container logs: podman logs $CONTAINER_NAME"
echo "   - Verify image compatibility and dependencies"
echo ""
echo "4. If Podman socket issues:"
echo "   - Start Podman socket: systemctl --user start podman.socket"
echo "   - Or system-wide: sudo systemctl start podman.socket"
echo ""
echo "=== Diagnostic Complete ==="
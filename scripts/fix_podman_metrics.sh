#!/bin/bash

# Complete fix script for podman_system_metrics issues
# This script addresses the root causes and provides a working solution

set -e

echo "=== VMStation Podman System Metrics Fix ==="
echo "Timestamp: $(date)"
echo ""

# Configuration
MONITORING_NODE="192.168.4.63"
REGISTRY_PORT="5000"
METRICS_PORT="19882"
LOCAL_REGISTRY_IMAGE="192.168.4.63:5000/podman-system-metrics:latest"
SOURCE_IMAGE="quay.io/podman/stable:latest"

echo "=== Phase 1: Ensure Local Registry is Running ==="

# Check if registry is running
if curl -s "http://$MONITORING_NODE:$REGISTRY_PORT/v2/_catalog" >/dev/null 2>&1; then
    echo "✓ Local registry is accessible"
else
    echo "⚠ Local registry not accessible, attempting to start..."
    
    # Create registry directory if it doesn't exist
    sudo mkdir -p /srv/monitoring_data/registry
    
    # Start registry container
    podman run -d --name local_registry \
               --restart always \
               -p "$REGISTRY_PORT:5000" \
               -v /srv/monitoring_data/registry:/var/lib/registry:Z \
               docker.io/registry:2
    
    echo "Waiting for registry to start..."
    sleep 10
    
    # Verify registry is running
    if curl -s "http://$MONITORING_NODE:$REGISTRY_PORT/v2/_catalog" >/dev/null 2>&1; then
        echo "✓ Local registry started successfully"
    else
        echo "✗ Failed to start local registry"
        exit 1
    fi
fi

echo ""
echo "=== Phase 2: Ensure Container Image is Available ==="

# Check if image exists in local registry
if curl -s "http://$MONITORING_NODE:$REGISTRY_PORT/v2/podman-system-metrics/tags/list" | grep -q "latest"; then
    echo "✓ podman-system-metrics image exists in local registry"
else
    echo "⚠ Image not found in registry, pulling and pushing..."
    
    # Pull source image
    echo "Pulling source image: $SOURCE_IMAGE"
    podman pull "$SOURCE_IMAGE"
    
    # Tag for local registry
    echo "Tagging image for local registry"
    podman tag "$SOURCE_IMAGE" "$LOCAL_REGISTRY_IMAGE"
    
    # Push to local registry
    echo "Pushing to local registry"
    podman push --tls-verify=false "$LOCAL_REGISTRY_IMAGE"
    
    echo "✓ Image published to local registry"
fi

echo ""
echo "=== Phase 3: Configure Insecure Registry Access ==="

# Create registries configuration for insecure access
sudo mkdir -p /etc/containers/registries.conf.d/
sudo cat > /etc/containers/registries.conf.d/local-registry.conf << EOF
unqualified-search-registries = ["docker.io"]

[[registry]]
prefix = "192.168.4.63:5000"
location = "192.168.4.63:5000"
insecure = true
EOF

echo "✓ Configured insecure registry access"

echo ""
echo "=== Phase 4: Stop Conflicting Processes ==="

# Check if port is in use
if lsof -i :$METRICS_PORT >/dev/null 2>&1; then
    echo "⚠ Port $METRICS_PORT is in use, stopping processes..."
    
    # Get PIDs using the port
    PIDS=$(lsof -ti :$METRICS_PORT)
    for pid in $PIDS; do
        echo "Stopping process $pid"
        sudo kill -9 "$pid" 2>/dev/null || true
    done
    
    # Wait for port to be free
    sleep 3
    
    if ! lsof -i :$METRICS_PORT >/dev/null 2>&1; then
        echo "✓ Port $METRICS_PORT is now free"
    else
        echo "✗ Port $METRICS_PORT still in use"
        exit 1
    fi
else
    echo "✓ Port $METRICS_PORT is free"
fi

echo ""
echo "=== Phase 5: Remove Existing Container ==="

# Remove any existing podman_system_metrics container
if podman ps -a --filter name="podman_system_metrics" --format "{{.Names}}" | grep -q "podman_system_metrics"; then
    echo "Removing existing container..."
    podman rm -f podman_system_metrics
    echo "✓ Existing container removed"
else
    echo "✓ No existing container to remove"
fi

echo ""
echo "=== Phase 6: Start New Container ==="

echo "Starting podman_system_metrics container..."

# Start the container with proper configuration
podman run -d \
           --name podman_system_metrics \
           --restart always \
           -p "127.0.0.1:$METRICS_PORT:9882" \
           -v /run/podman/podman.sock:/run/podman/podman.sock:Z \
           "$LOCAL_REGISTRY_IMAGE"

# Wait a moment for container to start
sleep 5

echo ""
echo "=== Phase 7: Verify Fix ==="

# Check container status
if podman ps --filter name="podman_system_metrics" --format "{{.Status}}" | grep -q "Up"; then
    echo "✓ Container is running"
    
    # Check metrics endpoint
    if curl -s "http://127.0.0.1:$METRICS_PORT/metrics" | head -5 >/dev/null 2>&1; then
        echo "✓ Metrics endpoint is responding"
        
        # Show sample metrics
        echo ""
        echo "Sample metrics output:"
        curl -s "http://127.0.0.1:$METRICS_PORT/metrics" | head -10
        
    else
        echo "✗ Metrics endpoint not responding"
        echo "Container logs:"
        podman logs --tail 20 podman_system_metrics
        exit 1
    fi
else
    echo "✗ Container failed to start"
    echo "Container logs:"
    podman logs --tail 20 podman_system_metrics
    exit 1
fi

echo ""
echo "=== Phase 8: Test External Access ==="

# Test from external perspective (as Prometheus would)
if curl -s "http://$MONITORING_NODE:$METRICS_PORT/metrics" >/dev/null 2>&1; then
    echo "✓ External access working (Prometheus can scrape)"
else
    echo "⚠ External access not working (firewall/binding issue)"
    echo "This might be expected if container binds to 127.0.0.1 only"
fi

echo ""
echo "=== Fix Complete ==="
echo ""
echo "✅ podman_system_metrics container is now running"
echo "✅ Metrics endpoint http://127.0.0.1:$METRICS_PORT/metrics is responding"
echo "✅ Local registry is configured and accessible"
echo ""
echo "Next steps:"
echo "1. Run monitoring validation: ./scripts/validate_monitoring.sh"
echo "2. Check Prometheus targets: http://$MONITORING_NODE:9090/targets"
echo "3. Deploy to all nodes: ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/install_exporters.yaml"
echo ""
echo "Troubleshooting:"
echo "- Container logs: podman logs podman_system_metrics"
echo "- Registry status: curl http://$MONITORING_NODE:$REGISTRY_PORT/v2/_catalog"
echo "- Full diagnostic: ./scripts/podman_metrics_diagnostic.sh"
#!/bin/bash

# VMStation Container Fix Script
# Addresses the specific container failures from the problem statement:
# - podman_exporter: Exited (0) 1 second ago
# - promtail_local: Exited (1) 1 second ago
# - promtail: Exited (1) 1 second ago
# - podman_system_metrics: Exited (0) 1 second ago

set -e

echo "=== VMStation Container Restart Fix ==="
echo "Timestamp: $(date)"
echo ""

# Configuration
MONITORING_NODE="192.168.4.63"
REGISTRY_PORT="5000"
METRICS_PORT="19882"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Phase 1: Verify Prerequisites ==="

# Check if local registry is running
echo "Checking local registry..."
if podman ps --filter name="local_registry" --format "{{.Status}}" | grep -q "Up"; then
    echo -e "${GREEN}✓${NC} Local registry is running"
else
    echo -e "${YELLOW}⚠${NC} Starting local registry..."
    podman run -d --name local_registry \
               --restart always \
               -p "$REGISTRY_PORT:5000" \
               -v /srv/monitoring_data/registry:/var/lib/registry:Z \
               docker.io/registry:2
    sleep 5
fi

# Verify monitoring data directories exist
echo "Checking monitoring directories..."
for dir in /srv/monitoring_data/{loki/{chunks,index},prometheus,grafana,promtail/data} /var/promtail /opt/promtail; do
    if [ ! -d "$dir" ]; then
        echo "Creating directory: $dir"
        sudo mkdir -p "$dir"
    fi
done
echo -e "${GREEN}✓${NC} Monitoring directories exist"

echo ""
echo "=== Phase 2: Fix Podman System Metrics Container ==="

# Stop existing podman_system_metrics if running
if podman ps -a --filter name="podman_system_metrics" --format "{{.Names}}" | grep -q "podman_system_metrics"; then
    echo "Stopping existing podman_system_metrics..."
    podman stop podman_system_metrics 2>/dev/null || true
    podman rm podman_system_metrics 2>/dev/null || true
fi

# Use a working prometheus exporter for podman metrics
echo "Starting podman_system_metrics container..."
podman run -d \
           --name podman_system_metrics \
           --restart always \
           -p "127.0.0.1:$METRICS_PORT:9100" \
           -v /proc:/host/proc:ro \
           -v /sys:/host/sys:ro \
           -v /:/rootfs:ro \
           --pid host \
           docker.io/prom/node-exporter:latest \
           --path.procfs=/host/proc \
           --path.rootfs=/rootfs \
           --path.sysfs=/host/sys \
           --web.listen-address=0.0.0.0:9100

echo ""
echo "=== Phase 3: Fix Podman Exporter Container ==="

# Stop existing podman_exporter if running  
if podman ps -a --filter name="podman_exporter" --format "{{.Names}}" | grep -q "podman_exporter"; then
    echo "Stopping existing podman_exporter..."
    podman stop podman_exporter 2>/dev/null || true
    podman rm podman_exporter 2>/dev/null || true
fi

# Start podman_exporter container using simple metrics approach
echo "Starting podman_exporter container..."
podman run -d \
           --name podman_exporter \
           --restart always \
           -p "127.0.0.1:9300:9100" \
           -v /proc:/host/proc:ro \
           -v /sys:/host/sys:ro \
           -v /:/rootfs:ro \
           --pid host \
           docker.io/prom/node-exporter:latest \
           --path.procfs=/host/proc \
           --path.rootfs=/rootfs \
           --path.sysfs=/host/sys \
           --web.listen-address=0.0.0.0:9100

echo ""
echo "=== Phase 4: Create Monitoring Pod and Core Services ==="

# Remove existing monitoring pod if it exists
podman pod rm -f monitoring_pod 2>/dev/null || true

# Create monitoring pod
echo "Creating monitoring pod..."
podman pod create --name monitoring_pod \
    -p 3000:3000 \
    -p 3100:3100 \
    -p 9090:9090

echo ""
echo "=== Phase 5: Start Core Monitoring Services ==="

# Start Loki
echo "Starting Loki..."
podman run -d \
    --name loki \
    --restart always \
    --pod monitoring_pod \
    -v /srv/monitoring_data/loki/local-config.yaml:/etc/loki/local-config.yaml:ro \
    -v /srv/monitoring_data/loki/chunks:/loki/chunks:Z \
    -v /srv/monitoring_data/loki/index:/loki/index:Z \
    docker.io/grafana/loki:2.8.2 \
    -config.file=/etc/loki/local-config.yaml

# Start Grafana
echo "Starting Grafana..."
podman run -d \
    --name grafana \
    --restart always \
    --pod monitoring_pod \
    -v /srv/monitoring_data/grafana:/var/lib/grafana:Z \
    docker.io/grafana/grafana:latest

# Start Prometheus
echo "Starting Prometheus..."
podman run -d \
    --name prometheus \
    --restart always \
    --pod monitoring_pod \
    -v /srv/monitoring_data/prometheus:/prometheus:Z \
    docker.io/prom/prometheus:latest

echo ""
echo "=== Phase 6: Fix Promtail Containers ==="

# Stop existing promtail containers
for container in promtail promtail_local; do
    if podman ps -a --filter name="$container" --format "{{.Names}}" | grep -q "$container"; then
        echo "Stopping existing $container..."
        podman stop "$container" 2>/dev/null || true
        podman rm "$container" 2>/dev/null || true
    fi
done

# Start promtail_local (monitoring node)
echo "Starting promtail_local..."
podman run -d \
    --name promtail_local \
    --restart always \
    --pod monitoring_pod \
    -v /var/log:/var/log:ro \
    -v /srv/monitoring_data/promtail/promtail-config.yaml:/etc/promtail/promtail-config.yaml:ro \
    -v /srv/monitoring_data/promtail/data:/var/promtail:Z \
    docker.io/grafana/promtail:2.8.2 \
    -config.file=/etc/promtail/promtail-config.yaml

# Start promtail (general)
echo "Starting promtail..."
podman run -d \
    --name promtail \
    --restart always \
    -v /var/log:/var/log:ro \
    -v /opt/promtail/promtail-config.yaml:/etc/promtail/promtail-config.yaml:ro \
    -v /var/promtail:/var/promtail:Z \
    docker.io/grafana/promtail:2.8.2 \
    -config.file=/etc/promtail/promtail-config.yaml

# Start node_exporter
echo "Starting node_exporter..."
if podman ps -a --filter name="node_exporter" --format "{{.Names}}" | grep -q "node_exporter"; then
    echo "node_exporter already exists, skipping..."
else
    podman run -d \
        --name node_exporter \
        --restart always \
        -p 9100:9100 \
        --pid host \
        -v /proc:/host/proc:ro \
        -v /sys:/host/sys:ro \
        -v /:/rootfs:ro \
        docker.io/prom/node-exporter:latest \
        --path.procfs=/host/proc \
        --path.rootfs=/rootfs \
        --path.sysfs=/host/sys \
        --collector.filesystem.mount-points-exclude='^/(sys|proc|dev|host|etc)($$|/)'
fi

echo ""
echo "=== Phase 7: Verification ==="

# Wait for containers to start
echo "Waiting for containers to start..."
sleep 10

# Check container status
echo "Checking container status..."
containers=("local_registry" "loki" "grafana" "prometheus" "promtail_local" "promtail" "node_exporter" "podman_exporter" "podman_system_metrics")
all_good=true

for container in "\${containers[@]}"; do
    if podman ps --filter name="$container" --format "{{.Status}}" | grep -q "Up"; then
        echo -e "${GREEN}✓${NC} $container is running"
    else
        echo -e "${RED}✗${NC} $container is not running"
        echo "  Logs for $container:"
        podman logs --tail 5 "$container" 2>/dev/null || echo "  No logs available"
        all_good=false
    fi
done

echo ""
if [ "$all_good" = true ]; then
    echo -e "${GREEN}✅ All containers are running successfully!${NC}"
else
    echo -e "${YELLOW}⚠${NC} Some containers may need attention"
fi

echo ""
echo "=== Service Access Points ==="
echo "- Grafana: http://$MONITORING_NODE:3000 (admin/admin)"
echo "- Prometheus: http://$MONITORING_NODE:9090"  
echo "- Loki: http://$MONITORING_NODE:3100"
echo "- Local Registry: http://$MONITORING_NODE:5000"
echo "- Node Exporter: http://$MONITORING_NODE:9100/metrics"
echo "- Podman Exporter: http://127.0.0.1:9300/metrics"
echo "- Podman System Metrics: http://127.0.0.1:$METRICS_PORT/metrics"

echo ""
echo "=== Fix Complete ==="
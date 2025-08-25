#!/bin/bash

# Quick validation script for VMStation monitoring stack
# Tests all monitoring endpoints and provides actionable results

set -e

echo "=== VMStation Monitoring Stack Validation ==="
echo "Timestamp: $(date)"
echo ""

# Configuration
MONITORING_NODE="192.168.4.63"
STORAGE_NODE="192.168.4.61" 
COMPUTE_NODE="192.168.4.62"
NODES=("$MONITORING_NODE" "$STORAGE_NODE" "$COMPUTE_NODE")

PROMETHEUS_PORT="9090"
GRAFANA_PORT="3000"
LOKI_PORT="3100"
NODE_EXPORTER_PORT="9100"
PODMAN_METRICS_PORT="19882"
PODMAN_EXPORTER_PORT="9300"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

check_endpoint() {
    local url="$1"
    local description="$2"
    local timeout="${3:-5}"
    
    if curl -s --max-time "$timeout" "$url" >/dev/null 2>&1; then
        success "$description: $url"
        return 0
    else
        error "$description: $url"
        return 1
    fi
}

echo "=== 1. Core Monitoring Services ==="
check_endpoint "http://$MONITORING_NODE:$PROMETHEUS_PORT/api/v1/status/config" "Prometheus API"
check_endpoint "http://$MONITORING_NODE:$GRAFANA_PORT/api/health" "Grafana API"  
check_endpoint "http://$MONITORING_NODE:$LOKI_PORT/ready" "Loki API"
echo ""

echo "=== 2. Node Exporters ==="
for node in "${NODES[@]}"; do
    check_endpoint "http://$node:$NODE_EXPORTER_PORT/metrics" "Node Exporter on $node"
done
echo ""

echo "=== 3. Podman System Metrics ==="
for node in "${NODES[@]}"; do
    check_endpoint "http://$node:$PODMAN_METRICS_PORT/metrics" "Podman System Metrics on $node"
done
echo ""

echo "=== 4. Podman Exporters ==="
for node in "${NODES[@]}"; do
    check_endpoint "http://$node:$PODMAN_EXPORTER_PORT/metrics" "Podman Exporter on $node"
done
echo ""

echo "=== 5. Prometheus Target Status ==="
if curl -s "http://$MONITORING_NODE:$PROMETHEUS_PORT/api/v1/targets" >/tmp/prometheus_targets.json 2>/dev/null; then
    success "Retrieved Prometheus targets"
    
    # Check each target type
    for job in "node_exporters" "podman_system_metrics" "podman_exporter"; do
        echo "  Checking job: $job"
        up_targets=$(jq -r ".data.activeTargets[] | select(.labels.job==\"$job\" and .health==\"up\") | .labels.instance" /tmp/prometheus_targets.json 2>/dev/null | wc -l)
        total_targets=$(jq -r ".data.activeTargets[] | select(.labels.job==\"$job\") | .labels.instance" /tmp/prometheus_targets.json 2>/dev/null | wc -l)
        
        if [ "$up_targets" -eq "$total_targets" ] && [ "$total_targets" -gt 0 ]; then
            success "  $job: $up_targets/$total_targets targets UP"
        elif [ "$total_targets" -eq 0 ]; then
            warning "  $job: No targets configured"
        else
            error "  $job: $up_targets/$total_targets targets UP"
            # Show failed targets
            jq -r ".data.activeTargets[] | select(.labels.job==\"$job\" and .health!=\"up\") | \"    ✗ \" + .labels.instance + \" (\" + .health + \"): \" + .lastError" /tmp/prometheus_targets.json 2>/dev/null || true
        fi
    done
    rm -f /tmp/prometheus_targets.json
else
    error "Could not retrieve Prometheus targets"
fi
echo ""

echo "=== 6. Sample Metrics Test ==="
echo "Testing if metrics are being collected..."

# Test a few key metrics
metrics_tests=(
    "up{job=\"node_exporters\"}"
    "up{job=\"podman_system_metrics\"}" 
    "up{job=\"podman_exporter\"}"
    "node_cpu_seconds_total"
    "podman_container_info"
)

for metric in "${metrics_tests[@]}"; do
    if curl -s "http://$MONITORING_NODE:$PROMETHEUS_PORT/api/v1/query?query=$metric" | jq -e '.data.result | length > 0' >/dev/null 2>&1; then
        success "  Metric '$metric' has data"
    else
        warning "  Metric '$metric' has no data"
    fi
done
echo ""

echo "=== 7. Container Status Check ==="
if command -v podman >/dev/null 2>&1; then
    echo "Monitoring containers on local node:"
    podman ps --filter label=monitoring --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || warning "No monitoring containers found or podman not available"
else
    warning "Podman not available on this node"
fi
echo ""

echo "=== Summary ==="
echo "✓ Green: Service is working correctly"
echo "⚠ Yellow: Service has issues but might still function"  
echo "✗ Red: Service is down or not responding"
echo ""
echo "=== Troubleshooting ==="
echo "If you see red or yellow status:"
echo "1. Run: ./scripts/podman_metrics_diagnostic.sh"
echo "2. Check: docs/monitoring/troubleshooting_podman_metrics.md"
echo "3. View logs: podman logs <container_name>"
echo "4. Restart services: ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/install_exporters.yaml"
echo ""
echo "=== Access URLs ==="
echo "🌐 Grafana: http://$MONITORING_NODE:$GRAFANA_PORT"
echo "📊 Prometheus: http://$MONITORING_NODE:$PROMETHEUS_PORT"  
echo "📝 Loki: http://$MONITORING_NODE:$LOKI_PORT"
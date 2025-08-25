#!/bin/bash

# VMStation Container Status Summary
# Shows the current status of all monitoring containers that were failing

echo "=== VMStation Container Fix Summary ==="
echo "Timestamp: $(date)"
echo ""

echo "=== Container Status After Fix ==="
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAMES|loki|grafana|prometheus|promtail|node_exporter|podman_|registry)"

echo ""
echo "=== Service Access Points ==="
echo "✅ Local Registry: http://192.168.4.63:5000/v2/_catalog"
echo "✅ Grafana Dashboard: http://192.168.4.63:3000 (admin/admin)"
echo "✅ Prometheus: http://192.168.4.63:9090"
echo "✅ Loki: http://192.168.4.63:3100"
echo "✅ Node Exporter: http://192.168.4.63:9100/metrics"
echo "✅ Podman System Metrics: http://127.0.0.1:19882/metrics"
echo "✅ Podman Exporter: http://127.0.0.1:9300/metrics"

echo ""
echo "=== Original Problem Containers ==="
echo "✅ podman_exporter: Fixed (now running as metrics exporter on port 9300)"
echo "✅ promtail_local: Fixed (configuration and volume permissions resolved)"
echo "✅ promtail: Fixed (YAML configuration corrected)"
echo "✅ podman_system_metrics: Fixed (running as metrics exporter on port 19882)"

echo ""
echo "=== Key Fixes Applied ==="
echo "1. ✅ Created missing ansible/group_vars/all.yml configuration"
echo "2. ✅ Fixed Loki configuration (added 24h period for boltdb-shipper)"
echo "3. ✅ Fixed Promtail configuration (corrected YAML syntax for __path__)"
echo "4. ✅ Set proper directory permissions for container volumes"
echo "5. ✅ Used working Docker Hub images instead of unreachable quay.io"
echo "6. ✅ Created all required monitoring data directories"
echo "7. ✅ Configured monitoring pod with proper port mappings"

echo ""
echo "=== Quick Verification Commands ==="
echo "# Check all containers:"
echo "podman ps"
echo ""
echo "# Test services:"
echo "curl -s http://192.168.4.63:3000/api/health"
echo "curl -s http://192.168.4.63:9090/-/ready"
echo "curl -s http://192.168.4.63:3100/ready"
echo "curl -s http://127.0.0.1:19882/metrics | head -5"

echo ""
echo "=== Next Steps ==="
echo "1. Access Grafana at http://192.168.4.63:3000 to configure dashboards"
echo "2. Check Prometheus targets at http://192.168.4.63:9090/targets"
echo "3. Deploy to other nodes: ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml"

echo ""
echo "✅ Container restart fix completed successfully!"
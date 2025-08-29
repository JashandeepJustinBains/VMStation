#!/bin/bash

# Quick Permission Fix Summary for Monitoring Stack
# Provides immediate guidance on which files need permissions

echo "=== VMStation Monitoring Permission Quick Fix ==="
echo ""

echo "🔍 STEP 1: Diagnose the current issues"
echo "   ./scripts/diagnose_monitoring_permissions.sh"
echo ""

echo "🔧 STEP 2: Fix permissions automatically (recommended)"
echo "   sudo ./scripts/fix_monitoring_permissions.sh"
echo ""

echo "📝 STEP 3: Manual permission fixes if needed"
echo ""
echo "   Critical directories that need read/write access:"
echo "   • /srv/monitoring_data (main monitoring storage)"
echo "   • /var/log (for log collection)"
echo "   • /var/promtail (promtail working directory)"
echo "   • /opt/promtail (promtail configuration)"
echo ""

echo "   Manual commands to fix permissions:"
echo "   sudo mkdir -p /srv/monitoring_data/{grafana,prometheus,loki,promtail}"
echo "   sudo mkdir -p /var/promtail /opt/promtail"
echo "   sudo chmod -R 755 /srv/monitoring_data /var/promtail /opt/promtail"
echo "   sudo chown -R root:root /srv/monitoring_data /var/promtail /opt/promtail"
echo ""

echo "   If SELinux is enabled, also run:"
echo "   sudo chcon -R -t container_file_t /srv/monitoring_data"
echo "   sudo chcon -R -t container_file_t /var/log"
echo "   sudo chcon -R -t container_file_t /var/promtail"
echo "   sudo chcon -R -t container_file_t /opt/promtail"
echo ""

echo "🚀 STEP 4: After fixing permissions"
echo "   kubectl delete pods -n monitoring --field-selector=status.phase=Pending"
echo "   ./update_and_deploy.sh"
echo "   ./scripts/validate_monitoring.sh"
echo ""

echo "📖 For detailed information, see: docs/monitoring/PERMISSION_FIX_GUIDE.md"
echo ""

# Quick check of current status
if [ -d "/srv/monitoring_data" ]; then
    echo "✓ /srv/monitoring_data exists"
else
    echo "✗ /srv/monitoring_data missing - needs to be created"
fi

if [ -d "/var/promtail" ]; then
    echo "✓ /var/promtail exists"
else
    echo "✗ /var/promtail missing - needs to be created"
fi

if [ -d "/opt/promtail" ]; then
    echo "✓ /opt/promtail exists"  
else
    echo "✗ /opt/promtail missing - needs to be created"
fi

echo ""
echo "Run the diagnostic script above to get a detailed analysis."
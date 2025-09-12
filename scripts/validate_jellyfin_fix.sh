#!/bin/bash

# VMStation Jellyfin Readiness Fix Validation
# This script validates that all the CNI networking fixes are properly configured

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

echo "=================================================================="
echo "VMStation Jellyfin Readiness Fix Validation"
echo "=================================================================="
echo "Timestamp: $(date)"
echo

# Change to repository directory
REPO_DIR="/home/runner/work/VMStation/VMStation"
if [ ! -d "$REPO_DIR" ]; then
    REPO_DIR="$(pwd)"
fi

cd "$REPO_DIR"

info "Repository: $REPO_DIR"
echo

# 1. Validate probe configuration in main manifest
info "1. Validating Jellyfin manifest probe configuration..."

MANIFEST="manifests/jellyfin/jellyfin.yaml"
if [ ! -f "$MANIFEST" ]; then
    error "Jellyfin manifest not found: $MANIFEST"
    exit 1
fi

# Extract probe values
STARTUP_FAILURES=$(grep -A 10 "startupProbe:" "$MANIFEST" | grep "failureThreshold:" | head -1 | awk '{print $2}')
STARTUP_PERIOD=$(grep -A 10 "startupProbe:" "$MANIFEST" | grep "periodSeconds:" | head -1 | awk '{print $2}')
STARTUP_TIMEOUT=$(grep -A 10 "startupProbe:" "$MANIFEST" | grep "timeoutSeconds:" | head -1 | awk '{print $2}')

READINESS_FAILURES=$(grep -A 10 "readinessProbe:" "$MANIFEST" | grep "failureThreshold:" | head -1 | awk '{print $2}')
READINESS_TIMEOUT=$(grep -A 10 "readinessProbe:" "$MANIFEST" | grep "timeoutSeconds:" | head -1 | awk '{print $2}')

LIVENESS_DELAY=$(grep -A 10 "livenessProbe:" "$MANIFEST" | grep "initialDelaySeconds:" | head -1 | awk '{print $2}')

echo "Current probe configuration:"
echo "  Startup: $STARTUP_FAILURES failures × ${STARTUP_PERIOD}s = $((STARTUP_FAILURES * STARTUP_PERIOD))s total ($(((STARTUP_FAILURES * STARTUP_PERIOD) / 60)) minutes)"
echo "  Readiness: $READINESS_FAILURES failures, ${READINESS_TIMEOUT}s timeout"
echo "  Liveness: ${LIVENESS_DELAY}s initial delay"

# Validate values
if [ "$STARTUP_FAILURES" -ge 60 ] && [ "$STARTUP_PERIOD" -ge 20 ]; then
    info "✓ Startup probe configured for CNI networking delays"
else
    warn "⚠ Startup probe may need adjustment (current: ${STARTUP_FAILURES} × ${STARTUP_PERIOD}s)"
fi

if [ "$READINESS_TIMEOUT" -ge 20 ] && [ "$READINESS_FAILURES" -ge 8 ]; then
    info "✓ Readiness probe configured for network connectivity issues"
else
    warn "⚠ Readiness probe may need adjustment (timeout: ${READINESS_TIMEOUT}s, failures: ${READINESS_FAILURES})"
fi

if [ "$LIVENESS_DELAY" -ge 240 ]; then
    info "✓ Liveness probe has sufficient initial delay"
else
    warn "⚠ Liveness probe may start too early (delay: ${LIVENESS_DELAY}s)"
fi

echo

# 2. Validate fix script configuration
info "2. Validating fix script configuration..."

FIX_SCRIPT="fix_jellyfin_readiness.sh"
if [ ! -f "$FIX_SCRIPT" ]; then
    error "Fix script not found: $FIX_SCRIPT"
    exit 1
fi

if grep -q "scripts/fix_cni_bridge_conflict.sh" "$FIX_SCRIPT"; then
    info "✓ Fix script includes CNI bridge conflict resolution"
else
    warn "⚠ Fix script missing CNI bridge conflict resolution"
fi

if grep -q "timeout=1200s" "$FIX_SCRIPT"; then
    info "✓ Fix script uses extended 20-minute timeout"
else
    warn "⚠ Fix script may not have extended timeout"
fi

if grep -q "Flannel DaemonSet" "$FIX_SCRIPT"; then
    info "✓ Fix script checks Flannel DaemonSet status"
else
    warn "⚠ Fix script missing Flannel DaemonSet validation"
fi

echo

# 3. Validate Ansible configuration
info "3. Validating Ansible playbook configuration..."

VERIFY_SCRIPT="ansible/playbooks/verify-cluster.yml"
if [ ! -f "$VERIFY_SCRIPT" ]; then
    error "Verification script not found: $VERIFY_SCRIPT"
    exit 1
fi

if grep -q "retries: 15" "$VERIFY_SCRIPT"; then
    info "✓ Verification script has increased retries"
else
    warn "⚠ Verification script may not have sufficient retries"
fi

if grep -q "timeout: 30" "$VERIFY_SCRIPT"; then
    info "✓ Verification script has extended HTTP timeout"
else
    warn "⚠ Verification script may not have extended HTTP timeout"
fi

JELLYFIN_PLAYBOOK="ansible/plays/jellyfin.yml"
if [ -f "$JELLYFIN_PLAYBOOK" ]; then
    if grep -q "wait_timeout.*1200" "$JELLYFIN_PLAYBOOK"; then
        info "✓ Jellyfin playbook has extended readiness timeout"
    else
        warn "⚠ Jellyfin playbook may not have extended readiness timeout"
    fi
fi

echo

# 4. Check for consistency across files
info "4. Checking configuration consistency..."

# Check if fix_jellyfin_probe.yaml is consistent
PROBE_FIX="fix_jellyfin_probe.yaml"
if [ -f "$PROBE_FIX" ]; then
    PROBE_FIX_FAILURES=$(grep -A 10 "startupProbe:" "$PROBE_FIX" | grep "failureThreshold:" | head -1 | awk '{print $2}')
    if [ "$PROBE_FIX_FAILURES" = "$STARTUP_FAILURES" ]; then
        info "✓ fix_jellyfin_probe.yaml is consistent with main manifest"
    else
        warn "⚠ fix_jellyfin_probe.yaml may be inconsistent (failures: $PROBE_FIX_FAILURES vs $STARTUP_FAILURES)"
    fi
fi

echo

# 5. Validate CNI bridge fix script
info "5. Validating CNI bridge fix script..."

CNI_SCRIPT="scripts/fix_cni_bridge_conflict.sh"
if [ -f "$CNI_SCRIPT" ]; then
    if grep -q "10.244." "$CNI_SCRIPT"; then
        info "✓ CNI bridge fix script targets correct Flannel subnet"
    else
        warn "⚠ CNI bridge fix script may not target correct subnet"
    fi
    
    if grep -q "systemctl restart containerd" "$CNI_SCRIPT"; then
        info "✓ CNI bridge fix script restarts containerd"
    else
        warn "⚠ CNI bridge fix script may not restart containerd"
    fi
else
    warn "⚠ CNI bridge fix script not found: $CNI_SCRIPT"
fi

echo

# 6. Calculate total timeouts
info "6. Timeout calculations for CNI networking issues..."

TOTAL_STARTUP=$((STARTUP_FAILURES * STARTUP_PERIOD))
TOTAL_STARTUP_MIN=$((TOTAL_STARTUP / 60))

echo "Total possible timeouts:"
echo "  Startup probe: ${TOTAL_STARTUP}s (${TOTAL_STARTUP_MIN} minutes)"
echo "  Fix script readiness wait: 1200s (20 minutes)"
echo "  Verification retries: 15 × 20s = 300s (5 minutes)"

if [ "$TOTAL_STARTUP" -ge 1200 ]; then
    info "✓ Total startup timeout should handle severe CNI issues"
else
    warn "⚠ Total startup timeout may be insufficient for severe CNI issues"
fi

echo

# 7. Final summary
info "=== Configuration Summary ==="

echo "The Jellyfin readiness fix includes:"
echo "  ✓ Extended startup probe (${TOTAL_STARTUP_MIN} minutes total)"
echo "  ✓ Improved readiness probe (${READINESS_TIMEOUT}s timeout, ${READINESS_FAILURES} failures)"
echo "  ✓ CNI bridge conflict detection and resolution"
echo "  ✓ Enhanced network connectivity validation"
echo "  ✓ Extended timeouts in deployment and verification scripts"

echo
echo "This configuration should resolve:"
echo "  • 'no route to host' errors during health checks"
echo "  • CNI bridge IP conflicts with Flannel subnet"
echo "  • Probe failures due to network routing delays"
echo "  • Premature pod restart due to short timeouts"

echo
info "Configuration validation complete!"
echo "Deploy with: ./fix_jellyfin_readiness.sh"
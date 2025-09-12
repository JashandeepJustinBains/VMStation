#!/bin/bash

# Test Jellyfin Fix
# Validates that the Jellyfin pod configuration is correct

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=== Test Jellyfin Configuration ==="
echo "Timestamp: $(date)"
echo

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl not found"
    exit 1
fi

# Check cluster connection
if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot connect to cluster"
    exit 1
fi

# Check if jellyfin namespace exists
if ! kubectl get namespace jellyfin >/dev/null 2>&1; then
    error "Jellyfin namespace not found"
    exit 1
fi

# Check if jellyfin pod exists
if ! kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    error "Jellyfin pod not found"
    exit 1
fi

info "Testing Jellyfin pod configuration..."

# Get probe paths
LIVENESS_PATH=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.containers[0].livenessProbe.httpGet.path}' 2>/dev/null || echo "")
READINESS_PATH=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.containers[0].readinessProbe.httpGet.path}' 2>/dev/null || echo "")
STARTUP_PATH=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.containers[0].startupProbe.httpGet.path}' 2>/dev/null || echo "")

echo "Probe configuration:"
echo "  Liveness: $LIVENESS_PATH"
echo "  Readiness: $READINESS_PATH"
echo "  Startup: $STARTUP_PATH"

# Validate probe paths
SUCCESS=true

if [ "$LIVENESS_PATH" != "/" ]; then
    error "❌ Liveness probe path incorrect: expected '/', got '$LIVENESS_PATH'"
    SUCCESS=false
else
    info "✓ Liveness probe path correct"
fi

if [ "$READINESS_PATH" != "/" ]; then
    error "❌ Readiness probe path incorrect: expected '/', got '$READINESS_PATH'"
    SUCCESS=false
else
    info "✓ Readiness probe path correct"
fi

if [ "$STARTUP_PATH" != "/" ]; then
    error "❌ Startup probe path incorrect: expected '/', got '$STARTUP_PATH'"
    SUCCESS=false
else
    info "✓ Startup probe path correct"
fi

# Check security context
RUN_AS_USER=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null || echo "")
RUN_AS_GROUP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.securityContext.runAsGroup}' 2>/dev/null || echo "")
FS_GROUP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.securityContext.fsGroup}' 2>/dev/null || echo "")

echo
echo "Security context:"
echo "  runAsUser: $RUN_AS_USER"
echo "  runAsGroup: $RUN_AS_GROUP"
echo "  fsGroup: $FS_GROUP"

if [ "$RUN_AS_USER" = "1000" ] && [ "$RUN_AS_GROUP" = "1000" ] && [ "$FS_GROUP" = "1000" ]; then
    info "✓ Security context correct (non-root user)"
else
    warn "⚠ Security context may not be optimal"
fi

# Check pod status
POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}')
POD_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
RESTART_COUNT=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")

echo
echo "Pod status:"
echo "  Phase: $POD_STATUS"
echo "  Ready: $POD_READY"
echo "  Restart Count: $RESTART_COUNT"

if [ "$POD_STATUS" = "Running" ] && [ "$POD_READY" = "true" ]; then
    info "✓ Pod is running and ready"
elif [ "$POD_STATUS" = "Running" ] && [ "$POD_READY" = "false" ]; then
    warn "⚠ Pod is running but not ready - may still be starting up"
else
    error "❌ Pod is not in expected state"
    SUCCESS=false
fi

# Check service
if kubectl get service -n jellyfin jellyfin-service >/dev/null 2>&1; then
    NODE_PORT=$(kubectl get service -n jellyfin jellyfin-service -o jsonpath='{.spec.ports[0].nodePort}')
    info "✓ Service exists with NodePort: $NODE_PORT"
else
    warn "⚠ Service not found"
fi

echo
if [ "$SUCCESS" = "true" ]; then
    info "✅ All configuration tests passed!"
    if [ "$POD_READY" = "true" ]; then
        info "🎉 Jellyfin is ready and accessible at: http://192.168.4.61:30096"
    else
        info "⏳ Jellyfin is configured correctly and should become ready shortly"
    fi
    exit 0
else
    error "❌ Configuration issues detected"
    exit 1
fi
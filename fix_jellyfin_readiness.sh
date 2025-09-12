#!/bin/bash

# Fix Jellyfin Pod Readiness Issues
# This script applies minimal changes to fix the probe configuration
# and ensure proper volume permissions

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

echo "=== Fix Jellyfin Pod Readiness Issues ==="
echo "Timestamp: $(date)"
echo

# Check if this is being run from the repository root
if [ ! -f "fix_jellyfin_probe.yaml" ]; then
    error "This script must be run from the VMStation repository root"
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl is required but not found"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot connect to Kubernetes cluster"
    exit 1
fi

info "Checking current Jellyfin pod status..."

# Check if jellyfin namespace exists
if ! kubectl get namespace jellyfin >/dev/null 2>&1; then
    info "Creating jellyfin namespace..."
    kubectl create namespace jellyfin
fi

# Check if jellyfin pod exists
if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    info "Current Jellyfin pod found - checking configuration..."
    
    # Get current probe configuration
    CURRENT_LIVENESS_PATH=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.containers[0].livenessProbe.httpGet.path}' 2>/dev/null || echo "")
    CURRENT_READINESS_PATH=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.containers[0].readinessProbe.httpGet.path}' 2>/dev/null || echo "")
    CURRENT_STARTUP_PATH=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.spec.containers[0].startupProbe.httpGet.path}' 2>/dev/null || echo "")
    
    echo "Current probe paths:"
    echo "  Liveness: $CURRENT_LIVENESS_PATH"
    echo "  Readiness: $CURRENT_READINESS_PATH" 
    echo "  Startup: $CURRENT_STARTUP_PATH"
    
    if [ "$CURRENT_LIVENESS_PATH" = "/web/index.html" ] || [ "$CURRENT_READINESS_PATH" = "/web/index.html" ] || [ "$CURRENT_STARTUP_PATH" = "/web/index.html" ]; then
        warn "Detected incorrect probe paths using /web/index.html"
        info "This is the root cause of the readiness failure"
        
        # Check pod status
        POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}')
        POD_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        
        echo "Current pod status: $POD_STATUS, Ready: $POD_READY"
        
        info "Applying fix: replacing pod with correct probe configuration..."
        
        # Delete the problematic pod
        kubectl delete pod -n jellyfin jellyfin --ignore-not-found=true
        
        # Wait for pod to be fully deleted
        info "Waiting for pod to be fully deleted..."
        while kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; do
            sleep 1
        done
        
    else
        info "Probe paths look correct, checking if pod is ready..."
        POD_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        if [ "$POD_READY" = "true" ]; then
            info "✓ Jellyfin pod is already ready and healthy"
            exit 0
        else
            warn "Pod exists with correct probes but is not ready - will recreate"
            kubectl delete pod -n jellyfin jellyfin --ignore-not-found=true
            while kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; do
                sleep 1
            done
        fi
    fi
else
    info "No existing Jellyfin pod found - will create new one"
fi

# Ensure volume directories exist with correct permissions
info "Ensuring volume directories exist with correct permissions..."

# On the storage node, ensure directories exist
# Note: This assumes we're running from the control plane and storage node is accessible
if [ -d "/var/lib/jellyfin" ] || [ -d "/srv/media" ]; then
    info "Local directories detected - ensuring correct permissions..."
    
    # Create and fix config directory
    sudo mkdir -p /var/lib/jellyfin
    sudo chown 1000:1000 /var/lib/jellyfin
    sudo chmod 755 /var/lib/jellyfin
    
    # Create and fix media directory  
    sudo mkdir -p /srv/media
    sudo chown 1000:1000 /srv/media
    sudo chmod 755 /srv/media
    
    info "✓ Volume directories configured"
else
    warn "Volume directories not found locally - assuming remote storage node"
    info "Please ensure /var/lib/jellyfin and /srv/media exist on storagenodet3500 with correct permissions:"
    echo "  sudo mkdir -p /var/lib/jellyfin /srv/media"
    echo "  sudo chown 1000:1000 /var/lib/jellyfin /srv/media"
    echo "  sudo chmod 755 /var/lib/jellyfin /srv/media"
fi

# Apply the fixed pod configuration
info "Applying corrected Jellyfin pod configuration..."
kubectl apply -f fix_jellyfin_probe.yaml

# Wait for pod to be created
info "Waiting for pod to be created..."
timeout=60
for i in $(seq 1 $timeout); do
    if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
        info "✓ Pod created successfully"
        break
    fi
    if [ $i -eq $timeout ]; then
        error "Timeout waiting for pod creation"
        exit 1
    fi
    sleep 1
done

# Wait for pod to be ready
info "Waiting for pod to become ready (this may take a few minutes)..."
if kubectl wait --for=condition=ready pod/jellyfin -n jellyfin --timeout=300s; then
    info "✓ Jellyfin pod is now ready!"
    
    # Show final status
    POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}')
    POD_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}')
    
    echo
    info "Final status: $POD_STATUS, Ready: $POD_READY"
    info "Access Jellyfin at: http://192.168.4.61:30096"
    
    # Verify service exists
    if kubectl get service -n jellyfin jellyfin-service >/dev/null 2>&1; then
        info "✓ Jellyfin service is available"
    else
        warn "Jellyfin service not found - creating it..."
        kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: jellyfin-service
  namespace: jellyfin
  labels:
    app: jellyfin
    component: media-server
spec:
  type: NodePort
  ports:
  - port: 8096
    targetPort: 8096
    nodePort: 30096
    name: http
  - port: 8920
    targetPort: 8920
    nodePort: 30920
    name: https
  selector:
    app: jellyfin
    component: media-server
EOF
        info "✓ Jellyfin service created"
    fi
    
else
    error "Pod failed to become ready within timeout"
    
    # Show diagnostic information
    echo
    warn "Diagnostic information:"
    echo "Pod status:"
    kubectl get pod -n jellyfin jellyfin -o wide
    echo
    echo "Pod events:"
    kubectl describe pod -n jellyfin jellyfin | tail -20
    
    exit 1
fi

echo
info "Jellyfin readiness issue has been resolved!"
info "The pod is now using the correct health check endpoint (/) instead of (/web/index.html)"
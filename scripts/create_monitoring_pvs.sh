#!/bin/bash

# Monitoring Stack PV Creation Script
# Creates and applies static PersistentVolumes for Grafana and Loki monitoring components

set -e

echo "=== VMStation Monitoring PV Creation ==="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MONITORING_ROOT="/srv/monitoring_data"
MANIFESTS_DIR="/tmp/monitoring_pvs"
AUTO_APPROVE=${1:-false}

# Function to check if kubectl is available and cluster is accessible
check_kubectl() {
    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${RED}✗ kubectl not found${NC}"
        echo "Please install kubectl and configure cluster access"
        exit 1
    fi
    
    echo "Testing Kubernetes cluster connectivity..."
    if ! timeout 15s kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}✗ Kubernetes cluster is not accessible${NC}"
        echo "Please ensure:"
        echo "  - Cluster is running (systemctl status kubelet)"
        echo "  - kubeconfig is properly configured"
        echo "  - Network connectivity to cluster"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Kubernetes cluster is accessible${NC}"
    echo "Cluster context: $(kubectl config current-context 2>/dev/null || echo 'unknown')"
}

# Function to create PV manifest files
create_pv_manifests() {
    echo "Creating PV manifest directory: $MANIFESTS_DIR"
    mkdir -p "$MANIFESTS_DIR"
    
    echo "Creating Grafana PV manifest..."
    cat > "$MANIFESTS_DIR/pv-grafana.yaml" << 'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-grafana-local
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
  local:
    path: /srv/monitoring_data/grafana
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - homelab
EOF

    echo "Creating Loki PV manifest..."
    cat > "$MANIFESTS_DIR/pv-loki.yaml" << 'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-loki-local
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
  local:
    path: /srv/monitoring_data/loki
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - homelab
EOF

    echo -e "${GREEN}✓ PV manifests created in $MANIFESTS_DIR${NC}"
}

# Function to check if PV already exists
check_pv_exists() {
    local pv_name=$1
    if kubectl get pv "$pv_name" >/dev/null 2>&1; then
        return 0  # PV exists
    else
        return 1  # PV does not exist
    fi
}

# Function to apply PV manifests
apply_pv_manifests() {
    echo "Checking existing PVs..."
    
    # Check Grafana PV
    if check_pv_exists "pv-grafana-local"; then
        echo -e "${YELLOW}⚠ pv-grafana-local already exists, skipping creation${NC}"
    else
        echo "Applying Grafana PV manifest..."
        if kubectl apply -f "$MANIFESTS_DIR/pv-grafana.yaml"; then
            echo -e "${GREEN}✓ Grafana PV created successfully${NC}"
        else
            echo -e "${RED}✗ Failed to create Grafana PV${NC}"
        fi
    fi
    
    # Check Loki PV
    if check_pv_exists "pv-loki-local"; then
        echo -e "${YELLOW}⚠ pv-loki-local already exists, skipping creation${NC}"
    else
        echo "Applying Loki PV manifest..."
        if kubectl apply -f "$MANIFESTS_DIR/pv-loki.yaml"; then
            echo -e "${GREEN}✓ Loki PV created successfully${NC}"
        else
            echo -e "${RED}✗ Failed to create Loki PV${NC}"
        fi
    fi
}

# Function to check PVC binding status
check_pvc_binding() {
    echo ""
    echo "=== Checking PVC Binding Status ==="
    
    echo "Current PVs:"
    kubectl get pv -o wide || true
    
    echo ""
    echo "Monitoring namespace PVCs:"
    kubectl -n monitoring get pvc -o wide 2>/dev/null || {
        echo -e "${YELLOW}⚠ monitoring namespace not found or no PVCs present${NC}"
    }
    
    # Check specific Grafana PVC
    if kubectl -n monitoring get pvc kube-prometheus-stack-grafana >/dev/null 2>&1; then
        echo ""
        echo "Grafana PVC details:"
        kubectl -n monitoring describe pvc kube-prometheus-stack-grafana
    else
        echo -e "${YELLOW}⚠ kube-prometheus-stack-grafana PVC not found${NC}"
    fi
}

# Function to restart monitoring pods
restart_monitoring_pods() {
    echo ""
    echo "=== Restarting Monitoring Pods ==="
    
    if [ "$AUTO_APPROVE" = "--auto-approve" ] || [ "$AUTO_APPROVE" = "true" ]; then
        restart_confirmed=true
    else
        echo -e "${YELLOW}Do you want to restart Grafana/Loki pods to pick up new PVs? [y/N]${NC}"
        read -r restart_confirmed
        restart_confirmed=${restart_confirmed,,}  # convert to lowercase
    fi
    
    if [[ "$restart_confirmed" =~ ^(yes|y|true)$ ]]; then
        echo "Deleting Grafana pods to trigger recreation..."
        kubectl -n monitoring delete pod -l app.kubernetes.io/name=grafana --grace-period=0 --force 2>/dev/null || {
            echo -e "${YELLOW}⚠ No Grafana pods found or failed to delete${NC}"
        }
        
        echo "Deleting Loki pods to trigger recreation..."
        kubectl -n monitoring delete pod -l app=loki --grace-period=0 --force 2>/dev/null || {
            echo -e "${YELLOW}⚠ No Loki pods found or failed to delete${NC}"
        }
        
        echo -e "${GREEN}✓ Pod deletion commands executed${NC}"
        echo "Pods will be automatically recreated by their controllers"
    else
        echo "Skipping pod restart"
    fi
}

# Function to provide verification commands
show_verification_commands() {
    echo ""
    echo "=== Verification Commands ==="
    echo "Run these commands to verify the setup:"
    echo ""
    echo "1. Check PV status:"
    echo "   kubectl get pv -o wide"
    echo ""
    echo "2. Check PVC binding:"
    echo "   kubectl -n monitoring get pvc -o wide"
    echo ""
    echo "3. Check Grafana PVC details:"
    echo "   kubectl -n monitoring describe pvc kube-prometheus-stack-grafana"
    echo ""
    echo "4. Check Grafana PV details:"
    echo "   kubectl -n monitoring describe pv pv-grafana-local"
    echo ""
    echo "5. Watch pod status:"
    echo "   kubectl -n monitoring get pods -w"
    echo ""
    echo "6. Check Grafana init container logs:"
    echo "   kubectl -n monitoring logs <grafana-pod-name> -c init-chown-data --tail=200"
    echo ""
    echo "7. Verify host directory permissions:"
    echo "   sudo ls -la /srv/monitoring_data/"
    echo "   sudo stat -c 'UID:%u GID:%g MODE:%a' /srv/monitoring_data/grafana"
}

# Function to cleanup temporary files
cleanup() {
    if [ -d "$MANIFESTS_DIR" ]; then
        echo "Cleaning up temporary manifest files..."
        rm -rf "$MANIFESTS_DIR"
        echo -e "${GREEN}✓ Cleanup completed${NC}"
    fi
}

# Main execution
echo "=== Phase 1: Pre-flight Checks ==="
check_kubectl
echo ""

echo "=== Phase 2: Create PV Manifests ==="
create_pv_manifests
echo ""

echo "=== Phase 3: Apply PV Manifests ==="
apply_pv_manifests
echo ""

echo "=== Phase 4: Check PVC Binding ==="
check_pvc_binding
echo ""

echo "=== Phase 5: Pod Restart (Optional) ==="
restart_monitoring_pods
echo ""

echo "=== Phase 6: Verification ==="
show_verification_commands
echo ""

echo "=== Phase 7: Cleanup ==="
cleanup
echo ""

echo -e "${GREEN}=== PV Creation Script Completed ===${NC}"
echo ""
echo "Next steps:"
echo "1. Wait a few minutes for PVCs to bind to the new PVs"
echo "2. Run verification commands above to confirm setup"
echo "3. If Grafana still has permission issues, ensure host directories have correct ownership (UID:GID 472:472)"
echo "4. Monitor pod logs for any remaining issues"
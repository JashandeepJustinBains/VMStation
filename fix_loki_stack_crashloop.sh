#!/bin/bash

# Fix Loki Stack CrashLoopBackOff Issues
# Targets only loki-stack components while preserving working pods like Jellyfin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MONITORING_NAMESPACE="monitoring"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check if kubectl is available and cluster is accessible
check_cluster_access() {
    info "Checking cluster access..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not available. Please install kubectl first."
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot access Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    if ! kubectl get namespace "$MONITORING_NAMESPACE" &> /dev/null; then
        error "Monitoring namespace '$MONITORING_NAMESPACE' does not exist."
        exit 1
    fi
    
    info "Cluster access confirmed."
}

# Analyze current Loki stack status
analyze_loki_stack() {
    info "Analyzing current Loki stack status..."
    
    echo "=== Pod Status ==="
    kubectl get pods -n "$MONITORING_NAMESPACE" -l app=loki -o wide || true
    kubectl get pods -n "$MONITORING_NAMESPACE" -l app=promtail -o wide || true
    
    echo -e "\n=== Loki Stack Helm Release ==="
    helm list -n "$MONITORING_NAMESPACE" | grep loki-stack || true
    
    echo -e "\n=== Recent Events ==="
    kubectl get events -n "$MONITORING_NAMESPACE" --sort-by=.metadata.creationTimestamp --field-selector reason!=Scheduled | tail -20 || true
    
    echo -e "\n=== PVC Status ==="
    kubectl get pvc -n "$MONITORING_NAMESPACE" | grep loki || true
}

# Get logs from failing pods
collect_failure_logs() {
    info "Collecting logs from failing pods..."
    
    local loki_pods=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=loki --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)
    local promtail_pods=$(kubectl get pods -n "$MONITORING_NAMESPACE" -l app=promtail --no-headers -o custom-columns=":metadata.name" 2>/dev/null || true)
    
    if [[ -n "$loki_pods" ]]; then
        for pod in $loki_pods; do
            echo -e "\n=== Logs for $pod ==="
            kubectl logs "$pod" -n "$MONITORING_NAMESPACE" --tail=50 || true
            echo -e "\n=== Previous logs for $pod ==="
            kubectl logs "$pod" -n "$MONITORING_NAMESPACE" --previous --tail=50 2>/dev/null || true
        done
    fi
    
    if [[ -n "$promtail_pods" ]]; then
        for pod in $promtail_pods; do
            echo -e "\n=== Logs for $pod ==="
            kubectl logs "$pod" -n "$MONITORING_NAMESPACE" --tail=50 || true
            echo -e "\n=== Previous logs for $pod ==="
            kubectl logs "$pod" -n "$MONITORING_NAMESPACE" --previous --tail=50 2>/dev/null || true
        done
    fi
}

# Create improved Loki stack configuration
create_loki_fix_values() {
    info "Creating improved Loki stack configuration..."
    
    cat > /tmp/loki-stack-fix-values.yaml << 'EOF'
# Fixed Loki Stack Configuration to resolve CrashLoopBackOff

loki:
  enabled: true
  image:
    tag: "2.9.2"  # Use a stable version
  
  # Resource limits to prevent OOM kills
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 200m
      memory: 256Mi
  
  # Persistence configuration
  persistence:
    enabled: true
    storageClassName: local-path
    size: 10Gi
    # Ensure proper access modes for local-path
    accessModes:
      - ReadWriteOnce
  
  # Loki configuration optimized for small clusters
  config:
    auth_enabled: false
    server:
      http_listen_port: 3100
      grpc_listen_port: 9095
      
    # Distributor configuration
    distributor:
      ring:
        kvstore:
          store: inmemory
    
    # Ingester configuration - more reliable for single node
    ingester:
      lifecycler:
        address: 127.0.0.1
        ring:
          kvstore:
            store: inmemory
          replication_factor: 1
        final_sleep: 0s
      chunk_idle_period: 1h
      max_chunk_age: 1h
      chunk_target_size: 1048576
      chunk_retain_period: 30s
      max_transfer_retries: 0
      
    # Schema configuration
    schema_config:
      configs:
        - from: 2020-10-24
          store: boltdb-shipper
          object_store: filesystem
          schema: v11
          index:
            prefix: index_
            period: 24h
            
    # Storage configuration with safer paths
    storage_config:
      boltdb_shipper:
        active_index_directory: /loki/boltdb-shipper-active
        cache_location: /loki/boltdb-shipper-cache
        shared_store: filesystem
      filesystem:
        directory: /loki/chunks
        
    # Limits configuration to prevent issues
    limits_config:
      enforce_metric_name: false
      reject_old_samples: true
      reject_old_samples_max_age: 168h
      ingestion_rate_mb: 16
      ingestion_burst_size_mb: 32
      max_streams_per_user: 10000
      max_line_size: 256000
      
    # Table manager configuration
    table_manager:
      retention_deletes_enabled: false
      retention_period: 0s
      
    # Query configuration
    querier:
      max_concurrent: 16
      
    limits_config:
      split_queries_by_interval: 15m
      max_retries: 5
      
    # Compactor configuration
    compactor:
      working_directory: /loki/boltdb-shipper-compactor
      shared_store: filesystem
      
  # Security context for proper permissions
  securityContext:
    fsGroup: 10001
    runAsGroup: 10001
    runAsNonRoot: true
    runAsUser: 10001
    
  # Service configuration
  service:
    type: NodePort
    nodePort: 31100
    port: 3100

promtail:
  enabled: true
  image:
    tag: "2.9.2"  # Match Loki version
    
  # Resource limits for promtail
  resources:
    limits:
      cpu: 500m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi
      
  # Promtail configuration
  config:
    server:
      http_listen_port: 3101
      grpc_listen_port: 0
      
    positions:
      filename: /tmp/positions.yaml
      
    clients:
      - url: http://loki-stack:3100/loki/api/v1/push
        timeout: 60s
        backoff_config:
          min_period: 500ms
          max_period: 5m
          max_retries: 10
        
    scrape_configs:
      - job_name: kubernetes-pods
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels:
              - __meta_kubernetes_pod_controller_name
            regex: ([0-9a-z-.]+?)(-[0-9a-f]{8,10})?
            action: replace
            target_label: __tmp_controller_name
          - source_labels:
              - __meta_kubernetes_pod_label_app_kubernetes_io_name
              - __meta_kubernetes_pod_label_app
              - __tmp_controller_name
              - __meta_kubernetes_pod_name
            regex: ^;*([^;]+)(;.*)?$
            action: replace
            target_label: app
          - source_labels:
              - __meta_kubernetes_pod_label_app_kubernetes_io_instance
              - __meta_kubernetes_pod_label_release
            regex: ^;*([^;]+)(;.*)?$
            action: replace
            target_label: instance
          - source_labels:
              - __meta_kubernetes_pod_label_app_kubernetes_io_component
              - __meta_kubernetes_pod_label_component
            regex: ^;*([^;]+)(;.*)?$
            action: replace
            target_label: component
          - action: replace
            source_labels:
            - __meta_kubernetes_pod_node_name
            target_label: node_name
          - action: replace
            source_labels:
            - __meta_kubernetes_namespace
            target_label: namespace
          - action: replace
            replacement: /var/log/pods/*$1/*.log
            separator: /
            source_labels:
            - __meta_kubernetes_pod_uid
            - __meta_kubernetes_pod_container_name
            target_label: __path__
            
  # Security context
  securityContext:
    readOnlyRootFilesystem: true
    runAsGroup: 0
    runAsUser: 0
    
  # Volume mounts for log access
  volumeMounts:
    - name: varlog
      mountPath: /var/log
      readOnly: true
    - name: varlibdockercontainers
      mountPath: /var/lib/docker/containers
      readOnly: true
      
  volumes:
    - name: varlog
      hostPath:
        path: /var/log
    - name: varlibdockercontainers
      hostPath:
        path: /var/lib/docker/containers

# Disable Grafana since we use kube-prometheus-stack
grafana:
  enabled: false
  
fluent-bit:
  enabled: false
  
logstash:
  enabled: false
EOF

    info "Loki stack fix configuration created at /tmp/loki-stack-fix-values.yaml"
}

# Apply the fix
apply_loki_fix() {
    info "Applying Loki stack fix..."
    
    # First check if helm is available
    if ! command -v helm &> /dev/null; then
        error "Helm is not available. Please install Helm first."
        exit 1
    fi
    
    # Add Grafana helm repo if not present
    info "Ensuring Grafana Helm repository is available..."
    helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
    helm repo update
    
    # Upgrade the loki-stack release with new values
    info "Upgrading loki-stack with improved configuration..."
    helm upgrade loki-stack grafana/loki-stack \
        --namespace "$MONITORING_NAMESPACE" \
        --values /tmp/loki-stack-fix-values.yaml \
        --timeout 10m \
        --wait
    
    info "Loki stack upgrade completed."
}

# Wait for pods to be ready and verify fix
verify_fix() {
    info "Waiting for Loki stack pods to be ready..."
    
    # Wait for loki pod
    kubectl wait --for=condition=ready pod \
        -l app=loki \
        -n "$MONITORING_NAMESPACE" \
        --timeout=600s || true
    
    # Wait for promtail pods
    kubectl wait --for=condition=ready pod \
        -l app=promtail \
        -n "$MONITORING_NAMESPACE" \
        --timeout=300s || true
    
    info "Verification complete. Checking final status..."
    
    echo -e "\n=== Final Pod Status ==="
    kubectl get pods -n "$MONITORING_NAMESPACE" -l app=loki -o wide
    kubectl get pods -n "$MONITORING_NAMESPACE" -l app=promtail -o wide
    
    echo -e "\n=== Service Status ==="
    kubectl get svc -n "$MONITORING_NAMESPACE" | grep loki || true
    
    echo -e "\n=== Recent Events ==="
    kubectl get events -n "$MONITORING_NAMESPACE" --sort-by=.metadata.creationTimestamp | tail -10
}

# Preserve existing working pods check
check_working_pods() {
    info "Checking status of working pods to ensure they remain unaffected..."
    
    echo -e "\n=== Jellyfin Status ==="
    kubectl get pods -n jellyfin -o wide 2>/dev/null || echo "No Jellyfin pods found"
    
    echo -e "\n=== Other Working Pods ==="
    kubectl get pods --all-namespaces | grep -E "(Running|Ready)" | grep -v "$MONITORING_NAMESPACE" || true
}

# Main execution
main() {
    echo -e "${BLUE}=== VMStation Loki Stack CrashLoopBackOff Fix ===${NC}"
    echo "This script will fix Loki stack issues while preserving working pods."
    echo ""
    
    # Pre-flight checks
    check_cluster_access
    
    echo -e "\n${YELLOW}=== Current Status Analysis ===${NC}"
    analyze_loki_stack
    
    echo -e "\n${YELLOW}=== Collecting Failure Logs ===${NC}"
    collect_failure_logs
    
    echo -e "\n${YELLOW}=== Checking Working Pods Status ===${NC}"
    check_working_pods
    
    echo -e "\n${YELLOW}=== Applying Fix ===${NC}"
    create_loki_fix_values
    apply_loki_fix
    
    echo -e "\n${YELLOW}=== Verifying Fix ===${NC}"
    verify_fix
    
    echo -e "\n${YELLOW}=== Final Working Pods Check ===${NC}"
    check_working_pods
    
    echo -e "\n${GREEN}=== Fix Complete ===${NC}"
    info "Loki stack fix has been applied."
    info "Working pods like Jellyfin should remain unaffected."
    info "Monitor the logs and pod status to ensure stability."
    
    # Cleanup temporary files
    rm -f /tmp/loki-stack-fix-values.yaml
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
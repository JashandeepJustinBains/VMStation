#!/bin/bash
# VMStation Monitoring Stack - Automated Remediation Script
# Date: October 10, 2025
# Purpose: Fix Prometheus and Loki failures with safe, non-destructive changes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
NAMESPACE="monitoring"
BACKUP_DIR="${BACKUP_DIR:-/tmp/monitoring-backups-$(date +%Y%m%d-%H%M%S)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VMStation Monitoring Stack - Automated Remediation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Function to print section headers
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to ask for confirmation
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [ "$default" = "y" ]; then
        read -p "$prompt [Y/n] " -n 1 -r
    else
        read -p "$prompt [y/N] " -n 1 -r
    fi
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

print_section "Step 1: Safety Checks and Backups"

echo -e "${YELLOW}Creating backup directory: ${BACKUP_DIR}${NC}"
mkdir -p "${BACKUP_DIR}"

echo -e "${YELLOW}Backing up current monitoring namespace state...${NC}"
kubectl --kubeconfig=${KUBECONFIG} get all -n ${NAMESPACE} -o yaml > "${BACKUP_DIR}/monitoring-all-backup.yaml"
kubectl --kubeconfig=${KUBECONFIG} get pvc,pv -n ${NAMESPACE} -o yaml > "${BACKUP_DIR}/monitoring-storage-backup.yaml"
kubectl --kubeconfig=${KUBECONFIG} get configmap -n ${NAMESPACE} -o yaml > "${BACKUP_DIR}/monitoring-configmaps-backup.yaml"
echo -e "${GREEN}✓ Backups saved to: ${BACKUP_DIR}${NC}"

print_section "Step 2: Fix Prometheus Permission Issue"

echo ""
echo "This will add explicit SecurityContext to Prometheus StatefulSet:"
echo "  - fsGroup: 65534 (nobody group)"
echo "  - runAsUser: 65534 (nobody user)"
echo "  - runAsGroup: 65534 (nobody group)"
echo "  - runAsNonRoot: true"
echo ""

if confirm "Apply Prometheus SecurityContext fix?"; then
    echo -e "${YELLOW}Patching Prometheus StatefulSet...${NC}"
    
    kubectl --kubeconfig=${KUBECONFIG} patch statefulset prometheus -n ${NAMESPACE} --type='json' -p='[
      {
        "op": "add",
        "path": "/spec/template/spec/securityContext",
        "value": {
          "fsGroup": 65534,
          "runAsUser": 65534,
          "runAsGroup": 65534,
          "runAsNonRoot": true
        }
      }
    ]'
    
    echo -e "${GREEN}✓ Prometheus StatefulSet patched${NC}"
    
    echo -e "${YELLOW}Deleting prometheus-0 pod to apply changes...${NC}"
    kubectl --kubeconfig=${KUBECONFIG} delete pod prometheus-0 -n ${NAMESPACE} --wait=false
    echo -e "${GREEN}✓ Prometheus pod deletion initiated${NC}"
else
    echo -e "${YELLOW}Skipped Prometheus fix${NC}"
fi

print_section "Step 3: Fix Loki Frontend Worker Issue"

echo ""
echo "This will disable the frontend_worker in Loki configuration:"
echo "  - Removes frontend_worker.frontend_address connection"
echo "  - Safe for single-instance deployments"
echo "  - Loki will continue to function normally"
echo ""

if confirm "Apply Loki frontend_worker fix?"; then
    echo -e "${YELLOW}Getting current Loki ConfigMap...${NC}"
    
    # Get current ConfigMap
    kubectl --kubeconfig=${KUBECONFIG} get configmap loki-config -n ${NAMESPACE} -o yaml > "${BACKUP_DIR}/loki-config-original.yaml"
    
    # Create patched ConfigMap
    cat > /tmp/loki-config-patch.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config
  namespace: monitoring
  labels:
    app: loki
    vmstation.io/component: monitoring
  annotations:
    vmstation.io/anonymous-access: "true"
data:
  loki.yaml: |
    # Loki Enterprise Configuration
    # Target: All-in-one mode (suitable for small-medium deployments)
    
    auth_enabled: false
    
    server:
      http_listen_port: 3100
      grpc_listen_port: 9096
      log_level: info
      log_format: json
      
      # Graceful shutdown
      grpc_server_max_concurrent_streams: 0
      http_server_read_timeout: 30s
      http_server_write_timeout: 30s
    
    # Common configuration
    common:
      path_prefix: /loki
      storage:
        filesystem:
          chunks_directory: /loki/chunks
          rules_directory: /loki/rules
      replication_factor: 1
      ring:
        kvstore:
          store: inmemory
    
    # Distributor configuration
    distributor:
      ring:
        kvstore:
          store: inmemory
    
    # Ingester configuration
    ingester:
      lifecycler:
        address: 127.0.0.1
        ring:
          kvstore:
            store: inmemory
          replication_factor: 1
        final_sleep: 0s
      
      # Chunk settings
      chunk_idle_period: 1h       # Flush chunks after 1h idle
      chunk_block_size: 262144    # 256KB chunks
      chunk_target_size: 1536000  # Target 1.5MB compressed chunk
      chunk_retain_period: 30s    # Keep chunks in memory 30s after flush
      max_transfer_retries: 0
      
      # WAL configuration
      wal:
        enabled: true
        dir: /loki/wal
        checkpoint_duration: 5m
        flush_on_shutdown: true
        replay_memory_ceiling: 1GB
    
    # Schema configuration
    schema_config:
      configs:
      - from: 2020-10-24
        store: boltdb-shipper
        object_store: filesystem
        schema: v11
        index:
          prefix: index_
          period: 24h    # 24h index period (required for boltdb-shipper)
    
    # Storage configuration
    storage_config:
      boltdb_shipper:
        active_index_directory: /loki/index
        cache_location: /loki/index_cache
        cache_ttl: 24h
        shared_store: filesystem
      
      filesystem:
        directory: /loki/chunks
      
      # Index query cache
      index_queries_cache_config:
        memcached_client:
          consistent_hash: true
        enable_fifocache: true
        fifocache:
          max_size_items: 1024
          ttl: 24h
    
    # Limits configuration (production tuned)
    limits_config:
      # Ingestion limits
      enforce_metric_name: false
      reject_old_samples: true
      reject_old_samples_max_age: 168h  # 7 days
      ingestion_rate_mb: 10            # 10MB/s per distributor
      ingestion_burst_size_mb: 20      # Burst to 20MB
      
      # Query limits
      max_query_length: 721h           # 30 days
      max_query_parallelism: 32        # Parallel query workers
      max_query_series: 500            # Series per query
      max_streams_per_user: 10000      # Total streams per tenant
      max_global_streams_per_user: 10000
      
      # Label limits
      max_label_name_length: 1024
      max_label_value_length: 2048
      max_label_names_per_series: 30
      
      # Line limits
      max_line_size: 256KB             # Max size per log line
      max_entries_limit_per_query: 5000
      
      # Cardinality limits
      cardinality_limit: 100000
      max_streams_matchers_per_query: 1000
      
      # Split queries by interval
      split_queries_by_interval: 15m
      
      # Per-stream rate limits
      per_stream_rate_limit: 3MB
      per_stream_rate_limit_burst: 15MB
    
    # Chunk store configuration
    chunk_store_config:
      max_look_back_period: 0s
      chunk_cache_config:
        enable_fifocache: true
        fifocache:
          max_size_items: 1024
          ttl: 24h
    
    # Table manager (retention)
    table_manager:
      retention_deletes_enabled: true
      retention_period: 720h  # 30 days retention
      poll_interval: 10m
    
    # Compactor (log compaction and retention)
    compactor:
      working_directory: /loki/compactor
      shared_store: filesystem
      compaction_interval: 10m
      retention_enabled: true
      retention_delete_delay: 2h
      retention_delete_worker_count: 150
    
    # Query scheduler (optional, for better query distribution)
    query_scheduler:
      max_outstanding_requests_per_tenant: 256
    
    # Frontend (query frontend for better caching)
    frontend:
      log_queries_longer_than: 5s
      max_outstanding_per_tenant: 256
      compress_responses: true
    
    # Frontend worker - DISABLED for single-instance deployment
    # Uncommenting this can cause "connection refused" errors in all-in-one mode
    # frontend_worker:
    #   frontend_address: 127.0.0.1:9095
    #   parallelism: 10
    
    # Querier configuration
    querier:
      max_concurrent: 10
      query_ingesters_within: 3h
    
    # Query range configuration
    query_range:
      align_queries_with_step: true
      cache_results: true
      max_retries: 5
      results_cache:
        cache:
          enable_fifocache: true
          fifocache:
            max_size_items: 1024
            ttl: 24h
    
    # Ruler configuration
    ruler:
      storage:
        type: local
        local:
          directory: /loki/rules
      rule_path: /loki/rules-temp
      alertmanager_url: http://localhost:9093
      ring:
        kvstore:
          store: inmemory
      enable_api: true
      enable_alertmanager_v2: true
EOF
    
    echo -e "${YELLOW}Applying Loki ConfigMap patch...${NC}"
    kubectl --kubeconfig=${KUBECONFIG} apply -f /tmp/loki-config-patch.yaml
    echo -e "${GREEN}✓ Loki ConfigMap updated${NC}"
    
    echo -e "${YELLOW}Deleting loki-0 pod to apply changes...${NC}"
    kubectl --kubeconfig=${KUBECONFIG} delete pod loki-0 -n ${NAMESPACE} --wait=false
    echo -e "${GREEN}✓ Loki pod deletion initiated${NC}"
    
    rm -f /tmp/loki-config-patch.yaml
else
    echo -e "${YELLOW}Skipped Loki fix${NC}"
fi

print_section "Step 4: Verify Host Directory Permissions (Optional)"

echo ""
echo "Checking if we're running on the masternode..."
if [ -d "/srv/monitoring_data" ]; then
    echo -e "${GREEN}✓ Found /srv/monitoring_data directory${NC}"
    echo ""
    echo "Current permissions:"
    ls -la /srv/monitoring_data
    echo ""
    
    if confirm "Fix host directory permissions?"; then
        echo -e "${YELLOW}Setting correct ownership...${NC}"
        chown -R 65534:65534 /srv/monitoring_data/prometheus
        chown -R 10001:10001 /srv/monitoring_data/loki
        chown -R 472:472 /srv/monitoring_data/grafana
        chmod -R 755 /srv/monitoring_data
        echo -e "${GREEN}✓ Permissions fixed${NC}"
        echo ""
        echo "Updated permissions:"
        ls -la /srv/monitoring_data
    else
        echo -e "${YELLOW}Skipped permission fix${NC}"
        echo ""
        echo "To fix permissions manually, run:"
        echo "  sudo chown -R 65534:65534 /srv/monitoring_data/prometheus"
        echo "  sudo chown -R 10001:10001 /srv/monitoring_data/loki"
        echo "  sudo chown -R 472:472 /srv/monitoring_data/grafana"
        echo "  sudo chmod -R 755 /srv/monitoring_data"
    fi
else
    echo -e "${YELLOW}Not running on masternode (no /srv/monitoring_data found)${NC}"
    echo ""
    echo "To fix permissions on the masternode, SSH and run:"
    echo "  ssh root@masternode"
    echo "  chown -R 65534:65534 /srv/monitoring_data/prometheus"
    echo "  chown -R 10001:10001 /srv/monitoring_data/loki"
    echo "  chown -R 472:472 /srv/monitoring_data/grafana"
    echo "  chmod -R 755 /srv/monitoring_data"
fi

print_section "Step 5: Wait for Pods to Restart"

echo ""
echo -e "${YELLOW}Waiting for pods to restart (max 120 seconds)...${NC}"
echo ""

# Wait for prometheus-0
echo "Waiting for prometheus-0..."
kubectl --kubeconfig=${KUBECONFIG} wait --for=condition=ready pod/prometheus-0 -n ${NAMESPACE} --timeout=120s 2>&1 || echo "Timeout waiting for prometheus-0 (check manually)"

# Wait for loki-0
echo "Waiting for loki-0..."
kubectl --kubeconfig=${KUBECONFIG} wait --for=condition=ready pod/loki-0 -n ${NAMESPACE} --timeout=120s 2>&1 || echo "Timeout waiting for loki-0 (check manually)"

print_section "Step 6: Validation"

echo ""
echo -e "${CYAN}Pod Status:${NC}"
kubectl --kubeconfig=${KUBECONFIG} get pods -n ${NAMESPACE}

echo ""
echo -e "${CYAN}Endpoints Status:${NC}"
kubectl --kubeconfig=${KUBECONFIG} get endpoints prometheus loki -n ${NAMESPACE}

echo ""
echo -e "${CYAN}Recent Events:${NC}"
kubectl --kubeconfig=${KUBECONFIG} get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | tail -10

print_section "Remediation Complete"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Remediation steps completed!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Backups saved to: ${BACKUP_DIR}"
echo ""
echo "Next steps:"
echo "  1. Monitor pod status: kubectl get pods -n monitoring -w"
echo "  2. Check logs if issues persist:"
echo "     - kubectl logs -n monitoring prometheus-0"
echo "     - kubectl logs -n monitoring loki-0"
echo "  3. Validate Grafana connectivity:"
echo "     - Access Grafana: http://<masternode-ip>:30300"
echo "     - Check datasources under Configuration"
echo "  4. Run validation script: ./scripts/validate-monitoring-stack.sh"
echo ""
echo "If issues persist:"
echo "  - Review logs in ${BACKUP_DIR}"
echo "  - Check the diagnostic output"
echo "  - Restore from backup if needed: kubectl apply -f ${BACKUP_DIR}/"
echo ""

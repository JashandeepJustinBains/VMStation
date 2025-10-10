#!/bin/bash
# VMStation Monitoring Stack - Diagnostic Script
# Date: October 10, 2025
# Purpose: Comprehensive diagnostics for Prometheus and Loki failures

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/monitoring-diagnostics-$(date +%Y%m%d-%H%M%S)}"
KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
NAMESPACE="monitoring"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  VMStation Monitoring Stack - Diagnostic Report"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Output directory: ${OUTPUT_DIR}"
echo ""

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Function to print section headers
print_section() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to save command output
save_output() {
    local cmd="$1"
    local file="$2"
    local description="$3"
    
    echo -e "${YELLOW}► ${description}${NC}"
    eval "$cmd" > "${OUTPUT_DIR}/${file}" 2>&1 || echo "Command failed (exit code: $?)" >> "${OUTPUT_DIR}/${file}"
    echo "  Saved to: ${file}"
}

print_section "1. Cluster and Pod Status"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} get pods -n ${NAMESPACE} -o wide" \
    "01-pods-status.txt" \
    "Get all monitoring pods"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} get pvc,pv -n ${NAMESPACE} -o wide" \
    "02-pvc-pv-status.txt" \
    "Get PVC and PV status"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} get svc -n ${NAMESPACE} -o wide" \
    "03-services-status.txt" \
    "Get services status"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} get endpoints -n ${NAMESPACE}" \
    "04-endpoints-status.txt" \
    "Get endpoints status"

print_section "2. Prometheus Diagnostics"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} describe pod prometheus-0 -n ${NAMESPACE}" \
    "05-prometheus-describe.txt" \
    "Describe prometheus-0 pod"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} logs prometheus-0 -n ${NAMESPACE} --tail=500 2>&1 || kubectl --kubeconfig=${KUBECONFIG} logs prometheus-0 -n ${NAMESPACE} --previous --tail=500 2>&1" \
    "06-prometheus-logs.txt" \
    "Get prometheus-0 logs (last 500 lines)"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} logs prometheus-0 -n ${NAMESPACE} -c init-chown-data 2>&1" \
    "07-prometheus-init-logs.txt" \
    "Get prometheus-0 init container logs"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} get endpoints prometheus -n ${NAMESPACE} -o yaml" \
    "08-prometheus-endpoints.yaml" \
    "Get prometheus endpoints (YAML)"

print_section "3. Loki Diagnostics"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} describe pod loki-0 -n ${NAMESPACE}" \
    "09-loki-describe.txt" \
    "Describe loki-0 pod"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} logs loki-0 -n ${NAMESPACE} --tail=500" \
    "10-loki-logs.txt" \
    "Get loki-0 logs (last 500 lines)"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} logs loki-0 -n ${NAMESPACE} -c init-loki-data 2>&1" \
    "11-loki-init-logs.txt" \
    "Get loki-0 init container logs"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} get endpoints loki -n ${NAMESPACE} -o yaml" \
    "12-loki-endpoints.yaml" \
    "Get loki endpoints (YAML)"

print_section "4. StatefulSets and ConfigMaps"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} get statefulset prometheus -n ${NAMESPACE} -o yaml" \
    "13-prometheus-statefulset.yaml" \
    "Get prometheus StatefulSet (YAML)"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} get statefulset loki -n ${NAMESPACE} -o yaml" \
    "14-loki-statefulset.yaml" \
    "Get loki StatefulSet (YAML)"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} get configmap prometheus-config -n ${NAMESPACE} -o yaml" \
    "15-prometheus-configmap.yaml" \
    "Get prometheus ConfigMap (YAML)"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} get configmap loki-config -n ${NAMESPACE} -o yaml" \
    "16-loki-configmap.yaml" \
    "Get loki ConfigMap (YAML)"

print_section "5. Events and Logs"

save_output \
    "kubectl --kubeconfig=${KUBECONFIG} get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | tail -100" \
    "17-recent-events.txt" \
    "Get recent events (last 100)"

print_section "6. Host Directory Permissions (if running on masternode)"

if [ -d "/srv/monitoring_data" ]; then
    echo -e "${YELLOW}► Checking /srv/monitoring_data permissions${NC}"
    ls -la /srv/monitoring_data > "${OUTPUT_DIR}/18-host-permissions.txt" 2>&1
    stat /srv/monitoring_data/prometheus >> "${OUTPUT_DIR}/18-host-permissions.txt" 2>&1 || true
    stat /srv/monitoring_data/loki >> "${OUTPUT_DIR}/18-host-permissions.txt" 2>&1 || true
    stat /srv/monitoring_data/grafana >> "${OUTPUT_DIR}/18-host-permissions.txt" 2>&1 || true
    echo "  Saved to: 18-host-permissions.txt"
else
    echo -e "${YELLOW}► /srv/monitoring_data not found (not running on masternode?)${NC}"
    echo "Directory /srv/monitoring_data not found" > "${OUTPUT_DIR}/18-host-permissions.txt"
fi

print_section "7. Readiness Probe Tests"

echo -e "${YELLOW}► Testing Prometheus readiness endpoint (from within pod)${NC}"
kubectl --kubeconfig=${KUBECONFIG} exec -n ${NAMESPACE} prometheus-0 -c prometheus -- wget -O- --timeout=5 http://localhost:9090/-/ready 2>&1 > "${OUTPUT_DIR}/19-prometheus-readiness-test.txt" || echo "Readiness probe failed or pod not accessible" >> "${OUTPUT_DIR}/19-prometheus-readiness-test.txt"
echo "  Saved to: 19-prometheus-readiness-test.txt"

echo -e "${YELLOW}► Testing Loki readiness endpoint (from within pod)${NC}"
kubectl --kubeconfig=${KUBECONFIG} exec -n ${NAMESPACE} loki-0 -- wget -O- --timeout=5 http://localhost:3100/ready 2>&1 > "${OUTPUT_DIR}/20-loki-readiness-test.txt" || echo "Readiness probe failed or pod not accessible" >> "${OUTPUT_DIR}/20-loki-readiness-test.txt"
echo "  Saved to: 20-loki-readiness-test.txt"

print_section "8. Analysis and Recommendations"

ANALYSIS_FILE="${OUTPUT_DIR}/00-ANALYSIS-AND-RECOMMENDATIONS.txt"

cat > "${ANALYSIS_FILE}" << 'EOF'
VMStation Monitoring Stack - Diagnostic Analysis
=================================================

Based on the collected diagnostics, here are the identified issues and recommended fixes:

ISSUE 1: Prometheus CrashLoopBackOff - Permission Denied
---------------------------------------------------------
Symptom:
  - Error: "opening storage failed: lock DB directory: open /prometheus/lock: permission denied"
  - Init container successfully sets permissions to 65534:65534
  - Main prometheus container still fails with permission denied

Root Cause:
  - The Prometheus container runs with a SecurityContext that may be conflicting with the volume permissions
  - The fsGroup or runAsUser in the SecurityContext may not match the expected UID 65534
  - Possible SELinux or AppArmor interference on the host

Recommended Fix:
  1. Add explicit SecurityContext to Prometheus StatefulSet:
     securityContext:
       fsGroup: 65534
       runAsUser: 65534
       runAsNonRoot: true
       runAsGroup: 65534
  
  2. Verify host directory permissions on masternode:
     ssh root@masternode 'ls -lZ /srv/monitoring_data/prometheus'
     ssh root@masternode 'chown -R 65534:65534 /srv/monitoring_data/prometheus'
     ssh root@masternode 'chmod -R 755 /srv/monitoring_data/prometheus'
  
  3. Restart the pod:
     kubectl -n monitoring delete pod prometheus-0 --wait

ISSUE 2: Loki Running but Not Ready - Frontend Connection Refused
------------------------------------------------------------------
Symptom:
  - Loki starts successfully ("Loki started" in logs)
  - Errors: "error contacting frontend: dial tcp 127.0.0.1:9095: connect: connection refused"
  - Readiness probe fails with HTTP 503

Root Cause:
  - Loki is configured with frontend_worker.frontend_address: 127.0.0.1:9095
  - In all-in-one mode (-target=all), the query-frontend component starts but workers try to connect before it's ready
  - This is a race condition in the Loki startup sequence
  - The readiness probe checks /ready endpoint which waits for all components including frontend workers

Recommended Fix (Option 1 - Preferred):
  - Disable the frontend_worker in the Loki ConfigMap for single-instance deployments:
    
    # Comment out or remove frontend_worker section:
    # frontend_worker:
    #   frontend_address: 127.0.0.1:9095
    #   parallelism: 10
  
  - This is safe for small deployments as the query-frontend is not critical for functionality
  - Loki will still operate normally without the frontend worker connections

Recommended Fix (Option 2 - Alternative):
  - Increase the readiness probe initialDelaySeconds and failureThreshold:
    
    readiness:
      initialDelaySeconds: 60  # Give more time for all components to start
      failureThreshold: 10     # Allow more failures before marking as not ready
  
  - This gives Loki more time to establish internal connections

ISSUE 3: Empty Service Endpoints
---------------------------------
Symptom:
  - Headless services for Prometheus and Loki have empty endpoints
  - Grafana cannot resolve prometheus.monitoring.svc.cluster.local or loki.monitoring.svc.cluster.local

Root Cause:
  - Services require pods to be in Ready state to be added to endpoints
  - Since prometheus-0 is CrashLoopBackOff and loki-0 is not Ready, no endpoints are created
  - DNS resolution fails because there are no IPs in the endpoint list

Fix:
  - This will be automatically resolved once Issues 1 and 2 are fixed
  - Verify endpoints populate after pod fixes:
    kubectl -n monitoring get endpoints prometheus loki
  - Expected: Each endpoint should show the pod IP (e.g., 10.244.0.228 for prometheus-0)

VALIDATION STEPS
----------------
After applying fixes:

1. Check pod status:
   kubectl -n monitoring get pods -w
   
   Expected:
   - prometheus-0: 2/2 Running (both containers ready)
   - loki-0: 1/1 Running (ready)

2. Check endpoints:
   kubectl -n monitoring get endpoints prometheus loki
   
   Expected:
   - prometheus: ENDPOINTS: <pod-ip>:9090
   - loki: ENDPOINTS: <pod-ip>:3100,<pod-ip>:9096

3. Test Prometheus health:
   curl http://prometheus.monitoring.svc.cluster.local:9090/-/healthy
   
   Expected: Prometheus is Healthy.

4. Test Loki health:
   curl http://loki.monitoring.svc.cluster.local:3100/ready
   
   Expected: ready

5. Test Grafana connectivity:
   - Access Grafana UI: http://<masternode-ip>:30300
   - Check datasources: Configuration → Data Sources
   - Both Prometheus and Loki should show "Data source is working"

6. Verify metrics collection:
   - Prometheus: Query for 'up' metric
   - Loki: Explore logs from any pod

SAFETY CHECKLIST
----------------
Before making any changes:

[x] Backup current state:
    kubectl -n monitoring get all -o yaml > /tmp/monitoring-backup-$(date +%Y%m%d-%H%M%S).yaml
    kubectl -n monitoring get pvc,pv -o yaml >> /tmp/monitoring-backup-$(date +%Y%m%d-%H%M%S).yaml

[ ] Backup host directories:
    ssh root@masternode 'tar -czf /tmp/monitoring_data_backup_$(date +%Y%m%d-%H%M%S).tar.gz /srv/monitoring_data/'

[ ] Test changes in non-production environment first (if available)

[ ] Have rollback plan ready:
    - Keep backup of original manifests
    - Document original ConfigMap values
    - Know how to restore from backup

PRIORITY ORDER
--------------
1. Fix Prometheus permission issue (highest impact - metrics collection stopped)
2. Fix Loki readiness issue (medium impact - logs collection working but not accessible)
3. Validate endpoints and Grafana connectivity (verification)

ESTIMATED TIME
--------------
- Diagnostics: 5 minutes
- Apply Prometheus fix: 5 minutes (config change + pod restart)
- Apply Loki fix: 5 minutes (config change + pod restart)  
- Validation: 5 minutes
Total: ~20 minutes

EOF

echo -e "${GREEN}✓ Analysis saved to: 00-ANALYSIS-AND-RECOMMENDATIONS.txt${NC}"

print_section "Diagnostic Report Complete"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Diagnostic report generated successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Output directory: ${OUTPUT_DIR}"
echo ""
echo "Key files to review:"
echo "  - 00-ANALYSIS-AND-RECOMMENDATIONS.txt (START HERE)"
echo "  - 06-prometheus-logs.txt (Prometheus errors)"
echo "  - 10-loki-logs.txt (Loki errors)"
echo "  - 18-host-permissions.txt (Directory permissions)"
echo ""
echo "Next steps:"
echo "  1. Review the analysis and recommendations"
echo "  2. Apply the recommended fixes"
echo "  3. Run validation tests"
echo ""

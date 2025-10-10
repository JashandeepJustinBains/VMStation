#!/bin/bash
# VMStation - Headless Service Endpoints Diagnostic Script
# 
# Purpose: Diagnose and validate headless service endpoints for Prometheus and Loki
# Based on: Problem statement diagnostic checklist for empty endpoints
#
# This script checks for common issues that cause headless services to have
# empty endpoints, including:
# - Service selector and pod label mismatches
# - Pods not running or not ready
# - PVC/PV binding issues
# - Container crashes and permission errors

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_pass() {
  echo -e "${GREEN}✓${NC} $1"
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
  log_fail "kubectl not found. This script requires kubectl to be installed."
  exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
  log_fail "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
  exit 1
fi

echo "======================================================================"
echo "VMStation Headless Service Endpoints Diagnostic"
echo "======================================================================"
echo ""

# Test 1: Check if monitoring namespace exists
echo "[1/10] Checking monitoring namespace..."
if kubectl get namespace monitoring &> /dev/null; then
  log_pass "Monitoring namespace exists"
else
  log_fail "Monitoring namespace does not exist"
  echo "  Run: kubectl create namespace monitoring"
  exit 1
fi
echo ""

# Test 2: Check pod status
echo "[2/10] Checking pod status in monitoring namespace..."
POD_OUTPUT=$(kubectl get pods -n monitoring -o wide 2>&1)

if [[ $? -eq 0 ]]; then
  echo "$POD_OUTPUT"
  echo ""
  
  # Check for prometheus pods
  PROM_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | wc -l)
  if [[ $PROM_PODS -gt 0 ]]; then
    log_pass "Found $PROM_PODS Prometheus pod(s)"
    
    # Check if ready
    PROM_READY=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [[ "$PROM_READY" == *"True"* ]]; then
      log_pass "Prometheus pod(s) are Ready"
    else
      log_fail "Prometheus pod(s) are NOT Ready"
      kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o wide
    fi
  else
    log_fail "No Prometheus pods found with label app.kubernetes.io/name=prometheus"
  fi
  
  # Check for loki pods
  LOKI_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=loki --no-headers 2>/dev/null | wc -l)
  if [[ $LOKI_PODS -gt 0 ]]; then
    log_pass "Found $LOKI_PODS Loki pod(s)"
    
    # Check if ready
    LOKI_READY=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=loki -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [[ "$LOKI_READY" == *"True"* ]]; then
      log_pass "Loki pod(s) are Ready"
    else
      log_fail "Loki pod(s) are NOT Ready"
      kubectl get pods -n monitoring -l app.kubernetes.io/name=loki -o wide
    fi
  else
    log_fail "No Loki pods found with label app.kubernetes.io/name=loki"
  fi
else
  log_warn "No pods found in monitoring namespace"
fi
echo ""

# Test 3: Check StatefulSets and Deployments
echo "[3/10] Checking StatefulSets and Deployments..."
STATEFULSETS=$(kubectl get statefulset -n monitoring 2>&1)
if [[ $? -eq 0 ]]; then
  echo "$STATEFULSETS"
  
  # Check Prometheus StatefulSet
  if echo "$STATEFULSETS" | grep -q "prometheus"; then
    log_pass "Prometheus StatefulSet exists"
    PROM_REPLICAS=$(kubectl get statefulset prometheus -n monitoring -o jsonpath='{.status.replicas}' 2>/dev/null)
    PROM_READY_REPLICAS=$(kubectl get statefulset prometheus -n monitoring -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [[ "$PROM_REPLICAS" == "$PROM_READY_REPLICAS" ]] && [[ -n "$PROM_REPLICAS" ]]; then
      log_pass "Prometheus StatefulSet: $PROM_READY_REPLICAS/$PROM_REPLICAS replicas ready"
    else
      log_fail "Prometheus StatefulSet: $PROM_READY_REPLICAS/$PROM_REPLICAS replicas ready"
    fi
  else
    log_fail "Prometheus StatefulSet not found"
  fi
  
  # Check Loki StatefulSet
  if echo "$STATEFULSETS" | grep -q "loki"; then
    log_pass "Loki StatefulSet exists"
    LOKI_REPLICAS=$(kubectl get statefulset loki -n monitoring -o jsonpath='{.status.replicas}' 2>/dev/null)
    LOKI_READY_REPLICAS=$(kubectl get statefulset loki -n monitoring -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [[ "$LOKI_REPLICAS" == "$LOKI_READY_REPLICAS" ]] && [[ -n "$LOKI_REPLICAS" ]]; then
      log_pass "Loki StatefulSet: $LOKI_READY_REPLICAS/$LOKI_REPLICAS replicas ready"
    else
      log_fail "Loki StatefulSet: $LOKI_READY_REPLICAS/$LOKI_REPLICAS replicas ready"
    fi
  else
    log_fail "Loki StatefulSet not found"
  fi
else
  log_warn "Could not retrieve StatefulSets"
fi
echo ""

# Test 4: Check service configuration and selectors
echo "[4/10] Checking service selectors..."

# Check Prometheus service
log_info "Prometheus service:"
PROM_SVC_SELECTOR=$(kubectl get svc prometheus -n monitoring -o jsonpath='{.spec.selector}' 2>/dev/null)
if [[ -n "$PROM_SVC_SELECTOR" ]]; then
  echo "  Selector: $PROM_SVC_SELECTOR"
  log_pass "Prometheus service selector found"
else
  log_fail "Prometheus service not found or has no selector"
fi

# Check Loki service
log_info "Loki service:"
LOKI_SVC_SELECTOR=$(kubectl get svc loki -n monitoring -o jsonpath='{.spec.selector}' 2>/dev/null)
if [[ -n "$LOKI_SVC_SELECTOR" ]]; then
  echo "  Selector: $LOKI_SVC_SELECTOR"
  log_pass "Loki service selector found"
else
  log_fail "Loki service not found or has no selector"
fi
echo ""

# Test 5: Check pod labels match service selectors
echo "[5/10] Checking pod labels match service selectors..."

# Get Prometheus pod labels
PROM_POD_LABELS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null)
if [[ -n "$PROM_POD_LABELS" ]]; then
  log_info "Prometheus pod labels:"
  echo "  $PROM_POD_LABELS"
  
  # Check if selector keys exist in pod labels
  if echo "$PROM_POD_LABELS" | grep -q "app.kubernetes.io/name.*prometheus"; then
    log_pass "Prometheus pod has correct app.kubernetes.io/name label"
  else
    log_fail "Prometheus pod missing app.kubernetes.io/name=prometheus label"
  fi
  
  if echo "$PROM_POD_LABELS" | grep -q "app.kubernetes.io/component.*monitoring"; then
    log_pass "Prometheus pod has correct app.kubernetes.io/component label"
  else
    log_fail "Prometheus pod missing app.kubernetes.io/component=monitoring label"
  fi
else
  log_warn "No Prometheus pods found to check labels"
fi

# Get Loki pod labels
LOKI_POD_LABELS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=loki -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null)
if [[ -n "$LOKI_POD_LABELS" ]]; then
  log_info "Loki pod labels:"
  echo "  $LOKI_POD_LABELS"
  
  # Check if selector keys exist in pod labels
  if echo "$LOKI_POD_LABELS" | grep -q "app.kubernetes.io/name.*loki"; then
    log_pass "Loki pod has correct app.kubernetes.io/name label"
  else
    log_fail "Loki pod missing app.kubernetes.io/name=loki label"
  fi
  
  if echo "$LOKI_POD_LABELS" | grep -q "app.kubernetes.io/component.*logging"; then
    log_pass "Loki pod has correct app.kubernetes.io/component label"
  else
    log_fail "Loki pod missing app.kubernetes.io/component=logging label"
  fi
else
  log_warn "No Loki pods found to check labels"
fi
echo ""

# Test 6: Check endpoints
echo "[6/10] Checking service endpoints..."

# Check Prometheus endpoints
PROM_ENDPOINTS=$(kubectl get endpoints prometheus -n monitoring -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
if [[ -n "$PROM_ENDPOINTS" ]]; then
  log_pass "Prometheus endpoints: $PROM_ENDPOINTS"
else
  log_fail "Prometheus service has NO endpoints (empty)"
  log_info "This means pods are not matching the service selector or pods are not ready"
fi

# Check Loki endpoints
LOKI_ENDPOINTS=$(kubectl get endpoints loki -n monitoring -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
if [[ -n "$LOKI_ENDPOINTS" ]]; then
  log_pass "Loki endpoints: $LOKI_ENDPOINTS"
else
  log_fail "Loki service has NO endpoints (empty)"
  log_info "This means pods are not matching the service selector or pods are not ready"
fi
echo ""

# Test 7: Check PVC status
echo "[7/10] Checking PersistentVolumeClaims..."
PVC_OUTPUT=$(kubectl get pvc -n monitoring 2>&1)
if [[ $? -eq 0 ]]; then
  echo "$PVC_OUTPUT"
  
  # Check for pending PVCs
  PENDING_PVCS=$(echo "$PVC_OUTPUT" | grep -c "Pending" || true)
  if [[ $PENDING_PVCS -eq 0 ]]; then
    log_pass "No PVCs in Pending state"
  else
    log_fail "$PENDING_PVCS PVC(s) in Pending state"
    log_info "Pending PVCs can prevent pods from starting, causing empty endpoints"
  fi
  
  # Check for Bound PVCs
  BOUND_PVCS=$(echo "$PVC_OUTPUT" | grep -c "Bound" || true)
  if [[ $BOUND_PVCS -gt 0 ]]; then
    log_pass "$BOUND_PVCS PVC(s) successfully bound"
  fi
else
  log_warn "No PVCs found in monitoring namespace"
fi
echo ""

# Test 8: Check for CrashLoopBackOff or ImagePullBackOff
echo "[8/10] Checking for pod failures..."

CRASHED_PODS=$(kubectl get pods -n monitoring --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null)
if [[ -n "$CRASHED_PODS" ]] && [[ $(echo "$CRASHED_PODS" | wc -l) -gt 1 ]]; then
  log_fail "Found pods with issues:"
  echo "$CRASHED_PODS"
  log_info "Run: kubectl describe pod <pod-name> -n monitoring"
  log_info "Run: kubectl logs <pod-name> -n monitoring --tail=100"
else
  log_pass "No pods in error states"
fi
echo ""

# Test 9: Check headless service configuration
echo "[9/10] Checking headless service configuration..."

# Check if Prometheus service is headless
PROM_CLUSTER_IP=$(kubectl get svc prometheus -n monitoring -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [[ "$PROM_CLUSTER_IP" == "None" ]]; then
  log_pass "Prometheus service is headless (ClusterIP: None)"
  log_info "For headless services, use FQDN: prometheus.monitoring.svc.cluster.local"
else
  log_info "Prometheus service has ClusterIP: $PROM_CLUSTER_IP (not headless)"
fi

# Check if Loki service is headless
LOKI_CLUSTER_IP=$(kubectl get svc loki -n monitoring -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [[ "$LOKI_CLUSTER_IP" == "None" ]]; then
  log_pass "Loki service is headless (ClusterIP: None)"
  log_info "For headless services, use FQDN: loki.monitoring.svc.cluster.local"
else
  log_info "Loki service has ClusterIP: $LOKI_CLUSTER_IP (not headless)"
fi
echo ""

# Test 10: DNS resolution test
echo "[10/10] Testing DNS resolution for headless services..."

# Try to create a test pod for DNS resolution
cat > /tmp/dns-test-pod.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: dns-test
  namespace: monitoring
spec:
  containers:
  - name: dns-test
    image: busybox:latest
    command: ['sh', '-c', 'sleep 60']
  restartPolicy: Never
EOF

kubectl apply -f /tmp/dns-test-pod.yaml &> /dev/null || true
sleep 5

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/dns-test -n monitoring --timeout=30s &> /dev/null || true

# Test DNS resolution
if kubectl get pod dns-test -n monitoring &> /dev/null; then
  log_info "Testing DNS resolution from within cluster..."
  
  # Test Prometheus FQDN
  PROM_DNS_TEST=$(kubectl exec -n monitoring dns-test -- nslookup prometheus.monitoring.svc.cluster.local 2>&1 || echo "FAILED")
  if echo "$PROM_DNS_TEST" | grep -q "Address"; then
    log_pass "DNS resolution works for prometheus.monitoring.svc.cluster.local"
  else
    log_fail "DNS resolution FAILED for prometheus.monitoring.svc.cluster.local"
    log_info "Headless services need endpoints to resolve in DNS"
  fi
  
  # Test Loki FQDN
  LOKI_DNS_TEST=$(kubectl exec -n monitoring dns-test -- nslookup loki.monitoring.svc.cluster.local 2>&1 || echo "FAILED")
  if echo "$LOKI_DNS_TEST" | grep -q "Address"; then
    log_pass "DNS resolution works for loki.monitoring.svc.cluster.local"
  else
    log_fail "DNS resolution FAILED for loki.monitoring.svc.cluster.local"
    log_info "Headless services need endpoints to resolve in DNS"
  fi
  
  # Cleanup
  kubectl delete pod dns-test -n monitoring &> /dev/null || true
else
  log_warn "Could not create DNS test pod, skipping DNS resolution test"
fi

rm -f /tmp/dns-test-pod.yaml

echo ""
echo "======================================================================"
echo "Diagnostic Summary"
echo "======================================================================"
echo ""
log_info "Common root causes for empty endpoints:"
echo "  A) Service selector and pod labels don't match"
echo "  B) Pods not running or not ready (CrashLoopBackOff, Pending, etc.)"
echo "  C) PVCs stuck in Pending state"
echo "  D) Permission errors on PersistentVolumes"
echo ""
log_info "Recommended fixes:"
echo "  1. Check pod status: kubectl get pods -n monitoring -o wide"
echo "  2. Check pod logs: kubectl logs -n monitoring <pod-name> --tail=100"
echo "  3. Describe pod: kubectl describe pod -n monitoring <pod-name>"
echo "  4. Check PVC status: kubectl get pvc -n monitoring"
echo "  5. Verify service selector matches pod labels"
echo "  6. Use FQDNs for headless services in Grafana datasources"
echo ""
log_info "For detailed troubleshooting, see:"
echo "  docs/HEADLESS_SERVICE_ENDPOINTS_TROUBLESHOOTING.md"
echo ""

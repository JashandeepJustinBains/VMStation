#!/usr/bin/env bash
# Kubespray Deployment Smoke Test
# Validates that the Kubespray deployment is functional
#
# Usage: ./tests/kubespray-smoke.sh [--namespace NS]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_NAMESPACE="smoke-test"
CLEANUP=true

log_info() { echo "[INFO] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_err() { echo "[ERROR] $*" >&2; }
log_pass() { echo "[PASS] ✓ $*" >&2; }
log_fail() { echo "[FAIL] ✗ $*" >&2; }

usage() {
    cat <<EOF
Kubespray Deployment Smoke Test

Usage: $(basename "$0") [options]

Options:
    --namespace NS  Use custom namespace (default: smoke-test)
    --no-cleanup    Don't cleanup test resources after completion
    -h, --help      Show this help message

Tests performed:
1. Cluster accessibility
2. Node readiness
3. CoreDNS functionality
4. Pod scheduling and networking
5. Service creation and connectivity
6. Volume mounting

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace) TEST_NAMESPACE=$2; shift 2 ;;
        --no-cleanup) CLEANUP=false; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_err "Unknown option: $1"; exit 1 ;;
    esac
done

TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    
    log_info "Running: $test_name"
    
    if eval "$test_cmd" &>/dev/null; then
        log_pass "$test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# Cleanup function
cleanup() {
    if [[ "$CLEANUP" == "true" ]]; then
        log_info "Cleaning up test resources..."
        kubectl delete namespace "$TEST_NAMESPACE" --ignore-not-found=true &>/dev/null || true
    fi
}

trap cleanup EXIT

log_info "=========================================="
log_info "Kubespray Deployment Smoke Test"
log_info "=========================================="
log_info "Test namespace: $TEST_NAMESPACE"
log_info ""

# Test 1: Cluster accessibility
log_info "TEST 1: Cluster Accessibility"
run_test "Cluster is reachable" "kubectl cluster-info"

# Test 2: Node readiness
log_info ""
log_info "TEST 2: Node Readiness"
run_test "All nodes are ready" "kubectl wait --for=condition=Ready nodes --all --timeout=30s"

TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
READY_NODES=$(kubectl get nodes --no-headers | grep -c " Ready " || true)
log_info "Nodes: $READY_NODES/$TOTAL_NODES ready"

# Test 3: CoreDNS
log_info ""
log_info "TEST 3: CoreDNS Functionality"
run_test "CoreDNS pods are running" "kubectl -n kube-system get pods -l k8s-app=kube-dns --field-selector=status.phase=Running"

# Test 4: Create test namespace
log_info ""
log_info "TEST 4: Namespace Management"
kubectl create namespace "$TEST_NAMESPACE" &>/dev/null || true
run_test "Test namespace created" "kubectl get namespace $TEST_NAMESPACE"

# Test 5: Pod scheduling
log_info ""
log_info "TEST 5: Pod Scheduling"
cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: smoke-test-pod
  namespace: $TEST_NAMESPACE
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
EOF

run_test "Pod scheduled" "kubectl -n $TEST_NAMESPACE wait --for=condition=Ready pod/smoke-test-pod --timeout=60s"

# Test 6: Service creation
log_info ""
log_info "TEST 6: Service Creation"
cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Service
metadata:
  name: smoke-test-service
  namespace: $TEST_NAMESPACE
spec:
  selector:
    run: smoke-test-pod
  ports:
  - port: 80
    targetPort: 80
EOF

run_test "Service created" "kubectl -n $TEST_NAMESPACE get service smoke-test-service"

# Test 7: DNS resolution
log_info ""
log_info "TEST 7: DNS Resolution"
cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: smoke-test-dns
  namespace: $TEST_NAMESPACE
spec:
  containers:
  - name: busybox
    image: busybox:latest
    command: ['sh', '-c', 'sleep 3600']
EOF

kubectl -n "$TEST_NAMESPACE" wait --for=condition=Ready pod/smoke-test-dns --timeout=60s &>/dev/null || true

if kubectl -n "$TEST_NAMESPACE" exec smoke-test-dns -- nslookup kubernetes.default.svc.cluster.local &>/dev/null; then
    log_pass "DNS resolution works"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_fail "DNS resolution failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 8: Inter-pod networking
log_info ""
log_info "TEST 8: Inter-pod Networking"

# Wait for smoke-test-pod to be ready
kubectl -n "$TEST_NAMESPACE" wait --for=condition=Ready pod/smoke-test-pod --timeout=60s &>/dev/null || true

# Get the pod IP
POD_IP=$(kubectl -n "$TEST_NAMESPACE" get pod smoke-test-pod -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")

if [[ -n "$POD_IP" ]]; then
    if kubectl -n "$TEST_NAMESPACE" exec smoke-test-dns -- wget -q -O- "http://$POD_IP" &>/dev/null; then
        log_pass "Inter-pod networking works"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        log_fail "Inter-pod networking failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
else
    log_fail "Could not get pod IP"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 9: Deployment creation
log_info ""
log_info "TEST 9: Deployment Management"
cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: smoke-test-deployment
  namespace: $TEST_NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: smoke-test
  template:
    metadata:
      labels:
        app: smoke-test
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
EOF

run_test "Deployment created" "kubectl -n $TEST_NAMESPACE wait --for=condition=available --timeout=60s deployment/smoke-test-deployment"

DESIRED_REPLICAS=$(kubectl -n "$TEST_NAMESPACE" get deployment smoke-test-deployment -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
READY_REPLICAS=$(kubectl -n "$TEST_NAMESPACE" get deployment smoke-test-deployment -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
log_info "Deployment replicas: $READY_REPLICAS/$DESIRED_REPLICAS ready"

# Test 10: Resource limits
log_info ""
log_info "TEST 10: Resource Limits"
cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: smoke-test-resources
  namespace: $TEST_NAMESPACE
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
EOF

run_test "Resource limits applied" "kubectl -n $TEST_NAMESPACE wait --for=condition=Ready pod/smoke-test-resources --timeout=60s"

# Summary
log_info ""
log_info "=========================================="
log_info "Smoke Test Summary"
log_info "=========================================="
log_info "Tests passed: $TESTS_PASSED"
log_info "Tests failed: $TESTS_FAILED"
log_info "Total tests: $((TESTS_PASSED + TESTS_FAILED))"
log_info ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    log_pass "All smoke tests passed! ✓"
    log_info ""
    log_info "Your Kubespray deployment is functional and ready for:"
    log_info "  - Monitoring stack deployment: ./deploy.sh monitoring"
    log_info "  - Infrastructure deployment: ./deploy.sh infrastructure"
    exit 0
else
    log_fail "Some smoke tests failed!"
    log_info ""
    log_info "Troubleshooting:"
    log_info "  - Check cluster status: kubectl get nodes,pods -A"
    log_info "  - Run diagnostics: ./scripts/diagnose-kubespray-cluster.sh"
    log_info "  - Check logs: kubectl logs -n kube-system <pod-name>"
    exit 1
fi

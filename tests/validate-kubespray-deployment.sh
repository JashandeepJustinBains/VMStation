#!/usr/bin/env bash
# Kubespray Deployment End-to-End Validation
# Validates complete deployment workflow and cluster health
#
# Usage: ./tests/validate-kubespray-deployment.sh [--verbose]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLAG_VERBOSE=false

log_info() { echo "[INFO] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_err() { echo "[ERROR] $*" >&2; }
log_pass() { echo "[PASS] ✓ $*" >&2; }
log_fail() { echo "[FAIL] ✗ $*" >&2; }

usage() {
    cat <<EOF
Kubespray Deployment End-to-End Validation

Usage: $(basename "$0") [options]

Options:
    --verbose   Show detailed output
    -h, --help  Show this help message

This script validates:
1. Kubespray setup and venv
2. Inventory configuration
3. Ansible connectivity
4. Cluster accessibility
5. Node readiness
6. System pods (CoreDNS, kube-proxy, CNI)
7. Monitoring stack
8. Infrastructure services

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose) FLAG_VERBOSE=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) log_err "Unknown option: $1"; exit 1 ;;
    esac
done

CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

# Check function
check() {
    local description="$1"
    local command="$2"
    local required="${3:-true}"
    
    log_info "Checking: $description"
    
    if eval "$command" &>/dev/null; then
        log_pass "$description"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        return 0
    else
        if [[ "$required" == "true" ]]; then
            log_fail "$description"
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
        else
            log_warn "$description (optional)"
            CHECKS_WARNING=$((CHECKS_WARNING + 1))
        fi
        return 1
    fi
}

log_info "=========================================="
log_info "Kubespray Deployment Validation"
log_info "=========================================="
log_info ""

# === 1. Kubespray Setup ===
log_info "━━━ 1. Kubespray Setup ━━━"

check "Kubespray directory exists" "test -d $REPO_ROOT/.cache/kubespray"
check "Kubespray venv exists" "test -d $REPO_ROOT/.cache/kubespray/.venv"
check "Kubespray venv has ansible" "test -f $REPO_ROOT/.cache/kubespray/.venv/bin/ansible"
check "Kubespray venv has ansible-playbook" "test -f $REPO_ROOT/.cache/kubespray/.venv/bin/ansible-playbook"

# Check inventory
KUBESPRAY_INVENTORY="$REPO_ROOT/.cache/kubespray/inventory/mycluster/inventory.ini"
MAIN_INVENTORY="$REPO_ROOT/inventory.ini"

check "Kubespray inventory exists" "test -f $KUBESPRAY_INVENTORY"
check "Main inventory exists" "test -f $MAIN_INVENTORY"

# Validate inventory structure
if check "Inventory is valid YAML/INI" "ansible-inventory -i $MAIN_INVENTORY --list" false; then
    if [[ "$FLAG_VERBOSE" == "true" ]]; then
        log_info "Inventory groups:"
        ansible-inventory -i "$MAIN_INVENTORY" --graph
    fi
fi

log_info ""

# === 2. Node Connectivity ===
log_info "━━━ 2. Node Connectivity ━━━"

# Check if ansible can reach nodes
if check "Ansible can ping all nodes" "ansible all -i $MAIN_INVENTORY -m ping" false; then
    log_info "All nodes are reachable via Ansible"
else
    log_warn "Some nodes may be unreachable. Try: ./scripts/wake-node.sh all --wait"
fi

log_info ""

# === 3. Cluster Accessibility ===
log_info "━━━ 3. Kubernetes Cluster ━━━"

# Check if kubectl is available
if ! check "kubectl is installed" "command -v kubectl"; then
    log_err "kubectl not found. Cannot validate cluster."
    exit 1
fi

# Check if kubeconfig exists
KUBECONFIG_PATHS=(
    "$REPO_ROOT/.cache/kubespray/inventory/mycluster/artifacts/admin.conf"
    "$HOME/.kube/config"
    "/etc/kubernetes/admin.conf"
)

KUBECONFIG_FOUND=""
for kconfig in "${KUBECONFIG_PATHS[@]}"; do
    if [[ -f "$kconfig" ]]; then
        KUBECONFIG_FOUND="$kconfig"
        log_pass "Kubeconfig found at: $kconfig"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        break
    fi
done

if [[ -z "$KUBECONFIG_FOUND" ]]; then
    log_fail "No kubeconfig found"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
    log_err "Expected kubeconfig at one of: ${KUBECONFIG_PATHS[*]}"
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_FOUND"

# Check cluster access
check "Cluster is accessible" "kubectl cluster-info"

log_info ""

# === 4. Node Status ===
log_info "━━━ 4. Node Status ━━━"

if kubectl get nodes &>/dev/null; then
    TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
    READY_NODES=$(kubectl get nodes --no-headers | grep -c " Ready " || echo "0")
    
    log_info "Nodes: $READY_NODES/$TOTAL_NODES ready"
    
    if [[ "$FLAG_VERBOSE" == "true" ]]; then
        kubectl get nodes -o wide
    fi
    
    if [[ $READY_NODES -eq $TOTAL_NODES ]]; then
        log_pass "All nodes are Ready"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_fail "Not all nodes are Ready ($READY_NODES/$TOTAL_NODES)"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
else
    log_fail "Cannot get nodes"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

log_info ""

# === 5. System Pods ===
log_info "━━━ 5. System Pods (kube-system) ━━━"

if kubectl -n kube-system get pods &>/dev/null; then
    TOTAL_SYSTEM_PODS=$(kubectl -n kube-system get pods --no-headers | wc -l)
    RUNNING_SYSTEM_PODS=$(kubectl -n kube-system get pods --no-headers | grep -c "Running\|Completed" || echo "0")
    
    log_info "System pods: $RUNNING_SYSTEM_PODS/$TOTAL_SYSTEM_PODS running"
    
    if [[ "$FLAG_VERBOSE" == "true" ]]; then
        kubectl -n kube-system get pods -o wide
    fi
    
    if [[ $RUNNING_SYSTEM_PODS -eq $TOTAL_SYSTEM_PODS ]]; then
        log_pass "All system pods are Running/Completed"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        log_warn "Some system pods are not Running ($RUNNING_SYSTEM_PODS/$TOTAL_SYSTEM_PODS)"
        CHECKS_WARNING=$((CHECKS_WARNING + 1))
        
        log_info "Failing pods:"
        kubectl -n kube-system get pods --no-headers | grep -vE "Running|Completed" || true
    fi
else
    log_fail "Cannot get system pods"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

log_info ""

# === 6. CoreDNS ===
log_info "━━━ 6. CoreDNS ━━━"

check "CoreDNS deployment exists" "kubectl -n kube-system get deployment coredns"
check "CoreDNS pods are running" "kubectl -n kube-system get pods -l k8s-app=kube-dns --field-selector=status.phase=Running" false

log_info ""

# === 7. CNI/Networking ===
log_info "━━━ 7. CNI/Networking ━━━"

check "CNI DaemonSet exists" "kubectl -n kube-system get ds" false

if [[ "$FLAG_VERBOSE" == "true" ]]; then
    log_info "DaemonSets:"
    kubectl -n kube-system get ds -o wide
fi

log_info ""

# === 8. Monitoring Stack ===
log_info "━━━ 8. Monitoring Stack (optional) ━━━"

check "Prometheus namespace exists" "kubectl get namespace monitoring" false
check "Prometheus pods running" "kubectl -n monitoring get pods -l app=prometheus --field-selector=status.phase=Running" false
check "Grafana pods running" "kubectl -n monitoring get pods -l app=grafana --field-selector=status.phase=Running" false

log_info ""

# === 9. Infrastructure Services ===
log_info "━━━ 9. Infrastructure Services (optional) ━━━"

check "NTP service exists" "systemctl is-active chrony || systemctl is-active ntp" false
check "Syslog service exists" "systemctl is-active rsyslog || systemctl is-active syslog-ng" false

log_info ""

# === 10. Scripts and Tools ===
log_info "━━━ 10. Deployment Scripts ━━━"

check "deploy-kubespray-full.sh exists" "test -x $REPO_ROOT/scripts/deploy-kubespray-full.sh"
check "normalize-kubespray-inventory.sh exists" "test -x $REPO_ROOT/scripts/normalize-kubespray-inventory.sh"
check "wake-node.sh exists" "test -x $REPO_ROOT/scripts/wake-node.sh"
check "diagnose-kubespray-cluster.sh exists" "test -x $REPO_ROOT/scripts/diagnose-kubespray-cluster.sh"
check "kubespray-smoke.sh exists" "test -x $REPO_ROOT/tests/kubespray-smoke.sh"

log_info ""

# === Summary ===
log_info "=========================================="
log_info "Validation Summary"
log_info "=========================================="
log_info "Passed:   $CHECKS_PASSED ✓"
log_info "Failed:   $CHECKS_FAILED ✗"
log_info "Warnings: $CHECKS_WARNING ⚠"
log_info "Total:    $((CHECKS_PASSED + CHECKS_FAILED + CHECKS_WARNING))"
log_info ""

if [[ $CHECKS_FAILED -eq 0 ]]; then
    log_pass "Validation PASSED - Deployment is healthy!"
    log_info ""
    log_info "Next steps:"
    log_info "  - Run smoke tests: ./tests/kubespray-smoke.sh"
    log_info "  - Deploy monitoring: ./deploy.sh monitoring"
    log_info "  - Deploy infrastructure: ./deploy.sh infrastructure"
    exit 0
else
    log_fail "Validation FAILED - $CHECKS_FAILED critical issues found"
    log_info ""
    log_info "Troubleshooting:"
    log_info "  - Run diagnostics: ./scripts/diagnose-kubespray-cluster.sh"
    log_info "  - Check logs in: ansible/artifacts/"
    log_info "  - Refer to: docs/KUBESPRAY_DEPLOYMENT_GUIDE.md"
    exit 1
fi

#!/usr/bin/env bash
# =============================================================================
# VMStation Cluster Validation Script
# Runs comprehensive checks to validate deployment health
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; ((WARN_COUNT++)); }
fail() { echo -e "${RED}[FAIL]${NC} $*"; ((FAIL_COUNT++)); }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; ((PASS_COUNT++)); }

check_command() {
  if command -v "$1" &>/dev/null; then
    pass "$1 is installed"
    return 0
  else
    fail "$1 is not installed"
    return 1
  fi
}

check_file() {
  if [ -f "$1" ]; then
    pass "File exists: $1"
    return 0
  else
    fail "File missing: $1"
    return 1
  fi
}

echo "======================================================================"
echo "          VMStation Cluster Validation"
echo "======================================================================"
echo ""

# -----------------------------------------------------------------------------
info "Checking prerequisites..."
# -----------------------------------------------------------------------------
check_command kubectl
check_command ansible
check_command ansible-playbook

# -----------------------------------------------------------------------------
info "Checking node status..."
# -----------------------------------------------------------------------------
if kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes &>/dev/null; then
  total_nodes=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --no-headers | wc -l)
  ready_nodes=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --no-headers | awk '$2 == "Ready"' | wc -l)
  
  if [ "$total_nodes" -eq 3 ]; then
    pass "All 3 nodes registered"
  else
    fail "Expected 3 nodes, found $total_nodes"
  fi
  
  if [ "$ready_nodes" -eq "$total_nodes" ]; then
    pass "All nodes are Ready ($ready_nodes/$total_nodes)"
  else
    fail "Not all nodes Ready: $ready_nodes/$total_nodes"
    kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o wide
  fi
else
  fail "kubectl cannot connect to cluster"
fi

# -----------------------------------------------------------------------------
info "Checking kube-system pods..."
# -----------------------------------------------------------------------------
if kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system get pods &>/dev/null; then
  crash_pods=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A \
    -o json | jq -r '.items[] | select(.status.containerStatuses[]? | .state.waiting.reason? == "CrashLoopBackOff") | .metadata.name' | wc -l)
  
  if [ "$crash_pods" -eq 0 ]; then
    pass "No CrashLoopBackOff pods detected"
  else
    fail "CrashLoopBackOff pods detected: $crash_pods"
    kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A | grep -i crash
  fi
  
  kube_proxy_running=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system get pods -l k8s-app=kube-proxy --field-selector=status.phase=Running --no-headers | wc -l)
  
  if [ "$kube_proxy_running" -eq 3 ]; then
    pass "All 3 kube-proxy pods are Running"
  else
    fail "Not all kube-proxy pods Running: $kube_proxy_running/3"
  fi
else
  fail "Cannot query kube-system namespace"
fi

# -----------------------------------------------------------------------------
info "Checking Flannel CNI..."
# -----------------------------------------------------------------------------
if kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-flannel get pods &>/dev/null; then
  flannel_running=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-flannel get pods -l app=flannel --field-selector=status.phase=Running --no-headers | wc -l)
  
  if [ "$flannel_running" -eq 3 ]; then
    pass "All 3 Flannel pods are Running"
  else
    fail "Not all Flannel pods Running: $flannel_running/3"
  fi
else
  fail "Flannel namespace not found"
fi

# -----------------------------------------------------------------------------
info "Checking CNI configuration on all nodes..."
# -----------------------------------------------------------------------------
for node in $(kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes -o name | cut -d/ -f2); do
  if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$node" \
    'test -f /etc/cni/net.d/10-flannel.conflist' 2>/dev/null; then
    pass "CNI config present on $node"
  else
    fail "CNI config missing on $node"
  fi
done

# -----------------------------------------------------------------------------
info "Checking RHEL 10 iptables configuration..."
# -----------------------------------------------------------------------------
if ssh -o StrictHostKeyChecking=no homelab \
  'update-alternatives --display iptables | grep -q iptables-nft' 2>/dev/null; then
  pass "RHEL 10 node using nftables backend"
else
  fail "RHEL 10 node not using nftables backend"
fi

if ssh -o StrictHostKeyChecking=no homelab \
  'iptables -t nat -L | grep -q KUBE-SERVICES' 2>/dev/null; then
  pass "RHEL 10 iptables chains exist"
else
  fail "RHEL 10 iptables chains missing"
fi

# -----------------------------------------------------------------------------
info "Checking auto-sleep setup..."
# -----------------------------------------------------------------------------
if crontab -l 2>/dev/null | grep -q "VMStation Auto-Sleep"; then
  pass "Auto-sleep cron job configured"
else
  warn "Auto-sleep cron job not configured (run: ./deploy.sh setup)"
fi

check_file /var/log/vmstation-autosleep.log || warn "Auto-sleep log file not created yet"
check_file /root/VMStation/ansible/playbooks/trigger-sleep.sh
check_file /root/VMStation/ansible/playbooks/wake-cluster.sh

if command -v wakeonlan &>/dev/null; then
  pass "wakeonlan utility installed"
else
  warn "wakeonlan not installed (needed for auto-sleep)"
fi

# -----------------------------------------------------------------------------
info "Checking file permissions..."
# -----------------------------------------------------------------------------
if [ -x /root/VMStation/ansible/playbooks/trigger-sleep.sh ]; then
  pass "trigger-sleep.sh is executable"
else
  fail "trigger-sleep.sh is not executable"
fi

if [ -x /root/VMStation/ansible/playbooks/wake-cluster.sh ]; then
  pass "wake-cluster.sh is executable"
else
  fail "wake-cluster.sh is not executable"
fi

# -----------------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "                    Validation Summary"
echo "======================================================================"
echo -e "${GREEN}PASSED:${NC} $PASS_COUNT"
echo -e "${YELLOW}WARNINGS:${NC} $WARN_COUNT"
echo -e "${RED}FAILED:${NC} $FAIL_COUNT"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}✅ Cluster validation PASSED${NC}"
  echo ""
  echo "Your cluster is healthy and ready for use!"
  echo ""
  echo "Next steps:"
  echo "  - Deploy applications: kubectl apply -f manifests/"
  echo "  - Setup auto-sleep: ./deploy.sh setup (if not done)"
  echo "  - Monitor logs: tail -f /var/log/vmstation-autosleep.log"
  exit 0
else
  echo -e "${RED}❌ Cluster validation FAILED${NC}"
  echo ""
  echo "Please review failures above and fix issues."
  echo ""
  echo "Common fixes:"
  echo "  - Reset and redeploy: ./deploy.sh reset && ./deploy.sh"
  echo "  - Check logs: kubectl logs -n kube-system <pod-name>"
  echo "  - Check kubelet: ssh <node> journalctl -u kubelet -f"
  exit 1
fi

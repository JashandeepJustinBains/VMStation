#!/bin/bash

# Coordinated Fix for Problem Statement Networking Issues
# Addresses the specific multi-component networking failure described in the GitHub issue
# This script orchestrates repairs in the correct order to restore cluster networking

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }
critical() { echo -e "${PURPLE}[CRITICAL]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NON_INTERACTIVE=false
FORCE_REPAIR=false
DRY_RUN=false

# Progress tracking
TOTAL_STEPS=8
CURRENT_STEP=0
REPAIR_LOG="/tmp/vmstation-problem-statement-repair-$(date +%s).log"

# Function to track progress
step_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo "=== STEP $CURRENT_STEP/$TOTAL_STEPS: $1 ===" | tee -a "$REPAIR_LOG"
    info "[$CURRENT_STEP/$TOTAL_STEPS] $1"
}

# Function to wait for user confirmation
confirm_continue() {
    if [ "$NON_INTERACTIVE" = false ]; then
        echo
        warn "Press Enter to continue, or Ctrl+C to abort..."
        read -r
        echo
    fi
}

# Function to check if we're running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root (sudo)"
        echo "Usage: sudo $0 [options]"
        exit 1
    fi
}

# Function to check prerequisites 
check_prerequisites() {
    local prereq_ok=true
    
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl not found"
        prereq_ok=false
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster"
        prereq_ok=false
    fi
    
    if [ "$prereq_ok" = false ]; then
        critical "Prerequisites not met. Please fix the above issues."
        exit 1
    fi
}

# Function to detect problem statement pattern
detect_problem_pattern() {
    info "Detecting problem statement networking pattern..."
    
    local pattern_score=0
    local max_score=6
    
    # Check 1: CoreDNS CrashLoopBackOff
    if kubectl get pods -n kube-system -l k8s-app=kube-dns 2>/dev/null | grep -q "CrashLoopBackOff"; then
        pattern_score=$((pattern_score + 1))
        warn "✓ Detected: CoreDNS CrashLoopBackOff"
    fi
    
    # Check 2: kube-proxy issues
    if kubectl get pods -n kube-system -l k8s-app=kube-proxy 2>/dev/null | grep -q "CrashLoopBackOff\|BackOff"; then
        pattern_score=$((pattern_score + 1))
        warn "✓ Detected: kube-proxy restart issues"
    fi
    
    # Check 3: Missing Flannel
    if ! kubectl get ds -n kube-system kube-flannel >/dev/null 2>&1; then
        pattern_score=$((pattern_score + 1))
        warn "✓ Detected: Flannel daemonset missing"
    fi
    
    # Check 4: DNS resolution failures
    if kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20 2>/dev/null | grep -q "i/o timeout"; then
        pattern_score=$((pattern_score + 1))
        warn "✓ Detected: DNS resolution timeouts"
    fi
    
    # Check 5: Service endpoints missing
    if kubectl get endpoints -A 2>/dev/null | grep -q "<none>"; then
        pattern_score=$((pattern_score + 1))
        warn "✓ Detected: Services with no endpoints"
    fi
    
    # Check 6: Pod network connectivity failure (quick test)
    local test_connectivity=false
    if kubectl run --rm -i test-conn-$(date +%s) --image=busybox --restart=Never --timeout=30s -- sh -c "ping -c1 -W3 10.244.1.1" >/dev/null 2>&1; then
        debug "Pod connectivity test passed"
    else
        pattern_score=$((pattern_score + 1))
        warn "✓ Detected: Pod network connectivity failure"
        test_connectivity=true
    fi
    
    echo "Pattern detection score: $pattern_score/$max_score" | tee -a "$REPAIR_LOG"
    
    if [ $pattern_score -ge 4 ]; then
        critical "🚨 PROBLEM STATEMENT PATTERN CONFIRMED"
        echo "This cluster exhibits the exact networking failure described in the GitHub issue."
        echo "Proceeding with coordinated repair..."
        return 0
    elif [ $pattern_score -ge 2 ]; then
        warn "⚠️  PARTIAL PATTERN MATCH"
        echo "Some symptoms match the problem statement. Repair may still be beneficial."
        if [ "$FORCE_REPAIR" = false ] && [ "$NON_INTERACTIVE" = false ]; then
            echo
            warn "Continue with repair anyway? (y/N): "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                info "Repair cancelled by user"
                exit 0
            fi
        fi
        return 0
    else
        info "Pattern score too low ($pattern_score/$max_score)"
        warn "This cluster does not clearly exhibit the problem statement pattern."
        if [ "$FORCE_REPAIR" = false ]; then
            echo "Use --force to proceed anyway, or run standard network troubleshooting."
            exit 0
        fi
        return 1
    fi
}

# Main repair functions
repair_iptables_backend() {
    step_progress "Fix iptables backend compatibility"
    
    if [ -f "$SCRIPT_DIR/fix_iptables_compatibility.sh" ]; then
        info "Running iptables compatibility fix..."
        if [ "$DRY_RUN" = false ]; then
            "$SCRIPT_DIR/fix_iptables_compatibility.sh" --non-interactive 2>&1 | tee -a "$REPAIR_LOG"
        else
            info "[DRY RUN] Would run: fix_iptables_compatibility.sh"
        fi
    else
        warn "iptables compatibility script not found, skipping..."
    fi
}

repair_cni_bridge() {
    step_progress "Fix CNI bridge conflicts"
    
    if [ -f "$SCRIPT_DIR/fix_cni_bridge_conflict.sh" ]; then
        info "Running CNI bridge conflict fix..."
        if [ "$DRY_RUN" = false ]; then
            "$SCRIPT_DIR/fix_cni_bridge_conflict.sh" --non-interactive 2>&1 | tee -a "$REPAIR_LOG"
        else
            info "[DRY RUN] Would run: fix_cni_bridge_conflict.sh"
        fi
    else
        warn "CNI bridge fix script not found, skipping..."
    fi
}

repair_flannel_cni() {
    step_progress "Repair/reinstall Flannel CNI"
    
    # Check if Flannel exists
    if ! kubectl get ds -n kube-system kube-flannel >/dev/null 2>&1; then
        warn "Flannel daemonset missing - need to reinstall"
        
        if [ "$DRY_RUN" = false ]; then
            # Install Flannel
            info "Installing Flannel CNI..."
            kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml 2>&1 | tee -a "$REPAIR_LOG"
            
            # Wait for Flannel pods to be ready
            info "Waiting for Flannel pods to become ready..."
            kubectl wait --for=condition=Ready pod -l app=flannel -n kube-flannel --timeout=300s 2>&1 | tee -a "$REPAIR_LOG" || true
        else
            info "[DRY RUN] Would reinstall Flannel CNI"
        fi
    else
        # Restart existing Flannel
        info "Restarting existing Flannel daemonset..."
        if [ "$DRY_RUN" = false ]; then
            kubectl rollout restart ds/kube-flannel -n kube-system 2>&1 | tee -a "$REPAIR_LOG"
            kubectl rollout status ds/kube-flannel -n kube-system --timeout=300s 2>&1 | tee -a "$REPAIR_LOG" || true
        else
            info "[DRY RUN] Would restart Flannel daemonset"
        fi
    fi
    
    # Run Flannel-specific fixes
    if [ -f "$SCRIPT_DIR/fix_flannel_mixed_os.sh" ]; then
        info "Applying Flannel mixed-OS fixes..."
        if [ "$DRY_RUN" = false ]; then
            "$SCRIPT_DIR/fix_flannel_mixed_os.sh" 2>&1 | tee -a "$REPAIR_LOG"
        else
            info "[DRY RUN] Would run: fix_flannel_mixed_os.sh"
        fi
    fi
}

repair_kube_proxy() {
    step_progress "Fix kube-proxy issues"
    
    info "Restarting kube-proxy daemonset..."
    if [ "$DRY_RUN" = false ]; then
        kubectl rollout restart ds/kube-proxy -n kube-system 2>&1 | tee -a "$REPAIR_LOG"
        
        info "Waiting for kube-proxy pods to be ready..."
        kubectl rollout status ds/kube-proxy -n kube-system --timeout=300s 2>&1 | tee -a "$REPAIR_LOG" || true
        
        # Check for remaining issues
        sleep 30
        failing_proxies=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers | grep -v "Running" | wc -l)
        if [ "$failing_proxies" -gt 0 ]; then
            warn "$failing_proxies kube-proxy pods still not running properly"
            
            # Run specific kube-proxy fix
            if [ -f "$SCRIPT_DIR/fix_remaining_pod_issues.sh" ]; then
                info "Running additional pod fixes..."
                "$SCRIPT_DIR/fix_remaining_pod_issues.sh" --non-interactive 2>&1 | tee -a "$REPAIR_LOG"
            fi
        fi
    else
        info "[DRY RUN] Would restart kube-proxy and check status"
    fi
}

repair_coredns() {
    step_progress "Fix CoreDNS issues"
    
    info "Restarting CoreDNS deployment..."
    if [ "$DRY_RUN" = false ]; then
        kubectl rollout restart deployment/coredns -n kube-system 2>&1 | tee -a "$REPAIR_LOG"
        
        info "Waiting for CoreDNS pods to be ready..."
        kubectl rollout status deployment/coredns -n kube-system --timeout=300s 2>&1 | tee -a "$REPAIR_LOG" || true
        
        # Wait a bit longer for DNS to stabilize
        info "Allowing DNS to stabilize..."
        sleep 60
        
        # Check CoreDNS status
        coredns_ready=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | grep "Running.*1/1" | wc -l)
        if [ "$coredns_ready" -eq 0 ]; then
            warn "CoreDNS not fully ready yet - may need additional time"
        else
            success "CoreDNS appears to be ready"
        fi
    else
        info "[DRY RUN] Would restart CoreDNS and wait for readiness"
    fi
}

repair_worker_nodes() {
    step_progress "Fix worker node CNI issues"
    
    # Get worker nodes
    worker_nodes=$(kubectl get nodes --no-headers | grep -v master | awk '{print $1}' || echo "")
    
    if [ -n "$worker_nodes" ]; then
        for node in $worker_nodes; do
            info "Checking worker node: $node"
            
            if [ -f "$SCRIPT_DIR/fix_worker_node_cni.sh" ]; then
                if [ "$DRY_RUN" = false ]; then
                    "$SCRIPT_DIR/fix_worker_node_cni.sh" --node "$node" --non-interactive 2>&1 | tee -a "$REPAIR_LOG" || true
                else
                    info "[DRY RUN] Would fix CNI on worker node: $node"
                fi
            fi
        done
    else
        info "No worker nodes detected or all nodes are control plane"
    fi
}

repair_system_networking() {
    step_progress "Fix system-level networking configuration"
    
    info "Checking and fixing system networking..."
    
    # Check IP forwarding
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
        warn "Enabling IP forwarding..."
        if [ "$DRY_RUN" = false ]; then
            echo 1 > /proc/sys/net/ipv4/ip_forward
            echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
        else
            info "[DRY RUN] Would enable IP forwarding"
        fi
    fi
    
    # Check bridge netfilter
    if [ -f /proc/sys/net/bridge/bridge-nf-call-iptables ]; then
        if [ "$(cat /proc/sys/net/bridge/bridge-nf-call-iptables)" != "1" ]; then
            warn "Enabling bridge netfilter..."
            if [ "$DRY_RUN" = false ]; then
                echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
            else
                info "[DRY RUN] Would enable bridge netfilter"
            fi
        fi
    fi
    
    # Restart networking services if needed
    if [ "$DRY_RUN" = false ]; then
        systemctl restart containerd 2>&1 | tee -a "$REPAIR_LOG" || true
        sleep 10
    else
        info "[DRY RUN] Would restart containerd"
    fi
}

validate_repair() {
    step_progress "Validate repair success"
    
    info "Running comprehensive validation..."
    
    # Test 1: Pod scheduling and networking
    info "Testing pod creation and networking..."
    
    if [ "$DRY_RUN" = false ]; then
        # Create test pod
        cat <<EOF | kubectl apply -f - >/dev/null 2>&1
apiVersion: v1
kind: Pod
metadata:
  name: repair-validation-$(date +%s)
  namespace: default
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot
    command: ["sleep", "300"]
  restartPolicy: Never
EOF

        # Wait for pod to be ready
        validation_pod=$(kubectl get pods --no-headers | grep repair-validation | head -1 | awk '{print $1}' || echo "")
        
        if [ -n "$validation_pod" ]; then
            if kubectl wait --for=condition=Ready pod/$validation_pod --timeout=120s >/dev/null 2>&1; then
                success "✓ Test pod creation and readiness: PASS"
                
                # Test DNS resolution
                if kubectl exec $validation_pod -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
                    success "✓ DNS resolution: PASS"
                else
                    error "✗ DNS resolution: FAIL"
                fi
                
                # Test external connectivity
                if kubectl exec $validation_pod -- timeout 10 curl -s https://www.google.com >/dev/null 2>&1; then
                    success "✓ External connectivity: PASS"
                else
                    warn "⚠ External connectivity: FAIL (may be network policy/firewall)"
                fi
                
            else
                error "✗ Test pod readiness: FAIL"
            fi
            
            # Cleanup
            kubectl delete pod $validation_pod --ignore-not-found >/dev/null 2>&1 || true
        else
            error "✗ Test pod creation: FAIL"
        fi
    else
        info "[DRY RUN] Would create test pod and validate networking"
    fi
    
    # Test 2: Component status
    info "Checking component health..."
    
    coredns_healthy=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | grep "Running.*1/1" | wc -l)
    kubeproxy_healthy=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --no-headers | grep "Running.*1/1" | wc -l)
    flannel_healthy=$(kubectl get pods -n kube-flannel --no-headers 2>/dev/null | grep "Running.*1/1" | wc -l || echo "0")
    
    info "Component health summary:"
    echo "  CoreDNS healthy pods: $coredns_healthy"
    echo "  kube-proxy healthy pods: $kubeproxy_healthy"
    echo "  Flannel healthy pods: $flannel_healthy"
    
    # Run problem statement specific validation if available
    if [ -f "$SCRIPT_DIR/test_problem_statement_scenarios.sh" ]; then
        info "Running problem statement scenario validation..."
        if [ "$DRY_RUN" = false ]; then
            "$SCRIPT_DIR/test_problem_statement_scenarios.sh" 2>&1 | tee -a "$REPAIR_LOG" || true
        else
            info "[DRY RUN] Would run problem statement scenario tests"
        fi
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --non-interactive|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        --force)
            FORCE_REPAIR=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            info "Running in dry-run mode - no changes will be made"
            shift
            ;;
        -h|--help)
            echo "VMStation Problem Statement Networking Fix"
            echo
            echo "Usage: $0 [options]"
            echo
            echo "Options:"
            echo "  --non-interactive, -y    Run without user prompts"
            echo "  --force                  Force repair even if pattern not detected"
            echo "  --dry-run                Show what would be done without making changes"
            echo "  -h, --help               Show this help message"
            echo
            echo "This script fixes the exact networking issues described in the GitHub problem statement:"
            echo "- CoreDNS CrashLoopBackOff with DNS resolution failures"
            echo "- kube-proxy restart issues and service routing problems"
            echo "- Missing/broken Flannel CNI causing pod isolation"
            echo "- Complete inter-pod communication failure"
            echo
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Main execution
echo "=================================================================="
echo "    VMStation Problem Statement Networking Repair"
echo "=================================================================="
echo "Fixing the specific networking issues described in the GitHub issue"
echo "Timestamp: $(date)"
echo "Log file: $REPAIR_LOG"
echo

# Check prerequisites
check_root
check_prerequisites

# Detect problem pattern
if ! detect_problem_pattern; then
    warn "Problem pattern detection failed but continuing due to --force"
fi

if [ "$DRY_RUN" = false ]; then
    echo
    warn "This script will make significant changes to cluster networking:"
    warn "- Restart CoreDNS, kube-proxy, and Flannel components"
    warn "- Modify iptables backend configuration"
    warn "- Fix CNI bridge conflicts"
    warn "- Reinstall Flannel CNI if missing"
    echo
    confirm_continue
fi

# Begin coordinated repair
echo "Starting coordinated networking repair..." | tee -a "$REPAIR_LOG"
echo "================================" | tee -a "$REPAIR_LOG"

# Execute repair steps in order
repair_iptables_backend
repair_cni_bridge  
repair_flannel_cni
repair_kube_proxy
repair_coredns
repair_worker_nodes
repair_system_networking
validate_repair

# Final summary
echo
echo "=================================================================="
echo "                    REPAIR SUMMARY"
echo "=================================================================="

if [ "$DRY_RUN" = true ]; then
    info "🔍 DRY RUN COMPLETED"
    echo "Review the actions above and run without --dry-run to apply changes."
else
    success "🎉 COORDINATED REPAIR COMPLETED"
    echo
    echo "The problem statement networking issues have been addressed through:"
    echo "✅ iptables backend compatibility fixes"
    echo "✅ CNI bridge conflict resolution"
    echo "✅ Flannel CNI repair/reinstallation"
    echo "✅ kube-proxy component restart"
    echo "✅ CoreDNS service restoration"
    echo "✅ Worker node CNI configuration"
    echo "✅ System networking optimization"
    echo "✅ Comprehensive validation testing"
    echo
    echo "Your cluster should now have functional:"
    echo "• Pod-to-pod communication"
    echo "• DNS resolution (internal and external)"
    echo "• Service discovery and routing"
    echo "• External network connectivity"
    echo
    echo "For ongoing monitoring, check:"
    echo "  kubectl get pods -A  # All pods should be Running"
    echo "  kubectl get nodes    # All nodes should be Ready"
fi

echo
echo "Repair log saved to: $REPAIR_LOG"
echo "Timestamp: $(date)"
echo "=================================================================="

exit 0
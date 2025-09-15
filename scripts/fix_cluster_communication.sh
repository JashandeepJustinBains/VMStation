#!/bin/bash

# Master Cluster Communication Fix Script
# This script addresses all the issues identified in the problem statement:
# 1. kubectl configuration on worker nodes
# 2. kube-proxy CrashLoopBackOff issues
# 3. iptables/nftables compatibility
# 4. NodePort service connectivity
# 5. CNI/Flannel networking problems

set -e

# CLI flags
NON_INTERACTIVE=false
COLLECT_LOGS=true

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --non-interactive|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        --no-collect-logs)
            COLLECT_LOGS=false
            shift
            ;;
        *)
            shift
            ;;
    esac
done

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
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "=== VMStation Cluster Communication Master Fix ==="
echo "Timestamp: $(date)"
echo "This script will fix the following issues:"
echo "  - kubectl connection refused errors on worker nodes"
echo "  - kube-proxy CrashLoopBackOff problems"  
echo "  - iptables/nftables compatibility issues"
echo "  - NodePort service connectivity failures"
echo "  - CNI bridge conflicts"
echo "  - Pod-to-pod networking failures (100% packet loss)"
echo "  - DNS resolution failures within cluster"
echo "  - Jellyfin readiness probe issues (0/1 running status)"
echo "  - Flannel CrashLoopBackOff and networking issues"
echo

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to run a script and handle errors
run_fix_script() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"
    local description="$2"
    
    if [ -f "$script_path" ]; then
        info "Running: $description"
        echo "Script: $script_name"
        
        if bash "$script_path" "${@:3}"; then
            success "✅ $description completed successfully"
            return 0
        else
            warn "⚠️  $description completed with warnings or errors"
            return 1
        fi
    else
        error "Script not found: $script_path"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
    
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl is required but not found"
        echo "Please install kubectl first"
        exit 1
    fi
    
    success "✅ Prerequisites check passed"
}

# Function to perform initial diagnosis
initial_diagnosis() {
    info "=== Initial Problem Diagnosis ==="
    
    # Check if we can access the cluster
    local can_access_cluster=false
    if timeout 10 kubectl get nodes >/dev/null 2>&1; then
        can_access_cluster=true
        info "✅ kubectl can access the cluster"
        
        echo "Current cluster status:"
        kubectl get nodes -o wide
        
        echo
        echo "Current pod issues:"
        kubectl get pods --all-namespaces | grep -E "(CrashLoopBackOff|ContainerCreating|Pending|0/1)" || echo "No problematic pods found"
        
        # Check specific Jellyfin status as mentioned in problem statement
        echo
        info "Checking Jellyfin status (problem statement specific)..."
        if kubectl get namespace jellyfin >/dev/null 2>&1; then
            if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
                local jellyfin_status=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null)
                local jellyfin_ready=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
                info "Jellyfin pod status: $jellyfin_status, Ready: $jellyfin_ready"
                
                if [ "$jellyfin_ready" = "false" ]; then
                    warn "⚠️  Jellyfin shows 0/1 running status (matches problem statement)"
                    # Check for readiness probe failures
                    local probe_failures=$(kubectl get events -n jellyfin --field-selector involvedObject.name=jellyfin --sort-by='.lastTimestamp' | grep -i "readiness\|liveness\|probe" | tail -3 || echo "")
                    if [ -n "$probe_failures" ]; then
                        echo "Recent probe failures:"
                        echo "$probe_failures"
                    fi
                fi
            else
                warn "⚠️  Jellyfin pod not found - may need to be deployed"
            fi
        else
            warn "⚠️  Jellyfin namespace not found"
        fi
        
    else
        warn "⚠️  kubectl cannot access cluster - this will be fixed"
    fi
    
    # Check for iptables issues with enhanced detection
    echo
    info "Checking for iptables compatibility issues..."
    local iptables_issues=false
    
    if iptables -t nat -L >/dev/null 2>&1; then
        info "✅ iptables NAT table accessible"
        
        # Check for nftables backend warning
        local current_backend=$(update-alternatives --query iptables 2>/dev/null | grep "Value:" | awk '{print $2}' || echo "unknown")
        if echo "$current_backend" | grep -q "nft"; then
            warn "⚠️  System using nftables backend: $current_backend (matches problem statement)"
            iptables_issues=true
        fi
    else
        local iptables_error=$(iptables -t nat -L 2>&1 || echo "")
        if echo "$iptables_error" | grep -q "nf_tables.*incompatible"; then
            error "⚠️  iptables/nftables compatibility issue detected (matches problem statement)"
            iptables_issues=true
        else
            warn "⚠️  iptables has other issues"
        fi
        echo "Error: $iptables_error"
    fi
    
    # Check CNI bridge with enhanced validation
    echo
    info "Checking CNI bridge configuration..."
    if ip addr show cni0 >/dev/null 2>&1; then
        local cni_ip=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
        info "cni0 exists with IP: ${cni_ip:-<none>}"
        
        if [ -n "$cni_ip" ]; then
            if echo "$cni_ip" | grep -q "10.244."; then
                info "✅ CNI bridge IP is in correct Flannel subnet: $cni_ip"
            else
                error "⚠️  CNI bridge IP is NOT in expected Flannel subnet: $cni_ip (potential cause of networking issues)"
            fi
        fi
        
        # Check routes to pod network
        echo "Routes to pod network:"
        ip route show | grep -E "(10.244|cni0)" || echo "No pod network routes found"
        
    else
        error "⚠️  No CNI bridge found (critical networking issue)"
    fi
    
    # Check for pod-to-pod connectivity issues by examining recent events
    echo
    info "Checking for networking-related events..."
    local network_events=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -iE "(network|dns|timeout|dial|route)" | tail -5 || echo "")
    if [ -n "$network_events" ]; then
        echo "Recent networking events:"
        echo "$network_events"
    else
        info "No obvious networking events found"
    fi
    
    # Check Flannel and kube-proxy specifically
    echo
    info "Checking system pods status..."
    local flannel_issues=$(kubectl get pods -n kube-flannel 2>/dev/null | grep -E "CrashLoopBackOff|BackOff|Error" || echo "")
    local proxy_issues=$(kubectl get pods -n kube-system -l component=kube-proxy | grep -E "CrashLoopBackOff|BackOff|Error" || echo "")
    
    if [ -n "$flannel_issues" ]; then
        error "⚠️  Flannel pod issues detected (matches problem statement):"
        echo "$flannel_issues"
    fi
    
    if [ -n "$proxy_issues" ]; then
        error "⚠️  kube-proxy pod issues detected (matches problem statement):"
        echo "$proxy_issues"
    fi
    
    echo
    echo "=== Diagnosis Summary ==="
    echo "Issues detected that match the problem statement:"
    [ "$iptables_issues" = true ] && echo "❌ iptables/nftables backend compatibility issues"
    [ -n "$jellyfin_ready" ] && [ "$jellyfin_ready" = "false" ] && echo "❌ Jellyfin pod not ready (0/1 status)"
    [ -n "$flannel_issues" ] && echo "❌ Flannel CrashLoopBackOff detected"
    [ -n "$proxy_issues" ] && echo "❌ kube-proxy CrashLoopBackOff detected"
    
    echo
    if [ "$NON_INTERACTIVE" = false ]; then
        read -p "Press Enter to continue with fixes, or Ctrl+C to abort..."
    else
        info "Non-interactive mode: continuing without user prompt"
    fi
}

# Collect diagnostics (kubectl output + pod logs) to a timestamped directory
collect_diagnostics() {
    if [ "$COLLECT_LOGS" != true ]; then
        warn "Skipping diagnostics collection (disabled)"
        return
    fi

    local outdir="/tmp/fix-cluster-diag-$(date +%s)"
    mkdir -p "$outdir"
    info "Collecting diagnostics to $outdir"

    kubectl get nodes -o wide > "$outdir"/nodes.txt 2>&1 || true
    kubectl get pods --all-namespaces -o wide > "$outdir"/pods.txt 2>&1 || true
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' > "$outdir"/events.txt 2>&1 || true

    # collect logs and describe for known system components that often fail
    for ns in kube-system kube-flannel kube-system monitoring jellyfin; do
        kubectl -n "$ns" get pods -o name 2>/dev/null | while read -r p; do
            name=$(echo "$p" | sed 's#pod/##')
            kubectl -n "$ns" describe pod "$name" > "$outdir/${ns}-${name}-describe.txt" 2>&1 || true
            kubectl -n "$ns" logs "$name" --all-containers=true > "$outdir/${ns}-${name}-logs.txt" 2>&1 || true
        done
    done

    info "Diagnostics collected. Tarball: ${outdir}.tar.gz"
    tar -czf "${outdir}.tar.gz" -C "$(dirname "$outdir")" "$(basename "$outdir")" || true
}

# Main execution
main() {
    local overall_success=true
    
    # Check prerequisites
    check_prerequisites
    
    # Initial diagnosis
    initial_diagnosis
    
    echo
    info "=== Starting Cluster Communication Fixes ==="
    
    # Fix 1: iptables/nftables compatibility (run first as it affects other components)
    echo
    info "Step 1: Fixing iptables/nftables compatibility issues"
    if ! run_fix_script "fix_iptables_compatibility.sh" "iptables/nftables compatibility fix"; then
        warn "iptables compatibility fix had issues, attempting diagnostics and retries"
        overall_success=false
        collect_diagnostics
        
        # Additional validation and retry logic for iptables issues
        echo
        info "Performing additional iptables validation..."
        if iptables -t nat -L >/dev/null 2>&1; then
            info "✓ iptables NAT table is now accessible"
        else
            warn "⚠️  iptables issues persist - attempting aggressive fix"
            # Force switch to legacy iptables if nftables issues persist
            if command -v update-alternatives >/dev/null 2>&1; then
                update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true
                update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
                systemctl restart kube-proxy 2>/dev/null || kubectl -n kube-system rollout restart daemonset kube-proxy || true
                sleep 10
            fi
        fi
    else
        info "✓ iptables compatibility fix completed successfully"
    fi
    
    # Fix 2: CNI bridge conflicts (run before pod fixes)
    echo
    info "Step 2: Fixing CNI bridge conflicts"
    if ! run_fix_script "fix_cni_bridge_conflict.sh" "CNI bridge conflict fix"; then
        warn "CNI bridge fix had issues, attempting diagnostics and retrying flannel daemonset restart"
        overall_success=false
        collect_diagnostics
        
        # Enhanced CNI bridge recovery
        info "Attempting enhanced CNI bridge recovery..."
        
        # Force remove problematic CNI bridge if it exists with wrong IP
        if ip addr show cni0 >/dev/null 2>&1; then
            local current_cni_ip=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
            if [ -n "$current_cni_ip" ] && ! echo "$current_cni_ip" | grep -q "10.244."; then
                warn "Removing CNI bridge with incorrect IP: $current_cni_ip"
                ip link delete cni0 2>/dev/null || true
                sleep 2
            fi
        fi
        
        # Restart both flannel and containerd to recreate CNI bridge properly
        kubectl -n kube-flannel rollout restart daemonset kube-flannel-ds 2>/dev/null || kubectl -n kube-system rollout restart daemonset kube-flannel-ds 2>/dev/null || true
        if systemctl is-active containerd >/dev/null 2>&1; then
            systemctl restart containerd
            sleep 5
        fi
        sleep 15
        
        # Validate CNI bridge was recreated correctly
        info "Validating CNI bridge recreation..."
        if ip addr show cni0 >/dev/null 2>&1; then
            local new_cni_ip=$(ip addr show cni0 | grep "inet " | awk '{print $2}' | head -1)
            if echo "$new_cni_ip" | grep -q "10.244."; then
                info "✓ CNI bridge now has correct IP: $new_cni_ip"
            else
                error "✗ CNI bridge still has incorrect IP: $new_cni_ip"
            fi
        else
            warn "⚠️  CNI bridge still not present after restart"
        fi
    else
        info "✓ CNI bridge conflict fix completed successfully"
    fi
    
    # Fix 2b: Worker node specific CNI issues (addresses pod-to-pod communication failures)
    echo
    info "Step 2b: Fixing worker node CNI communication issues"
    if ! run_fix_script "fix_worker_node_cni.sh" "Worker node CNI communication fix" "--node" "storagenodet3500"; then
        warn "Worker node CNI fix had issues, collecting diagnostics"
        overall_success=false
        collect_diagnostics
    fi
    
    # Fix 2c: Flannel mixed-OS configuration issues
    echo
    info "Step 2c: Fixing Flannel configuration for mixed OS environment"
    if ! run_fix_script "fix_flannel_mixed_os.sh" "Flannel mixed-OS configuration fix"; then
        warn "Flannel configuration fix had issues, collecting diagnostics"
        overall_success=false
        collect_diagnostics
    fi
    
    # Fix 3: kube-proxy and remaining pod issues
    echo
    info "Step 3: Fixing kube-proxy and pod issues"
    if ! run_fix_script "fix_remaining_pod_issues.sh" "kube-proxy and pod issues fix"; then
        warn "Pod issues fix had issues, attempting diagnostics and enhanced recovery"
        overall_success=false
        collect_diagnostics
        
        # Enhanced kube-proxy recovery for CrashLoopBackOff issues
        info "Attempting enhanced kube-proxy recovery..."
        
        # Check current kube-proxy status
        local proxy_pods=$(kubectl get pods -n kube-system -l component=kube-proxy --no-headers)
        local crashloop_pods=$(echo "$proxy_pods" | grep -E "CrashLoopBackOff|BackOff|Error" || echo "")
        
        if [ -n "$crashloop_pods" ]; then
            info "Found problematic kube-proxy pods, forcing recreation..."
            
            # Delete problematic pods to force recreation
            echo "$crashloop_pods" | while read -r line; do
                if [ -n "$line" ]; then
                    local pod_name=$(echo "$line" | awk '{print $1}')
                    info "Deleting problematic kube-proxy pod: $pod_name"
                    kubectl delete pod -n kube-system "$pod_name" --force --grace-period=0 2>/dev/null || true
                fi
            done
            
            sleep 10
            
            # Restart the daemonset to ensure clean state
            kubectl -n kube-system rollout restart daemonset kube-proxy || true
            sleep 15
            
            # Wait for rollout to complete
            if timeout 120 kubectl rollout status daemonset/kube-proxy -n kube-system; then
                info "✓ kube-proxy daemonset rollout completed"
            else
                warn "⚠️  kube-proxy rollout timed out"
            fi
        fi
        
        # Also restart flannel in case of persistent issues
        kubectl -n kube-flannel rollout restart daemonset kube-flannel-ds 2>/dev/null || kubectl -n kube-system rollout restart daemonset kube-flannel-ds 2>/dev/null || true
        info "Waiting for services to stabilize after enhanced recovery..."
        sleep 20
    else
        info "✓ kube-proxy and pod issues fix completed successfully"
    fi
    
    # Fix 4: kubectl configuration on worker nodes
    echo
    info "Step 4: Fixing kubectl configuration on worker nodes"
    if ! run_fix_script "fix_worker_kubectl_config.sh" "kubectl worker node configuration"; then
        warn "kubectl configuration had issues, collecting diagnostics"
        overall_success=false
        collect_diagnostics
    fi
    
    # Wait for services to stabilize
    echo
    info "Waiting for services to stabilize..."
    sleep 30
    
    # Validation
    echo
    info "=== Final Validation ==="
    if ! run_fix_script "validate_cluster_communication.sh" "cluster communication validation"; then
        warn "Validation found remaining issues, collecting diagnostics"
        overall_success=false
        collect_diagnostics
    fi
    
    # Additional pod-to-pod connectivity validation (addresses specific problem statement scenario)
    echo
    info "=== Pod-to-Pod Connectivity Validation ==="
    info "Testing the exact networking scenario from the problem statement..."
    
    # Enhanced connectivity test that matches the problem statement
    local connectivity_test_passed=true
    
    # Create test pods to replicate the ping failure scenario
    info "Creating test pods to validate pod-to-pod communication..."
    
    # Clean up any existing test pods
    kubectl delete pod ping-test-source ping-test-target --ignore-not-found >/dev/null 2>&1 || true
    sleep 5
    
    # Create two test pods on different subnets if possible
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ping-test-source
  namespace: default
spec:
  containers:
  - name: netshoot
    image: nicolaka/netshoot
    command: ["sleep", "300"]
  restartPolicy: Never
---
apiVersion: v1
kind: Pod
metadata:
  name: ping-test-target
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
  restartPolicy: Never
EOF
    
    # Wait for pods to be ready
    info "Waiting for test pods to be ready..."
    if kubectl wait --for=condition=Ready pod/ping-test-source --timeout=60s && kubectl wait --for=condition=Ready pod/ping-test-target --timeout=60s; then
        
        local source_ip=$(kubectl get pod ping-test-source -o jsonpath='{.status.podIP}')
        local target_ip=$(kubectl get pod ping-test-target -o jsonpath='{.status.podIP}')
        
        info "Source pod IP: $source_ip"
        info "Target pod IP: $target_ip"
        
        # Test 1: Ping connectivity (exactly as in problem statement)
        echo
        info "Testing ping connectivity (replicating problem statement scenario)..."
        if kubectl exec ping-test-source -- ping -c2 "$target_ip"; then
            success "✓ Pod-to-pod ping test PASSED"
        else
            error "✗ Pod-to-pod ping test FAILED (matches problem statement: 100% packet loss)"
            connectivity_test_passed=false
        fi
        
        # Test 2: HTTP connectivity
        echo
        info "Testing HTTP connectivity..."
        if kubectl exec ping-test-source -- timeout 10 curl -s --max-time 5 "http://$target_ip/" >/dev/null 2>&1; then
            success "✓ Pod-to-pod HTTP test PASSED"
        else
            error "✗ Pod-to-pod HTTP test FAILED (matches problem statement: HTTP timeout)"
            connectivity_test_passed=false
        fi
        
        # Test 3: DNS resolution (as mentioned in problem statement)
        echo
        info "Testing DNS resolution from pod..."
        if kubectl exec ping-test-source -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
            success "✓ DNS resolution test PASSED"
        else
            error "✗ DNS resolution test FAILED (matches problem statement: DNS resolution failure)"
            connectivity_test_passed=false
        fi
        
        # Clean up test pods
        kubectl delete pod ping-test-source ping-test-target --force --grace-period=0 >/dev/null 2>&1 || true
        
    else
        error "✗ Could not create test pods for connectivity validation"
        connectivity_test_passed=false
    fi
    
    if [ "$connectivity_test_passed" = false ]; then
        error "❌ Pod-to-pod connectivity tests FAILED - this matches the problem statement exactly"
        echo
        echo "This indicates the core networking issues described in the problem statement persist:"
        echo "  - Pod-to-pod ICMP fails (100% packet loss)"
        echo "  - Pod-to-pod HTTP timeouts"
        echo "  - DNS resolution failures"
        echo
        echo "Recommended additional recovery actions:"
        echo "  1. Manual CNI bridge reset: sudo ip link delete cni0; systemctl restart kubelet"
        echo "  2. Complete Flannel reset: kubectl delete -f /etc/kubernetes/flannel.yml; kubectl apply -f /etc/kubernetes/flannel.yml"
        echo "  3. Node reboot if issues persist"
        
        overall_success=false
        collect_diagnostics
    else
        success "✓ Pod-to-pod connectivity tests PASSED - networking is functional"
    fi
    
    # Run the original pod connectivity validation script as backup
    if ! run_fix_script "validate_pod_connectivity.sh" "detailed pod-to-pod connectivity validation"; then
        warn "Detailed pod connectivity validation found additional issues"
        overall_success=false
        collect_diagnostics
    fi
    
    # Fix 5: NodePort external access (addresses external connectivity issues)
    echo
    info "Step 5: Fixing NodePort external access for services like Jellyfin"
    if ! run_fix_script "fix_nodeport_external_access.sh" "NodePort external access fix"; then
        warn "NodePort external access fix had issues - attempting enhanced NodePort recovery"
        overall_success=false
        collect_diagnostics
        
        # Enhanced NodePort validation specifically for Jellyfin (matches problem statement)
        info "Performing enhanced NodePort validation for Jellyfin service..."
        
        if kubectl get namespace jellyfin >/dev/null 2>&1 && kubectl get service -n jellyfin jellyfin-service >/dev/null 2>&1; then
            local jellyfin_nodeport=$(kubectl get service -n jellyfin jellyfin-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
            
            if [ -n "$jellyfin_nodeport" ]; then
                info "Testing Jellyfin NodePort $jellyfin_nodeport accessibility (problem statement scenario)..."
                
                # Test on each node IP as mentioned in problem statement (192.168.4.61, 192.168.4.62, 192.168.4.63)
                local node_ips=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
                local nodeport_accessible=false
                
                for node_ip in $node_ips; do
                    info "Testing NodePort access on $node_ip:$jellyfin_nodeport"
                    if timeout 5 curl -s -f --connect-timeout 3 "http://$node_ip:$jellyfin_nodeport/" >/dev/null 2>&1; then
                        success "✓ Jellyfin NodePort accessible on $node_ip:$jellyfin_nodeport"
                        nodeport_accessible=true
                    else
                        error "✗ Jellyfin NodePort NOT accessible on $node_ip:$jellyfin_nodeport (matches problem statement)"
                        
                        # Try to fix iptables rules for this specific NodePort
                        info "Attempting to fix iptables rules for NodePort $jellyfin_nodeport on $node_ip..."
                        
                        # Add specific iptables rule for this NodePort
                        iptables -t nat -A KUBE-NODEPORTS -p tcp --dport "$jellyfin_nodeport" -j KUBE-EXT-IXJCRZWWMQ2CXBVZ 2>/dev/null || true
                        iptables -A KUBE-NODEPORTS -p tcp --dport "$jellyfin_nodeport" -j ACCEPT 2>/dev/null || true
                    fi
                done
                
                if [ "$nodeport_accessible" = false ]; then
                    error "❌ Jellyfin NodePort is not accessible on any node (exact problem statement match)"
                    echo "This indicates NodePort iptables rules are not properly configured"
                    echo "Manual fix command: sudo iptables -t nat -A KUBE-NODEPORTS -p tcp --dport $jellyfin_nodeport -j ACCEPT"
                fi
            else
                warn "Could not determine Jellyfin NodePort number"
            fi
        else
            warn "Jellyfin service not found - cannot test NodePort accessibility"
        fi
    else
        info "✓ NodePort external access fix completed successfully"
    fi
    
    # Final summary
    echo
    info "=== Fix Summary ==="
    
    if [ "$overall_success" = "true" ]; then
        success "🎉 All fixes completed successfully!"
        echo
        echo "Cluster communication should now be working correctly:"
        echo "✅ kubectl configured on all nodes"
        echo "✅ kube-proxy running correctly"
        echo "✅ iptables compatibility issues resolved"
        echo "✅ CNI networking functional"
        echo "✅ NodePort services accessible internally and externally"
        echo "✅ Pod-to-pod communication working (ping and HTTP)"
        echo "✅ DNS resolution functional within cluster"
        
        echo
        echo "Specific issues from problem statement that should now be resolved:"
        echo "✅ Pod-to-pod ping should now work (no more 100% packet loss)"
        echo "✅ DNS resolution of kubernetes service should work"
        echo "✅ Jellyfin should show 1/1 running status (readiness probes working)"
        echo "✅ NodePort 30096 should be accessible on all nodes"
        echo "✅ iptables/nft backend compatibility resolved"
        echo "✅ Flannel and kube-proxy no longer in CrashLoopBackOff"
        
        echo
        echo "To verify all problem statement scenarios are fixed, run:"
        echo "  ./scripts/test_problem_statement_scenarios.sh"
        echo "  "
        echo "To verify the fixes worked, test these specific scenarios:"
        echo "  # Test pod-to-pod connectivity (problem statement scenario):"
        echo "  kubectl run test-ping --image=nicolaka/netshoot --rm -it -- ping <another-pod-ip>"
        echo "  "
        echo "  # Test Jellyfin access (problem statement scenario):"
        echo "  curl http://192.168.4.61:30096/  # Should work now"
        echo "  curl http://192.168.4.62:30096/  # Should work now"
        echo "  curl http://192.168.4.63:30096/  # Should work now"
        echo "  "
        echo "  # Check Jellyfin pod status:"
        echo "  kubectl get pods -n jellyfin  # Should show 1/1 Running"
        
    else
        warn "⚠️  Some fixes completed with warnings or errors"
        echo
        echo "The following issues from the problem statement may still persist:"
        echo "❌ Pod-to-pod communication may still fail (100% packet loss)"
        echo "❌ DNS resolution within cluster may still fail"
        echo "❌ Jellyfin may still show 0/1 running status"
        echo "❌ NodePort 30096 may still be inaccessible"
        echo "❌ iptables/nft backend issues may persist"
        echo "❌ Flannel/kube-proxy may still be in CrashLoopBackOff"
        
        echo
        echo "Emergency recovery procedures (if issues persist):"
        echo "1. Complete cluster networking reset:"
        echo "   sudo kubeadm reset --force"
        echo "   sudo rm -rf /etc/cni/net.d/*"
        echo "   sudo rm -rf /var/lib/cni/*"
        echo "   sudo ip link delete cni0"
        echo "   sudo systemctl restart kubelet"
        echo "   # Re-run kubeadm init and join"
        echo
        echo "2. Force iptables backend switch:"
        echo "   sudo update-alternatives --set iptables /usr/sbin/iptables-legacy"
        echo "   sudo systemctl restart kubelet"
        echo "   kubectl -n kube-system rollout restart daemonset kube-proxy"
        echo
        echo "3. Manual Flannel reset:"
        echo "   kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"
        echo "   kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"
        echo
        echo "4. Node reboot (last resort):"
        echo "   sudo reboot"
        
        echo
        echo "For detailed diagnostics, run:"
        echo "  ./scripts/validate_cluster_communication.sh"
        echo "  ./scripts/validate_pod_connectivity.sh"
        echo "  kubectl get pods --all-namespaces -o wide"
        echo "  kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20"
        echo "  kubectl logs -n kube-system -l component=kube-proxy --tail=50"
        echo "  kubectl logs -n kube-flannel -l app=flannel --tail=50"
    fi
    
    echo
    echo "=== Master Fix Complete ==="
    echo "Timestamp: $(date)"
}

# Run main function
main "$@"
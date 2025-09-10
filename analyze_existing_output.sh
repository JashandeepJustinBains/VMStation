#!/bin/bash

# Analyze Existing Worker Node Join Scripts Output
# This script analyzes the existing worker_node_join_scripts_output.txt file
# to provide insights and recommendations for the join issues

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_section() { echo -e "\n${MAGENTA}=== $1 ===${NC}"; }
log_finding() { echo -e "${CYAN}[FINDING]${NC} $1"; }

# Check if output file exists
OUTPUT_FILE="worker_node_join_scripts_output.txt"

if [ ! -f "$OUTPUT_FILE" ]; then
    log_error "Output file not found: $OUTPUT_FILE"
    log_info "This script analyzes the existing worker_node_join_scripts_output.txt file"
    exit 1
fi

# Analyze the execution context
analyze_execution_context() {
    log_section "EXECUTION CONTEXT ANALYSIS"
    
    local hostname=$(grep "Hostname:" "$OUTPUT_FILE" | head -1 | cut -d: -f2 | xargs)
    local ip=$(grep "IP Address:" "$OUTPUT_FILE" | head -1 | cut -d: -f2 | xargs)
    
    log_info "Scripts were executed on:"
    log_info "  Hostname: $hostname"
    log_info "  IP Address: $ip"
    
    # Check if this was run on masternode
    if [[ "$hostname" == *"master"* ]] || [[ "$ip" == "192.168.4.63" ]]; then
        log_warn "❌ CRITICAL ISSUE: Scripts were run on CONTROL PLANE node ($hostname)"
        log_warn "   These diagnostic scripts should be run on the WORKER NODE having join issues"
        log_warn "   Running on control plane provides limited insight into worker node problems"
        echo ""
        log_error "RECOMMENDED ACTION:"
        echo "   1. Identify the actual worker node having join problems"
        echo "   2. SSH to the worker node"
        echo "   3. Run the enhanced_worker_join_troubleshooter.sh script on the worker node"
        echo "   4. Capture join logs during actual join attempt on worker node"
        echo ""
    else
        log_success "✓ Scripts executed on worker node (good)"
    fi
}

# Analyze diagnostic results
analyze_diagnostic_results() {
    log_section "DIAGNOSTIC RESULTS ANALYSIS"
    
    # CNI Configuration Analysis
    log_finding "CNI Configuration Status:"
    if grep -q "10-flannel.conflist" "$OUTPUT_FILE"; then
        log_success "✓ Flannel CNI configuration found"
        log_info "  Configuration includes flannel and portmap plugins"
    else
        log_warn "❌ No Flannel CNI configuration detected"
    fi
    
    if grep -q "/opt/cni/bin.*flannel" "$OUTPUT_FILE"; then
        log_success "✓ Flannel binary present in CNI bin directory"
    else
        log_warn "❌ Flannel binary may be missing from /opt/cni/bin/"
    fi
    
    # Containerd Analysis
    log_finding "Containerd Status:"
    if grep -q "containerd.*active (running)" "$OUTPUT_FILE"; then
        log_success "✓ Containerd service is running"
    else
        log_warn "❌ Containerd service status unclear"
    fi
    
    local containerd_capacity=$(grep -A 2 "Containerd Filesystem Capacity" "$OUTPUT_FILE" | grep -oE '[0-9]+G' | head -1)
    if [ -n "$containerd_capacity" ]; then
        log_success "✓ Containerd filesystem capacity: $containerd_capacity"
    else
        log_warn "❌ Could not determine containerd filesystem capacity"
    fi
    
    # Kubelet Analysis  
    log_finding "Kubelet Status:"
    if grep -q "kubelet.*active (running)" "$OUTPUT_FILE"; then
        log_info "ℹ️  Kubelet was running during diagnostic (expected on control plane)"
    elif grep -q "kubelet.*inactive" "$OUTPUT_FILE"; then
        log_info "ℹ️  Kubelet inactive (expected state after remediation)"
    fi
    
    # Port 10250 Analysis
    if grep -q "tcp.*:10250.*kubelet" "$OUTPUT_FILE"; then
        log_info "ℹ️  Port 10250 in use by kubelet (normal on control plane)"
    else
        log_success "✓ Port 10250 available for worker kubelet"
    fi
}

# Analyze remediation results
analyze_remediation_results() {
    log_section "REMEDIATION RESULTS ANALYSIS"
    
    log_finding "Remediation Actions Performed:"
    
    # Check if remediation was run
    if grep -q "Worker Node Join Remediation Script" "$OUTPUT_FILE"; then
        log_success "✓ Remediation script was executed"
        
        # Check specific actions
        if grep -q "kubelet stopped" "$OUTPUT_FILE"; then
            log_success "✓ Kubelet service stopped"
        fi
        
        if grep -q "kubelet masked" "$OUTPUT_FILE"; then
            log_success "✓ Kubelet service masked"
        fi
        
        if grep -q "Port 10250 released successfully" "$OUTPUT_FILE"; then
            log_success "✓ Port 10250 released"
        fi
        
        if grep -q "Kubernetes state reset completed" "$OUTPUT_FILE"; then
            log_success "✓ Kubernetes state reset completed"
        fi
        
        if grep -q "kubelet unmasked" "$OUTPUT_FILE"; then
            log_success "✓ Kubelet service unmasked"
        fi
        
        if grep -q "System prepared for kubeadm join" "$OUTPUT_FILE"; then
            log_success "✓ System prepared for join operation"
        fi
        
    else
        log_warn "❌ No remediation script execution detected"
    fi
}

# Identify missing information
identify_missing_information() {
    log_section "MISSING INFORMATION ANALYSIS"
    
    log_warn "Critical information missing from the output:"
    echo ""
    
    log_error "1. WORKER NODE LOGS MISSING"
    echo "   - No journalctl logs from actual worker node during join attempt"
    echo "   - Need logs from worker node showing join failure details"
    echo "   - Should capture: journalctl -u kubelet -f (during join attempt)"
    echo ""
    
    log_error "2. ACTUAL JOIN ATTEMPT OUTPUT MISSING"
    echo "   - No kubeadm join command output visible"
    echo "   - Need to see the actual join command and its verbose output"
    echo "   - Should capture: kubeadm join ... --v=5 (full output)"
    echo ""
    
    log_error "3. WORKER NODE SYSTEM STATE MISSING"
    echo "   - Diagnostics were run on control plane, not worker node"
    echo "   - Need actual worker node system state and configuration"
    echo "   - Should run enhanced_worker_join_troubleshooter.sh on worker node"
    echo ""
    
    log_error "4. CONTROL PLANE STATUS MISSING"
    echo "   - No verification that control plane is healthy during join"
    echo "   - Should check: kubectl get nodes, kubectl get pods -n kube-system"
    echo "   - Need control plane resource utilization during join"
    echo ""
    
    log_error "5. NETWORK CONNECTIVITY MISSING"
    echo "   - No network connectivity tests between worker and control plane"
    echo "   - Should test: ping, port 6443 connectivity, DNS resolution"
    echo "   - Need firewall and routing information"
}

# Generate specific recommendations based on analysis
generate_recommendations() {
    log_section "SPECIFIC RECOMMENDATIONS"
    
    log_info "Based on the analysis, here are the recommended next steps:"
    echo ""
    
    log_warn "IMMEDIATE ACTIONS NEEDED:"
    echo ""
    
    echo "1. IDENTIFY THE ACTUAL WORKER NODE:"
    echo "   - Determine which node is having join issues (not masternode)"
    echo "   - SSH to the problematic worker node"
    echo "   - Verify it's the correct node that cannot join the cluster"
    echo ""
    
    echo "2. RUN ENHANCED DIAGNOSTICS ON WORKER NODE:"
    echo "   - Copy enhanced_worker_join_troubleshooter.sh to worker node"
    echo "   - Run: sudo ./enhanced_worker_join_troubleshooter.sh"
    echo "   - Save complete output for analysis"
    echo ""
    
    echo "3. CAPTURE ACTUAL JOIN ATTEMPT:"
    echo "   - On control plane: kubeadm token create --print-join-command"
    echo "   - On worker node, run join with verbose logging:"
    echo "     kubeadm join [control-plane-ip]:6443 --token [token] \\"
    echo "       --discovery-token-ca-cert-hash sha256:[hash] --v=5"
    echo "   - In separate terminal: journalctl -u kubelet -f"
    echo "   - Capture both outputs completely"
    echo ""
    
    echo "4. VERIFY CONTROL PLANE HEALTH:"
    echo "   - On control plane: kubectl get nodes -o wide"
    echo "   - Check CNI: kubectl get pods -n kube-flannel"
    echo "   - Check system resources: kubectl top nodes"
    echo ""
    
    echo "5. ANALYZE LOGS WITH NEW TOOLS:"
    echo "   - Run analyze_worker_join_logs.sh on captured logs"
    echo "   - Use -v flag for verbose analysis"
    echo "   - Focus on specific error patterns and timelines"
    echo ""
    
    log_warn "PROCESS IMPROVEMENT:"
    echo ""
    echo "For future troubleshooting, follow this workflow:"
    echo "1. Run diagnostics on the WORKER NODE (not control plane)"
    echo "2. Verify control plane health before attempting join"
    echo "3. Capture complete join attempt with verbose logging"
    echo "4. Use log analysis tools to identify specific failure patterns"
    echo "5. Apply targeted remediation based on specific issues found"
}

# Look for specific indicators in the logs
analyze_specific_indicators() {
    log_section "SPECIFIC INDICATOR ANALYSIS"
    
    # Check for container logs that might indicate worker node activity
    if grep -q "storagenodeT3500" "$OUTPUT_FILE"; then
        log_finding "Worker node identifier found: storagenodeT3500"
        log_info "This appears to be the actual worker node that should be analyzed"
        echo ""
    fi
    
    # Check for systemd configuration issues
    if grep -q "Assignment outside of section" "$OUTPUT_FILE"; then
        log_warn "❌ Systemd configuration issue detected:"
        echo "   Error: '/etc/systemd/system/kubelet.service.d/20-join-config.conf:1: Assignment outside of section'"
        echo "   This indicates a malformed systemd drop-in file"
        echo "   Recommended: Check and fix kubelet service drop-in configuration"
        echo ""
    fi
    
    # Check for failed services
    if grep -q "fail2ban\|podman-metrics\|monitoring-cleanup" "$OUTPUT_FILE"; then
        log_warn "❌ Failed services detected (may not impact join directly):"
        grep -A 10 "UNIT.*LOAD.*ACTIVE.*SUB.*DESCRIPTION" "$OUTPUT_FILE" | grep -E "fail2ban|podman-metrics|monitoring-cleanup" || true
        echo ""
    fi
    
    # Check final status
    if grep -q "Ready for kubeadm join" "$OUTPUT_FILE"; then
        log_success "✓ System reported ready for join after remediation"
        echo "   The remediation appears to have completed successfully"
        echo "   Next step should be attempting the actual join operation"
        echo ""
    fi
}

# Provide troubleshooting workflow
provide_troubleshooting_workflow() {
    log_section "RECOMMENDED TROUBLESHOOTING WORKFLOW"
    
    log_info "Complete troubleshooting workflow for worker node join issues:"
    echo ""
    
    echo "PHASE 1: PREPARATION AND VERIFICATION"
    echo "  □ Identify the correct worker node having issues"
    echo "  □ Verify control plane is healthy (kubectl get nodes)"
    echo "  □ Check control plane resources (kubectl top nodes)"
    echo "  □ Verify CNI is deployed (kubectl get pods -n kube-flannel)"
    echo ""
    
    echo "PHASE 2: WORKER NODE DIAGNOSTICS"
    echo "  □ SSH to the worker node (not control plane)"
    echo "  □ Run enhanced_worker_join_troubleshooter.sh on worker node"
    echo "  □ Address any issues identified in the diagnostic output"
    echo "  □ Verify worker node system health and connectivity"
    echo ""
    
    echo "PHASE 3: JOIN ATTEMPT WITH MONITORING"
    echo "  □ Generate fresh join command on control plane"
    echo "  □ Start log monitoring on worker: journalctl -u kubelet -f"
    echo "  □ Run join command with verbose logging: --v=5"
    echo "  □ Capture complete output from both join command and logs"
    echo ""
    
    echo "PHASE 4: LOG ANALYSIS AND REMEDIATION"
    echo "  □ Analyze captured logs with analyze_worker_join_logs.sh"
    echo "  □ Identify specific failure patterns and root causes"
    echo "  □ Apply targeted fixes based on analysis results"
    echo "  □ Re-run diagnostics to verify fixes"
    echo ""
    
    echo "PHASE 5: VERIFICATION AND DOCUMENTATION"
    echo "  □ Verify successful join: kubectl get nodes"
    echo "  □ Test pod scheduling on new node"
    echo "  □ Document issues found and solutions applied"
    echo "  □ Update troubleshooting procedures if needed"
}

# Main execution
main() {
    echo "========================================================================"
    echo "          Analysis of Worker Node Join Scripts Output"
    echo "========================================================================"
    echo "Analyzing: $OUTPUT_FILE"
    echo "Timestamp: $(date)"
    echo "========================================================================"
    
    # Run analysis functions
    analyze_execution_context
    analyze_diagnostic_results
    analyze_remediation_results
    analyze_specific_indicators
    identify_missing_information
    generate_recommendations
    provide_troubleshooting_workflow
    
    echo ""
    log_section "ANALYSIS SUMMARY"
    
    log_warn "KEY FINDINGS:"
    echo "  1. Scripts were executed on control plane instead of worker node"
    echo "  2. Missing actual worker node join attempt logs" 
    echo "  3. Remediation completed successfully on control plane"
    echo "  4. Need to repeat process on actual worker node"
    echo ""
    
    log_info "NEXT STEPS:"
    echo "  1. Use enhanced_worker_join_troubleshooter.sh on actual worker node"
    echo "  2. Capture complete join attempt with verbose logging"
    echo "  3. Use analyze_worker_join_logs.sh for detailed log analysis"
    echo "  4. Follow the recommended troubleshooting workflow above"
    echo ""
    
    log_success "Analysis complete. Use the recommendations above to continue troubleshooting."
}

# Execute main function
main "$@"
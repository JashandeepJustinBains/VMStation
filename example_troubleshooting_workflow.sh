#!/bin/bash

# Example Troubleshooting Workflow for Worker Node Join Issues
# This script demonstrates the proper workflow for troubleshooting
# It's meant to be educational - not necessarily run as-is

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_step() { echo -e "\n${BLUE}STEP $1:${NC} $2"; }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "========================================================================"
echo "      Example Worker Node Join Troubleshooting Workflow"
echo "========================================================================"
echo "This demonstrates the proper sequence for troubleshooting join issues"
echo "========================================================================"

log_step "1" "IDENTIFY THE PROBLEM NODE"
log_info "On control plane, check which worker node is missing or problematic:"
echo "  kubectl get nodes -o wide"
echo "  # Look for nodes in NotReady state or missing entirely"
echo ""

log_step "2" "VERIFY CONTROL PLANE HEALTH"  
log_info "Before troubleshooting worker, ensure control plane is healthy:"
echo "  kubectl get nodes"
echo "  kubectl get pods -n kube-system"
echo "  kubectl get pods -n kube-flannel"
echo "  kubectl top nodes  # Check resource utilization"
echo ""

log_step "3" "SSH TO THE WORKER NODE"
log_info "Connect to the actual worker node having issues (NOT the control plane):"
echo "  ssh user@worker-node-ip"
echo "  # Verify you're on the correct node:"
echo "  hostname"
echo "  ip addr show"
echo ""

log_step "4" "RUN ENHANCED DIAGNOSTICS ON WORKER"
log_info "Copy and run the enhanced troubleshooter on the worker node:"
echo "  # Copy script to worker node:"
echo "  scp enhanced_worker_join_troubleshooter.sh user@worker-node:/tmp/"
echo "  "
echo "  # Run on worker node:"
echo "  sudo /tmp/enhanced_worker_join_troubleshooter.sh | tee worker_diagnostics.txt"
echo ""

log_step "5" "ADDRESS ANY ISSUES FOUND"
log_info "Fix problems identified in diagnostics before attempting join:"
echo "  # Common issues and fixes:"
echo "  # - CNI missing: Deploy Flannel on control plane"
echo "  # - Port conflicts: Stop conflicting services"
echo "  # - containerd issues: Restart containerd service"
echo "  # - Previous join artifacts: Run remediation script"
echo ""

log_step "6" "GENERATE FRESH JOIN COMMAND"
log_info "On control plane, create a new join token and command:"
echo "  kubeadm token create --print-join-command"
echo "  # Copy the complete command output"
echo ""

log_step "7" "CAPTURE JOIN ATTEMPT WITH MONITORING"
log_info "On worker node, monitor logs while attempting join:"
echo "  # Terminal 1 - Start log monitoring:"
echo "  journalctl -u kubelet -f | tee kubelet_join_logs.txt"
echo "  "
echo "  # Terminal 2 - Run join command with verbose logging:"
echo "  kubeadm join [control-plane-ip]:6443 \\"
echo "    --token [token] \\"
echo "    --discovery-token-ca-cert-hash sha256:[hash] \\"
echo "    --v=5 | tee join_attempt_output.txt"
echo ""

log_step "8" "ANALYZE LOGS IF JOIN FAILS"
log_info "If join fails, analyze the captured logs:"
echo "  # Copy log analyzer to worker node:"
echo "  scp analyze_worker_join_logs.sh user@worker-node:/tmp/"
echo "  "
echo "  # Analyze the logs:"
echo "  /tmp/analyze_worker_join_logs.sh -f kubelet_join_logs.txt -v"
echo ""

log_step "9" "APPLY TARGETED FIXES"
log_info "Based on log analysis, apply specific fixes:"
echo "  # Examples based on common patterns:"
echo "  # - CNI issues: kubectl apply -f flannel.yml (on control plane)"
echo "  # - Certificate issues: Check system time sync"
echo "  # - Network issues: Test connectivity, check firewall"
echo "  # - Token issues: Generate new join command"
echo ""

log_step "10" "USE REMEDIATION IF NEEDED"
log_info "For persistent issues or to start fresh:"
echo "  sudo ./worker_node_join_remediation.sh"
echo "  # This will clean up previous join attempts and prepare for fresh join"
echo ""

log_step "11" "VERIFY SUCCESSFUL JOIN"
log_info "After successful join, verify the worker node:"
echo "  # On control plane:"
echo "  kubectl get nodes -o wide"
echo "  kubectl describe node [worker-node-name]"
echo "  "
echo "  # Test pod scheduling:"
echo "  kubectl run test-pod --image=nginx --restart=Never"
echo "  kubectl get pods -o wide"
echo ""

log_step "12" "DOCUMENT FINDINGS"
log_info "Document what was found and how it was fixed:"
echo "  # Save diagnostic outputs"
echo "  # Record specific errors and solutions"
echo "  # Update troubleshooting procedures"
echo "  # Share knowledge with team"
echo ""

echo "========================================================================"
log_success "WORKFLOW COMPLETE"
echo ""
echo "Key Points to Remember:"
echo "  ✓ Always run diagnostics on the WORKER node, not control plane"  
echo "  ✓ Capture complete logs during join attempts"
echo "  ✓ Use verbose logging (--v=5) for join commands"
echo "  ✓ Analyze logs systematically with provided tools"
echo "  ✓ Apply targeted fixes based on specific findings"
echo "  ✓ Document solutions for future reference"
echo ""
echo "Available Tools:"
echo "  - enhanced_worker_join_troubleshooter.sh (comprehensive diagnostics)"
echo "  - analyze_worker_join_logs.sh (log analysis)"
echo "  - worker_node_join_remediation.sh (cleanup and preparation)"
echo "  - analyze_existing_output.sh (analyze troubleshooting output)"
echo ""
log_info "For immediate help with existing output, run: ./analyze_existing_output.sh"
echo "========================================================================"
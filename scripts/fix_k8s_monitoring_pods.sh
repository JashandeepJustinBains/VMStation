#!/bin/bash

# Kubernetes Monitoring Pod Failure Fix Script
# Analyzes CrashLoopBackOff and Pending state issues and provides specific fixes for config files, manifests, scheduling, and directory permissions
# 
# Usage: ./fix_k8s_monitoring_pods.sh [--auto-approve]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BOLD}=== VMStation Kubernetes Monitoring Pod Fix Assistant ===${NC}"
echo "Timestamp: $(date)"
echo ""

# Check for auto-approve flag
AUTO_APPROVE="no"
if [[ "$1" == "--auto-approve" ]]; then
    AUTO_APPROVE="yes"
    echo -e "${YELLOW}⚠️  AUTO_APPROVE mode enabled - destructive commands will be shown${NC}"
else
    echo -e "${BLUE}ℹ️  Safe mode - only diagnostic and safe remediation commands will be shown${NC}"
    echo "   Use --auto-approve to include destructive commands"
fi
echo ""

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${RED}✗ kubectl not found. Please install kubectl and configure cluster access.${NC}"
        exit 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}✗ Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ kubectl connection verified${NC}"
}

# Function to analyze current pod status
analyze_pod_status() {
    echo -e "${BOLD}=== Current Pod Status Analysis ===${NC}"
    
    if ! kubectl get namespace monitoring >/dev/null 2>&1; then
        echo -e "${RED}✗ monitoring namespace not found${NC}"
        echo "Create monitoring namespace: kubectl create namespace monitoring"
        return 1
    fi
    
    echo "Checking monitoring pods..."
    local failed_pods=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -E "(CrashLoopBackOff|Init:CrashLoopBackOff)" || true)
    local pending_pods=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -E "Pending" || true)
    
    local has_issues=false
    
    if [[ -n "$failed_pods" ]]; then
        echo -e "${RED}✗ Found pods in CrashLoopBackOff state:${NC}"
        echo "$failed_pods"
        echo ""
        
        # Analyze specific failure patterns
        analyze_grafana_failures "$failed_pods"
        analyze_loki_failures "$failed_pods"
        has_issues=true
    fi
    
    if [[ -n "$pending_pods" ]]; then
        echo -e "${RED}✗ Found pods in Pending state:${NC}"
        echo "$pending_pods"
        echo ""
        
        # Analyze pending pod issues
        analyze_pending_pods "$pending_pods"
        has_issues=true
    fi
    
    if [[ "$has_issues" == "false" ]]; then
        echo -e "${GREEN}✓ No pods in CrashLoopBackOff or Pending state found${NC}"
        echo "Current monitoring pods:"
        kubectl get pods -n monitoring -o wide 2>/dev/null || echo "No pods found in monitoring namespace"
        return 0
    fi
    
    return 1
}

# Function to analyze Grafana-specific failures
analyze_grafana_failures() {
    local failed_pods="$1"
    
    echo -e "${BOLD}=== Grafana Init Container Analysis ===${NC}"
    
    local grafana_pods=$(echo "$failed_pods" | grep "grafana" || true)
    if [[ -z "$grafana_pods" ]]; then
        echo "No Grafana pods in failed state"
        return 0
    fi
    
    echo "Grafana pods with issues:"
    echo "$grafana_pods"
    echo ""
    
    # Get the first Grafana pod name for analysis
    local grafana_pod=$(echo "$grafana_pods" | head -1 | awk '{print $1}')
    
    echo "Analyzing Grafana pod: $grafana_pod"
    echo ""
    
    # Check for init container failures
    echo -e "${BLUE}Diagnostic Command:${NC} kubectl -n monitoring describe pod $grafana_pod"
    echo "Expected findings: Init container exit codes, permission denied errors"
    echo ""
    
    echo -e "${BLUE}Log Analysis Command:${NC} kubectl -n monitoring logs $grafana_pod -c init-chown-data --tail=50"
    echo "Expected findings: chown permission denied errors, UID 472:472 failures"
    echo ""
    
    # Provide Grafana-specific fixes
    provide_grafana_fixes "$grafana_pod"
}

# Function to analyze Loki-specific failures  
analyze_loki_failures() {
    local failed_pods="$1"
    
    echo -e "${BOLD}=== Loki Configuration Analysis ===${NC}"
    
    local loki_pods=$(echo "$failed_pods" | grep "loki" || true)
    if [[ -z "$loki_pods" ]]; then
        echo "No Loki pods in failed state"
        return 0
    fi
    
    echo "Loki pods with issues:"
    echo "$loki_pods"
    echo ""
    
    # Get the first Loki pod name for analysis  
    local loki_pod=$(echo "$loki_pods" | head -1 | awk '{print $1}')
    
    echo "Analyzing Loki pod: $loki_pod"
    echo ""
    
    echo -e "${BLUE}Diagnostic Command:${NC} kubectl -n monitoring logs $loki_pod --tail=100"
    echo "Expected findings: YAML parse errors, max_retries field not found"
    echo ""
    
    echo -e "${BLUE}Config Analysis Command:${NC} kubectl -n monitoring get secret loki-stack -o jsonpath='{.data.loki\\.yaml}' | base64 -d | head -50"
    echo "Expected findings: Invalid max_retries configuration around line 33"
    echo ""
    
    # Provide Loki-specific fixes
    provide_loki_fixes "$loki_pod"
}

# Function to analyze pods stuck in Pending state
analyze_pending_pods() {
    local pending_pods="$1"
    
    echo -e "${BOLD}=== Pending Pods Analysis ===${NC}"
    echo ""
    
    # Get the first pending pod for detailed analysis
    local first_pending_pod=$(echo "$pending_pods" | head -1 | awk '{print $1}')
    
    echo "Analyzing pending pod: $first_pending_pod"
    echo ""
    
    echo -e "${BLUE}1. Check pod scheduling events:${NC}"
    echo "   kubectl -n monitoring describe pod $first_pending_pod | grep -A10 Events"
    echo ""
    
    echo -e "${BLUE}2. Check node resources and taints:${NC}"
    echo "   kubectl get nodes -o wide"
    echo "   kubectl describe nodes | grep -E 'Name:|Taints:|Allocatable:|Allocated resources:' -A5"
    echo ""
    
    echo -e "${BLUE}3. Check storage class availability:${NC}"
    echo "   kubectl get storageclass"
    echo "   kubectl get pv | grep Available"
    echo ""
    
    echo -e "${BLUE}4. Check for node selector constraints:${NC}"
    echo "   kubectl -n monitoring get pod $first_pending_pod -o jsonpath='{.spec.nodeSelector}'"
    echo ""
    
    # Analyze common causes of pending state
    echo -e "${YELLOW}Common causes of Pending state:${NC}"
    echo "• Node taints preventing pod scheduling"
    echo "• Insufficient CPU/memory resources on nodes"  
    echo "• Node selector constraints (hostname/labels)"
    echo "• Storage class not available or PVs not provisioned"
    echo "• Pod anti-affinity rules preventing scheduling"
    echo ""
    
    # Provide specific remediation suggestions
    provide_pending_fixes "$first_pending_pod"
}

# Function to provide Grafana-specific fixes
provide_grafana_fixes() {
    local grafana_pod="$1"
    
    echo -e "${BOLD}=== Grafana Permission Fixes ===${NC}"
    echo ""
    
    echo -e "${YELLOW}1. Directory Permission Fix (Node-level operation):${NC}"
    echo "   Issue: Grafana init container cannot chown data directory to UID 472:472"
    echo "   Detection: kubectl -n monitoring logs $grafana_pod -c init-chown-data | grep 'Permission denied'"
    echo ""
    
    echo -e "${BLUE}   Step 1 - Find the PVC and PV:${NC}"
    echo "   kubectl -n monitoring get pvc kube-prometheus-stack-grafana -o jsonpath='{.spec.volumeName}'"
    echo "   kubectl get pv \$PV_NAME -o yaml | grep 'path:'"
    echo ""
    
    echo -e "${BLUE}   Step 2 - Fix permissions on the node (run on the node hosting the PV):${NC}"
    echo "   # First, find which node hosts the PV:"
    echo "   kubectl get pv \$PV_NAME -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}'"
    echo ""
    echo "   # SSH to that node and fix permissions:"
    echo "   sudo chown -R 472:472 /var/lib/kubernetes/local-path-provisioner/pvc-*_monitoring_kube-prometheus-stack-grafana"
    echo "   sudo chmod -R 755 /var/lib/kubernetes/local-path-provisioner/pvc-*_monitoring_kube-prometheus-stack-grafana"
    echo ""
    
    echo -e "${YELLOW}2. Pod Recreation (after fixing permissions):${NC}"
    if [[ "$AUTO_APPROVE" == "yes" ]]; then
        echo "   kubectl -n monitoring delete pod -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=kube-prometheus-stack"
        echo "   kubectl -n monitoring get pods -w"
    else
        echo "   Use --auto-approve to show destructive pod recreation commands"
    fi
    echo ""
    
    echo -e "${YELLOW}3. Verification Commands:${NC}"
    echo "   kubectl -n monitoring get pods | grep grafana"
    echo "   kubectl -n monitoring logs \$NEW_GRAFANA_POD -c init-chown-data"
    echo ""
}

# Function to provide Loki-specific fixes
provide_loki_fixes() {
    local loki_pod="$1"
    
    echo -e "${BOLD}=== Loki Configuration Fixes ===${NC}"
    echo ""
    
    echo -e "${YELLOW}1. Loki Configuration Fix (Helm values override):${NC}"
    echo "   Issue: Invalid max_retries field in Loki configuration"
    echo "   Detection: kubectl -n monitoring logs $loki_pod | grep 'field max_retries not found'"
    echo ""
    
    echo -e "${BLUE}   Step 1 - Create fixed configuration file:${NC}"
    cat << 'EOF'
   cat > /tmp/loki-fix-values.yaml << 'YAML_EOF'
loki:
  config:
    table_manager:
      # Remove invalid max_retries field
      retention_deletes_enabled: true
      retention_period: 168h
YAML_EOF
EOF
    echo ""
    
    echo -e "${BLUE}   Step 2 - Test the fix with dry-run:${NC}"
    echo "   helm -n monitoring upgrade --reuse-values loki-stack grafana/loki-stack -f /tmp/loki-fix-values.yaml --dry-run"
    echo ""
    
    if [[ "$AUTO_APPROVE" == "yes" ]]; then
        echo -e "${BLUE}   Step 3 - Apply the fix:${NC}"
        echo "   helm -n monitoring upgrade --reuse-values loki-stack grafana/loki-stack -f /tmp/loki-fix-values.yaml"
        echo ""
        echo -e "${BLUE}   Alternative - Rollback option:${NC}"
        echo "   helm -n monitoring rollback loki-stack"
    else
        echo "   Use --auto-approve to show destructive helm upgrade commands"
    fi
    echo ""
    
    echo -e "${YELLOW}2. Verification Commands:${NC}"
    echo "   kubectl -n monitoring get pods | grep loki"
    echo "   kubectl -n monitoring logs loki-stack-0 --tail=50"
    echo "   helm -n monitoring status loki-stack"
    echo ""
}

# Function to provide fixes for pods stuck in Pending state
provide_pending_fixes() {
    local pending_pod="$1"
    
    echo -e "${BOLD}=== Pending Pod Remediation Steps ===${NC}"
    echo ""
    
    echo -e "${YELLOW}1. Node Taint Issues:${NC}"
    echo "   Check if master/control-plane nodes have taints:"
    echo "   kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.spec.taints[*].key}{\"\\n\"}{end}'"
    echo ""
    echo "   If nodes have taints, add tolerations to pod spec or remove taints:"
    echo "   # Remove taint (if safe):"
    echo "   kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-"
    echo "   kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule-"
    echo ""
    
    echo -e "${YELLOW}2. Node Selector Constraints:${NC}"
    echo "   Check current node selector:"
    echo "   kubectl -n monitoring get pod $pending_pod -o jsonpath='{.spec.nodeSelector}'"
    echo ""
    echo "   Available nodes and their labels:"
    echo "   kubectl get nodes --show-labels"
    echo ""
    echo "   Fix: Ensure nodes have required labels or modify deployment to remove strict hostname requirements"
    echo ""
    
    echo -e "${YELLOW}3. Resource Constraints:${NC}"
    echo "   Check node resource availability:"
    echo "   kubectl top nodes 2>/dev/null || echo 'metrics-server not available'"
    echo "   kubectl describe nodes | grep -E 'Name:|Allocatable:|Allocated resources:' -A10"
    echo ""
    echo "   Fix: Free up resources on nodes or reduce pod resource requests"
    echo ""
    
    echo -e "${YELLOW}4. Storage Class Issues:${NC}"
    echo "   Check if local-path storage class exists:"
    echo "   kubectl get storageclass local-path"
    echo ""
    echo "   If missing, install local-path-provisioner:"
    echo "   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml"
    echo ""
    
    if [[ "$AUTO_APPROVE" == "yes" ]]; then
        echo -e "${YELLOW}5. Emergency Fixes (USE WITH CAUTION):${NC}"
        echo "   Remove node taints (if this is a single-node cluster):"
        echo "   kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- || true"
        echo "   kubectl taint nodes --all node-role.kubernetes.io/master:NoSchedule- || true"
        echo ""
        echo "   Force reschedule pending pods:"
        echo "   kubectl -n monitoring delete pods --field-selector=status.phase=Pending"
        echo ""
        echo "   Patch deployment to remove node selector (temporary fix):"
        echo "   kubectl -n monitoring patch deployment kube-prometheus-stack-grafana -p '{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":null}}}}'"
    else
        echo "   Use --auto-approve to show destructive fix commands"
    fi
    echo ""
}

# Function to provide comprehensive fix summary
provide_fix_summary() {
    echo -e "${BOLD}=== Complete Fix Summary ===${NC}"
    echo ""
    
    echo -e "${GREEN}For the failing pods mentioned in your issue:${NC}"
    echo ""
    
    echo -e "${YELLOW}Grafana pods (Init:CrashLoopBackOff):${NC}"
    echo "• kube-prometheus-stack-grafana-878594f88-cdbzt"
    echo "• kube-prometheus-stack-grafana-8c4bb9b97-7prbs"
    echo ""
    echo "Root cause: Init container cannot change ownership of data directory to grafana UID (472:472)"
    echo "Fix: Run chown command on the node hosting the PersistentVolume"
    echo ""
    
    echo -e "${YELLOW}Loki pod (CrashLoopBackOff):${NC}"
    echo "• loki-stack-0"
    echo ""
    echo "Root cause: Invalid 'max_retries' field in Loki configuration"
    echo "Fix: Update Helm values to remove invalid configuration field"
    echo ""
    
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Run the diagnostic commands above to confirm the issues"
    echo "2. Apply the node-level permission fixes for Grafana"
    echo "3. Update Loki configuration via Helm"
    echo "4. Verify pods reach Running state"
    echo ""
    
    echo -e "${GREEN}Additional Resources:${NC}"
    echo "• For detailed analysis: ./scripts/analyze_k8s_monitoring_diagnostics.sh"
    echo "• For permission diagnostics: ./scripts/diagnose_monitoring_permissions.sh"
    echo "• For premium troubleshooting: ./scripts/get_copilot_prompt.sh --show"
}

# Main execution flow
main() {
    # Check prerequisites
    check_kubectl
    echo ""
    
    # Analyze current state
    if analyze_pod_status; then
        echo -e "${GREEN}✓ No immediate CrashLoopBackOff or Pending issues detected${NC}"
        echo ""
        echo "If you're still experiencing issues, run the diagnostic commands provided"
        echo "or use the detailed analysis tools:"
        echo "  ./scripts/analyze_k8s_monitoring_diagnostics.sh"
    else
        echo ""
        provide_fix_summary
    fi
    
    echo ""
    echo -e "${BOLD}=== Fix Complete ===${NC}"
    echo "Follow the specific steps above to resolve your monitoring pod issues."
}

# Run main function
main "$@"
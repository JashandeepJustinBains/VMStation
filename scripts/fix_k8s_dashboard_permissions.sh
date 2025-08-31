#!/bin/bash

# Kubernetes Dashboard Permission Fix Script
# Fixes CrashLoopBackOff issues related to directory permissions and certificate access
# Similar to monitoring permission fixes but specifically for the kubernetes-dashboard

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BOLD}=== VMStation Kubernetes Dashboard Permission Fix ===${NC}"
echo "Timestamp: $(date)"
echo ""

# Check for auto-approve flag
AUTO_APPROVE="no"
if [[ "$1" == "--auto-approve" ]]; then
    AUTO_APPROVE="yes"
    echo -e "${YELLOW}⚠️  AUTO_APPROVE mode enabled - destructive commands will be shown${NC}"
else
    echo "Use --auto-approve to show pod recreation commands"
fi
echo ""

# Function to check kubectl availability
check_kubectl() {
    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${RED}✗ kubectl not found${NC}"
        echo "Install kubectl and ensure it's configured to access your cluster"
        return 1
    fi
    
    echo -e "${GREEN}✓ kubectl available${NC}"
    return 0
}

# Function to analyze kubernetes-dashboard pod status
analyze_dashboard_status() {
    echo -e "${BOLD}=== Analyzing Kubernetes Dashboard Status ===${NC}"
    
    # Check if kubernetes-dashboard namespace exists
    if ! kubectl get namespace kubernetes-dashboard >/dev/null 2>&1; then
        echo -e "${RED}✗ kubernetes-dashboard namespace not found${NC}"
        echo "Create kubernetes-dashboard namespace first"
        return 1
    fi
    
    echo "Checking kubernetes-dashboard pods..."
    local failed_pods=$(kubectl get pods -n kubernetes-dashboard --no-headers 2>/dev/null | grep -E "(CrashLoopBackOff|Init:CrashLoopBackOff|Error)" || true)
    
    if [[ -z "$failed_pods" ]]; then
        echo -e "${GREEN}✓ No pods in CrashLoopBackOff state found${NC}"
        echo "Current dashboard pods:"
        kubectl get pods -n kubernetes-dashboard -o wide 2>/dev/null || echo "No pods found in kubernetes-dashboard namespace"
        return 0
    fi
    
    echo -e "${RED}✗ Found pods in failed state:${NC}"
    echo "$failed_pods"
    echo ""
    
    # Analyze specific failure patterns
    analyze_dashboard_failures "$failed_pods"
    return 1
}

# Function to analyze dashboard-specific failures
analyze_dashboard_failures() {
    local failed_pods="$1"
    
    echo -e "${BOLD}=== Dashboard Failure Analysis ===${NC}"
    
    local dashboard_pods=$(echo "$failed_pods" | grep "kubernetes-dashboard" || true)
    if [[ -z "$dashboard_pods" ]]; then
        echo "No kubernetes-dashboard pods in failed state"
        return 0
    fi
    
    echo "Dashboard pods with issues:"
    echo "$dashboard_pods"
    echo ""
    
    # Get the first dashboard pod name for analysis
    local dashboard_pod=$(echo "$dashboard_pods" | head -n 1 | awk '{print $1}')
    
    echo -e "${BLUE}Diagnostic Commands:${NC}"
    echo "kubectl -n kubernetes-dashboard describe pod $dashboard_pod"
    echo "kubectl -n kubernetes-dashboard logs $dashboard_pod --previous"
    echo "kubectl -n kubernetes-dashboard logs $dashboard_pod"
    echo ""
    
    # Provide dashboard-specific fixes
    provide_dashboard_fixes "$dashboard_pod"
}

# Function to provide dashboard-specific permission fixes
provide_dashboard_fixes() {
    local dashboard_pod="$1"
    
    echo -e "${BOLD}=== Dashboard Permission Fixes ===${NC}"
    echo ""
    
    echo -e "${YELLOW}1. Certificate Generation Issue Fix:${NC}"
    echo "   Issue: Dashboard may fail to generate auto-certificates due to write permissions"
    echo "   Detection: kubectl -n kubernetes-dashboard logs $dashboard_pod | grep 'certificate'"
    echo ""
    
    echo -e "${BLUE}   Fix - Update dashboard with proper security context:${NC}"
        echo "   kubectl -n kubernetes-dashboard patch deployment kubernetes-dashboard -p '{\"spec\":{\"template\":{\"spec\":{\"securityContext\":{\"fsGroup\":65534}}}}}'"
    echo ""
    
    echo -e "${YELLOW}2. Directory Permission Fix (Node-level operation):${NC}"
    echo "   Issue: Dashboard container cannot write certificates to /certs directory"
    echo "   Detection: kubectl -n kubernetes-dashboard logs $dashboard_pod | grep 'Permission denied'"
    echo ""
    
    echo -e "${BLUE}   Step 1 - Find which node is running the dashboard:${NC}"
    echo "   kubectl -n kubernetes-dashboard get pod $dashboard_pod -o jsonpath='{.spec.nodeName}'"
    echo ""
    
    echo -e "${BLUE}   Step 2 - Create certificate directory on the node:${NC}"
    echo "   # SSH to the node and create the directory:"
    echo "   sudo mkdir -p /tmp/k8s-dashboard-certs"
    echo "   sudo chown -R 65534:65534 /tmp/k8s-dashboard-certs"
    echo "   sudo chmod -R 755 /tmp/k8s-dashboard-certs"
    echo ""
    
    echo -e "${YELLOW}3. SELinux Context Fix (if SELinux is enabled):${NC}"
    echo "   sudo semanage fcontext -a -t container_file_t '/tmp/k8s-dashboard-certs(/.*)?'"
    echo "   sudo restorecon -R /tmp/k8s-dashboard-certs"
    echo ""
    
    echo -e "${YELLOW}4. Pod Recreation (after fixing permissions):${NC}"
    if [[ "$AUTO_APPROVE" == "yes" ]]; then
        echo "   kubectl -n kubernetes-dashboard delete pod -l app=kubernetes-dashboard"
        echo "   kubectl -n kubernetes-dashboard rollout restart deployment kubernetes-dashboard"
        echo "   kubectl -n kubernetes-dashboard get pods -w"
    else
        echo "   Use --auto-approve to show destructive pod recreation commands"
    fi
    echo ""
    
    echo -e "${YELLOW}5. Alternative - Remove auto-certificate generation:${NC}"
    echo "   kubectl -n kubernetes-dashboard patch deployment kubernetes-dashboard --type='json' -p='[{\"op\": \"remove\", \"path\": \"/spec/template/spec/containers/0/args\"}]'"
    echo "   kubectl -n kubernetes-dashboard patch deployment kubernetes-dashboard --type='json' -p='[{\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args\", \"value\": [\"--namespace=kubernetes-dashboard\", \"--enable-insecure-login\"]}]'"
    echo ""
    
    echo -e "${YELLOW}6. Verification Commands:${NC}"
    echo "   kubectl -n kubernetes-dashboard get pods | grep kubernetes-dashboard"
    echo "   kubectl -n kubernetes-dashboard logs $dashboard_pod --tail=50"
    echo "   curl -k https://NODE_IP:32000  # Test access (replace NODE_IP)"
}

# Function to create a comprehensive dashboard fix
create_dashboard_fix_manifest() {
    echo -e "${BOLD}=== Creating Dashboard Fix Manifest ===${NC}"
    
    cat > /tmp/dashboard-permission-fix.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
spec:
  template:
    spec:
      securityContext:
        fsGroup: 65534
        runAsUser: 1001
        runAsGroup: 2001
      containers:
      - name: kubernetes-dashboard
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: false
          runAsNonRoot: true
          runAsUser: 1001
          runAsGroup: 2001
        volumeMounts:
        - name: tmp-volume
          mountPath: /tmp
        - name: kubernetes-dashboard-certs
          mountPath: /certs
      volumes:
      - name: tmp-volume
        emptyDir: {}
      - name: kubernetes-dashboard-certs
        emptyDir: {}
EOF
    
    echo "Created fix manifest at /tmp/dashboard-permission-fix.yaml"
    echo ""
    echo "Apply with:"
    echo "kubectl -n kubernetes-dashboard patch deployment kubernetes-dashboard --patch-file /tmp/dashboard-permission-fix.yaml"
}

# Main execution flow
main() {
    # Check prerequisites
    check_kubectl
    echo ""
    
    # Analyze current state
    if analyze_dashboard_status; then
        echo -e "${GREEN}✓ No dashboard permission issues detected${NC}"
        echo ""
        echo "If you're still experiencing issues, try:"
        echo "1. Check resource constraints: kubectl top nodes"
        echo "2. Check events: kubectl get events -n kubernetes-dashboard --sort-by='.lastTimestamp'"
        echo "3. Check logs: kubectl -n kubernetes-dashboard logs -l app=kubernetes-dashboard"
    else
        echo ""
        echo -e "${BLUE}Next Steps:${NC}"
        echo "1. Run the diagnostic commands above to identify specific issues"
        echo "2. Apply the permission fixes for your specific failure pattern"
        echo "3. Recreate pods and verify they reach Running state"
        echo "4. Test dashboard access via NodePort"
        echo ""
        
        echo -e "${GREEN}Additional Resources:${NC}"
        echo "• For detailed pod logs: kubectl -n kubernetes-dashboard logs -l app=kubernetes-dashboard --previous"
        echo "• For events: kubectl get events -n kubernetes-dashboard --sort-by='.lastTimestamp'"
        echo "• For node permissions: ./scripts/diagnose_monitoring_permissions.sh"
        
        # Create the fix manifest
        create_dashboard_fix_manifest
    fi
}

# Run main function
main "$@"
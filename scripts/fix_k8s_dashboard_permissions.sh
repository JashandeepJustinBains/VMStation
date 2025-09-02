#!/bin/bash

# Kubernetes Dashboard Permission Fix Script
# Fixes CrashLoopBackOff issues related to directory permissions and certificate access
# Similar to monitoring permission fixes but specifically for the kubernetes-dashboard
#
# ENHANCED VERSION: Now includes automatic fix application when --auto-approve is used
#
# Usage:
#   ./fix_k8s_dashboard_permissions.sh                 # Diagnostic mode (shows manual commands)
#   ./fix_k8s_dashboard_permissions.sh --auto-approve  # Automatic fix mode (applies fixes automatically)
#
# Features:
# - Automatic log analysis to detect specific failure reasons
# - Targeted fixes based on detected failure patterns
# - Validation and retry logic to ensure fixes work
# - Support for common issues: permission errors, certificate problems, volume issues, etc.

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
    
    echo -e "${BLUE}Analyzing pod logs for failure patterns...${NC}"
    
    # Analyze the actual logs to determine failure reason
    local failure_reason=$(analyze_pod_logs "$dashboard_pod")
    echo "Detected failure reason: $failure_reason"
    echo ""
    
    echo -e "${BLUE}Diagnostic Commands (for manual reference):${NC}"
    echo "kubectl -n kubernetes-dashboard describe pod $dashboard_pod"
    echo "kubectl -n kubernetes-dashboard logs $dashboard_pod --previous"
    echo "kubectl -n kubernetes-dashboard logs $dashboard_pod"
    echo ""
    
    # Apply automatic fixes if auto-approve is enabled, otherwise show manual instructions
    if [[ "$AUTO_APPROVE" == "yes" ]]; then
        apply_dashboard_fixes "$dashboard_pod" "$failure_reason"
    else
        provide_dashboard_fixes "$dashboard_pod"
    fi
}

# Function to analyze pod logs and determine specific failure reason
analyze_pod_logs() {
    local pod_name="$1"
    local failure_reason="unknown"
    
    # Get current and previous logs
    local current_logs=$(kubectl -n kubernetes-dashboard logs "$pod_name" 2>/dev/null || echo "")
    local previous_logs=$(kubectl -n kubernetes-dashboard logs "$pod_name" --previous 2>/dev/null || echo "")
    local all_logs="${current_logs}\n${previous_logs}"
    
    # Analyze logs for specific patterns
    if echo -e "$all_logs" | grep -i "permission denied" >/dev/null 2>&1; then
        failure_reason="permission_denied"
    elif echo -e "$all_logs" | grep -i "certificate" >/dev/null 2>&1 && echo -e "$all_logs" | grep -i "write" >/dev/null 2>&1; then
        failure_reason="certificate_write_error"
    elif echo -e "$all_logs" | grep -i "unable to create directories" >/dev/null 2>&1; then
        failure_reason="directory_creation_error"
    elif echo -e "$all_logs" | grep -i "read-only file system" >/dev/null 2>&1; then
        failure_reason="readonly_filesystem"
    elif echo -e "$all_logs" | grep -i "dial tcp.*connection refused" >/dev/null 2>&1; then
        failure_reason="api_connection_error"
    elif echo -e "$all_logs" | grep -i "bind.*address already in use" >/dev/null 2>&1; then
        failure_reason="port_in_use"
    elif echo -e "$all_logs" | grep -i "context deadline exceeded" >/dev/null 2>&1; then
        failure_reason="timeout_error"
    fi
    
    echo "$failure_reason"
}

# Function to automatically apply dashboard fixes based on detected failure reason
apply_dashboard_fixes() {
    local dashboard_pod="$1"
    local failure_reason="$2"
    
    echo -e "${BOLD}=== Applying Automatic Dashboard Fixes ===${NC}"
    echo "Failure reason: $failure_reason"
    echo ""
    
    case "$failure_reason" in
        "permission_denied"|"certificate_write_error"|"directory_creation_error")
            echo -e "${YELLOW}Applying permission and security context fixes...${NC}"
            apply_permission_fixes "$dashboard_pod"
            ;;
        "readonly_filesystem")
            echo -e "${YELLOW}Applying read-only filesystem fixes...${NC}"
            apply_volume_fixes "$dashboard_pod"
            ;;
        "api_connection_error")
            echo -e "${YELLOW}Applying API connectivity fixes...${NC}"
            apply_connectivity_fixes "$dashboard_pod"
            ;;
        "port_in_use")
            echo -e "${YELLOW}Applying port conflict fixes...${NC}"
            apply_port_fixes "$dashboard_pod"
            ;;
        "timeout_error")
            echo -e "${YELLOW}Applying timeout fixes...${NC}"
            apply_timeout_fixes "$dashboard_pod"
            ;;
        *)
            echo -e "${YELLOW}Applying general dashboard fixes...${NC}"
            apply_general_fixes "$dashboard_pod"
            ;;
    esac
    
    # Wait for fix application and validate
    validate_and_retry_fixes "$dashboard_pod"
}

# Function to apply permission-related fixes
apply_permission_fixes() {
    local dashboard_pod="$1"
    
    echo "1. Updating deployment with proper security context..."
    kubectl -n kubernetes-dashboard patch deployment kubernetes-dashboard --type='merge' -p='{
        "spec": {
            "template": {
                "spec": {
                    "securityContext": {
                        "fsGroup": 65534,
                        "runAsUser": 1001,
                        "runAsGroup": 2001
                    },
                    "containers": [
                        {
                            "name": "kubernetes-dashboard",
                            "securityContext": {
                                "allowPrivilegeEscalation": false,
                                "readOnlyRootFilesystem": false,
                                "runAsNonRoot": true,
                                "runAsUser": 1001,
                                "runAsGroup": 2001
                            }
                        }
                    ]
                }
            }
        }
    }' && echo -e "${GREEN}✓ Security context updated${NC}" || echo -e "${RED}✗ Failed to update security context${NC}"
    
    echo "2. Deleting failed pod to trigger recreation..."
    kubectl -n kubernetes-dashboard delete pod "$dashboard_pod" --grace-period=0 --force && echo -e "${GREEN}✓ Pod deleted${NC}" || echo -e "${RED}✗ Failed to delete pod${NC}"
}

# Function to apply volume-related fixes
apply_volume_fixes() {
    local dashboard_pod="$1"
    
    echo "1. Adding writable volumes for certificates and temp files..."
    kubectl -n kubernetes-dashboard patch deployment kubernetes-dashboard --type='merge' -p='{
        "spec": {
            "template": {
                "spec": {
                    "containers": [
                        {
                            "name": "kubernetes-dashboard",
                            "volumeMounts": [
                                {
                                    "name": "tmp-volume",
                                    "mountPath": "/tmp"
                                },
                                {
                                    "name": "kubernetes-dashboard-certs",
                                    "mountPath": "/certs"
                                }
                            ]
                        }
                    ],
                    "volumes": [
                        {
                            "name": "tmp-volume",
                            "emptyDir": {}
                        },
                        {
                            "name": "kubernetes-dashboard-certs",
                            "emptyDir": {}
                        }
                    ]
                }
            }
        }
    }' && echo -e "${GREEN}✓ Volumes configured${NC}" || echo -e "${RED}✗ Failed to configure volumes${NC}"
    
    echo "2. Deleting failed pod to apply volume changes..."
    kubectl -n kubernetes-dashboard delete pod "$dashboard_pod" --grace-period=0 --force && echo -e "${GREEN}✓ Pod deleted${NC}" || echo -e "${RED}✗ Failed to delete pod${NC}"
}

# Function to apply API connectivity fixes
apply_connectivity_fixes() {
    local dashboard_pod="$1"
    
    echo "1. Checking and updating dashboard arguments for API connectivity..."
    kubectl -n kubernetes-dashboard patch deployment kubernetes-dashboard --type='json' -p='[
        {
            "op": "replace",
            "path": "/spec/template/spec/containers/0/args",
            "value": [
                "--namespace=kubernetes-dashboard",
                "--enable-insecure-login",
                "--enable-skip-login",
                "--auto-generate-certificates=false"
            ]
        }
    ]' && echo -e "${GREEN}✓ Dashboard arguments updated${NC}" || echo -e "${RED}✗ Failed to update arguments${NC}"
    
    echo "2. Restarting deployment..."
    kubectl -n kubernetes-dashboard rollout restart deployment kubernetes-dashboard && echo -e "${GREEN}✓ Deployment restarted${NC}" || echo -e "${RED}✗ Failed to restart deployment${NC}"
}

# Function to apply port conflict fixes
apply_port_fixes() {
    local dashboard_pod="$1"
    
    echo "1. Checking service configuration..."
    local service_info=$(kubectl -n kubernetes-dashboard get service kubernetes-dashboard -o yaml 2>/dev/null || echo "")
    
    echo "2. Deleting conflicting pod..."
    kubectl -n kubernetes-dashboard delete pod "$dashboard_pod" --grace-period=0 --force && echo -e "${GREEN}✓ Pod deleted${NC}" || echo -e "${RED}✗ Failed to delete pod${NC}"
    
    echo "3. Waiting for port cleanup..."
    sleep 10
}

# Function to apply timeout-related fixes
apply_timeout_fixes() {
    local dashboard_pod="$1"
    
    echo "1. Updating deployment with increased timeouts and resource limits..."
    kubectl -n kubernetes-dashboard patch deployment kubernetes-dashboard --type='merge' -p='{
        "spec": {
            "template": {
                "spec": {
                    "containers": [
                        {
                            "name": "kubernetes-dashboard",
                            "resources": {
                                "requests": {
                                    "cpu": "100m",
                                    "memory": "256Mi"
                                },
                                "limits": {
                                    "cpu": "500m",
                                    "memory": "512Mi"
                                }
                            },
                            "livenessProbe": {
                                "httpGet": {
                                    "scheme": "HTTPS",
                                    "path": "/",
                                    "port": 8443
                                },
                                "initialDelaySeconds": 30,
                                "timeoutSeconds": 30,
                                "periodSeconds": 10,
                                "failureThreshold": 3
                            },
                            "readinessProbe": {
                                "httpGet": {
                                    "scheme": "HTTPS",
                                    "path": "/",
                                    "port": 8443
                                },
                                "initialDelaySeconds": 10,
                                "timeoutSeconds": 30,
                                "periodSeconds": 5,
                                "failureThreshold": 3
                            }
                        }
                    ]
                }
            }
        }
    }' && echo -e "${GREEN}✓ Resource limits and probes updated${NC}" || echo -e "${RED}✗ Failed to update resources${NC}"
    
    echo "2. Restarting deployment..."
    kubectl -n kubernetes-dashboard rollout restart deployment kubernetes-dashboard && echo -e "${GREEN}✓ Deployment restarted${NC}" || echo -e "${RED}✗ Failed to restart deployment${NC}"
}

# Function to apply general fixes when specific reason is unknown
apply_general_fixes() {
    local dashboard_pod="$1"
    
    echo "1. Applying comprehensive dashboard fix manifest..."
    
    # Apply the manifest from the create_dashboard_fix_manifest function
    create_dashboard_fix_manifest >/dev/null 2>&1
    
    if kubectl -n kubernetes-dashboard patch deployment kubernetes-dashboard --patch-file /tmp/dashboard-permission-fix.yaml; then
        echo -e "${GREEN}✓ Comprehensive fix manifest applied${NC}"
    else
        echo -e "${RED}✗ Failed to apply fix manifest, trying individual patches...${NC}"
        apply_permission_fixes "$dashboard_pod"
        apply_volume_fixes "$dashboard_pod"
    fi
}

# Function to validate fixes and retry if needed
validate_and_retry_fixes() {
    local dashboard_pod="$1"
    local max_retries=3
    local retry_count=0
    
    echo ""
    echo -e "${BOLD}=== Validating Fix Application ===${NC}"
    
    while [[ $retry_count -lt $max_retries ]]; do
        echo "Attempt $((retry_count + 1))/$max_retries: Waiting for pod recreation..."
        sleep 20
        
        # Check if new pods are running
        local pod_status=$(kubectl get pods -n kubernetes-dashboard --no-headers 2>/dev/null | grep kubernetes-dashboard || echo "")
        
        if echo "$pod_status" | grep -q "Running"; then
            echo -e "${GREEN}✓ Dashboard pod is now running successfully!${NC}"
            
            # Show final status
            echo ""
            echo "Final pod status:"
            kubectl get pods -n kubernetes-dashboard -o wide
            
            echo ""
            echo "Testing dashboard accessibility..."
            test_dashboard_access
            return 0
        elif echo "$pod_status" | grep -q "CrashLoopBackOff"; then
            echo -e "${YELLOW}⚠ Pod still in CrashLoopBackOff, analyzing new failure...${NC}"
            
            # Get the new pod name
            local new_pod=$(echo "$pod_status" | grep "CrashLoopBackOff" | head -n 1 | awk '{print $1}')
            if [[ -n "$new_pod" ]]; then
                local new_failure_reason=$(analyze_pod_logs "$new_pod")
                echo "New failure reason: $new_failure_reason"
                
                # If it's a different failure, try a different fix
                if [[ "$new_failure_reason" != "unknown" ]]; then
                    echo "Applying targeted fix for new failure reason..."
                    apply_dashboard_fixes "$new_pod" "$new_failure_reason"
                fi
            fi
        else
            echo "Pod status: $pod_status"
            echo "Waiting for pod to stabilize..."
        fi
        
        ((retry_count++))
    done
    
    echo -e "${RED}✗ Failed to fix dashboard after $max_retries attempts${NC}"
    echo ""
    echo "Current pod status:"
    kubectl get pods -n kubernetes-dashboard -o wide
    
    echo ""
    echo "For manual troubleshooting, check:"
    echo "1. kubectl -n kubernetes-dashboard describe pods"
    echo "2. kubectl -n kubernetes-dashboard logs -l app=kubernetes-dashboard"
    echo "3. kubectl get events -n kubernetes-dashboard --sort-by='.lastTimestamp'"
    
    return 1
}

# Function to test dashboard accessibility
test_dashboard_access() {
    echo "Checking dashboard service..."
    kubectl get service -n kubernetes-dashboard
    
    echo ""
    echo "Getting node information for access testing..."
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "NODE_IP")
    
    echo "Dashboard should be accessible at:"
    echo "• HTTPS: https://$node_ip:32000"
    echo "• Or check service NodePort with: kubectl get service -n kubernetes-dashboard"
    
    # Quick connectivity test
    if command -v curl >/dev/null 2>&1; then
        echo ""
        echo "Testing connectivity (insecure, expect certificate errors)..."
        if timeout 10 curl -k -I "https://$node_ip:32000" 2>/dev/null | head -n 1; then
            echo -e "${GREEN}✓ Dashboard is responding to HTTP requests${NC}"
        else
            echo -e "${YELLOW}⚠ Dashboard may not be responding yet, check NodePort service${NC}"
        fi
    fi
}

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
        if [[ "$AUTO_APPROVE" == "yes" ]]; then
            echo -e "${BOLD}=== AUTO-APPROVE MODE: Attempting Automatic Fixes ===${NC}"
            echo "The script will attempt to automatically fix detected issues..."
            echo ""
        else
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
            echo ""
            echo -e "${YELLOW}💡 TIP: Use --auto-approve to automatically apply fixes instead of just showing instructions${NC}"
            echo ""
            
            # Create the fix manifest for manual use
            create_dashboard_fix_manifest
        fi
    fi
}

# Run main function
main "$@"
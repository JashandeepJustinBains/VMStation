#!/bin/bash

# Diagnostic script for cert-manager stalling during site.yaml execution
# Provides real-time monitoring and detailed analysis of cert-manager deployment issues

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="/tmp/cert_manager_stall_diagnosis_${TIMESTAMP// /_}.log"

echo "=== Cert-Manager Stall Diagnosis Tool ===" | tee "$LOG_FILE"
echo "Timestamp: $TIMESTAMP" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check command availability
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}✗ $1 command not found${NC}" | tee -a "$LOG_FILE"
        return 1
    else
        echo -e "${GREEN}✓ $1 available${NC}" | tee -a "$LOG_FILE"
        return 0
    fi
}

# Function to capture and analyze kubectl cluster state
analyze_cluster_state() {
    log_with_timestamp "=== Phase 1: Cluster State Analysis ==="
    
    # Basic cluster connectivity
    if kubectl cluster-info &>/dev/null; then
        log_with_timestamp "${GREEN}✓ kubectl connected to cluster${NC}"
        kubectl cluster-info | tee -a "$LOG_FILE"
    else
        log_with_timestamp "${RED}✗ kubectl cannot connect to cluster${NC}"
        return 1
    fi
    
    echo "" | tee -a "$LOG_FILE"
    
    # Node status and resources
    log_with_timestamp "Node status and resources:"
    kubectl get nodes -o wide | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    if kubectl top nodes &>/dev/null; then
        log_with_timestamp "Node resource usage:"
        kubectl top nodes | tee -a "$LOG_FILE"
    else
        log_with_timestamp "${YELLOW}⚠ Metrics server not available for resource monitoring${NC}"
    fi
    echo "" | tee -a "$LOG_FILE"
}

# Function to analyze cert-manager namespace and resources
analyze_cert_manager_state() {
    log_with_timestamp "=== Phase 2: Cert-Manager State Analysis ==="
    
    # Check namespace
    if kubectl get namespace cert-manager &>/dev/null; then
        log_with_timestamp "${GREEN}✓ cert-manager namespace exists${NC}"
    else
        log_with_timestamp "${RED}✗ cert-manager namespace missing${NC}"
        log_with_timestamp "Creating cert-manager namespace..."
        kubectl create namespace cert-manager | tee -a "$LOG_FILE"
    fi
    
    # Check Helm release
    if helm status cert-manager -n cert-manager &>/dev/null; then
        log_with_timestamp "${GREEN}✓ cert-manager Helm release found${NC}"
        helm status cert-manager -n cert-manager | tee -a "$LOG_FILE"
    else
        log_with_timestamp "${YELLOW}⚠ cert-manager Helm release not found or failed${NC}"
    fi
    
    echo "" | tee -a "$LOG_FILE"
    
    # Pod status with detailed information
    log_with_timestamp "Cert-manager pod status:"
    kubectl get pods -n cert-manager -o wide | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # Deployment status
    log_with_timestamp "Cert-manager deployment status:"
    kubectl get deployments -n cert-manager -o wide | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # CRD status
    log_with_timestamp "Cert-manager CRDs:"
    kubectl get crd | grep cert-manager | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# Function to capture problematic pod details
analyze_problematic_pods() {
    log_with_timestamp "=== Phase 3: Problematic Pod Analysis ==="
    
    # Find non-running pods
    local failed_pods=$(kubectl get pods -n cert-manager --no-headers | grep -v "Running\|Completed" | awk '{print $1}' || true)
    
    if [[ -n "$failed_pods" ]]; then
        log_with_timestamp "${RED}Found problematic pods:${NC}"
        echo "$failed_pods" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        
        # Describe each failed pod
        while IFS= read -r pod; do
            if [[ -n "$pod" ]]; then
                log_with_timestamp "Describing pod: $pod"
                kubectl describe pod "$pod" -n cert-manager | tee -a "$LOG_FILE"
                echo "" | tee -a "$LOG_FILE"
                
                # Get logs if available
                log_with_timestamp "Logs for pod: $pod"
                kubectl logs "$pod" -n cert-manager --tail=50 | tee -a "$LOG_FILE" || echo "No logs available" | tee -a "$LOG_FILE"
                echo "" | tee -a "$LOG_FILE"
            fi
        done <<< "$failed_pods"
    else
        log_with_timestamp "${GREEN}✓ No problematic pods found${NC}"
    fi
}

# Function to capture recent events
analyze_recent_events() {
    log_with_timestamp "=== Phase 4: Recent Events Analysis ==="
    
    log_with_timestamp "Recent cert-manager events (last 20):"
    kubectl get events -n cert-manager --sort-by=.metadata.creationTimestamp | tail -20 | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    log_with_timestamp "Warning and error events:"
    kubectl get events -n cert-manager --field-selector type!=Normal | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# Function to test network connectivity
test_network_connectivity() {
    log_with_timestamp "=== Phase 5: Network Connectivity Tests ==="
    
    # Test Jetstack charts
    log_with_timestamp "Testing Jetstack chart repository connectivity..."
    if curl -s --max-time 10 https://charts.jetstack.io/index.yaml >/dev/null; then
        log_with_timestamp "${GREEN}✓ Jetstack charts accessible${NC}"
    else
        log_with_timestamp "${RED}✗ Jetstack charts inaccessible${NC}"
    fi
    
    # Test Docker Hub
    log_with_timestamp "Testing Docker Hub connectivity..."
    if curl -s --max-time 10 https://registry-1.docker.io/v2/ >/dev/null; then
        log_with_timestamp "${GREEN}✓ Docker Hub accessible${NC}"
    else
        log_with_timestamp "${RED}✗ Docker Hub inaccessible${NC}"
    fi
    
    # Test Quay.io (cert-manager images)
    log_with_timestamp "Testing Quay.io connectivity..."
    if curl -s --max-time 10 https://quay.io/v2/ >/dev/null; then
        log_with_timestamp "${GREEN}✓ Quay.io accessible${NC}"
    else
        log_with_timestamp "${RED}✗ Quay.io inaccessible${NC}"
    fi
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to check image pull status
check_image_pull_status() {
    log_with_timestamp "=== Phase 6: Image Pull Status ==="
    
    local pods=$(kubectl get pods -n cert-manager --no-headers | awk '{print $1}' || true)
    
    if [[ -n "$pods" ]]; then
        while IFS= read -r pod; do
            if [[ -n "$pod" ]]; then
                log_with_timestamp "Image pull status for pod: $pod"
                kubectl get pod "$pod" -n cert-manager -o jsonpath='{.status.containerStatuses[*].image}' | tee -a "$LOG_FILE"
                echo "" | tee -a "$LOG_FILE"
                kubectl get pod "$pod" -n cert-manager -o jsonpath='{.status.containerStatuses[*].imageID}' | tee -a "$LOG_FILE"
                echo "" | tee -a "$LOG_FILE"
                
                # Check for image pull errors
                local pull_status=$(kubectl get pod "$pod" -n cert-manager -o jsonpath='{.status.containerStatuses[*].state}' || true)
                if [[ "$pull_status" == *"ImagePullBackOff"* ]] || [[ "$pull_status" == *"ErrImagePull"* ]]; then
                    log_with_timestamp "${RED}✗ Image pull issues detected for $pod${NC}"
                fi
            fi
        done <<< "$pods"
    else
        log_with_timestamp "${YELLOW}⚠ No cert-manager pods found${NC}"
    fi
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to provide specific recommendations
provide_recommendations() {
    log_with_timestamp "=== Phase 7: Diagnosis and Recommendations ==="
    
    local recommendations=()
    
    # Check for common stalling scenarios
    local namespace_exists=$(kubectl get namespace cert-manager --no-headers 2>/dev/null | wc -l)
    local helm_release_exists=$(helm list -n cert-manager --no-headers 2>/dev/null | wc -l)
    local pods_count=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | wc -l)
    local running_pods=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep "Running" | wc -l)
    
    if [[ $namespace_exists -eq 0 ]]; then
        recommendations+=("ISSUE: cert-manager namespace missing")
        recommendations+=("ACTION: Run 'kubectl create namespace cert-manager'")
    fi
    
    if [[ $helm_release_exists -eq 0 ]]; then
        recommendations+=("ISSUE: cert-manager Helm release not found")
        recommendations+=("ACTION: Check if Helm installation failed or is still in progress")
    fi
    
    if [[ $pods_count -eq 0 ]]; then
        recommendations+=("ISSUE: No cert-manager pods found")
        recommendations+=("ACTION: Helm installation may have failed - check Helm logs")
    elif [[ $running_pods -eq 0 ]]; then
        recommendations+=("ISSUE: No cert-manager pods are running")
        recommendations+=("ACTION: Check pod descriptions and events for failure reasons")
    fi
    
    # Check for stuck deployments
    local pending_pods=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep -c "Pending\|ContainerCreating\|ImagePullBackOff" || echo "0")
    if [[ $pending_pods -gt 0 ]]; then
        recommendations+=("ISSUE: $pending_pods pods stuck in non-running state")
        recommendations+=("ACTION: Check node resources, image pull capabilities, and network connectivity")
    fi
    
    # Network connectivity issues
    if ! curl -s --max-time 5 https://charts.jetstack.io/index.yaml >/dev/null; then
        recommendations+=("ISSUE: Cannot reach Jetstack chart repository")
        recommendations+=("ACTION: Check firewall, proxy settings, and DNS resolution")
    fi
    
    # Resource constraints
    if kubectl top nodes &>/dev/null; then
        local high_cpu_nodes=$(kubectl top nodes --no-headers | awk '{if ($3 > 80) print $1}' | wc -l)
        local high_mem_nodes=$(kubectl top nodes --no-headers | awk '{if ($5 > 80) print $1}' | wc -l)
        
        if [[ $high_cpu_nodes -gt 0 ]]; then
            recommendations+=("ISSUE: $high_cpu_nodes nodes have high CPU usage (>80%)")
            recommendations+=("ACTION: Consider scaling or reducing workload")
        fi
        
        if [[ $high_mem_nodes -gt 0 ]]; then
            recommendations+=("ISSUE: $high_mem_nodes nodes have high memory usage (>80%)")
            recommendations+=("ACTION: Consider scaling or reducing workload")
        fi
    fi
    
    # Output recommendations
    if [[ ${#recommendations[@]} -gt 0 ]]; then
        log_with_timestamp "${YELLOW}Recommendations:${NC}"
        for rec in "${recommendations[@]}"; do
            log_with_timestamp "  $rec"
        done
    else
        log_with_timestamp "${GREEN}✓ No obvious issues detected${NC}"
    fi
    
    echo "" | tee -a "$LOG_FILE"
}

# Function to provide recovery commands
provide_recovery_commands() {
    log_with_timestamp "=== Phase 8: Recovery Commands ==="
    
    cat << 'EOF' | tee -a "$LOG_FILE"
If cert-manager is stalling during site.yaml execution, try these recovery steps:

1. Emergency stop and cleanup:
   kubectl delete namespace cert-manager --force --grace-period=0
   helm uninstall cert-manager -n cert-manager || true

2. Manual cert-manager installation:
   kubectl create namespace cert-manager
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.crds.yaml
   helm repo add jetstack https://charts.jetstack.io --force-update
   helm repo update
   helm install cert-manager jetstack/cert-manager \
     --namespace cert-manager \
     --timeout 600s \
     --wait \
     --values /dev/stdin << 'VALUES'
installCRDs: false
prometheus:
  enabled: true
global:
  imagePullPolicy: IfNotPresent
image:
  pullPolicy: IfNotPresent
webhook:
  image:
    pullPolicy: IfNotPresent
  resources:
    requests:
      cpu: 10m
      memory: 32Mi
cainjector:
  image:
    pullPolicy: IfNotPresent
  resources:
    requests:
      cpu: 10m
      memory: 32Mi
resources:
  requests:
    cpu: 10m
    memory: 32Mi
VALUES

3. Verify installation:
   kubectl get pods -n cert-manager -w
   kubectl rollout status deployment/cert-manager -n cert-manager
   kubectl rollout status deployment/cert-manager-webhook -n cert-manager
   kubectl rollout status deployment/cert-manager-cainjector -n cert-manager

4. Test functionality:
   kubectl apply -f - << 'TEST'
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: test-selfsigned
  namespace: cert-manager
spec:
  selfSigned: {}
TEST
   kubectl get issuer test-selfsigned -n cert-manager
   kubectl delete issuer test-selfsigned -n cert-manager

5. Resume site.yaml from monitoring stack:
   ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml
EOF
}

# Main execution
main() {
    echo "Starting cert-manager stall diagnosis..." | tee -a "$LOG_FILE"
    
    # Check prerequisites
    log_with_timestamp "Checking prerequisites..."
    check_command kubectl || exit 1
    check_command helm || exit 1
    check_command curl || exit 1
    
    echo "" | tee -a "$LOG_FILE"
    
    # Run analysis phases
    analyze_cluster_state
    analyze_cert_manager_state
    analyze_problematic_pods
    analyze_recent_events
    test_network_connectivity
    check_image_pull_status
    provide_recommendations
    provide_recovery_commands
    
    log_with_timestamp "=== Diagnosis Complete ==="
    log_with_timestamp "Full log saved to: $LOG_FILE"
    log_with_timestamp ""
    log_with_timestamp "To monitor cert-manager deployment in real-time:"
    log_with_timestamp "  watch 'kubectl get pods -n cert-manager'"
    log_with_timestamp ""
    log_with_timestamp "To follow deployment events:"
    log_with_timestamp "  kubectl get events -n cert-manager -w"
}

# Execute main function
main "$@"
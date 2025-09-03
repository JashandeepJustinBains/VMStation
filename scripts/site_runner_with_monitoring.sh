#!/bin/bash

# Enhanced site.yaml runner with cert-manager stall detection and recovery
# Provides real-time monitoring and automatic recovery for cert-manager deployment issues

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="/tmp/site_deployment_${TIMESTAMP}.log"
MONITOR_INTERVAL=10  # seconds between monitoring checks
MAX_CERT_MANAGER_WAIT=900  # 15 minutes max wait for cert-manager

echo "=== VMStation Site.yaml Enhanced Deployment ===" | tee "$LOG_FILE"
echo "Timestamp: $(date)" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to monitor cert-manager deployment progress
monitor_cert_manager_progress() {
    local start_time=$(date +%s)
    local timeout_time=$((start_time + MAX_CERT_MANAGER_WAIT))
    
    log_with_timestamp "Starting cert-manager deployment monitoring (max wait: ${MAX_CERT_MANAGER_WAIT}s)"
    
    while true; do
        local current_time=$(date +%s)
        
        # Check if timeout reached
        if [[ $current_time -gt $timeout_time ]]; then
            log_with_timestamp "${RED}✗ cert-manager deployment timeout reached (${MAX_CERT_MANAGER_WAIT}s)${NC}"
            return 1
        fi
        
        # Check cert-manager namespace exists
        if ! kubectl get namespace cert-manager &>/dev/null; then
            log_with_timestamp "Waiting for cert-manager namespace creation..."
            sleep $MONITOR_INTERVAL
            continue
        fi
        
        # Check if Helm release exists
        if ! helm list -n cert-manager | grep -q cert-manager; then
            log_with_timestamp "Waiting for cert-manager Helm release..."
            sleep $MONITOR_INTERVAL
            continue
        fi
        
        # Check deployment status
        local deployments=("cert-manager" "cert-manager-webhook" "cert-manager-cainjector")
        local all_ready=true
        
        for deployment in "${deployments[@]}"; do
            if ! kubectl get deployment "$deployment" -n cert-manager &>/dev/null; then
                log_with_timestamp "Waiting for deployment: $deployment"
                all_ready=false
                break
            fi
            
            local ready_replicas=$(kubectl get deployment "$deployment" -n cert-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            local desired_replicas=$(kubectl get deployment "$deployment" -n cert-manager -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
            
            if [[ "$ready_replicas" != "$desired_replicas" ]]; then
                log_with_timestamp "Deployment $deployment: $ready_replicas/$desired_replicas ready"
                all_ready=false
            fi
        done
        
        if $all_ready; then
            log_with_timestamp "${GREEN}✓ All cert-manager deployments are ready${NC}"
            return 0
        fi
        
        # Check for stuck pods
        local stuck_pods=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep -E "ImagePullBackOff|CrashLoopBackOff|Error" | wc -l || echo "0")
        if [[ $stuck_pods -gt 0 ]]; then
            log_with_timestamp "${YELLOW}⚠ Found $stuck_pods stuck pods, checking for recovery...${NC}"
            
            # Show current pod status
            kubectl get pods -n cert-manager -o wide | tee -a "$LOG_FILE"
            
            # If stuck for more than 5 minutes, trigger recovery
            local elapsed_time=$((current_time - start_time))
            if [[ $elapsed_time -gt 300 ]]; then
                log_with_timestamp "${YELLOW}Pods stuck for >5 minutes, triggering recovery${NC}"
                return 2  # Recovery needed
            fi
        fi
        
        # Show progress every 30 seconds
        if [[ $((current_time % 30)) -eq 0 ]]; then
            log_with_timestamp "cert-manager deployment in progress..."
            kubectl get pods -n cert-manager --no-headers | tee -a "$LOG_FILE"
        fi
        
        sleep $MONITOR_INTERVAL
    done
}

# Function to recover from cert-manager deployment issues
recover_cert_manager() {
    log_with_timestamp "${YELLOW}Starting cert-manager recovery process...${NC}"
    
    # Stop monitoring and clean up
    log_with_timestamp "Cleaning up failed cert-manager installation..."
    
    # Remove stuck Helm release
    helm uninstall cert-manager -n cert-manager || true
    
    # Force delete namespace if stuck
    kubectl delete namespace cert-manager --force --grace-period=0 || true
    
    # Wait for cleanup
    log_with_timestamp "Waiting for cleanup to complete..."
    sleep 30
    
    # Recreate namespace
    kubectl create namespace cert-manager
    
    # Install CRDs
    log_with_timestamp "Installing cert-manager CRDs..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.crds.yaml
    
    # Update Helm repos
    log_with_timestamp "Updating Helm repositories..."
    helm repo add jetstack https://charts.jetstack.io --force-update
    helm repo update
    
    # Install cert-manager with explicit values
    log_with_timestamp "Installing cert-manager with recovery configuration..."
    cat << 'VALUES' > /tmp/cert-manager-recovery-values.yaml
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
    limits:
      cpu: 100m
      memory: 128Mi
cainjector:
  image:
    pullPolicy: IfNotPresent
  resources:
    requests:
      cpu: 10m
      memory: 32Mi
    limits:
      cpu: 100m
      memory: 128Mi
resources:
  requests:
    cpu: 10m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 128Mi
VALUES

    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --timeout 600s \
        --wait \
        --values /tmp/cert-manager-recovery-values.yaml
    
    # Verify recovery
    if monitor_cert_manager_progress; then
        log_with_timestamp "${GREEN}✓ cert-manager recovery successful${NC}"
        rm -f /tmp/cert-manager-recovery-values.yaml
        return 0
    else
        log_with_timestamp "${RED}✗ cert-manager recovery failed${NC}"
        return 1
    fi
}

# Function to run site.yaml with monitoring
run_site_with_monitoring() {
    local inventory_file="${1:-ansible/inventory.txt}"
    
    log_with_timestamp "Starting site.yaml deployment with enhanced monitoring..."
    
    # Pre-flight checks
    log_with_timestamp "Running pre-flight checks..."
    if ! kubectl cluster-info &>/dev/null; then
        log_with_timestamp "${RED}✗ kubectl cannot connect to cluster${NC}"
        exit 1
    fi
    
    if ! helm version &>/dev/null; then
        log_with_timestamp "${RED}✗ helm not available${NC}"
        exit 1
    fi
    
    log_with_timestamp "${GREEN}✓ Pre-flight checks passed${NC}"
    
    # Start site.yaml in background
    log_with_timestamp "Starting ansible-playbook site.yaml..."
    
    ansible-playbook -i "$inventory_file" ansible/site.yaml \
        --extra-vars "monitor_cert_manager=true" \
        2>&1 | tee -a "$LOG_FILE" &
    
    local ansible_pid=$!
    log_with_timestamp "Ansible playbook PID: $ansible_pid"
    
    # Monitor cert-manager phase
    sleep 30  # Give Ansible time to start
    
    while kill -0 $ansible_pid 2>/dev/null; do
        # Check if we're in the cert-manager phase
        if kubectl get namespace cert-manager &>/dev/null; then
            log_with_timestamp "Detected cert-manager deployment phase, starting monitoring..."
            
            # Monitor with recovery
            if ! monitor_cert_manager_progress; then
                local monitor_result=$?
                
                if [[ $monitor_result -eq 2 ]]; then
                    # Recovery needed
                    log_with_timestamp "${YELLOW}Attempting cert-manager recovery...${NC}"
                    
                    # Kill Ansible if it's stuck
                    if kill -0 $ansible_pid 2>/dev/null; then
                        log_with_timestamp "Terminating stuck Ansible process..."
                        kill $ansible_pid || true
                        wait $ansible_pid 2>/dev/null || true
                    fi
                    
                    # Attempt recovery
                    if recover_cert_manager; then
                        log_with_timestamp "${GREEN}Recovery successful, resuming deployment...${NC}"
                        
                        # Resume from monitoring stack
                        ansible-playbook -i "$inventory_file" ansible/plays/kubernetes/deploy_monitoring.yaml \
                            2>&1 | tee -a "$LOG_FILE" &
                        ansible_pid=$!
                    else
                        log_with_timestamp "${RED}Recovery failed, stopping deployment${NC}"
                        exit 1
                    fi
                else
                    # Timeout without recovery
                    log_with_timestamp "${RED}cert-manager deployment timeout${NC}"
                    if kill -0 $ansible_pid 2>/dev/null; then
                        kill $ansible_pid || true
                    fi
                    exit 1
                fi
            else
                log_with_timestamp "${GREEN}cert-manager deployment completed successfully${NC}"
                break
            fi
        fi
        
        sleep $MONITOR_INTERVAL
    done
    
    # Wait for Ansible to complete
    if kill -0 $ansible_pid 2>/dev/null; then
        log_with_timestamp "Waiting for site.yaml deployment to complete..."
        wait $ansible_pid
        local exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            log_with_timestamp "${GREEN}✓ Site deployment completed successfully${NC}"
        else
            log_with_timestamp "${RED}✗ Site deployment failed with exit code: $exit_code${NC}"
            exit $exit_code
        fi
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Enhanced site.yaml runner with cert-manager stall detection and recovery.

OPTIONS:
    -i, --inventory FILE    Ansible inventory file (default: ansible/inventory.txt)
    -h, --help             Show this help message
    --diagnose-only        Run diagnosis without deployment
    --monitor-only         Monitor existing cert-manager deployment
    --recover-only         Attempt cert-manager recovery only

EXAMPLES:
    $0                                    # Run full site deployment with monitoring
    $0 -i custom_inventory.txt            # Use custom inventory
    $0 --diagnose-only                    # Diagnose current cert-manager state
    $0 --recover-only                     # Attempt cert-manager recovery

EOF
}

# Main execution
main() {
    local inventory_file="ansible/inventory.txt"
    local mode="deploy"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--inventory)
                inventory_file="$2"
                shift 2
                ;;
            --diagnose-only)
                mode="diagnose"
                shift
                ;;
            --monitor-only)
                mode="monitor"
                shift
                ;;
            --recover-only)
                mode="recover"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_with_timestamp "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Execute based on mode
    case $mode in
        deploy)
            run_site_with_monitoring "$inventory_file"
            ;;
        diagnose)
            ./scripts/diagnose_cert_manager_stall.sh
            ;;
        monitor)
            monitor_cert_manager_progress
            ;;
        recover)
            recover_cert_manager
            ;;
    esac
    
    log_with_timestamp "Operation completed. Log saved to: $LOG_FILE"
}

# Handle script interruption
trap 'log_with_timestamp "Script interrupted"; exit 130' INT TERM

# Execute main function
main "$@"
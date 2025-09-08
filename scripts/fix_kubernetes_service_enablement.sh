#!/bin/bash

# Fix script for enabling disabled Kubernetes services
# Addresses kubelet, containerd services that were disabled during testing

set -e

echo "=== VMStation Kubernetes Service Enablement Fix ==="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

notice() {
    echo -e "${BLUE}[NOTICE]${NC} $1"
}

echo "=== Phase 1: Check Current Service Status ==="

# Function to check and fix service status
check_and_fix_service() {
    local service_name=$1
    local description=$2
    
    echo ""
    notice "Checking $description ($service_name)..."
    
    # Check if service exists
    if ! systemctl list-unit-files "$service_name.service" >/dev/null 2>&1; then
        warn "$service_name service not found on this system"
        return 1
    fi
    
    # Get service status
    local status=$(systemctl is-active "$service_name" 2>/dev/null || echo "inactive")
    local enabled=$(systemctl is-enabled "$service_name" 2>/dev/null || echo "disabled")
    
    echo "  Current status: $status"
    echo "  Current enabled state: $enabled"
    
    # Fix service if needed
    local needs_fix=false
    
    if [ "$enabled" = "disabled" ]; then
        warn "$service_name is disabled - enabling it"
        if sudo systemctl enable "$service_name"; then
            info "Successfully enabled $service_name"
            needs_fix=true
        else
            error "Failed to enable $service_name"
            return 1
        fi
    else
        info "$service_name is already enabled"
    fi
    
    if [ "$status" != "active" ]; then
        warn "$service_name is not active - starting it"
        if sudo systemctl start "$service_name"; then
            info "Successfully started $service_name"
            needs_fix=true
        else
            error "Failed to start $service_name - checking logs..."
            echo "Recent logs for $service_name:"
            sudo journalctl -u "$service_name" -n 10 --no-pager || true
            return 1
        fi
    else
        info "$service_name is already active"
    fi
    
    # Verify final status
    local final_status=$(systemctl is-active "$service_name" 2>/dev/null || echo "inactive")
    local final_enabled=$(systemctl is-enabled "$service_name" 2>/dev/null || echo "disabled")
    
    if [ "$final_status" = "active" ] && [ "$final_enabled" = "enabled" ]; then
        info "✓ $service_name is now active and enabled"
        return 0
    else
        error "✗ $service_name fix incomplete: status=$final_status, enabled=$final_enabled"
        return 1
    fi
}

# Track services that were fixed
fixed_services=()
failed_services=()

# Check and fix containerd
if check_and_fix_service "containerd" "Container Runtime (containerd)"; then
    fixed_services+=("containerd")
else
    failed_services+=("containerd")
fi

# Check and fix kubelet
if check_and_fix_service "kubelet" "Kubernetes Node Agent (kubelet)"; then
    fixed_services+=("kubelet")
else
    failed_services+=("kubelet")
fi

echo ""
echo "=== Phase 2: Check Flannel Status ==="

notice "Checking Flannel networking..."
echo "Note: Flannel runs as Kubernetes pods, not systemd services"

# Check if kubectl is available and cluster is accessible
if command -v kubectl >/dev/null 2>&1; then
    if kubectl cluster-info >/dev/null 2>&1; then
        info "Kubernetes cluster is accessible"
        
        # Check flannel pods
        flannel_pods=$(kubectl get pods -n kube-flannel -l app=flannel 2>/dev/null | grep -c "Running" || echo "0")
        if [ "$flannel_pods" -gt 0 ]; then
            info "✓ Found $flannel_pods running Flannel pods"
        else
            warn "No running Flannel pods found"
            echo "  To check Flannel status: kubectl get pods -n kube-flannel"
            echo "  To restart Flannel: kubectl delete pods -n kube-flannel -l app=flannel"
        fi
        
        # Check flannel daemonset
        if kubectl get daemonset kube-flannel-ds -n kube-flannel >/dev/null 2>&1; then
            info "✓ Flannel DaemonSet exists"
        else
            warn "Flannel DaemonSet not found - may need to be deployed"
        fi
    else
        warn "Kubernetes cluster not accessible - cannot check Flannel pods"
        echo "  Ensure kubelet and containerd are running first"
    fi
else
    warn "kubectl not available - cannot check Flannel status"
fi

echo ""
echo "=== Phase 3: CNI Status Check ==="

notice "Checking CNI configuration..."

# Check CNI directories and files
cni_dirs=("/etc/cni/net.d" "/opt/cni/bin")
for dir in "${cni_dirs[@]}"; do
    if [ -d "$dir" ]; then
        file_count=$(ls "$dir" 2>/dev/null | wc -l)
        if [ "$file_count" -gt 0 ]; then
            info "✓ $dir exists with $file_count files"
        else
            warn "$dir exists but is empty"
        fi
    else
        warn "$dir does not exist"
    fi
done

echo ""
echo "=== Summary ==="

# Print results
if [ ${#fixed_services[@]} -gt 0 ]; then
    info "Services that were fixed:"
    for service in "${fixed_services[@]}"; do
        echo "  ✓ $service"
    done
fi

if [ ${#failed_services[@]} -gt 0 ]; then
    error "Services that failed to fix:"
    for service in "${failed_services[@]}"; do
        echo "  ✗ $service"
    done
fi

echo ""
info "Current service status:"
for service in "containerd" "kubelet"; do
    if systemctl list-unit-files "$service.service" >/dev/null 2>&1; then
        status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        enabled=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")
        echo "  $service: $status, $enabled"
    else
        echo "  $service: not found"
    fi
done

echo ""
echo "=== Next Steps ==="

if [ ${#failed_services[@]} -gt 0 ]; then
    error "Some services could not be fixed. Manual intervention may be required."
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check service logs: journalctl -u <service-name> -f"
    echo "2. Check configuration files:"
    echo "   - containerd: /etc/containerd/config.toml"
    echo "   - kubelet: /etc/systemd/system/kubelet.service.d/"
    echo "3. Verify installation: rpm -qa | grep -E 'kubelet|containerd' (RHEL) or dpkg -l | grep -E 'kubelet|containerd' (Ubuntu)"
    exit 1
else
    info "All critical Kubernetes services are now enabled and running!"
    echo ""
    echo "Additional checks you can run:"
    echo "1. Verify cluster status: kubectl cluster-info"
    echo "2. Check node status: kubectl get nodes"
    echo "3. Check system pods: kubectl get pods -n kube-system"
    echo "4. Check Flannel: kubectl get pods -n kube-flannel"
    echo ""
    info "If you continue to have issues, consider running the full setup:"
    echo "  ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes_stack.yaml"
fi

echo ""
info "Fix completed at $(date)"
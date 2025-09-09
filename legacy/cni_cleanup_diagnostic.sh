#!/bin/bash
# CNI Cleanup and Diagnostic Script for VMStation
# Addresses cert-manager hanging issues due to stale CNI state

set -euo pipefail

echo "=== VMStation CNI Cleanup and Diagnostics ==="
echo "Hostname: $(hostname)"
echo "IP Address: $(hostname -I | awk '{print $1}')"
echo "Date: $(date)"
echo ""

# Function to check if we're on a worker node
is_worker_node() {
    # Check if this is not a control plane node
    if kubectl get nodes "$(hostname)" --show-labels 2>/dev/null | grep -q "node-role.kubernetes.io/control-plane"; then
        return 1  # This is a control plane node
    else
        return 0  # This is a worker node
    fi
}

# Function to display current CNI state
show_cni_state() {
    echo "=== Current CNI State ==="
    
    echo "Network interfaces:"
    ip link show | grep -E "(cni0|cbr0|flannel)" || echo "No CNI interfaces found"
    
    echo ""
    echo "CNI configuration files:"
    if [ -d /etc/cni/net.d ]; then
        ls -la /etc/cni/net.d/ || echo "CNI config directory empty"
    else
        echo "CNI config directory does not exist"
    fi
    
    echo ""
    echo "CNI binaries:"
    if [ -d /opt/cni/bin ]; then
        echo "CNI plugins found:"
        ls -la /opt/cni/bin/ | grep -E "(flannel|bridge|portmap|loopback)" || echo "No standard CNI binaries found"
    else
        echo "CNI binary directory does not exist"
    fi
    
    echo ""
    echo "IP routes related to pod networks:"
    ip route show | grep -E "(10\.244|cni0|cbr0|flannel)" || echo "No pod network routes found"
    
    echo ""
}

# Function to clean up CNI state
cleanup_cni_state() {
    echo "=== Cleaning Up CNI State ==="
    
    # Stop kubelet if running
    echo "Stopping kubelet service..."
    systemctl stop kubelet 2>/dev/null || echo "kubelet was not running"
    
    # Remove CNI interfaces
    echo "Removing CNI network interfaces..."
    for interface in cni0 cbr0 flannel.1; do
        if ip link show "$interface" 2>/dev/null; then
            echo "  Removing $interface interface"
            ip link set "$interface" down 2>/dev/null || true
            ip link delete "$interface" 2>/dev/null || true
        else
            echo "  $interface interface not found"
        fi
    done
    
    # Clear CNI configuration
    echo "Clearing CNI configuration files..."
    rm -rf /etc/cni/net.d/* 2>/dev/null || true
    rm -rf /opt/cni/bin/flannel 2>/dev/null || true
    
    # Clear CNI state
    echo "Clearing CNI plugin state..."
    rm -rf /var/lib/cni/networks/* 2>/dev/null || true
    rm -rf /var/lib/cni/results/* 2>/dev/null || true
    
    # Clear kubelet CNI state
    echo "Clearing kubelet CNI state..."
    rm -rf /var/lib/kubelet/pods/* 2>/dev/null || true
    rm -rf /var/lib/kubelet/plugins_registry/* 2>/dev/null || true
    
    echo "CNI cleanup completed!"
    echo ""
}

# Function to validate clean state
validate_clean_state() {
    echo "=== Validating Clean CNI State ==="
    
    local issues_found=0
    
    # Check for remaining CNI interfaces
    for interface in cni0 cbr0 flannel.1; do
        if ip link show "$interface" 2>/dev/null; then
            echo "❌ $interface interface still exists"
            issues_found=$((issues_found + 1))
        else
            echo "✅ $interface interface removed"
        fi
    done
    
    # Check for CNI config files
    if [ -d /etc/cni/net.d ] && [ "$(ls -A /etc/cni/net.d/)" ]; then
        echo "❌ CNI configuration files still exist:"
        ls -la /etc/cni/net.d/
        issues_found=$((issues_found + 1))
    else
        echo "✅ No CNI configuration files found"
    fi
    
    # Check for flannel binary
    if [ -f /opt/cni/bin/flannel ]; then
        echo "❌ Flannel CNI binary still exists"
        issues_found=$((issues_found + 1))
    else
        echo "✅ No flannel CNI binary found"
    fi
    
    echo ""
    if [ $issues_found -eq 0 ]; then
        echo "🎉 CNI state is clean - ready for cluster join!"
        return 0
    else
        echo "⚠️  $issues_found CNI cleanup issues found"
        return 1
    fi
}

# Function to check cert-manager readiness
check_cert_manager() {
    echo "=== Checking cert-manager Status ==="
    
    if ! command -v kubectl >/dev/null 2>&1; then
        echo "kubectl not available - cannot check cert-manager"
        return
    fi
    
    if ! kubectl get namespaces cert-manager 2>/dev/null; then
        echo "cert-manager namespace not found"
        return
    fi
    
    echo "cert-manager pods:"
    kubectl get pods -n cert-manager -o wide 2>/dev/null || echo "Cannot get cert-manager pods"
    
    echo ""
    echo "cert-manager pod events (recent failures):"
    kubectl get events -n cert-manager --field-selector type!=Normal --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -10 || echo "Cannot get cert-manager events"
    
    echo ""
}

# Main execution
main() {
    case "${1:-help}" in
        "show")
            show_cni_state
            check_cert_manager
            ;;
        "cleanup")
            show_cni_state
            cleanup_cni_state
            validate_clean_state
            ;;
        "validate")
            validate_clean_state
            ;;
        "worker-cleanup")
            if is_worker_node; then
                echo "This is a worker node - performing CNI cleanup"
                show_cni_state
                cleanup_cni_state
                validate_clean_state
            else
                echo "This is a control plane node - skipping worker CNI cleanup"
                show_cni_state
            fi
            ;;
        *)
            echo "VMStation CNI Cleanup and Diagnostic Script"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  show            - Display current CNI state and cert-manager status"
            echo "  cleanup         - Clean up all CNI state (USE WITH CAUTION)"
            echo "  validate        - Check if CNI state is clean"
            echo "  worker-cleanup  - Clean up CNI state only on worker nodes"
            echo "  help            - Show this help message"
            echo ""
            echo "This script addresses cert-manager hanging issues caused by:"
            echo "- Stale CNI interfaces (cni0, cbr0, flannel.1) on worker nodes"
            echo "- Conflicting CNI configuration files"
            echo "- Leftover CNI plugin state"
            echo ""
            echo "Run 'worker-cleanup' on all worker nodes before cluster join to prevent"
            echo "cert-manager pods from failing with CNI bridge address conflicts."
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
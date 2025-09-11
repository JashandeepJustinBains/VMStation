#!/bin/bash

# Manual Containerd Filesystem Fix
# Comprehensive manual fix for containerd imageFilesystem detection issues
# This script should be run when the automated enhanced_kubeadm_join.sh fails

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

echo "=== Manual Containerd Filesystem Fix ==="
echo "Timestamp: $(date)"
echo ""

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
        error "Please run: sudo $0"
        exit 1
    fi
}

# Function to backup current containerd config
backup_containerd_config() {
    info "Creating backup of current containerd configuration..."
    
    # Create backup directory
    local backup_dir="/tmp/containerd-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup containerd config if it exists
    if [ -f /etc/containerd/config.toml ]; then
        cp /etc/containerd/config.toml "$backup_dir/"
        info "✓ Backed up containerd config to: $backup_dir/config.toml"
    fi
    
    # Backup crictl config if it exists
    if [ -f /etc/crictl.yaml ]; then
        cp /etc/crictl.yaml "$backup_dir/"
        info "✓ Backed up crictl config to: $backup_dir/crictl.yaml"
    fi
    
    echo "$backup_dir" > /tmp/containerd-backup-location
    info "✓ Backup location saved to: /tmp/containerd-backup-location"
}

# Function to regenerate containerd configuration
regenerate_containerd_config() {
    info "Regenerating containerd configuration..."
    
    # Ensure containerd config directory exists
    mkdir -p /etc/containerd
    
    # Generate default containerd config
    info "Generating fresh containerd configuration..."
    containerd config default > /etc/containerd/config.toml
    
    # Modify config for Kubernetes compatibility
    info "Modifying containerd config for Kubernetes compatibility..."
    
    # Enable SystemdCgroup
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # Ensure sandbox_image is set correctly
    sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.9"|' /etc/containerd/config.toml
    
    info "✓ Containerd configuration regenerated"
}

# Function to configure crictl
configure_crictl() {
    info "Configuring crictl..."
    
    # Create crictl config
    cat > /etc/crictl.yaml << EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
    
    info "✓ crictl configuration created"
}

# Function to reset containerd completely
reset_containerd_completely() {
    info "Performing complete containerd reset..."
    
    # Stop all related services
    info "Stopping kubelet and containerd services..."
    systemctl stop kubelet 2>/dev/null || true
    systemctl stop containerd 2>/dev/null || true
    
    # Wait for services to stop
    sleep 5
    
    # Remove containerd socket files
    info "Removing containerd socket files..."
    rm -f /run/containerd/containerd.sock
    rm -f /run/containerd/containerd.sock.ttrpc
    
    # Clear containerd state (but preserve data)
    info "Clearing containerd runtime state..."
    rm -rf /run/containerd/*
    
    # Ensure proper permissions on containerd directory
    info "Setting proper permissions on containerd directories..."
    chown -R root:root /var/lib/containerd
    chmod -R 755 /var/lib/containerd
    
    # Create necessary runtime directories
    mkdir -p /run/containerd
    chown root:root /run/containerd
    chmod 755 /run/containerd
    
    info "✓ Containerd reset completed"
}

# Function to start containerd with verification
start_containerd_with_verification() {
    info "Starting containerd with comprehensive verification..."
    
    # Start containerd service
    info "Starting containerd service..."
    systemctl start containerd
    
    # Wait for containerd to start
    local retry_count=0
    local max_retries=30
    while [ $retry_count -lt $max_retries ]; do
        if systemctl is-active --quiet containerd; then
            info "✓ Containerd service is active"
            break
        else
            warn "Waiting for containerd to start... ($((retry_count + 1))/$max_retries)"
            sleep 2
            ((retry_count++))
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "Containerd failed to start after $max_retries attempts"
        systemctl status containerd --no-pager
        return 1
    fi
    
    # Verify containerd socket
    info "Verifying containerd socket..."
    retry_count=0
    max_retries=15
    while [ $retry_count -lt $max_retries ]; do
        if [ -S /run/containerd/containerd.sock ]; then
            info "✓ Containerd socket exists"
            break
        else
            warn "Waiting for containerd socket... ($((retry_count + 1))/$max_retries)"
            sleep 2
            ((retry_count++))
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "Containerd socket not found after $max_retries attempts"
        return 1
    fi
    
    # Test containerd functionality
    info "Testing containerd functionality..."
    retry_count=0
    max_retries=10
    while [ $retry_count -lt $max_retries ]; do
        if timeout 10 ctr version >/dev/null 2>&1; then
            info "✓ Containerd responding to API calls"
            break
        else
            warn "Waiting for containerd API... ($((retry_count + 1))/$max_retries)"
            sleep 3
            ((retry_count++))
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "Containerd API not responding after $max_retries attempts"
        return 1
    fi
    
    info "✓ Containerd started and verified successfully"
}

# Function to initialize containerd filesystem aggressively
initialize_containerd_filesystem_aggressive() {
    info "Performing aggressive containerd filesystem initialization..."
    
    # Create k8s.io namespace with verification
    info "Creating k8s.io namespace..."
    ctr namespace create k8s.io 2>/dev/null || true
    
    # Verify namespace creation
    if ctr namespace ls | grep -q k8s.io; then
        info "✓ k8s.io namespace created successfully"
    else
        warn "Failed to create k8s.io namespace"
    fi
    
    # Force image filesystem detection
    info "Forcing image filesystem detection..."
    ctr --namespace k8s.io images ls >/dev/null 2>&1 || true
    
    # Initialize snapshotter
    info "Initializing snapshotter..."
    ctr --namespace k8s.io snapshots ls >/dev/null 2>&1 || true
    
    # Force filesystem capacity detection by accessing the filesystem
    info "Triggering filesystem capacity detection..."
    find /var/lib/containerd -maxdepth 2 -type d >/dev/null 2>&1 || true
    du -sb /var/lib/containerd >/dev/null 2>&1 || true
    
    # Sync filesystem
    sync
    
    # Force CRI runtime status detection
    info "Forcing CRI runtime status detection..."
    crictl info >/dev/null 2>&1 || true
    
    # Additional CRI operations to trigger imageFilesystem
    info "Performing additional CRI operations..."
    crictl images >/dev/null 2>&1 || true
    crictl ps -a >/dev/null 2>&1 || true
    
    info "✓ Aggressive filesystem initialization completed"
}

# Function to verify imageFilesystem detection
verify_imagefilesystem_detection() {
    info "Verifying imageFilesystem detection..."
    
    local retry_count=0
    local max_retries=10
    
    while [ $retry_count -lt $max_retries ]; do
        info "Verification attempt $((retry_count + 1))/$max_retries..."
        
        # Check if crictl info shows imageFilesystem
        if crictl info 2>/dev/null | grep -q "\"imageFilesystem\""; then
            info "✓ SUCCESS: CRI status shows imageFilesystem section"
            
            # Get capacity information
            local cri_capacity=$(crictl info 2>/dev/null | grep -A10 "imageFilesystem" | grep "capacityBytes" | head -1 | grep -oE '[0-9]+' || echo "0")
            local fs_capacity=$(df -B1 /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")
            
            info "  CRI reported capacity: ${cri_capacity} bytes"
            info "  Filesystem capacity: ${fs_capacity} bytes"
            
            if [ "$cri_capacity" != "0" ] && [ "$fs_capacity" != "0" ]; then
                info "✓ SUCCESS: Both CRI and filesystem show non-zero capacity"
                return 0
            else
                warn "Capacity values are zero, retrying..."
            fi
        else
            warn "CRI status doesn't show imageFilesystem section yet"
        fi
        
        # Re-run initialization steps between retries
        if [ $retry_count -lt $((max_retries - 1)) ]; then
            info "Re-running initialization steps..."
            ctr namespace create k8s.io 2>/dev/null || true
            ctr --namespace k8s.io images ls >/dev/null 2>&1 || true
            ctr --namespace k8s.io snapshots ls >/dev/null 2>&1 || true
            crictl info >/dev/null 2>&1 || true
            crictl images >/dev/null 2>&1 || true
            sync
        fi
        
        sleep 5
        ((retry_count++))
    done
    
    error "Failed to detect imageFilesystem after $max_retries attempts"
    return 1
}

# Function to display diagnostic information
display_diagnostics() {
    info "Displaying diagnostic information..."
    
    echo ""
    info "=== System Status ==="
    info "containerd service: $(systemctl is-active containerd) (enabled: $(systemctl is-enabled containerd))"
    info "kubelet service: $(systemctl is-active kubelet) (enabled: $(systemctl is-enabled kubelet))"
    
    echo ""
    info "=== Containerd Socket ==="
    if [ -S /run/containerd/containerd.sock ]; then
        info "✓ Containerd socket exists"
        ls -la /run/containerd/containerd.sock
    else
        error "✗ Containerd socket missing"
    fi
    
    echo ""
    info "=== Filesystem Status ==="
    df -h /var/lib/containerd
    
    echo ""
    info "=== Containerd Namespaces ==="
    ctr namespace ls 2>/dev/null || warn "Failed to list containerd namespaces"
    
    echo ""
    info "=== CRI Status (First 50 lines) ==="
    crictl info 2>/dev/null | head -50 || warn "Failed to get CRI status"
    
    echo ""
    info "=== Recent Containerd Logs ==="
    journalctl -u containerd --no-pager --since "5 minutes ago" | tail -20
    
    if [ -f /tmp/containerd-backup-location ]; then
        local backup_dir=$(cat /tmp/containerd-backup-location)
        echo ""
        info "=== Backup Information ==="
        info "Configuration backup location: $backup_dir"
    fi
}

# Main function
main() {
    info "Starting manual containerd filesystem fix..."
    
    # Check prerequisites
    check_root
    
    # Backup current configuration
    backup_containerd_config
    
    # Perform complete reset and reconfiguration
    reset_containerd_completely
    regenerate_containerd_config
    configure_crictl
    
    # Start containerd with verification
    if ! start_containerd_with_verification; then
        error "Failed to start containerd properly"
        display_diagnostics
        exit 1
    fi
    
    # Perform aggressive filesystem initialization
    initialize_containerd_filesystem_aggressive
    
    # Wait a moment for initialization to settle
    info "Waiting for initialization to settle..."
    sleep 10
    
    # Verify imageFilesystem detection
    if verify_imagefilesystem_detection; then
        echo ""
        info "🎉 SUCCESS: Manual containerd filesystem fix completed!"
        info "✓ imageFilesystem is now properly detected by CRI"
        info "✓ System is ready for kubeadm join operation"
        
        echo ""
        info "Next steps:"
        info "1. Run your kubeadm join command"
        info "2. Or re-run the enhanced_kubeadm_join.sh script"
        
    else
        echo ""
        error "❌ FAILED: Manual fix could not resolve imageFilesystem detection"
        error "This indicates a deeper containerd or system configuration issue"
        
        display_diagnostics
        
        echo ""
        error "Manual troubleshooting required:"
        error "1. Check containerd logs: journalctl -u containerd -f"
        error "2. Verify containerd config: cat /etc/containerd/config.toml"
        error "3. Test containerd manually: ctr --namespace k8s.io images ls"
        error "4. Check filesystem permissions: ls -la /var/lib/containerd"
        
        exit 1
    fi
    
    # Display final diagnostics
    display_diagnostics
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
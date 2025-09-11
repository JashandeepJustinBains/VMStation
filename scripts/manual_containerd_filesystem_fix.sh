#!/bin/bash

# VMStation Manual Containerd Filesystem Fix
# Aggressive containerd configuration and filesystem initialization fix
# This script addresses persistent containerd image filesystem initialization issues

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

echo "=== VMStation Manual Containerd Filesystem Fix ==="
echo "Timestamp: $(date)"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

# Function to backup current configuration
backup_configs() {
    info "Backing up current containerd configurations..."
    
    local backup_dir="/tmp/containerd-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup containerd config
    if [ -f /etc/containerd/config.toml ]; then
        cp /etc/containerd/config.toml "$backup_dir/"
        info "✓ Backed up containerd config to $backup_dir/config.toml"
    fi
    
    # Backup crictl config
    if [ -f /etc/crictl.yaml ]; then
        cp /etc/crictl.yaml "$backup_dir/"
        info "✓ Backed up crictl config to $backup_dir/crictl.yaml"
    fi
    
    # Save service status
    systemctl status containerd --no-pager > "$backup_dir/containerd-status.txt" 2>&1 || true
    
    echo "$backup_dir" > /tmp/containerd-backup-location.txt
    info "✓ Backup location saved: $backup_dir"
}

# Function to completely reset containerd
reset_containerd() {
    info "Completely resetting containerd configuration and state..."
    
    # Stop containerd service
    info "Stopping containerd service..."
    systemctl stop containerd 2>/dev/null || true
    
    # Kill any remaining containerd processes
    pkill -f containerd 2>/dev/null || true
    sleep 5
    
    # Remove existing configuration
    warn "Removing existing containerd configuration..."
    rm -f /etc/containerd/config.toml 2>/dev/null || true
    rm -rf /etc/containerd/certs.d/* 2>/dev/null || true
    
    # Completely remove containerd state (this fixes filesystem capacity issues)
    warn "Removing all containerd state and data..."
    rm -rf /var/lib/containerd/* 2>/dev/null || true
    rm -rf /run/containerd/* 2>/dev/null || true
    
    # Remove any overlay mounts that might be stuck
    info "Cleaning up overlay mounts..."
    mount | grep overlay | awk '{print $3}' | xargs -r umount -l 2>/dev/null || true
    
    # Recreate containerd directory structure with proper permissions
    info "Recreating containerd directory structure..."
    mkdir -p /var/lib/containerd/{content,metadata,runtime,snapshots,io.containerd.grpc.v1.cri/containers,io.containerd.grpc.v1.cri/sandboxes}
    mkdir -p /run/containerd
    mkdir -p /etc/containerd
    
    # Set proper ownership and permissions
    chown -R root:root /var/lib/containerd
    chmod -R 755 /var/lib/containerd
    chown -R root:root /run/containerd
    chmod 755 /run/containerd
    chown -R root:root /etc/containerd
    chmod 755 /etc/containerd
    
    info "✓ Containerd state completely reset"
}

# Function to regenerate containerd configuration
regenerate_containerd_config() {
    info "Regenerating containerd configuration..."
    
    # Generate default containerd config
    containerd config default > /etc/containerd/config.toml
    
    # Configure containerd for Kubernetes compatibility
    info "Configuring containerd for Kubernetes..."
    
    # Enable systemd cgroup driver (required for kubelet compatibility)
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # Ensure proper sandbox_image for Kubernetes
    sed -i 's|sandbox_image = ".*"|sandbox_image = "registry.k8s.io/pause:3.6"|' /etc/containerd/config.toml
    
    # Configure runtime endpoint
    sed -i 's|runtime_root = ".*"|runtime_root = "/var/lib/containerd/runtime"|' /etc/containerd/config.toml
    sed -i 's|state_dir = ".*"|state_dir = "/run/containerd/runtime"|' /etc/containerd/config.toml
    
    # Ensure proper CNI configuration
    sed -i '/\[plugins."io.containerd.grpc.v1.cri".cni\]/,/^$/c\
    [plugins."io.containerd.grpc.v1.cri".cni]\
      bin_dir = "/opt/cni/bin"\
      conf_dir = "/etc/cni/net.d"\
      max_conf_num = 1\
      conf_template = ""' /etc/containerd/config.toml
    
    info "✓ Containerd configuration regenerated"
}

# Function to regenerate crictl configuration
regenerate_crictl_config() {
    info "Regenerating crictl configuration..."
    
    cat > /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 30
debug: false
pull-image-on-create: false
disable-pull-on-run: false
EOF
    
    chmod 644 /etc/crictl.yaml
    info "✓ Crictl configuration regenerated"
}

# Function to ensure filesystem capacity detection
ensure_filesystem_capacity() {
    info "Ensuring filesystem capacity detection..."
    
    # Check underlying filesystem
    local fs_info=$(df -h /var/lib/containerd 2>/dev/null | tail -1)
    info "Underlying filesystem: $fs_info"
    
    # Force filesystem operations to ensure proper capacity detection
    info "Performing filesystem operations to ensure capacity detection..."
    
    # Create test files to force filesystem stat operations
    touch /var/lib/containerd/.capacity-test
    echo "test" > /var/lib/containerd/.capacity-test
    sync
    rm -f /var/lib/containerd/.capacity-test
    
    # Run filesystem checks
    du -sh /var/lib/containerd >/dev/null 2>&1 || true
    find /var/lib/containerd -maxdepth 1 -type d >/dev/null 2>&1 || true
    
    # Verify the filesystem shows non-zero capacity
    local capacity=$(df -B1 /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")
    if [ "$capacity" = "0" ] || [ -z "$capacity" ]; then
        warn "Filesystem still shows zero capacity - attempting advanced fixes..."
        
        # Try remounting the filesystem (if it's a separate mount)
        if mount | grep -q "/var/lib/containerd"; then
            warn "Remounting /var/lib/containerd filesystem..."
            umount /var/lib/containerd 2>/dev/null || true
            sleep 2
            mount /var/lib/containerd 2>/dev/null || true
        fi
        
        # Force kernel to re-read filesystem statistics
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        sync
        
        # Check capacity again
        capacity=$(df -B1 /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")
    fi
    
    if [ "$capacity" != "0" ] && [ -n "$capacity" ]; then
        info "✓ Filesystem capacity detected: $capacity bytes"
        return 0
    else
        error "Filesystem capacity still shows as zero - manual intervention required"
        return 1
    fi
}

# Function to start and validate containerd
start_and_validate_containerd() {
    info "Starting and validating containerd..."
    
    # Reload systemd configuration
    systemctl daemon-reload
    
    # Start containerd
    systemctl start containerd
    
    # Wait for containerd to start
    sleep 10
    
    # Check if containerd is running
    if ! systemctl is-active containerd >/dev/null 2>&1; then
        error "containerd failed to start"
        systemctl status containerd --no-pager -l
        return 1
    fi
    
    info "✓ Containerd service started"
    
    # Wait for containerd socket to be available
    local retry_count=0
    local max_retries=10
    while [ $retry_count -lt $max_retries ]; do
        if [ -S /run/containerd/containerd.sock ]; then
            info "✓ Containerd socket available"
            break
        else
            retry_count=$((retry_count + 1))
            warn "Waiting for containerd socket... ($retry_count/$max_retries)"
            sleep 3
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "Containerd socket not available after $max_retries attempts"
        return 1
    fi
    
    # Test containerd connectivity
    retry_count=0
    max_retries=10
    while [ $retry_count -lt $max_retries ]; do
        if ctr version >/dev/null 2>&1; then
            info "✓ Containerd client connectivity working"
            break
        else
            retry_count=$((retry_count + 1))
            warn "Testing containerd connectivity... ($retry_count/$max_retries)"
            sleep 3
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "Containerd client connectivity failed after $max_retries attempts"
        return 1
    fi
    
    # Test crictl connectivity
    retry_count=0
    max_retries=10
    while [ $retry_count -lt $max_retries ]; do
        if crictl version >/dev/null 2>&1; then
            info "✓ Crictl connectivity working"
            break
        else
            retry_count=$((retry_count + 1))
            warn "Testing crictl connectivity... ($retry_count/$max_retries)"
            sleep 3
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "Crictl connectivity failed after $max_retries attempts"
        return 1
    fi
    
    info "✓ Containerd basic validation successful"
}

# Function to perform aggressive filesystem initialization
aggressive_filesystem_initialization() {
    info "Performing aggressive containerd image filesystem initialization..."
    
    # Initialize k8s.io namespace (critical for kubelet)
    info "Initializing k8s.io namespace..."
    ctr namespace create k8s.io 2>/dev/null || true
    
    # Force initial filesystem operations in all namespaces
    info "Forcing filesystem initialization in all namespaces..."
    for namespace in default k8s.io; do
        info "Initializing namespace: $namespace"
        
        # Force containerd to detect and initialize image filesystem for this namespace
        ctr --namespace "$namespace" version >/dev/null 2>&1 || true
        ctr --namespace "$namespace" images ls >/dev/null 2>&1 || true
        ctr --namespace "$namespace" snapshots ls >/dev/null 2>&1 || true
        
        # Wait between namespace operations
        sleep 2
    done
    
    # Force CRI to detect the image filesystem
    info "Forcing CRI image filesystem detection..."
    crictl info >/dev/null 2>&1 || true
    crictl images >/dev/null 2>&1 || true
    crictl ps -a >/dev/null 2>&1 || true
    
    # Extended wait for filesystem to stabilize
    info "Waiting for filesystem to stabilize..."
    sleep 15
    
    # Verify image filesystem is now detectable
    local retry_count=0
    local max_retries=10
    
    while [ $retry_count -lt $max_retries ]; do
        info "Verifying image filesystem detection... (attempt $((retry_count + 1))/$max_retries)"
        
        # Test both ctr and crictl to ensure both can see the filesystem
        local ctr_success=false
        local crictl_success=false
        
        if ctr --namespace k8s.io images ls >/dev/null 2>&1; then
            ctr_success=true
        fi
        
        if crictl info 2>/dev/null | grep -q "\"imageFilesystem\""; then
            # Check that imageFilesystem shows actual capacity
            local cri_capacity=$(crictl info 2>/dev/null | grep -A10 "imageFilesystem" | grep "capacityBytes" | head -1 | grep -oE '[0-9]+' || echo "0")
            if [ "$cri_capacity" != "0" ] && [ -n "$cri_capacity" ]; then
                crictl_success=true
                info "✓ CRI imageFilesystem detected with capacity: $cri_capacity bytes"
            fi
        fi
        
        if [ "$ctr_success" = "true" ] && [ "$crictl_success" = "true" ]; then
            info "✅ Image filesystem successfully initialized and detectable"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        
        if [ $retry_count -lt $max_retries ]; then
            warn "Image filesystem not fully initialized yet, retrying..."
            
            # Retry the initialization operations
            ctr namespace create k8s.io 2>/dev/null || true
            ctr --namespace k8s.io images ls >/dev/null 2>&1 || true
            ctr --namespace k8s.io snapshots ls >/dev/null 2>&1 || true
            crictl info >/dev/null 2>&1 || true
            
            # Force filesystem sync
            sync
            sleep 5
        fi
    done
    
    error "Failed to initialize image filesystem after $max_retries attempts"
    return 1
}

# Function to run comprehensive validation
comprehensive_validation() {
    info "Running comprehensive validation..."
    
    # Test 1: Service status
    if systemctl is-active containerd >/dev/null 2>&1; then
        info "✓ Containerd service is active"
    else
        error "✗ Containerd service is not active"
        return 1
    fi
    
    # Test 2: Socket connectivity
    if [ -S /run/containerd/containerd.sock ] && ctr version >/dev/null 2>&1; then
        info "✓ Containerd socket and client connectivity"
    else
        error "✗ Containerd socket or client connectivity failed"
        return 1
    fi
    
    # Test 3: CRI functionality
    if crictl version >/dev/null 2>&1; then
        info "✓ CRI (crictl) functionality"
    else
        error "✗ CRI (crictl) functionality failed"
        return 1
    fi
    
    # Test 4: Image filesystem detection
    if crictl info 2>/dev/null | grep -q "\"imageFilesystem\""; then
        local cri_capacity=$(crictl info 2>/dev/null | grep -A10 "imageFilesystem" | grep "capacityBytes" | head -1 | grep -oE '[0-9]+' || echo "0")
        if [ "$cri_capacity" != "0" ] && [ -n "$cri_capacity" ]; then
            info "✓ CRI imageFilesystem detected with capacity: $cri_capacity bytes"
        else
            error "✗ CRI imageFilesystem shows zero capacity"
            return 1
        fi
    else
        error "✗ CRI imageFilesystem not detected"
        return 1
    fi
    
    # Test 5: K8s namespace functionality
    if ctr --namespace k8s.io images ls >/dev/null 2>&1; then
        info "✓ K8s namespace functionality"
    else
        error "✗ K8s namespace functionality failed"
        return 1
    fi
    
    # Test 6: Filesystem capacity
    local fs_capacity=$(df -B1 /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")
    if [ "$fs_capacity" != "0" ] && [ -n "$fs_capacity" ]; then
        info "✓ Filesystem capacity: $fs_capacity bytes"
    else
        error "✗ Filesystem shows zero capacity"
        return 1
    fi
    
    info "✅ All validation tests passed!"
    return 0
}

# Function to show final status and next steps
show_final_status() {
    echo ""
    info "=== Final Status Summary ==="
    
    # Show containerd status
    echo ""
    info "Containerd Service Status:"
    systemctl status containerd --no-pager -l | head -10
    
    echo ""
    info "Containerd Version:"
    ctr version | head -5
    
    echo ""
    info "CRI Status:"
    crictl info | head -20
    
    echo ""
    info "Filesystem Information:"
    df -h /var/lib/containerd
    
    echo ""
    info "✅ Containerd filesystem fix completed successfully!"
    echo ""
    info "Next steps:"
    info "1. Retry the kubeadm join operation"
    info "2. Monitor kubelet logs during join: journalctl -u kubelet -f"
    info "3. Verify node joins cluster: kubectl get nodes"
    echo ""
    
    # Show backup location
    if [ -f /tmp/containerd-backup-location.txt ]; then
        local backup_location=$(cat /tmp/containerd-backup-location.txt)
        info "Configuration backup saved at: $backup_location"
    fi
}

# Main execution
main() {
    info "Starting comprehensive containerd filesystem fix..."
    echo ""
    
    # Step 1: Backup current configuration
    backup_configs
    echo ""
    
    # Step 2: Reset containerd completely
    reset_containerd
    echo ""
    
    # Step 3: Regenerate configurations
    regenerate_containerd_config
    regenerate_crictl_config
    echo ""
    
    # Step 4: Ensure filesystem capacity detection
    if ! ensure_filesystem_capacity; then
        error "Failed to ensure filesystem capacity detection"
        exit 1
    fi
    echo ""
    
    # Step 5: Start and validate containerd
    if ! start_and_validate_containerd; then
        error "Failed to start and validate containerd"
        exit 1
    fi
    echo ""
    
    # Step 6: Perform aggressive filesystem initialization
    if ! aggressive_filesystem_initialization; then
        error "Failed to perform aggressive filesystem initialization"
        exit 1
    fi
    echo ""
    
    # Step 7: Run comprehensive validation
    if ! comprehensive_validation; then
        error "Comprehensive validation failed"
        exit 1
    fi
    echo ""
    
    # Step 8: Show final status
    show_final_status
    
    echo ""
    info "🎉 Manual containerd filesystem fix completed successfully!"
    info "You can now retry the kubeadm join operation."
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
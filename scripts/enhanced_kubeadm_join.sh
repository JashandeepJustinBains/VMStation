#!/bin/bash

# VMStation Enhanced Kubeadm Join Process
# Comprehensive join process with prerequisite validation and robust error handling

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

# Configuration
MASTER_IP="${MASTER_IP:-192.168.4.63}"
JOIN_TIMEOUT="${JOIN_TIMEOUT:-90}"
MAX_RETRIES="${MAX_RETRIES:-2}"
LOG_FILE="/tmp/kubeadm-join-$(date +%Y%m%d-%H%M%S).log"

echo "=== VMStation Enhanced Kubeadm Join Process ==="
echo "Timestamp: $(date)"
echo "Master IP: $MASTER_IP"
echo "Join timeout: ${JOIN_TIMEOUT}s"
echo "Log file: $LOG_FILE"
echo ""

# Function to log both to console and file
log_both() {
    echo "$1" | tee -a "$LOG_FILE"
}

# Function to check if node is already joined
check_existing_join() {
    info "Checking existing join status..."
    
    if [ -f /etc/kubernetes/kubelet.conf ]; then
        if systemctl is-active kubelet >/dev/null 2>&1; then
            # Check if kubelet is actually connected to cluster
            if journalctl -u kubelet --no-pager -n 20 | grep -q "Started kubelet" && \
               ! journalctl -u kubelet --no-pager -n 20 | grep -q "standalone"; then
                info "✅ Node appears to already be successfully joined to cluster"
                info "Kubelet is running in cluster mode"
                return 0
            else
                warn "Node has kubelet.conf but kubelet is in standalone mode"
                warn "Will attempt to rejoin"
                return 1
            fi
        else
            warn "Node has kubelet.conf but kubelet is not running"
            return 1
        fi
    else
        info "No existing join detected"
        return 1
    fi
}

# Function to run prerequisite validation
validate_prerequisites() {
    info "Running comprehensive prerequisite validation..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local validator="$script_dir/validate_join_prerequisites.sh"
    
    if [ -f "$validator" ]; then
        if bash "$validator" "$MASTER_IP" | tee -a "$LOG_FILE"; then
            info "✅ All prerequisites validated successfully"
            return 0
        else
            error "❌ Prerequisites validation failed"
            return 1
        fi
    else
        warn "Prerequisite validator not found at $validator"
        warn "Proceeding with basic checks..."
        
        # Basic fallback checks
        if ! systemctl is-active containerd >/dev/null 2>&1; then
            error "containerd is not running"
            return 1
        fi
        
        if ! command -v kubeadm >/dev/null 2>&1; then
            error "kubeadm not found"
            return 1
        fi
        
        info "✓ Basic prerequisites OK"
        return 0
    fi
}

# Function to fix containerd filesystem issues
fix_containerd_filesystem() {
    info "Fixing containerd filesystem issues..."
    
    # Check if containerd directory exists and has proper permissions
    if [ ! -d "/var/lib/containerd" ]; then
        info "Creating missing containerd directory..."
        mkdir -p /var/lib/containerd
        chown root:root /var/lib/containerd
        chmod 755 /var/lib/containerd
    fi
    
    # Check for filesystem capacity issues that cause "invalid capacity 0"
    local containerd_capacity
    containerd_capacity=$(df -BG /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $2}' | sed 's/G//' || echo "0")
    
    if [ "$containerd_capacity" = "0" ] || [ -z "$containerd_capacity" ]; then
        warn "Containerd filesystem shows 0 capacity - fixing..."
        
        # Stop containerd for filesystem repair
        systemctl stop containerd 2>/dev/null || true
        sleep 3
        
        # Clear potentially corrupted containerd state that causes capacity issues
        rm -rf /var/lib/containerd/io.containerd.* 2>/dev/null || true
        
        # Recreate containerd directory structure
        mkdir -p /var/lib/containerd/{content,metadata,runtime,snapshots}
        chown -R root:root /var/lib/containerd
        chmod -R 755 /var/lib/containerd
        
        info "✓ Containerd filesystem repaired"
    else
        info "✓ Containerd filesystem capacity: ${containerd_capacity}G"
    fi
    
    # Restart containerd to ensure clean state and proper image filesystem detection
    info "Restarting containerd for clean image filesystem initialization..."
    systemctl restart containerd
    
    # Wait for containerd to be ready - increased wait time for proper initialization
    sleep 15
    
    # Verify containerd is working with retry logic
    local retry_count=0
    local max_retries=3
    while [ $retry_count -lt $max_retries ]; do
        if ctr version >/dev/null 2>&1; then
            break
        else
            warn "containerd not ready yet, waiting... ($((retry_count + 1))/$max_retries)"
            sleep 5
            ((retry_count++))
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "containerd is not responding after restart"
        return 1
    fi
    
    # Force containerd to initialize its image filesystem properly
    info "Initializing containerd image filesystem..."
    
    # Initialize the k8s.io namespace (used by kubelet)
    ctr namespace create k8s.io 2>/dev/null || true
    
    # Force containerd to detect and initialize image filesystem capacity
    # This prevents the "invalid capacity 0 on image filesystem" error
    ctr --namespace k8s.io images ls >/dev/null 2>&1 || true
    
    # Verify filesystem capacity is detectable before proceeding
    local initial_capacity=$(df -B1 /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")
    if [ "$initial_capacity" = "0" ]; then
        warn "Filesystem capacity detection issue - attempting to resolve..."
        # Force filesystem stat refresh
        find /var/lib/containerd -maxdepth 1 -type d >/dev/null 2>&1 || true
        du -sb /var/lib/containerd >/dev/null 2>&1 || true
        sync
        sleep 2
    fi
    
    # Additional step to ensure snapshotter is properly initialized after repointing
    # This is critical when containerd has been moved to a new filesystem location
    info "Ensuring snapshotter initialization for repointed containerd..."
    ctr --namespace k8s.io snapshots ls >/dev/null 2>&1 || true
    
    # Force CRI runtime status check to initialize image_filesystem detection
    # This ensures the CRI status shows image_filesystem after repointing operations
    info "Triggering CRI image_filesystem detection..."
    crictl info >/dev/null 2>&1 || true
    
    # Wait for containerd image filesystem to fully initialize
    sleep 5
    
    # Verify containerd image filesystem is properly initialized
    local retry_count=0
    local max_retries=5
    while [ $retry_count -lt $max_retries ]; do
        # Test both ctr command and CRI status to ensure image_filesystem is detected
        if ctr --namespace k8s.io images ls >/dev/null 2>&1 && crictl info 2>/dev/null | grep -q "image"; then
            
            # Enhanced validation: Check that CRI shows actual imageFilesystem with capacity
            if crictl info 2>/dev/null | grep -q "\"imageFilesystem\""; then
                # Further validate that filesystem shows non-zero capacity
                local cri_capacity=$(crictl info 2>/dev/null | grep -A10 "imageFilesystem" | grep "capacityBytes" | head -1 | grep -oE '[0-9]+' || echo "0")
                local fs_capacity=$(df -B1 /var/lib/containerd 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")
                
                if [ "$cri_capacity" != "0" ] && [ "$fs_capacity" != "0" ]; then
                    info "✓ Containerd image filesystem initialized successfully"
                    info "✓ CRI status shows image_filesystem with capacity: ${cri_capacity} bytes"
                    info "✓ Filesystem capacity verified: ${fs_capacity} bytes"
                    break
                else
                    warn "CRI shows imageFilesystem but capacity is zero (CRI: $cri_capacity, FS: $fs_capacity)"
                    # Continue retrying as this indicates incomplete initialization
                fi
            else
                warn "CRI status doesn't show imageFilesystem section yet"
                # Continue retrying
            fi
        fi
        
        warn "Containerd image filesystem not ready, retrying... ($((retry_count + 1))/$max_retries)"
        # Retry the initialization commands with enhanced filesystem verification
        ctr namespace create k8s.io 2>/dev/null || true
        
        # Force filesystem capacity detection by creating and removing a test image namespace
        ctr --namespace k8s.io images ls >/dev/null 2>&1 || true
        
        # Ensure snapshotter detects the filesystem
        ctr --namespace k8s.io snapshots ls >/dev/null 2>&1 || true
        
        # Force CRI to re-detect filesystem capacity
        crictl info >/dev/null 2>&1 || true
        
        # Additional aggressive measures for stubborn cases
        if [ $retry_count -ge 2 ]; then
            warn "Trying more aggressive initialization measures..."
            
            # Force filesystem stat operations
            find /var/lib/containerd -maxdepth 2 -type d >/dev/null 2>&1 || true
            du -sb /var/lib/containerd >/dev/null 2>&1 || true
            
            # Try additional CRI operations
            crictl images >/dev/null 2>&1 || true
            crictl ps -a >/dev/null 2>&1 || true
            
            # Sync filesystem
            sync
        fi
        
        # Additional filesystem verification to ensure proper capacity detection
        df -h /var/lib/containerd >/dev/null 2>&1 || true
        
        sleep 3
        ((retry_count++))
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "Failed to initialize containerd image filesystem after $max_retries attempts"
        error "This indicates a persistent containerd configuration or filesystem issue"
        
        # Provide diagnostic information
        local fs_capacity=$(df -h /var/lib/containerd 2>/dev/null | tail -1 || echo "N/A")
        local cri_output=$(crictl info 2>/dev/null | grep -A10 "imageFilesystem" || echo "No imageFilesystem section found")
        
        error "Diagnostic info:"
        error "  Filesystem: $fs_capacity"
        error "  CRI imageFilesystem: $cri_output"
        
        echo ""
        error "🔧 MANUAL FIX REQUIRED:"
        error "The automated containerd filesystem initialization has failed."
        error "Please run the manual fix script to resolve this issue:"
        error ""
        
        # Determine the correct path to the manual fix script
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local manual_fix_script="$script_dir/manual_containerd_filesystem_fix.sh"
        
        if [ -f "$manual_fix_script" ]; then
            error "   sudo $manual_fix_script"
        else
            error "   sudo ./scripts/manual_containerd_filesystem_fix.sh"
            error "   (Note: Run from the VMStation repository root directory)"
        fi
        error ""
        error "This script will:"
        error "  • Completely reset containerd configuration"
        error "  • Regenerate containerd and crictl configs"
        error "  • Perform aggressive filesystem initialization"
        error "  • Verify imageFilesystem detection"
        error ""
        error "After running the manual fix, retry the join operation."
        
        return 1
    fi
    
    return 0
}

# Function to prepare system for join
prepare_for_join() {
    info "Preparing system for join..."
    
    # Stop kubelet if running
    info "Stopping kubelet service..."
    systemctl stop kubelet 2>/dev/null || true
    
    # Wait for kubelet to stop
    sleep 5
    
    # Clear any existing kubelet state
    info "Cleaning existing kubelet state..."
    rm -f /var/lib/kubelet/config.yaml 2>/dev/null || true
    rm -f /var/lib/kubelet/kubeadm-flags.env 2>/dev/null || true
    rm -f /etc/kubernetes/bootstrap-kubelet.conf 2>/dev/null || true
    
    # Ensure kubelet service is enabled
    systemctl enable kubelet
    
    # Fix containerd filesystem issues before restart
    info "Checking containerd filesystem health..."
    if ! fix_containerd_filesystem; then
        error "Failed to fix containerd filesystem issues"
        return 1
    fi
    
    # Ensure CNI configuration directory exists for network readiness
    info "Preparing CNI network configuration..."
    mkdir -p /etc/cni/net.d
    mkdir -p /opt/cni/bin
    
    # Set proper CNI directory permissions
    chmod 755 /etc/cni/net.d
    chmod 755 /opt/cni/bin
    
    # Ensure kubelet has proper cgroup configuration to prevent TLS Bootstrap delays
    info "Configuring kubelet for faster TLS Bootstrap..."
    
    # Create kubelet directory if missing
    mkdir -p /var/lib/kubelet
    
    # Ensure proper permissions for kubelet directories
    chown -R root:root /var/lib/kubelet
    chmod 755 /var/lib/kubelet
    
    # Clear any stale kubelet PID files that could block startup
    rm -f /var/run/kubelet.pid 2>/dev/null || true
    
    # Verify system is ready for kubelet to start properly
    if ! systemctl is-enabled kubelet >/dev/null 2>&1; then
        error "kubelet service is not enabled"
        return 1
    fi
    
    info "✓ System prepared for join"
}

# Function to monitor kubelet during join
monitor_kubelet_join() {
    local timeout=${1:-90}  # Increased default timeout to account for containerd restarts
    info "Monitoring kubelet join process (timeout: ${timeout}s)..."
    
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    local last_check=0
    local containerd_fix_attempted=false  # Flag to prevent repeated containerd fixes
    
    while [ $(date +%s) -lt $end_time ]; do
        # Check if kubelet.conf was created (indicates successful bootstrap)
        if [ -f /etc/kubernetes/kubelet.conf ]; then
            info "✓ kubelet.conf created - TLS Bootstrap successful"
            
            # Wait a bit for kubelet to fully start
            sleep 5
            
            # Check if kubelet is running properly
            if systemctl is-active kubelet >/dev/null 2>&1; then
                if ! journalctl -u kubelet --no-pager --since "2 minutes ago" | grep -q "standalone"; then
                    info "✅ kubelet successfully joined cluster!"
                    return 0
                else
                    warn "kubelet started but still in standalone mode"
                fi
            fi
        fi
        
        # Every 20 seconds, check for specific failure patterns for faster detection
        local current_time=$(date +%s)
        if [ $((current_time - last_check)) -ge 20 ]; then
            last_check=$current_time
            
            # Check for TLS Bootstrap timeout (kubeadm's 40s internal timeout)
            if journalctl -u kubelet --no-pager --since "1 minute ago" | grep -q "timed out waiting for the condition"; then
                error "Detected kubeadm TLS Bootstrap timeout (40s limit exceeded)"
                error "This indicates kubelet cannot complete TLS Bootstrap to API server"
                return 1
            fi
            
            # Check for containerd capacity issues and attempt to fix them (only once per join attempt)
            if [ "$containerd_fix_attempted" = "false" ] && journalctl -u kubelet --no-pager --since "1 minute ago" | grep -q "invalid capacity 0 on image filesystem"; then
                warn "Detected containerd filesystem capacity issue during join"
                warn "Kubelet logs show 'invalid capacity 0 on image filesystem'"
                warn "This indicates containerd image filesystem was not properly initialized"
                warn "Attempting to fix containerd image filesystem during join..."
                
                containerd_fix_attempted=true  # Set flag to prevent repeated attempts
                
                # Attempt real-time fix of containerd filesystem
                if fix_containerd_filesystem; then
                    info "✓ Containerd filesystem fixed during join - continuing monitoring"
                    # Extend timeout to account for containerd restart time
                    end_time=$((end_time + 30))
                    info "Extended monitoring timeout by 30s to account for containerd restart"
                    # Reset last_check to avoid immediate re-detection
                    last_check=$current_time
                    continue
                else
                    error "❌ Failed to fix containerd filesystem during join"
                    error "This indicates a persistent containerd configuration issue"
                    error "The enhanced validation detected that containerd filesystem capacity"
                    error "is still not properly initialized after attempted fixes"
                    return 1
                fi
            fi
            
            # Check for API server connectivity issues
            if journalctl -u kubelet --no-pager --since "1 minute ago" | grep -q "connection refused\|network is unreachable"; then
                error "Detected API server connectivity issue"
                return 1
            fi
            
            info "TLS Bootstrap in progress... ($((current_time - start_time))s elapsed)"
        fi
        
        sleep 3
    done
    
    error "Kubelet join monitoring timed out after ${timeout}s"
    error "This suggests the root cause was not fixed - check kubelet logs"
    return 1
}

# Function to perform the actual join
perform_join() {
    local join_command="$1"
    local attempt="$2"
    
    info "Performing kubeadm join (attempt $attempt)..."
    log_both "Join command: $join_command"
    
    # Start monitoring in background
    monitor_kubelet_join $JOIN_TIMEOUT &
    local monitor_pid=$!
    
    # Execute join command with enhanced parameters - increased timeout for containerd restarts
    local enhanced_command="timeout $((JOIN_TIMEOUT + 60)) $join_command --v=5"
    log_both "Enhanced command: $enhanced_command"
    
    # Execute join using bash -c to properly handle the command string
    if bash -c "$enhanced_command" 2>&1 | tee -a "$LOG_FILE"; then
        # Wait for monitor to complete with timeout to prevent hanging
        local wait_timeout=30
        info "Waiting up to ${wait_timeout}s for kubelet monitoring to complete..."
        
        # Poll for monitor process completion instead of using problematic wait
        local start_time=$(date +%s)
        local end_time=$((start_time + wait_timeout))
        local monitor_result=1
        
        while [ $(date +%s) -lt $end_time ]; do
            # Check if monitor process is still running
            if ! kill -0 $monitor_pid 2>/dev/null; then
                # Process has finished, get its exit status by waiting
                wait $monitor_pid 2>/dev/null
                monitor_result=$?
                break
            fi
            sleep 1
        done
        
        # If we exited the loop because of timeout, kill the monitor process
        if kill -0 $monitor_pid 2>/dev/null; then
            warn "Kubelet monitoring timed out after ${wait_timeout}s - cleaning up monitor process"
            kill $monitor_pid 2>/dev/null || true
            # Wait briefly for process to be killed
            sleep 2
            # Force kill if still running
            kill -9 $monitor_pid 2>/dev/null || true
            warn "kubeadm join command succeeded but monitoring didn't complete in time"
            return 1
        fi
        
        # Check monitor result
        if [ $monitor_result -eq 0 ]; then
            info "✅ kubeadm join completed successfully!"
            return 0
        else
            warn "kubeadm join command succeeded but kubelet monitoring failed"
            return 1
        fi
    else
        local join_result=$?
        
        # Kill monitoring process immediately on join failure
        if kill -0 $monitor_pid 2>/dev/null; then
            kill $monitor_pid 2>/dev/null || true
            # Wait briefly for process to be killed
            sleep 2
            # Force kill if still running
            kill -9 $monitor_pid 2>/dev/null || true
        fi
        
        error "kubeadm join command failed with exit code: $join_result"
        return $join_result
    fi
}

# Function to validate successful join
validate_join_success() {
    info "Validating join success..."
    
    # Check if kubelet.conf exists
    if [ ! -f /etc/kubernetes/kubelet.conf ]; then
        error "kubelet.conf not found - join failed"
        return 1
    fi
    
    # Check if kubelet service is active
    if ! systemctl is-active kubelet >/dev/null 2>&1; then
        error "kubelet service is not active"
        return 1
    fi
    
    # Check kubelet logs for standalone mode
    if journalctl -u kubelet --no-pager --since "5 minutes ago" | grep -q "standalone"; then
        error "kubelet is still in standalone mode"
        return 1
    fi
    
    # Check kubelet logs for successful cluster connection
    if journalctl -u kubelet --no-pager --since "5 minutes ago" | grep -q "Started kubelet"; then
        if ! journalctl -u kubelet --no-pager --since "5 minutes ago" | grep -q "No API server defined"; then
            info "✅ kubelet successfully connected to cluster"
            return 0
        fi
    fi
    
    warn "kubelet status is unclear - may need verification from master node"
    return 1
}

# Function to perform aggressive cleanup for naughty nodes
aggressive_node_reset() {
    info "🔧 Performing aggressive node reset for stubborn naughty nodes..."
    info "This will completely reset kubectl, containerd, CNI, flannel, etc."
    info "Preserving /srv/media and /mnt/media directories as requested"
    
    # Stop all Kubernetes and container services first
    info "Stopping Kubernetes and container services..."
    systemctl stop kubelet 2>/dev/null || true
    systemctl stop containerd 2>/dev/null || true
    systemctl stop docker 2>/dev/null || true
    
    # Force kill any remaining Kubernetes processes
    info "Force killing any remaining Kubernetes processes..."
    pkill -f "kube-apiserver" 2>/dev/null || true
    pkill -f "kube-controller-manager" 2>/dev/null || true
    pkill -f "kube-scheduler" 2>/dev/null || true
    pkill -f "etcd" 2>/dev/null || true
    pkill -f "kubelet" 2>/dev/null || true
    pkill -f "flannel" 2>/dev/null || true
    
    # Clean up CNI network interfaces (especially flannel.1 which causes issues)
    info "Cleaning up CNI and Flannel network interfaces..."
    ip link set cni0 down 2>/dev/null || true
    ip link delete cni0 2>/dev/null || true
    ip link set cbr0 down 2>/dev/null || true  
    ip link delete cbr0 2>/dev/null || true
    ip link set flannel.1 down 2>/dev/null || true
    ip link delete flannel.1 2>/dev/null || true
    
    # Remove any vxlan interfaces that might be leftover
    for iface in $(ip link show 2>/dev/null | grep vxlan | cut -d: -f2 | tr -d ' ' || true); do
        if [ -n "$iface" ]; then
            info "Removing vxlan interface: $iface"
            ip link set "$iface" down 2>/dev/null || true
            ip link delete "$iface" 2>/dev/null || true
        fi
    done
    
    # Clean up iptables rules related to Kubernetes and CNI
    info "Cleaning up iptables rules..."
    iptables -t nat -F KUBE-SERVICES 2>/dev/null || true
    iptables -t nat -X KUBE-SERVICES 2>/dev/null || true
    iptables -t nat -F KUBE-NODEPORTS 2>/dev/null || true
    iptables -t nat -X KUBE-NODEPORTS 2>/dev/null || true
    iptables -t nat -F KUBE-POSTROUTING 2>/dev/null || true
    iptables -t nat -X KUBE-POSTROUTING 2>/dev/null || true
    iptables -t filter -F KUBE-FORWARD 2>/dev/null || true
    iptables -t filter -X KUBE-FORWARD 2>/dev/null || true
    iptables -t filter -F KUBE-FIREWALL 2>/dev/null || true
    iptables -t filter -X KUBE-FIREWALL 2>/dev/null || true
    
    # Clean up FLANNEL iptables chains
    iptables -t nat -F FLANNEL 2>/dev/null || true
    iptables -t nat -X FLANNEL 2>/dev/null || true
    iptables -t filter -F FLANNEL 2>/dev/null || true
    iptables -t filter -X FLANNEL 2>/dev/null || true
    
    # Reset kubeadm state completely
    info "Resetting kubeadm state..."
    kubeadm reset --force 2>/dev/null || true
    
    # Completely remove Kubernetes configurations and state
    info "Removing Kubernetes configurations and state..."
    rm -rf /etc/kubernetes/* 2>/dev/null || true
    rm -rf /var/lib/kubelet/* 2>/dev/null || true
    rm -rf /var/lib/etcd/* 2>/dev/null || true
    
    # Completely remove and recreate CNI configuration
    info "Completely resetting CNI configuration..."
    rm -rf /etc/cni/net.d/* 2>/dev/null || true
    rm -rf /var/lib/cni/* 2>/dev/null || true
    rm -rf /run/flannel/* 2>/dev/null || true
    
    # Recreate essential CNI directories with proper permissions
    mkdir -p /etc/cni/net.d
    mkdir -p /opt/cni/bin
    mkdir -p /var/lib/cni/networks
    mkdir -p /run/flannel
    chmod 755 /etc/cni/net.d
    chmod 755 /opt/cni/bin
    chmod 755 /var/lib/cni/networks
    chmod 755 /run/flannel
    
    # Completely reset containerd state and configuration
    info "Completely resetting containerd..."
    systemctl stop containerd 2>/dev/null || true
    
    # Remove containerd configuration and regenerate it
    rm -f /etc/containerd/config.toml 2>/dev/null || true
    
    # Completely remove containerd state (this is the key for fixing filesystem issues)
    rm -rf /var/lib/containerd/* 2>/dev/null || true
    rm -rf /run/containerd/* 2>/dev/null || true
    
    # Recreate containerd directory structure with proper permissions
    mkdir -p /var/lib/containerd/{content,metadata,runtime,snapshots}
    mkdir -p /run/containerd
    chown -R root:root /var/lib/containerd
    chmod -R 755 /var/lib/containerd
    chown -R root:root /run/containerd
    chmod 755 /run/containerd
    
    # Regenerate containerd configuration
    info "Regenerating containerd configuration..."
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    
    # Configure containerd cgroup driver to match kubelet
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # Clean up systemd state
    info "Resetting systemd state..."
    systemctl daemon-reload
    systemctl reset-failed kubelet 2>/dev/null || true
    systemctl reset-failed containerd 2>/dev/null || true
    systemctl reset-failed docker 2>/dev/null || true
    
    # Remove systemd drop-in directories that might cause conflicts
    rm -rf /etc/systemd/system/kubelet.service.d/* 2>/dev/null || true
    rm -rf /etc/systemd/system/containerd.service.d/* 2>/dev/null || true
    
    # Clean up any leftover container state
    info "Cleaning up container state..."
    rm -rf /var/lib/containers/storage/overlay* 2>/dev/null || true
    rm -rf /var/lib/containers/storage/vfs* 2>/dev/null || true
    
    # Unmount any overlay filesystems that might be stuck
    mount | grep overlay | awk '{print $3}' | xargs -r umount -l 2>/dev/null || true
    
    # Clean up IP routes that might interfere with new cluster join
    info "Cleaning up IP routes..."
    ip route del 10.244.0.0/16 2>/dev/null || true
    ip route show | grep -E "(cni0|cbr0|flannel)" | while read route; do
        ip route del $route 2>/dev/null || true
    done
    
    # Clean up kubectl configuration
    info "Cleaning up kubectl configuration..."
    rm -rf /root/.kube/* 2>/dev/null || true
    
    # Clean up temporary files related to Kubernetes
    info "Cleaning up temporary files..."
    rm -rf /tmp/kubeadm-* 2>/dev/null || true
    rm -rf /tmp/k8s-* 2>/dev/null || true
    rm -rf /tmp/kube-* 2>/dev/null || true
    rm -rf /tmp/flannel-* 2>/dev/null || true
    
    # Re-enable and restart services in clean state
    info "Restarting services in clean state..."
    systemctl enable containerd
    systemctl start containerd
    
    # Wait for containerd to start and verify it's working
    sleep 15
    local retry_count=0
    local max_retries=5
    while [ $retry_count -lt $max_retries ]; do
        if ctr version >/dev/null 2>&1; then
            info "✓ containerd restarted successfully"
            break
        else
            warn "containerd not ready yet, waiting... ($((retry_count + 1))/$max_retries)"
            sleep 5
            ((retry_count++))
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "containerd failed to start after aggressive reset"
        return 1
    fi
    
    # Enable kubelet (but don't start it yet - kubeadm join will handle that)
    systemctl enable kubelet
    
    info "✅ Aggressive node reset completed successfully"
    info "Node has been completely reset and is ready for kubeadm join"
    
    return 0
}

# Function to clean up after failed join (now uses aggressive reset for stubborn nodes)
cleanup_failed_join() {
    info "Cleaning up after failed join..."
    
    # For the first retry, try gentle cleanup
    if [ "${attempt:-1}" -eq 1 ]; then
        info "Attempting gentle cleanup first..."
        
        # Reset kubeadm state
        kubeadm reset --force 2>/dev/null || true
        
        # Clean up directories
        rm -rf /etc/kubernetes/* 2>/dev/null || true
        rm -rf /var/lib/kubelet/* 2>/dev/null || true
        rm -rf /etc/cni/net.d/* 2>/dev/null || true
        
        # Reset systemd
        systemctl daemon-reload
        systemctl reset-failed kubelet 2>/dev/null || true
        
        # Restart containerd
        systemctl restart containerd
        sleep 10
        
        info "✓ Gentle cleanup completed"
    else
        # For subsequent retries, use aggressive reset for naughty nodes
        warn "Previous gentle cleanup failed - using aggressive reset for naughty node"
        if ! aggressive_node_reset; then
            error "Aggressive node reset failed"
            return 1
        fi
    fi
    
    return 0
}

# Main join process
main() {
    # Handle join command passed as single quoted argument or multiple arguments
    if [ $# -eq 1 ] && [[ "$1" == kubeadm* ]]; then
        # Single argument containing the full command
        local join_command="$1"
    else
        # Multiple arguments - concatenate them
        local join_command="$*"
    fi
    
    if [ -z "$join_command" ]; then
        error "Usage: $0 <kubeadm-join-command>"
        error "Example: $0 kubeadm join 192.168.4.63:6443 --token abc.123 --discovery-token-ca-cert-hash sha256:xyz"
        exit 1
    fi
    
    log_both "=== Enhanced Kubeadm Join Process Started ==="
    log_both "Command: $join_command"
    log_both "Timestamp: $(date)"
    
    # Check if already joined
    if check_existing_join; then
        info "✅ Node already successfully joined - nothing to do"
        exit 0
    fi
    
    # Validate prerequisites
    if ! validate_prerequisites; then
        error "Prerequisites validation failed - cannot proceed with join"
        exit 1
    fi
    
    # Attempt join with retries
    local attempt=1
    while [ $attempt -le $MAX_RETRIES ]; do
        info "=== Join Attempt $attempt/$MAX_RETRIES ==="
        
        # Prepare system
        if ! prepare_for_join; then
            error "Failed to prepare system for join"
            exit 1
        fi
        
        # Perform join
        if perform_join "$join_command" $attempt; then
            # Validate success
            if validate_join_success; then
                info "🎉 Join completed successfully!"
                log_both "Join successful at $(date)"
                
                # Show final status
                echo ""
                info "Final kubelet status:"
                systemctl status kubelet --no-pager -l | head -10
                
                exit 0
            else
                warn "Join command succeeded but validation failed"
            fi
        else
            warn "Join attempt $attempt failed"
        fi
        
        # Clean up for retry
        if [ $attempt -lt $MAX_RETRIES ]; then
            warn "Cleaning up for retry..."
            # Pass attempt number to cleanup function so it knows when to be aggressive
            if ! cleanup_failed_join; then
                error "Cleanup failed - cannot retry"
                break
            fi
            
            # Shorter wait before retry for faster failure detection
            local wait_time=15
            info "Waiting ${wait_time}s before retry..."
            sleep $wait_time
        fi
        
        ((attempt++))
    done
    
    error "❌ All join attempts failed after $MAX_RETRIES tries"
    log_both "All join attempts failed at $(date)"
    
    # Show diagnostic information
    echo ""
    error "Diagnostic information:"
    error "1. Check log file: $LOG_FILE"
    error "2. Check kubelet status: systemctl status kubelet"
    error "3. Check kubelet logs: journalctl -u kubelet -f"
    error "4. Check containerd status: systemctl status containerd"
    error "5. Verify master node connectivity: curl -k https://$MASTER_IP:6443/healthz"
    
    echo ""
    error "🔧 MANUAL REMEDIATION OPTIONS:"
    echo ""
    error "If the issue is related to containerd filesystem initialization:"
    # Determine the correct path to the manual fix script
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local manual_fix_script="$script_dir/manual_containerd_filesystem_fix.sh"
    
    if [ -f "$manual_fix_script" ]; then
        error "   sudo $manual_fix_script"
    else
        error "   sudo ./scripts/manual_containerd_filesystem_fix.sh"
        error "   (Note: Run from the VMStation repository root directory)"
    fi
    echo ""
    error "For general worker node remediation:"
    error "   sudo ./worker_node_join_remediation.sh"
    echo ""
    error "For quick diagnostics:"
    error "   sudo ./scripts/quick_join_diagnostics.sh"
    echo ""
    error "After running manual fixes, retry the join operation with:"
    error "   sudo ./scripts/enhanced_kubeadm_join.sh \"<your-join-command>\""
    
    exit 1
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
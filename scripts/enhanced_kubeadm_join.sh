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
            info "✓ Containerd image filesystem initialized successfully"
            
            # Additional validation for repointing scenarios - ensure CRI shows image_filesystem
            if crictl info 2>/dev/null | grep -q "\"imageFilesystem\""; then
                info "✓ CRI status shows image_filesystem - repointing successful"
            else
                warn "CRI status doesn't show image_filesystem yet, but basic functionality works"
            fi
            break
        else
            warn "Containerd image filesystem not ready, retrying... ($((retry_count + 1))/$max_retries)"
            # Retry the initialization commands
            ctr namespace create k8s.io 2>/dev/null || true
            ctr --namespace k8s.io images ls >/dev/null 2>&1 || true
            ctr --namespace k8s.io snapshots ls >/dev/null 2>&1 || true
            crictl info >/dev/null 2>&1 || true
            sleep 3
            ((retry_count++))
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "Failed to initialize containerd image filesystem after $max_retries attempts"
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

# Function to clean up after failed join
cleanup_failed_join() {
    info "Cleaning up after failed join..."
    
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
    
    info "✓ Cleanup completed"
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
            cleanup_failed_join
            
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
    
    exit 1
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
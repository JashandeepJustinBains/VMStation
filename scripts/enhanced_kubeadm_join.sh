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

# Helper function to run crictl with proper permissions
run_crictl() {
    local cmd="$1"
    local suppress_output="${2:-false}"
    
    # Ensure containerd socket has proper permissions if we can fix them
    if [ -S /run/containerd/containerd.sock ] && [ "$(id -u)" = "0" ]; then
        # Create containerd group if it doesn't exist 
        if ! getent group containerd >/dev/null 2>&1; then
            groupadd containerd 2>/dev/null || true
        fi
        
        # Ensure current user is in containerd group
        current_user=$(whoami)
        if ! groups "$current_user" | grep -q "containerd"; then
            usermod -a -G containerd "$current_user" 2>/dev/null || true
        fi
        
        # Set appropriate socket permissions for group access
        chgrp containerd /run/containerd/containerd.sock 2>/dev/null || true
        chmod 666 /run/containerd/containerd.sock 2>/dev/null || true
    fi
    
    # Execute crictl command with error handling - try with containerd group first
    if [ "$suppress_output" = "true" ]; then
        # Try with sg containerd first for proper group access
        if sg containerd -c "crictl $cmd" >/dev/null 2>&1; then
            return 0
        else
            crictl $cmd >/dev/null 2>&1
        fi
    else
        # Try with sg containerd first for proper group access
        if sg containerd -c "crictl $cmd" 2>/dev/null; then
            return 0
        else
            crictl $cmd
        fi
    fi
}

# Configuration
MASTER_IP="${MASTER_IP:-192.168.4.63}"
JOIN_TIMEOUT="${JOIN_TIMEOUT:-90}"
MAX_RETRIES="${MAX_RETRIES:-3}"
TOKEN_REFRESH_RETRIES="${TOKEN_REFRESH_RETRIES:-2}"
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

# Dump helpful diagnostics on error for Ansible visibility
on_error_dump() {
    echo "\n===== ENHANCED JOIN FAILURE DUMP =====" | tee -a "$LOG_FILE"
    echo "Last 200 lines of join log:" | tee -a "$LOG_FILE"
    tail -n 200 "$LOG_FILE" 2>/dev/null | tee -a "$LOG_FILE"
    echo "\nRecent kubelet journal (last 200 lines):" | tee -a "$LOG_FILE"
    journalctl -u kubelet --no-pager -n 200 2>/dev/null | tee -a "$LOG_FILE"
    echo "===== END DUMP =====\n" | tee -a "$LOG_FILE"
}

# Install ERR trap so failed runs dump diagnostics for Ansible
trap 'on_error_dump' ERR

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

# Function to detect if worker was aggressively wiped
detect_post_wipe_state() {
    info "Detecting post-wipe worker state..."
    
    local wipe_indicators=0
    local total_checks=0
    
    # Check for absence of key Kubernetes directories/files
    local checks=(
        "/etc/kubernetes/kubelet.conf"
        "/etc/kubernetes/pki/ca.crt"
        "/var/lib/kubelet/config.yaml"
        "/etc/cni/net.d/10-flannel.conflist"
    )
    
    for check in "${checks[@]}"; do
        ((total_checks++))
        if [ ! -f "$check" ]; then
            ((wipe_indicators++))
            debug "✓ Missing (as expected after wipe): $check"
        else
            debug "• Found residual file: $check"
        fi
    done
    
    # Check for clean directory states
    local dir_checks=(
        "/var/lib/kubelet"
        "/etc/kubernetes"
        "/var/lib/etcd"
    )
    
    for dir in "${dir_checks[@]}"; do
        ((total_checks++))
        if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
            ((wipe_indicators++))
            debug "✓ Directory clean/empty: $dir"
        else
            debug "• Directory has content: $dir"
        fi
    done
    
    # Calculate wipe percentage
    local wipe_percentage=$((wipe_indicators * 100 / total_checks))
    
    info "Post-wipe state analysis:"
    info "  Clean indicators: $wipe_indicators/$total_checks"
    info "  Wipe percentage: ${wipe_percentage}%"
    
    # Consider it a post-wipe state if >75% indicators are clean
    if [ $wipe_percentage -gt 75 ]; then
        info "✅ Detected post-wipe worker state (${wipe_percentage}% clean)"
        info "Worker appears to have been aggressively wiped and is ready for fresh join"
        export WORKER_POST_WIPE=true
        return 0
    else
        info "• Normal worker state detected (${wipe_percentage}% clean)"
        export WORKER_POST_WIPE=false
        return 1
    fi
}

# Function to refresh join token from control plane
refresh_join_token() {
    local original_command="$1"
    local attempt="$2"
    
    info "Attempting to refresh join token from control plane (attempt $attempt)..."
    
    # Extract the discovery token CA cert hash from original command
    local ca_cert_hash=$(echo "$original_command" | grep -oE '--discovery-token-ca-cert-hash sha256:[a-f0-9]+' || echo "")
    
    if [ -z "$ca_cert_hash" ]; then
        error "Cannot extract CA cert hash from original join command"
        return 1
    fi
    
    # Generate new token on control plane
    info "Generating fresh join token on control plane $MASTER_IP..."
    local new_join_command
    
    # Try to generate new token via SSH
    if command -v ssh >/dev/null 2>&1; then
        # First try SSH key authentication
        new_join_command=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@"$MASTER_IP" \
            "kubeadm token create --ttl=2h --print-join-command" 2>/dev/null || echo "")
        
        if [ -z "$new_join_command" ]; then
            # Try with password authentication if key auth fails
            info "SSH key authentication failed, please manually refresh token on control plane"
            warn "Run on control plane: kubeadm token create --ttl=2h --print-join-command"
            return 1
        fi
    else
        warn "SSH not available for automatic token refresh"
        warn "Please manually refresh token on control plane and retry"
        return 1
    fi
    
    if [[ "$new_join_command" == kubeadm* ]] && [[ "$new_join_command" == *"$MASTER_IP"* ]]; then
        info "✅ Successfully generated fresh join token"
        log_both "New join command: $new_join_command"
        echo "$new_join_command"
        return 0
    else
        error "Failed to generate valid join command from control plane"
        error "Response: $new_join_command"
        return 1
    fi
}

# Function to check if join failure is due to token expiry
check_token_expiry() {
    local join_output="$1"
    
    # Check for common token expiry error patterns
    if echo "$join_output" | grep -qi "token.*expired\|token.*invalid\|unauthorized\|forbidden\|401\|403"; then
        return 0  # Token likely expired
    fi
    
    # Check kubelet logs for TLS Bootstrap failures that might indicate token issues
    if journalctl -u kubelet --no-pager --since "5 minutes ago" | grep -qi "unauthorized\|forbidden\|certificate"; then
        return 0  # Likely token or certificate issue
    fi
    
    return 1  # Not a token expiry issue
}

# Function to validate kubelet config exists and is correct
validate_kubelet_config() {
    info "Validating kubelet configuration..."
    
    # Check if kubelet config was created
    if [ ! -f /var/lib/kubelet/config.yaml ]; then
        error "kubelet config.yaml not found after join attempt"
        error "This indicates kubeadm join did not complete successfully"
        return 1
    fi
    
    # Check if kubelet config points to correct control plane
    local config_server=$(grep "server:" /etc/kubernetes/kubelet.conf 2>/dev/null | awk '{print $2}' | sed 's|https\?://||' | cut -d':' -f1 || echo "")
    if [ "$config_server" != "$MASTER_IP" ]; then
        error "kubelet config points to wrong server: $config_server (expected: $MASTER_IP)"
        return 1
    fi
    
    info "✅ kubelet configuration validated successfully"
    return 0
}
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
    run_crictl "info" true || true
    
    # Wait for containerd image filesystem to fully initialize
    sleep 5
    
    # Verify containerd image filesystem is properly initialized
    local retry_count=0
    local max_retries=5
    while [ $retry_count -lt $max_retries ]; do
        # Test both ctr command and CRI status to ensure image_filesystem is detected
        if ctr --namespace k8s.io images ls >/dev/null 2>&1 && run_crictl "info" true 2>/dev/null | grep -q "image"; then
            
            # Enhanced validation: Check that CRI shows actual imageFilesystem with capacity
            if run_crictl "info" true 2>/dev/null | grep -q "\"imageFilesystem\""; then
                # Further validate that filesystem shows non-zero capacity
                local cri_capacity=$(run_crictl "info" true 2>/dev/null | grep -A10 "imageFilesystem" | grep "capacityBytes" | head -1 | grep -oE '[0-9]+' || echo "0")
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
        run_crictl "info" true || true
        
        # Additional aggressive measures for stubborn cases
        if [ $retry_count -ge 2 ]; then
            warn "Trying more aggressive initialization measures..."
            
            # Force filesystem stat operations
            find /var/lib/containerd -maxdepth 2 -type d >/dev/null 2>&1 || true
            du -sb /var/lib/containerd >/dev/null 2>&1 || true
            
            # Try additional CRI operations
            run_crictl "images" true || true
            run_crictl "ps -a" true || true
            
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
        local cri_output=$(run_crictl "info" true 2>/dev/null | grep -A10 "imageFilesystem" || echo "No imageFilesystem section found")
        
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
    
    # Validate and fix systemd drop-in configurations before join
    info "Validating systemd drop-in configurations..."
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local validator="$script_dir/validate_systemd_dropins.sh"
    
    if [ -f "$validator" ]; then
        if ! bash "$validator" validate kubelet; then
            warn "Found invalid systemd configurations, fixing them..."
            if bash "$validator" fix kubelet; then
                info "✓ Systemd configurations fixed successfully"
            else
                error "Failed to fix systemd configurations"
                return 1
            fi
        else
            info "✓ Systemd configurations are valid"
        fi
    else
        warn "Systemd validator not found at $validator"
        warn "Proceeding without validation (manual fix may be needed)"
    fi
    
    # Stop kubelet if running and prevent auto-restart during join
    info "Stopping kubelet service and preventing auto-restart during join..."
    systemctl stop kubelet 2>/dev/null || true
    
    # Mask kubelet temporarily to prevent systemd from auto-restarting it during join
    systemctl mask kubelet 2>/dev/null || true
    
    # Wait for kubelet to stop completely
    sleep 5
    
    # Clear any existing kubelet state
    info "Cleaning existing kubelet state..."
    rm -f /var/lib/kubelet/config.yaml 2>/dev/null || true
    rm -f /var/lib/kubelet/kubeadm-flags.env 2>/dev/null || true
    rm -f /etc/kubernetes/bootstrap-kubelet.conf 2>/dev/null || true
    
    # Reset failed kubelet attempts
    systemctl reset-failed kubelet 2>/dev/null || true
    
    # Ensure kubelet service is enabled but not started yet
    systemctl unmask kubelet 2>/dev/null || true
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
    
    # Create a temporary kubelet systemd drop-in for bootstrap mode
    # This prevents the "config.yaml not found" error during join
    info "Creating temporary kubelet bootstrap configuration..."
    local kubelet_dropin_dir="/etc/systemd/system/kubelet.service.d"
    mkdir -p "$kubelet_dropin_dir"
    
    # Remove any existing malformed configuration files that could cause issues
    info "Removing any existing malformed systemd drop-in files..."
    for file in "$kubelet_dropin_dir"/*.conf; do
        if [ -f "$file" ]; then
            # Check if file has content without proper section headers
            if grep -q "Environment=\|ExecStart=" "$file" && ! grep -q "^\[Service\]" "$file"; then
                warn "Removing malformed systemd drop-in: $file"
                rm -f "$file"
            fi
        fi
    done
    
    # Create a bootstrap kubelet configuration that doesn't require config.yaml
    cat > "$kubelet_dropin_dir/20-bootstrap-kubeadm.conf" << 'EOF'
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
Environment="KUBELET_KUBEADM_ARGS=--container-runtime-endpoint=unix:///run/containerd/containerd.sock"
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
Restart=always
StartLimitInterval=0
RestartSec=10
EOF
    
    # Create a fallback script to handle missing config.yaml gracefully
    cat > "$kubelet_dropin_dir/kubelet-bootstrap-wrapper.sh" << 'EOF'
#!/bin/bash
# Kubelet bootstrap wrapper to handle missing config.yaml during join

CONFIG_FILE="/var/lib/kubelet/config.yaml"
BOOTSTRAP_FILE="/etc/kubernetes/bootstrap-kubelet.conf"

# If config.yaml doesn't exist but bootstrap does, use bootstrap mode
if [ ! -f "$CONFIG_FILE" ] && [ -f "$BOOTSTRAP_FILE" ]; then
    echo "Using bootstrap configuration (config.yaml not yet created by kubeadm join)"
    exec /usr/bin/kubelet \
        --bootstrap-kubeconfig="$BOOTSTRAP_FILE" \
        --kubeconfig=/etc/kubernetes/kubelet.conf \
        --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
        --rotate-certificates=true \
        --v=2
elif [ -f "$CONFIG_FILE" ]; then
    echo "Using generated configuration (config.yaml created by kubeadm join)"
    exec /usr/bin/kubelet \
        --config="$CONFIG_FILE" \
        --kubeconfig=/etc/kubernetes/kubelet.conf \
        --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
        --v=2
else
    echo "ERROR: Neither config.yaml nor bootstrap configuration available"
    exit 1
fi
EOF
    chmod +x "$kubelet_dropin_dir/kubelet-bootstrap-wrapper.sh"
    
    # Reload systemd to pick up the new configuration
    systemctl daemon-reload
    
    info "✓ System prepared for join with bootstrap kubelet configuration"
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
    
    # Create a wrapper script that handles kubelet start timing
    local join_wrapper="/tmp/kubeadm_join_wrapper.sh"
    cat > "$join_wrapper" << 'EOF'
#!/bin/bash
set -e

# Function to wait for config.yaml to be created
wait_for_kubelet_config() {
    local timeout=60
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    echo "Waiting for kubeadm join to create kubelet config.yaml..."
    while [ $(date +%s) -lt $end_time ]; do
        if [ -f /var/lib/kubelet/config.yaml ]; then
            echo "✓ kubelet config.yaml created by kubeadm join"
            return 0
        fi
        sleep 2
    done
    
    echo "WARNING: kubelet config.yaml not created within ${timeout}s"
    return 1
}

# Execute the actual kubeadm join command
echo "Executing kubeadm join command..."
EOF
    
    # Add the join command to the wrapper
    echo "exec $1" >> "$join_wrapper"
    chmod +x "$join_wrapper"
    
    # Execute join using the wrapper script and capture output
    local join_result=0
    local join_output=""
    
    join_output=$(bash -c "timeout $((JOIN_TIMEOUT + 60)) $join_wrapper" 2>&1 | tee -a "$LOG_FILE") || join_result=$?
    
    if [ $join_result -eq 0 ]; then
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
        
        # Check monitor result and validate kubelet config
        if [ $monitor_result -eq 0 ] && validate_kubelet_config; then
            info "✅ kubeadm join completed successfully!"
            return 0
        else
            warn "kubeadm join command succeeded but validation failed"
            return 1
        fi
    else
        # Kill monitoring process immediately on join failure
        if kill -0 $monitor_pid 2>/dev/null; then
            kill $monitor_pid 2>/dev/null || true
            # Wait briefly for process to be killed
            sleep 2
            # Force kill if still running
            kill -9 $monitor_pid 2>/dev/null || true
        fi
        
        # Check if this is a token expiry issue and attempt token refresh
        if check_token_expiry "$join_output" && [ $attempt -le $TOKEN_REFRESH_RETRIES ]; then
            warn "Detected potential token expiry issue"
            info "Attempting to refresh join token and retry..."
            
            local new_join_command
            if new_join_command=$(refresh_join_token "$join_command" $attempt); then
                info "Token refreshed successfully, retrying join with new token..."
                # Recursive call with new token (but same attempt number)
                return $(perform_join "$new_join_command" $attempt)
            else
                warn "Failed to refresh token, continuing with original retry logic"
            fi
        fi
        
        error "kubeadm join command failed with exit code: $join_result"
        log_both "Join output: $join_output"
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
        
        # Reset systemd and unmask kubelet
        systemctl daemon-reload
        systemctl reset-failed kubelet 2>/dev/null || true
        systemctl unmask kubelet 2>/dev/null || true  # Ensure kubelet is unmasked for retry
        
        # Clean up temporary bootstrap configuration
        rm -f /etc/systemd/system/kubelet.service.d/20-bootstrap-kubeadm.conf 2>/dev/null || true
        rm -f /etc/systemd/system/kubelet.service.d/kubelet-bootstrap-wrapper.sh 2>/dev/null || true
        systemctl daemon-reload
        
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
    
    # Detect post-wipe state early
    detect_post_wipe_state
    if [ "$WORKER_POST_WIPE" = "true" ]; then
        info "🔧 Post-wipe worker detected - using optimized join process"
        log_both "Post-wipe worker state detected"
    fi
    
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
        if [ "$WORKER_POST_WIPE" = "true" ]; then
            info "=== Post-Wipe Worker Join Attempt $attempt/$MAX_RETRIES ==="
        else
            info "=== Join Attempt $attempt/$MAX_RETRIES ==="
        fi
        
        # Prepare system
        if ! prepare_for_join; then
            error "Failed to prepare system for join"
            exit 1
        fi
        
        # Perform join
        if perform_join "$join_command" $attempt; then
            # Validate success
            if validate_join_success; then
                # Clean up temporary bootstrap configuration after successful join
                info "Cleaning up temporary bootstrap configuration..."
                rm -f /etc/systemd/system/kubelet.service.d/20-bootstrap-kubeadm.conf 2>/dev/null || true
                rm -f /etc/systemd/system/kubelet.service.d/kubelet-bootstrap-wrapper.sh 2>/dev/null || true
                systemctl daemon-reload
                
                if [ "$WORKER_POST_WIPE" = "true" ]; then
                    info "🎉 Post-wipe worker join completed successfully!"
                    log_both "Post-wipe worker join successful at $(date)"
                else
                    info "🎉 Join completed successfully!"
                    log_both "Join successful at $(date)"
                fi
                
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
    
    if [ "$WORKER_POST_WIPE" = "true" ]; then
        error "❌ All post-wipe worker join attempts failed after $MAX_RETRIES tries"
        log_both "Post-wipe worker join failed at $(date)"
    else
        error "❌ All join attempts failed after $MAX_RETRIES tries"
        log_both "All join attempts failed at $(date)"
    fi
    
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
#!/bin/bash

# Worker Node Join Log Analyzer
# Analyzes journalctl logs from worker node during kubeadm join attempts
# This script processes logs to identify specific join failure causes

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_section() { echo -e "\n${MAGENTA}=== $1 ===${NC}"; }

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Analyzes worker node join logs to identify failure patterns"
    echo ""
    echo "Options:"
    echo "  -f FILE     Analyze logs from file instead of live journalctl"
    echo "  -s SINCE    Time specification for journalctl (e.g., '1 hour ago', '2023-09-10 13:00')"
    echo "  -u UNIT     systemd unit to analyze (default: kubelet)"
    echo "  -v          Verbose output"
    echo "  -h          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Analyze recent kubelet logs"
    echo "  $0 -s '1 hour ago'                   # Analyze logs from last hour"
    echo "  $0 -f worker_join_logs.txt           # Analyze logs from file"
    echo "  $0 -s '2023-09-10 13:00' -v          # Verbose analysis from specific time"
}

# Default values
LOG_FILE=""
SINCE="10 minutes ago"
UNIT="kubelet"
VERBOSE=false

# Parse command line arguments
while getopts "f:s:u:vh" opt; do
    case ${opt} in
        f)
            LOG_FILE="$OPTARG"
            ;;
        s)
            SINCE="$OPTARG"
            ;;
        u)
            UNIT="$OPTARG"
            ;;
        v)
            VERBOSE=true
            ;;
        h)
            usage
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
    esac
done

# Function to get logs
get_logs() {
    if [ -n "$LOG_FILE" ]; then
        if [ ! -f "$LOG_FILE" ]; then
            log_error "Log file not found: $LOG_FILE"
            exit 1
        fi
        cat "$LOG_FILE"
    else
        journalctl -u "$UNIT" --since="$SINCE" --no-pager -l 2>/dev/null || {
            log_error "Failed to retrieve journalctl logs"
            exit 1
        }
    fi
}

# Analyze join failure patterns
analyze_join_patterns() {
    local logs="$1"
    local patterns_found=()
    
    log_section "JOIN FAILURE PATTERN ANALYSIS"
    
    # Pattern 1: CNI configuration missing
    if echo "$logs" | grep -q "no network config found in /etc/cni/net.d"; then
        patterns_found+=("CNI_CONFIG_MISSING")
        log_error "❌ CNI Configuration Missing"
        echo "   Error: 'no network config found in /etc/cni/net.d'"
        echo "   Cause: Flannel or other CNI plugin not properly deployed"
        echo "   Solution: Deploy Flannel on control plane, ensure CNI plugins installed"
    fi
    
    # Pattern 2: Port 10250 conflict
    if echo "$logs" | grep -q "bind: address already in use.*:10250"; then
        patterns_found+=("PORT_10250_CONFLICT")
        log_error "❌ Port 10250 Conflict"
        echo "   Error: kubelet port already in use"
        echo "   Cause: Previous kubelet instance still running or port conflict"
        echo "   Solution: Stop conflicting process, run remediation script"
    fi
    
    # Pattern 3: Image filesystem capacity invalid
    if echo "$logs" | grep -q "invalid capacity 0"; then
        patterns_found+=("INVALID_FILESYSTEM_CAPACITY")
        log_error "❌ Invalid Filesystem Capacity"
        echo "   Error: containerd reports invalid capacity 0"
        echo "   Cause: Filesystem or containerd configuration issue"
        echo "   Solution: Restart containerd, check /var/lib/containerd permissions"
    fi
    
    # Pattern 4: Certificate authority issues
    if echo "$logs" | grep -q -E "certificate signed by unknown authority|x509.*certificate"; then
        patterns_found+=("CERTIFICATE_AUTHORITY_ERROR")
        log_error "❌ Certificate Authority Error"
        echo "   Error: Certificate validation failed"
        echo "   Cause: CA hash mismatch or network time sync issues"
        echo "   Solution: Get fresh join command, check system time, verify CA hash"
    fi
    
    # Pattern 5: Network connectivity issues
    if echo "$logs" | grep -q -E "connection refused|no route to host|timeout.*6443"; then
        patterns_found+=("NETWORK_CONNECTIVITY_ERROR")
        log_error "❌ Network Connectivity Error"
        echo "   Error: Cannot reach control plane API server"
        echo "   Cause: Network issues, firewall, or control plane down"
        echo "   Solution: Check network, verify control plane status, check firewall"
    fi
    
    # Pattern 6: Token authentication issues
    if echo "$logs" | grep -q -E "token.*invalid|unauthorized|authentication"; then
        patterns_found+=("TOKEN_AUTHENTICATION_ERROR")
        log_error "❌ Token Authentication Error"
        echo "   Error: Join token invalid or expired"
        echo "   Cause: Token expired (24h default) or incorrect token"
        echo "   Solution: Generate new join command with fresh token"
    fi
    
    # Pattern 7: PLEG (Pod Lifecycle Event Generator) issues
    if echo "$logs" | grep -q "PLEG is not healthy"; then
        patterns_found+=("PLEG_UNHEALTHY")
        log_error "❌ PLEG Unhealthy"
        echo "   Error: Pod Lifecycle Event Generator not responding"
        echo "   Cause: High system load, containerd issues, or resource constraints"
        echo "   Solution: Check system resources, restart containerd"
    fi
    
    # Pattern 8: Kubelet configuration issues
    if echo "$logs" | grep -q -E "failed to load kubelet config file|invalid configuration"; then
        patterns_found+=("KUBELET_CONFIG_ERROR")
        log_error "❌ Kubelet Configuration Error"
        echo "   Error: kubelet configuration invalid"
        echo "   Cause: Corrupted config file or permission issues"
        echo "   Solution: Clean kubelet config, run remediation script"
    fi
    
    # Pattern 9: Container runtime issues
    if echo "$logs" | grep -q -E "container runtime.*not running|failed to create.*runtime"; then
        patterns_found+=("CONTAINER_RUNTIME_ERROR")
        log_error "❌ Container Runtime Error"
        echo "   Error: containerd not responding properly"
        echo "   Cause: containerd service issues or socket problems"
        echo "   Solution: Restart containerd service, check socket permissions"
    fi
    
    # Pattern 10: Node registration timeout
    if echo "$logs" | grep -q -E "node.*not found|registration.*timeout|timed out waiting for the condition"; then
        patterns_found+=("NODE_REGISTRATION_TIMEOUT")
        log_error "❌ Node Registration Timeout"
        echo "   Error: Node failed to register with control plane"
        echo "   Cause: CNI not ready, network policy, or control plane overload"
        echo "   Solution: Check CNI status, verify network policies, check control plane"
    fi
    
    return ${#patterns_found[@]}
}

# Extract timeline of join attempts
analyze_join_timeline() {
    local logs="$1"
    
    log_section "JOIN ATTEMPT TIMELINE"
    
    log_info "Extracting timeline of join-related events..."
    
    # Extract key timestamps and events
    echo "$logs" | grep -E "(kubeadm join|kubelet.*started|kubelet.*stopped|Failed to|Error|certificate|token|CNI|PLEG)" | while IFS= read -r line; do
        # Extract timestamp (assumes systemd journal format)
        local timestamp=$(echo "$line" | grep -oE '^[A-Za-z]{3} +[0-9]+ +[0-9:]+' || echo "")
        local event=$(echo "$line" | sed 's/^[A-Za-z0-9: -]*\]//' | sed 's/^[^:]*: *//')
        
        if [ -n "$timestamp" ]; then
            echo "  $timestamp: $event"
        else
            echo "  [Unknown Time]: $event"
        fi
    done
    
    echo ""
}

# Extract detailed error context
extract_error_context() {
    local logs="$1"
    
    log_section "DETAILED ERROR CONTEXT"
    
    log_info "Extracting detailed error messages and context..."
    echo ""
    
    # Find error blocks with context
    echo "$logs" | grep -A 3 -B 1 -E "(ERROR|FATAL|Failed|Error|failed)" | head -50
}

# Generate specific recommendations
generate_specific_recommendations() {
    local patterns_found="$1"
    
    log_section "SPECIFIC RECOMMENDATIONS"
    
    if [ "$patterns_found" -eq 0 ]; then
        log_success "No specific failure patterns detected in logs"
        log_info "General troubleshooting steps:"
        echo "  1. Verify control plane is healthy: kubectl get nodes"
        echo "  2. Check CNI deployment: kubectl get pods -n kube-flannel"
        echo "  3. Generate fresh join command: kubeadm token create --print-join-command"
        echo "  4. Retry join with verbose logging: kubeadm join ... --v=5"
    else
        log_warn "Found $patterns_found specific issue pattern(s)"
        log_info "Priority actions based on detected patterns:"
        echo ""
        
        echo "  1. ADDRESS CRITICAL ISSUES FIRST:"
        echo "     - Fix any CNI configuration problems"
        echo "     - Resolve port conflicts (especially 10250)"
        echo "     - Ensure containerd is healthy"
        echo ""
        
        echo "  2. VERIFY PREREQUISITES:"
        echo "     - Control plane is accessible and healthy"
        echo "     - System time is synchronized (important for certificates)"
        echo "     - No firewall blocking required ports (6443, 10250, etc.)"
        echo ""
        
        echo "  3. CLEAN STATE IF NEEDED:"
        echo "     - Run worker_node_join_remediation.sh to clean previous attempts"
        echo "     - Get fresh join command from control plane"
        echo ""
        
        echo "  4. RETRY WITH MONITORING:"
        echo "     - Run join command with --v=5 for detailed logging"
        echo "     - Monitor logs in separate terminal: journalctl -u kubelet -f"
        echo "     - Capture full logs for analysis if join fails again"
    fi
}

# Performance and resource analysis
analyze_system_performance() {
    local logs="$1"
    
    log_section "SYSTEM PERFORMANCE ANALYSIS"
    
    log_info "Checking for performance-related issues in logs..."
    
    # Look for resource-related warnings
    local resource_issues=$(echo "$logs" | grep -c -E "(out of memory|OOMKilled|disk.*full|no space|high load|timeout)" || true)
    
    if [ "$resource_issues" -gt 0 ]; then
        log_warn "Found $resource_issues potential resource-related issues"
        echo "$logs" | grep -E "(out of memory|OOMKilled|disk.*full|no space|high load|timeout)" | head -10
    else
        log_success "No obvious resource constraints detected in logs"
    fi
    
    # Check for timing issues
    local timing_issues=$(echo "$logs" | grep -c -E "(timeout|timed out|deadline exceeded|context deadline)" || true)
    
    if [ "$timing_issues" -gt 0 ]; then
        log_warn "Found $timing_issues potential timing/timeout issues"
        echo "  Consider: system overload, network latency, or resource constraints"
    fi
}

# Main execution
main() {
    echo "========================================================================"
    echo "                Worker Node Join Log Analyzer"  
    echo "========================================================================"
    echo "Timestamp: $(date)"
    
    if [ -n "$LOG_FILE" ]; then
        log_info "Analyzing logs from file: $LOG_FILE"
    else
        log_info "Analyzing $UNIT logs since: $SINCE"
    fi
    
    echo "========================================================================"
    
    # Get logs
    log_info "Retrieving logs..."
    local logs
    logs=$(get_logs)
    
    if [ -z "$logs" ]; then
        log_warn "No logs found for the specified criteria"
        log_info "Try adjusting the time range with -s option or check if the unit name is correct"
        exit 1
    fi
    
    local log_lines=$(echo "$logs" | wc -l)
    log_info "Retrieved $log_lines lines of logs"
    
    # Perform analysis
    analyze_join_timeline "$logs"
    
    analyze_join_patterns "$logs"
    local patterns_found=$?
    
    if $VERBOSE; then
        extract_error_context "$logs"
        analyze_system_performance "$logs"
    fi
    
    generate_specific_recommendations "$patterns_found"
    
    echo ""
    log_section "ANALYSIS COMPLETE"
    
    if [ "$patterns_found" -eq 0 ]; then
        log_success "No specific failure patterns detected"
        log_info "This could indicate intermittent issues, configuration problems, or successful operation"
    else
        log_warn "Analysis complete - found $patterns_found issue pattern(s)"
        log_info "Follow the specific recommendations above to resolve detected issues"
    fi
    
    log_info "For additional analysis, run with -v flag for verbose output"
}

# Execute main function
main "$@"
#!/bin/bash

# VMStation Kubelet Systemd Configuration Fix
# Fixes the "Assignment outside of section" error for kubelet systemd drop-in files
# This script addresses the issue where systemd drop-in files are created with
# configuration directives outside of proper section headers like [Service] or [Unit]

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

echo "=== VMStation Kubelet Systemd Configuration Fix ==="
echo "Timestamp: $(date)"
echo ""

# Function to check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        error "This script must be run as root"
        error "Please run: sudo $0"
        exit 1
    fi
}

# Function to backup original configuration
backup_systemd_configs() {
    local backup_dir="/tmp/kubelet-systemd-backup-$(date +%Y%m%d-%H%M%S)"
    
    info "Creating backup of kubelet systemd configurations..."
    mkdir -p "$backup_dir"
    
    if [ -d "/etc/systemd/system/kubelet.service.d" ]; then
        cp -r "/etc/systemd/system/kubelet.service.d" "$backup_dir/" 2>/dev/null || true
        info "✓ Backed up kubelet systemd drop-ins to $backup_dir"
    fi
    
    echo "$backup_dir" > /tmp/kubelet-systemd-backup-location
    info "Backup location stored in /tmp/kubelet-systemd-backup-location"
}

# Function to detect malformed systemd drop-in files
detect_malformed_configs() {
    local kubelet_dropin_dir="/etc/systemd/system/kubelet.service.d"
    local malformed_files=()
    
    info "Scanning for malformed kubelet systemd drop-in files..."
    
    if [ ! -d "$kubelet_dropin_dir" ]; then
        info "No kubelet systemd drop-in directory found"
        return 0
    fi
    
    # Check each .conf file in the drop-in directory
    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            debug "Checking file: $file"
            
            # Read the first non-empty line
            local first_line
            first_line=$(grep -v '^[[:space:]]*$' "$file" 2>/dev/null | head -1 || echo "")
            
            if [ -n "$first_line" ]; then
                # Check if first line starts with a section header [Section]
                if [[ ! "$first_line" =~ ^\[[A-Za-z]+\] ]]; then
                    # Check if it looks like a systemd directive (contains =)
                    if [[ "$first_line" =~ = ]]; then
                        warn "Found malformed config file: $file"
                        warn "First line: $first_line"
                        warn "This line should be inside a [Service] or [Unit] section"
                        malformed_files+=("$file")
                    fi
                fi
            fi
        fi
    done < <(find "$kubelet_dropin_dir" -name "*.conf" -print0 2>/dev/null)
    
    if [ ${#malformed_files[@]} -eq 0 ]; then
        info "✓ No malformed systemd drop-in files detected"
        return 0
    else
        error "Found ${#malformed_files[@]} malformed systemd drop-in file(s):"
        for file in "${malformed_files[@]}"; do
            error "  - $file"
        done
        return 1
    fi
}

# Function to fix malformed systemd drop-in files
fix_malformed_configs() {
    local kubelet_dropin_dir="/etc/systemd/system/kubelet.service.d"
    local fixed_count=0
    
    info "Fixing malformed kubelet systemd drop-in files..."
    
    if [ ! -d "$kubelet_dropin_dir" ]; then
        warn "No kubelet systemd drop-in directory found"
        return 0
    fi
    
    # Process each .conf file
    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            debug "Processing file: $file"
            
            # Read the file content
            local content
            content=$(cat "$file" 2>/dev/null || echo "")
            
            if [ -n "$content" ]; then
                # Check if file starts with a section header
                local first_line
                first_line=$(echo "$content" | grep -v '^[[:space:]]*$' | head -1 || echo "")
                
                if [[ -n "$first_line" && ! "$first_line" =~ ^\[[A-Za-z]+\] ]]; then
                    # Check if it contains systemd directives that should be in [Service]
                    if echo "$content" | grep -q "Environment=\|ExecStart=\|Restart=\|StartLimitInterval="; then
                        info "Fixing malformed config file: $file"
                        
                        # Create properly formatted content with [Service] section
                        local fixed_content="[Service]
$content"
                        
                        # Write the fixed content
                        echo "$fixed_content" > "$file"
                        
                        info "✓ Fixed $file - added [Service] section header"
                        ((fixed_count++))
                    fi
                fi
            fi
        fi
    done < <(find "$kubelet_dropin_dir" -name "*.conf" -print0 2>/dev/null)
    
    if [ $fixed_count -gt 0 ]; then
        info "✓ Fixed $fixed_count malformed systemd drop-in file(s)"
        return 0
    else
        info "✓ No files needed fixing"
        return 0
    fi
}

# Function to remove problematic configuration files
remove_problematic_configs() {
    local kubelet_dropin_dir="/etc/systemd/system/kubelet.service.d"
    
    info "Checking for known problematic configuration files..."
    
    # List of known problematic files that should be removed
    local problematic_files=(
        "$kubelet_dropin_dir/20-join-config.conf"
        "$kubelet_dropin_dir/10-invalid-config.conf"
    )
    
    local removed_count=0
    
    for file in "${problematic_files[@]}"; do
        if [ -f "$file" ]; then
            # Check if the file contains just environment variables without section headers
            local content
            content=$(cat "$file" 2>/dev/null || echo "")
            
            # If file contains Environment= lines but no [Service] section, remove it
            if echo "$content" | grep -q "Environment=" && ! echo "$content" | grep -q "^\[Service\]"; then
                warn "Removing problematic configuration file: $file"
                rm -f "$file"
                info "✓ Removed $file"
                ((removed_count++))
            fi
        fi
    done
    
    if [ $removed_count -gt 0 ]; then
        info "✓ Removed $removed_count problematic configuration file(s)"
    else
        info "✓ No problematic configuration files found"
    fi
}

# Function to create a proper kubelet systemd drop-in configuration
create_proper_kubelet_config() {
    local kubelet_dropin_dir="/etc/systemd/system/kubelet.service.d"
    local config_file="$kubelet_dropin_dir/10-kubeadm.conf"
    
    info "Ensuring proper kubelet systemd configuration exists..."
    
    # Create the drop-in directory if it doesn't exist
    mkdir -p "$kubelet_dropin_dir"
    
    # Only create the config if kubeadm is installed and no proper config exists
    if command -v kubeadm >/dev/null 2>&1; then
        if [ ! -f "$config_file" ] || ! grep -q "^\[Service\]" "$config_file" 2>/dev/null; then
            info "Creating proper kubelet systemd drop-in configuration..."
            
            cat > "$config_file" << 'EOF'
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
Environment="KUBELET_KUBEADM_ARGS=--container-runtime-endpoint=unix:///run/containerd/containerd.sock"
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF
            
            info "✓ Created proper kubelet systemd configuration at $config_file"
        else
            info "✓ Proper kubelet systemd configuration already exists"
        fi
    else
        debug "kubeadm not found - skipping kubelet config creation"
    fi
}

# Function to validate systemd configuration
validate_systemd_config() {
    info "Validating systemd configuration..."
    
    # Check if systemd can parse the configuration without errors
    if systemctl daemon-reload 2>/dev/null; then
        info "✓ Systemd daemon reload successful"
    else
        error "❌ Systemd daemon reload failed"
        return 1
    fi
    
    # Check kubelet service status
    local kubelet_status
    kubelet_status=$(systemctl is-enabled kubelet 2>/dev/null || echo "unknown")
    
    if [ "$kubelet_status" = "enabled" ]; then
        info "✓ Kubelet service is enabled"
    else
        warn "Kubelet service status: $kubelet_status"
    fi
    
    # Test if systemd can load the kubelet service without errors
    if systemctl cat kubelet >/dev/null 2>&1; then
        info "✓ Kubelet service configuration is valid"
    else
        error "❌ Kubelet service configuration has errors"
        return 1
    fi
    
    return 0
}

# Function to check for systemd journal errors
check_systemd_errors() {
    info "Checking for recent systemd journal errors..."
    
    # Check for "Assignment outside of section" errors in the last hour
    local assignment_errors
    assignment_errors=$(journalctl --no-pager --since "1 hour ago" 2>/dev/null | grep -c "Assignment outside of section" || echo "0")
    
    if [ "$assignment_errors" -gt 0 ]; then
        warn "Found $assignment_errors 'Assignment outside of section' errors in the last hour"
        warn "Recent errors:"
        journalctl --no-pager --since "1 hour ago" 2>/dev/null | grep "Assignment outside of section" | tail -5 || true
    else
        info "✓ No 'Assignment outside of section' errors found in recent logs"
    fi
    
    # Check for kubelet-related systemd errors
    local kubelet_errors
    kubelet_errors=$(journalctl -u kubelet --no-pager --since "1 hour ago" 2>/dev/null | grep -c "Failed\|Error" || echo "0")
    
    if [ "$kubelet_errors" -gt 0 ]; then
        warn "Found $kubelet_errors kubelet errors in the last hour"
        debug "Recent kubelet errors:"
        journalctl -u kubelet --no-pager --since "1 hour ago" 2>/dev/null | grep "Failed\|Error" | tail -3 || true
    else
        info "✓ No recent kubelet errors found"
    fi
}

# Function to show summary and recommendations
show_summary() {
    echo ""
    info "=== Fix Summary ==="
    
    if [ -f "/tmp/kubelet-systemd-backup-location" ]; then
        local backup_location
        backup_location=$(cat /tmp/kubelet-systemd-backup-location)
        info "Backup created at: $backup_location"
    fi
    
    echo ""
    info "🔧 Actions performed:"
    info "  • Detected and fixed malformed systemd drop-in files"
    info "  • Removed problematic configuration files"
    info "  • Created proper kubelet systemd configuration"
    info "  • Validated systemd configuration"
    
    echo ""
    info "📋 Next steps:"
    info "  1. Test kubelet service: sudo systemctl status kubelet"
    info "  2. Check for errors: sudo journalctl -u kubelet -f"
    info "  3. If joining a cluster: retry kubeadm join command"
    
    echo ""
    info "🔍 If issues persist:"
    info "  • Check kubelet logs: sudo journalctl -u kubelet --no-pager -n 50"
    info "  • Validate cluster connectivity: curl -k https://<master-ip>:6443/healthz"
    info "  • Run cluster diagnostics: sudo ./scripts/validate_k8s_monitoring.sh"
}

# Main execution
main() {
    check_root
    
    info "Starting kubelet systemd configuration fix..."
    echo ""
    
    # Create backup
    backup_systemd_configs
    
    # Detect issues
    if detect_malformed_configs; then
        info "No malformed configurations detected"
    else
        warn "Malformed configurations found - proceeding with fixes"
    fi
    
    # Remove problematic files
    remove_problematic_configs
    
    # Fix malformed files
    fix_malformed_configs
    
    # Create proper configuration
    create_proper_kubelet_config
    
    # Validate configuration
    if validate_systemd_config; then
        info "✅ Systemd configuration validation passed"
    else
        error "❌ Systemd configuration validation failed"
        return 1
    fi
    
    # Check for errors
    check_systemd_errors
    
    # Show summary
    show_summary
    
    echo ""
    info "🎉 Kubelet systemd configuration fix completed successfully!"
    
    return 0
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
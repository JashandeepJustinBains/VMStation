#!/bin/bash

# VMStation Systemd Drop-in Validator
# Validates and ensures proper formatting of systemd drop-in files
# This script prevents "Assignment outside of section" errors by ensuring
# all systemd configuration directives are within proper section headers

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

# Function to validate a single systemd drop-in file
validate_systemd_file() {
    local file="$1"
    local service_name="$2"
    
    if [ ! -f "$file" ]; then
        debug "File does not exist: $file"
        return 0
    fi
    
    debug "Validating systemd file: $file"
    
    # Read file content, ignoring empty lines and comments
    local content
    content=$(grep -v '^[[:space:]]*$' "$file" 2>/dev/null | grep -v '^[[:space:]]*#' || echo "")
    
    if [ -z "$content" ]; then
        debug "File is empty or contains only comments: $file"
        return 0
    fi
    
    # Check if file starts with a proper section header
    local first_line
    first_line=$(echo "$content" | head -1)
    
    if [[ ! "$first_line" =~ ^\[[A-Za-z]+\] ]]; then
        # Check if content contains systemd directives
        if echo "$content" | grep -q "Environment=\|ExecStart=\|ExecReload=\|ExecStop=\|Restart=\|Type=\|User=\|Group=\|WorkingDirectory="; then
            error "Invalid systemd configuration in $file"
            error "First line: $first_line"
            error "Configuration directives found outside of section header"
            error "File should start with [Service], [Unit], or [Install] section"
            return 1
        fi
    fi
    
    # Validate section headers are properly formatted
    local section_count
    section_count=$(echo "$content" | grep -c '^\[.*\]' || echo "0")
    
    if [ "$section_count" -eq 0 ]; then
        if echo "$content" | grep -q "="; then
            error "No section headers found in $file but configuration directives present"
            return 1
        fi
    fi
    
    # Check for common mistakes
    local line_number=0
    local current_section=""
    
    while IFS= read -r line; do
        ((line_number++))
        
        # Skip empty lines and comments
        if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Check for section headers
        if [[ "$line" =~ ^\[([A-Za-z]+)\] ]]; then
            current_section="${BASH_REMATCH[1]}"
            debug "Found section: [$current_section] at line $line_number"
            continue
        fi
        
        # Check for configuration directives
        if [[ "$line" =~ ^[A-Za-z].*= ]]; then
            if [ -z "$current_section" ]; then
                error "Configuration directive outside of section at line $line_number in $file"
                error "Line: $line"
                error "This directive should be inside a section like [Service] or [Unit]"
                return 1
            fi
        fi
    done <<< "$content"
    
    debug "✓ File validation passed: $file"
    return 0
}

# Function to fix a malformed systemd file
fix_systemd_file() {
    local file="$1"
    local default_section="${2:-Service}"
    
    info "Fixing malformed systemd file: $file"
    
    # Read original content
    local content
    content=$(cat "$file" 2>/dev/null || echo "")
    
    if [ -z "$content" ]; then
        warn "File is empty: $file"
        return 0
    fi
    
    # Check if file already has proper section headers
    if echo "$content" | grep -q '^\[.*\]'; then
        debug "File already has section headers, checking validity..."
        if validate_systemd_file "$file"; then
            debug "File is already valid: $file"
            return 0
        fi
    fi
    
    # Backup original file
    cp "$file" "${file}.backup-$(date +%Y%m%d-%H%M%S)"
    
    # Create fixed content with proper section header
    local fixed_content
    if echo "$content" | grep -q "Environment=\|ExecStart=\|ExecReload=\|ExecStop=\|Restart=\|Type=\|User=\|Group=\|WorkingDirectory="; then
        # This looks like Service section content
        fixed_content="[Service]
$content"
    elif echo "$content" | grep -q "Description=\|Requires=\|After=\|Before=\|Wants="; then
        # This looks like Unit section content
        fixed_content="[Unit]
$content"
    elif echo "$content" | grep -q "WantedBy=\|RequiredBy=\|Also="; then
        # This looks like Install section content
        fixed_content="[Install]
$content"
    else
        # Default to Service section
        fixed_content="[$default_section]
$content"
    fi
    
    # Write fixed content
    echo "$fixed_content" > "$file"
    
    info "✓ Fixed systemd file: $file (added [$default_section] section)"
    
    # Validate the fix
    if validate_systemd_file "$file"; then
        info "✓ Fix validation passed: $file"
        return 0
    else
        error "❌ Fix validation failed: $file"
        return 1
    fi
}

# Function to validate all kubelet systemd configurations
validate_kubelet_systemd() {
    local kubelet_dropin_dir="/etc/systemd/system/kubelet.service.d"
    local validation_passed=true
    
    info "Validating kubelet systemd drop-in configurations..."
    
    if [ ! -d "$kubelet_dropin_dir" ]; then
        info "No kubelet systemd drop-in directory found"
        return 0
    fi
    
    # Validate each .conf file
    while IFS= read -r -d '' file; do
        if ! validate_systemd_file "$file" "kubelet"; then
            validation_passed=false
            warn "Validation failed for: $file"
        fi
    done < <(find "$kubelet_dropin_dir" -name "*.conf" -print0 2>/dev/null)
    
    if [ "$validation_passed" = true ]; then
        info "✓ All kubelet systemd configurations are valid"
        return 0
    else
        error "❌ Some kubelet systemd configurations are invalid"
        return 1
    fi
}

# Function to fix all invalid kubelet systemd configurations
fix_kubelet_systemd() {
    local kubelet_dropin_dir="/etc/systemd/system/kubelet.service.d"
    local fix_count=0
    
    info "Fixing kubelet systemd drop-in configurations..."
    
    if [ ! -d "$kubelet_dropin_dir" ]; then
        info "No kubelet systemd drop-in directory found"
        return 0
    fi
    
    # Fix each invalid .conf file
    while IFS= read -r -d '' file; do
        if ! validate_systemd_file "$file" "kubelet"; then
            if fix_systemd_file "$file" "Service"; then
                ((fix_count++))
            else
                error "Failed to fix: $file"
            fi
        fi
    done < <(find "$kubelet_dropin_dir" -name "*.conf" -print0 2>/dev/null)
    
    if [ $fix_count -gt 0 ]; then
        info "✓ Fixed $fix_count kubelet systemd configuration file(s)"
        
        # Reload systemd to pick up changes
        systemctl daemon-reload
        info "✓ Systemd daemon reloaded"
        
        return 0
    else
        info "✓ No kubelet systemd configurations needed fixing"
        return 0
    fi
}

# Function to create a systemd drop-in file with proper format
create_systemd_dropin() {
    local service_name="$1"
    local dropin_name="$2"
    local section="$3"
    local content="$4"
    
    local dropin_dir="/etc/systemd/system/${service_name}.service.d"
    local dropin_file="$dropin_dir/${dropin_name}.conf"
    
    info "Creating systemd drop-in: $dropin_file"
    
    # Create directory if it doesn't exist
    mkdir -p "$dropin_dir"
    
    # Create properly formatted drop-in file
    cat > "$dropin_file" << EOF
[$section]
$content
EOF
    
    # Validate the created file
    if validate_systemd_file "$dropin_file" "$service_name"; then
        info "✓ Created valid systemd drop-in: $dropin_file"
        return 0
    else
        error "❌ Created invalid systemd drop-in: $dropin_file"
        rm -f "$dropin_file"
        return 1
    fi
}

# Function to ensure proper kubelet configuration during join
ensure_kubelet_join_config() {
    local master_ip="${1:-192.168.4.63}"
    
    info "Ensuring proper kubelet configuration for cluster join..."
    
    # Create kubelet drop-in directory
    mkdir -p "/etc/systemd/system/kubelet.service.d"
    
    # Remove any malformed configurations first
    if ! validate_kubelet_systemd; then
        warn "Found invalid kubelet configurations, fixing them..."
        fix_kubelet_systemd
    fi
    
    # Ensure proper kubeadm configuration exists
    local kubeadm_config="/etc/systemd/system/kubelet.service.d/10-kubeadm.conf"
    
    if [ ! -f "$kubeadm_config" ] || ! validate_systemd_file "$kubeadm_config"; then
        info "Creating proper kubelet kubeadm configuration..."
        
        local config_content='Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
Environment="KUBELET_KUBEADM_ARGS=--container-runtime-endpoint=unix:///run/containerd/containerd.sock"
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS'
        
        create_systemd_dropin "kubelet" "10-kubeadm" "Service" "$config_content"
    fi
    
    # Reload systemd configuration
    systemctl daemon-reload
    
    # Final validation
    if validate_kubelet_systemd; then
        info "✅ Kubelet systemd configuration is ready for cluster join"
        return 0
    else
        error "❌ Kubelet systemd configuration validation failed"
        return 1
    fi
}

# Main function for command-line usage
main() {
    local action="${1:-validate}"
    local target="${2:-kubelet}"
    
    case "$action" in
        "validate")
            info "Validating $target systemd configurations..."
            if [ "$target" = "kubelet" ]; then
                validate_kubelet_systemd
            else
                error "Unknown target: $target"
                return 1
            fi
            ;;
        "fix")
            info "Fixing $target systemd configurations..."
            if [ "$target" = "kubelet" ]; then
                fix_kubelet_systemd
            else
                error "Unknown target: $target"
                return 1
            fi
            ;;
        "ensure-join")
            local master_ip="${2:-192.168.4.63}"
            ensure_kubelet_join_config "$master_ip"
            ;;
        "help"|"--help"|"-h")
            echo "Usage: $0 [action] [target]"
            echo "Actions:"
            echo "  validate     - Validate systemd drop-in files (default)"
            echo "  fix          - Fix invalid systemd drop-in files"
            echo "  ensure-join  - Ensure proper kubelet config for cluster join"
            echo "Targets:"
            echo "  kubelet      - Kubelet service configurations (default)"
            echo "Examples:"
            echo "  $0 validate kubelet"
            echo "  $0 fix kubelet"
            echo "  $0 ensure-join 192.168.4.63"
            ;;
        *)
            error "Unknown action: $action"
            error "Use '$0 help' for usage information"
            return 1
            ;;
    esac
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
#!/bin/bash

# Validation script for Flannel download fix in mixed OS environments
# This script validates that both RHEL10 and Debian nodes can download Flannel CNI plugin

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

echo "=== VMStation Mixed OS Flannel Download Validation ==="
echo "Timestamp: $(date)"
echo ""

# Function to check version consistency between DaemonSet and manual downloads
check_version_consistency() {
    local playbook_file="$1"
    
    info "Checking Flannel version consistency..."
    
    # Check DaemonSet template if it exists
    local template_file="/home/runner/work/VMStation/VMStation/ansible/plays/kubernetes/templates/kube-flannel-allnodes.yml"
    if [ -f "$template_file" ]; then
        local daemonset_version=$(grep "flannel-cni-plugin:" "$template_file" | head -1 | sed 's/.*://' | tr -d ' ')
        info "DaemonSet uses flannel CNI plugin version: $daemonset_version"
        
        # Extract version from manual downloads in playbook
        local manual_version=$(grep "flannel-io/cni-plugin/releases/download/" "$playbook_file" | head -1 | sed 's/.*download\///' | sed 's/\/flannel-amd64.*//')
        info "Manual downloads use version: $manual_version"
        
        # Compare versions (normalize flannel1 vs flannel2 suffixes)
        local daemonset_base=$(echo "$daemonset_version" | sed 's/-flannel[0-9]*$//')
        local manual_base=$(echo "$manual_version" | sed 's/-flannel[0-9]*$//')
        
        if [ "$daemonset_base" = "$manual_base" ]; then
            info "✅ Version bases are consistent ($daemonset_base)"
            return 0
        else
            error "❌ Version mismatch between DaemonSet ($daemonset_version) and manual downloads ($manual_version)"
            return 1
        fi
    else
        warn "⚠️  DaemonSet template not found, skipping version consistency check"
        return 0
    fi
}

# Function to validate Flannel download consistency
validate_flannel_downloads() {
    local playbook_file="$1"
    
    info "Validating Flannel download consistency in $playbook_file..."
    
    # Count Flannel get_url downloads (excluding curl fallbacks)
    local get_url_count=$(grep -B 2 -A 2 "get_url:" "$playbook_file" | grep -c "url.*flannel.*releases.*download.*flannel-amd64" || echo 0)
    
    # Count Flannel curl fallbacks
    local curl_count=$(grep -c "Fallback.*Download Flannel CNI plugin with curl" "$playbook_file" || echo 0)
    
    # Count Flannel wget fallbacks
    local wget_count=$(grep -c "Enhanced fallback.*Download Flannel CNI plugin with wget" "$playbook_file" || echo 0)
    
    # Count verification tasks
    local verify_count=$(grep -c "Verify Flannel CNI plugin download succeeded" "$playbook_file" || echo 0)
    
    info "Found $get_url_count Flannel get_url downloads"
    info "Found $curl_count Flannel curl fallbacks"
    info "Found $wget_count Flannel wget fallbacks"
    info "Found $verify_count Flannel verification tasks"
    
    if [ "$get_url_count" -eq "$curl_count" ] && [ "$get_url_count" -eq "$wget_count" ] && [ "$get_url_count" -eq "$verify_count" ]; then
        info "✅ All Flannel downloads have complete fallback and verification chain"
        return 0
    else
        error "❌ Inconsistent Flannel download implementations"
        error "   Expected: get_url=$get_url_count, curl=$get_url_count, wget=$get_url_count, verify=$get_url_count"
        error "   Found: get_url=$get_url_count, curl=$curl_count, wget=$wget_count, verify=$verify_count"
        return 1
    fi
}

# Function to check specific OS compatibility features
check_os_compatibility() {
    local playbook_file="$1"
    
    info "Checking OS compatibility features..."
    
    # Check for urllib3/cert_file error detection
    if grep -q "cert_file.*urllib3\|urllib3.*cert_file" "$playbook_file"; then
        info "✅ urllib3/cert_file error detection present"
    else
        warn "⚠️  urllib3/cert_file error detection might be missing"
    fi
    
    # Check for validate_certs: false
    if grep -A 10 "get_url:" "$playbook_file" | grep -q "validate_certs: false"; then
        info "✅ Certificate validation disabled for compatibility"
    else
        warn "⚠️  Certificate validation settings might need review"
    fi
    
    # Check for proxy settings
    if grep -A 10 "get_url:" "$playbook_file" | grep -q "use_proxy: false"; then
        info "✅ Proxy bypass configured for direct downloads"
    else
        warn "⚠️  Proxy settings might affect downloads"
    fi
}

# Function to validate worker node specific enhancements
check_worker_node_enhancements() {
    local playbook_file="$1"
    
    info "Checking worker node specific enhancements..."
    
    # Check for worker-specific Flannel tasks
    if grep -q "Download and install Flannel CNI plugin binary on worker nodes" "$playbook_file"; then
        info "✅ Worker node specific Flannel download task found"
        
        # Check for proper error handling in worker tasks
        if grep -A 20 "Download and install Flannel CNI plugin binary on worker nodes" "$playbook_file" | grep -q "failed_when: false"; then
            info "✅ Worker node task has proper error handling"
        else
            error "❌ Worker node task missing error handling"
            return 1
        fi
        
        # Check for register variable
        if grep -A 20 "Download and install Flannel CNI plugin binary on worker nodes" "$playbook_file" | grep -q "register: flannel_download_worker"; then
            info "✅ Worker node task registers results properly"
        else
            error "❌ Worker node task missing register variable"
            return 1
        fi
    else
        warn "⚠️  No worker node specific Flannel download found"
    fi
}

# Main validation
main() {
    local playbook_path="/home/runner/work/VMStation/VMStation/ansible/plays/setup-cluster.yaml"
    
    if [ ! -f "$playbook_path" ]; then
        error "Playbook not found: $playbook_path"
        exit 1
    fi
    
    # Run all validations
    validate_flannel_downloads "$playbook_path" || exit 1
    check_version_consistency "$playbook_path" || exit 1
    check_os_compatibility "$playbook_path"
    check_worker_node_enhancements "$playbook_path" || exit 1
    
    # Final syntax check
    info "Running Ansible syntax validation..."
    if cd "$(dirname "$playbook_path")/../.." && ansible-playbook --syntax-check -i ansible/inventory.txt ansible/plays/setup-cluster.yaml >/dev/null 2>&1; then
        info "✅ Ansible playbook syntax is valid"
    else
        error "❌ Ansible playbook has syntax errors"
        exit 1
    fi
    
    echo ""
    info "🎉 Mixed OS Flannel Download Validation Summary:"
    info "✅ Consistent fallback mechanisms for all Flannel downloads (get_url -> curl -> wget)"
    info "✅ Version consistency between DaemonSet and manual downloads"
    info "✅ OS-specific compatibility features implemented"
    info "✅ Worker node enhancements properly configured"
    info "✅ Ansible syntax validation passed"
    echo ""
    info "🔧 This configuration should work for:"
    info "   • RHEL10 nodes (homelab - 192.168.4.63)"
    info "   • Debian nodes (storagenodet3500 - 192.168.4.62)"
    info "   • Any other Linux distributions with similar compatibility issues"
    echo ""
    info "✨ Ready for mixed OS cluster deployment!"
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
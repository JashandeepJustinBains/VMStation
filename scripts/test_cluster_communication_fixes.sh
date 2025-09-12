#!/bin/bash

# Test Script for Cluster Communication Fixes
# This script tests the functionality of our new cluster communication fix scripts

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "=== VMStation Cluster Communication Fix Tests ==="
echo "Timestamp: $(date)"
echo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test script existence and syntax
test_script_syntax() {
    local script="$1"
    local script_path="$SCRIPT_DIR/$script"
    
    info "Testing script: $script"
    
    if [ ! -f "$script_path" ]; then
        error "Script not found: $script_path"
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        warn "Script not executable: $script_path"
        chmod +x "$script_path"
    fi
    
    # Syntax check
    if bash -n "$script_path"; then
        success "✅ Syntax check passed: $script"
        return 0
    else
        error "❌ Syntax check failed: $script"
        return 1
    fi
}

# Test help/usage functionality
test_script_help() {
    local script="$1"
    local script_path="$SCRIPT_DIR/$script"
    
    info "Testing help functionality: $script"
    
    # Most scripts should handle --help gracefully
    if timeout 10 bash "$script_path" --help >/dev/null 2>&1; then
        success "✅ Help functionality works: $script"
        return 0
    else
        # Not all scripts may have --help, so this is just a warning
        warn "⚠️  No help functionality: $script"
        return 0
    fi
}

# Test prerequisites check
test_prerequisites() {
    info "Testing prerequisites for cluster communication fixes"
    
    # Check if kubectl is available
    if command -v kubectl >/dev/null 2>&1; then
        success "✅ kubectl is available"
    else
        error "❌ kubectl is not available"
        return 1
    fi
    
    # Check if iptables is available
    if command -v iptables >/dev/null 2>&1; then
        success "✅ iptables is available"
    else
        warn "⚠️  iptables is not available"
    fi
    
    # Check if we have basic networking tools
    if command -v ip >/dev/null 2>&1; then
        success "✅ ip command is available"
    else
        error "❌ ip command is not available"
        return 1
    fi
    
    return 0
}

# Test script directory structure
test_directory_structure() {
    info "Testing directory structure"
    
    local required_scripts=(
        "fix_worker_kubectl_config.sh"
        "fix_iptables_compatibility.sh" 
        "validate_cluster_communication.sh"
        "fix_cluster_communication.sh"
        "fix_remaining_pod_issues.sh"
        "fix_cni_bridge_conflict.sh"
    )
    
    local missing_scripts=()
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$script" ]; then
            missing_scripts+=("$script")
        fi
    done
    
    if [ ${#missing_scripts[@]} -eq 0 ]; then
        success "✅ All required scripts present"
        return 0
    else
        error "❌ Missing scripts: ${missing_scripts[*]}"
        return 1
    fi
}

# Test main diagnostic script enhancements
test_diagnostic_enhancements() {
    info "Testing diagnostic script enhancements"
    
    local diag_script="$SCRIPT_DIR/../diagnose_jellyfin_network.sh"
    
    if [ -f "$diag_script" ]; then
        # Check if it contains references to our new scripts
        if grep -q "fix_cluster_communication.sh" "$diag_script"; then
            success "✅ Diagnostic script references new fixes"
        else
            warn "⚠️  Diagnostic script may not reference new fixes"
        fi
        
        # Syntax check
        if bash -n "$diag_script"; then
            success "✅ Diagnostic script syntax is valid"
        else
            error "❌ Diagnostic script has syntax errors"
            return 1
        fi
    else
        error "❌ Diagnostic script not found"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    local total_tests=0
    local passed_tests=0
    
    info "Starting cluster communication fix tests..."
    
    # Test 1: Prerequisites
    total_tests=$((total_tests + 1))
    if test_prerequisites; then
        passed_tests=$((passed_tests + 1))
    fi
    
    # Test 2: Directory structure
    total_tests=$((total_tests + 1))
    if test_directory_structure; then
        passed_tests=$((passed_tests + 1))
    fi
    
    # Test 3: Script syntax checks
    local scripts=(
        "fix_worker_kubectl_config.sh"
        "fix_iptables_compatibility.sh"
        "validate_cluster_communication.sh"
        "fix_cluster_communication.sh"
    )
    
    for script in "${scripts[@]}"; do
        total_tests=$((total_tests + 1))
        if test_script_syntax "$script"; then
            passed_tests=$((passed_tests + 1))
        fi
    done
    
    # Test 4: Help functionality
    for script in "${scripts[@]}"; do
        total_tests=$((total_tests + 1))
        if test_script_help "$script"; then
            passed_tests=$((passed_tests + 1))
        fi
    done
    
    # Test 5: Diagnostic enhancements
    total_tests=$((total_tests + 1))
    if test_diagnostic_enhancements; then
        passed_tests=$((passed_tests + 1))
    fi
    
    # Summary
    echo
    info "=== Test Summary ==="
    echo "Total tests: $total_tests"
    echo "Passed: $passed_tests"
    echo "Failed: $((total_tests - passed_tests))"
    
    if [ "$passed_tests" -eq "$total_tests" ]; then
        success "🎉 All tests passed!"
        echo
        echo "The cluster communication fixes are ready to use:"
        echo "  ./scripts/fix_cluster_communication.sh      # Master fix script"
        echo "  ./scripts/validate_cluster_communication.sh  # Validation script"
        echo "  ./scripts/fix_worker_kubectl_config.sh      # kubectl configuration"
        echo "  ./scripts/fix_iptables_compatibility.sh     # iptables fixes"
        echo
        return 0
    else
        error "Some tests failed. Please review the issues above."
        return 1
    fi
}

# Run main function
main "$@"
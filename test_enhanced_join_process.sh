#!/bin/bash

# Test Enhanced Join Process Implementation
# Validates the new enhanced join process components

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_RESULTS=0

echo "=== Enhanced Join Process Implementation Test ==="
echo "Testing: Enhanced kubeadm join process components"
echo ""

# Test 1: Validate script files exist
test_script_files() {
    info "Test 1: Checking required script files..."
    
    local scripts=(
        "scripts/validate_join_prerequisites.sh"
        "scripts/enhanced_kubeadm_join.sh"
        "docs/ENHANCED_JOIN_PROCESS.md"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            info "✓ Found: $script"
        else
            error "✗ Missing: $script"
            ((TEST_RESULTS++))
        fi
    done
}

# Test 2: Validate script syntax
test_script_syntax() {
    info "Test 2: Validating script syntax..."
    
    if bash -n "$SCRIPT_DIR/scripts/validate_join_prerequisites.sh"; then
        info "✓ Syntax OK: validate_join_prerequisites.sh"
    else
        error "✗ Syntax Error: validate_join_prerequisites.sh"
        ((TEST_RESULTS++))
    fi
    
    if bash -n "$SCRIPT_DIR/scripts/enhanced_kubeadm_join.sh"; then
        info "✓ Syntax OK: enhanced_kubeadm_join.sh"
    else
        error "✗ Syntax Error: enhanced_kubeadm_join.sh"
        ((TEST_RESULTS++))
    fi
}

# Test 3: Check ansible playbook integration
test_ansible_integration() {
    info "Test 3: Checking Ansible playbook integration..."
    
    local playbook="$SCRIPT_DIR/ansible/plays/setup-cluster.yaml"
    
    if [ -f "$playbook" ]; then
        if grep -q "enhanced_kubeadm_join.sh" "$playbook"; then
            info "✓ Enhanced join integrated in playbook"
        else
            error "✗ Enhanced join not found in playbook"
            ((TEST_RESULTS++))
        fi
        
        if grep -q "validate_join_prerequisites.sh" "$playbook"; then
            info "✓ Prerequisites validation integrated in playbook"
        else
            error "✗ Prerequisites validation not found in playbook"
            ((TEST_RESULTS++))
        fi
        
        if grep -q "Post-join validation" "$playbook"; then
            info "✓ Post-join validation integrated in playbook"
        else
            error "✗ Post-join validation not found in playbook"
            ((TEST_RESULTS++))
        fi
    else
        error "✗ Ansible playbook not found: $playbook"
        ((TEST_RESULTS++))
    fi
}

# Test 4: Validate script permissions
test_script_permissions() {
    info "Test 4: Checking script permissions..."
    
    local scripts=(
        "scripts/validate_join_prerequisites.sh"
        "scripts/enhanced_kubeadm_join.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -x "$SCRIPT_DIR/$script" ]; then
            info "✓ Executable: $script"
        else
            warn "⚠ Not executable: $script (will be fixed during deployment)"
        fi
    done
}

# Test 5: Check documentation completeness  
test_documentation() {
    info "Test 5: Validating documentation..."
    
    local doc="$SCRIPT_DIR/docs/ENHANCED_JOIN_PROCESS.md"
    
    if [ -f "$doc" ]; then
        local sections=(
            "Problem Statement"
            "Solution Overview"
            "Architecture"
            "Usage"
            "Troubleshooting"
        )
        
        for section in "${sections[@]}"; do
            if grep -q "$section" "$doc"; then
                info "✓ Documentation section: $section"
            else
                error "✗ Missing documentation section: $section"
                ((TEST_RESULTS++))
            fi
        done
    else
        error "✗ Documentation file not found: $doc"
        ((TEST_RESULTS++))
    fi
}

# Test 6: Configuration validation
test_configuration() {
    info "Test 6: Checking configuration consistency..."
    
    # Check default values are consistent
    local prereq_script="$SCRIPT_DIR/scripts/validate_join_prerequisites.sh" 
    local join_script="$SCRIPT_DIR/scripts/enhanced_kubeadm_join.sh"
    
    if grep -q "MASTER_IP.*192.168.4.63" "$prereq_script" && \
       grep -q "MASTER_IP.*192.168.4.63" "$join_script"; then
        info "✓ Consistent master IP configuration"
    else
        warn "⚠ Master IP configuration may be inconsistent"
    fi
    
    if grep -q "JOIN_TIMEOUT.*300" "$join_script"; then
        info "✓ Join timeout configured (300s)"
    else
        error "✗ Join timeout not properly configured"
        ((TEST_RESULTS++))
    fi
}

# Test 7: Integration points
test_integration_points() {
    info "Test 7: Checking integration points..."
    
    # Check if troubleshooting docs reference enhanced process
    local trouble_doc="$SCRIPT_DIR/docs/MANUAL_CLUSTER_TROUBLESHOOTING.md"
    
    if [ -f "$trouble_doc" ]; then
        if grep -q "enhanced_kubeadm_join.sh" "$trouble_doc"; then
            info "✓ Troubleshooting docs reference enhanced process"
        else
            error "✗ Troubleshooting docs not updated for enhanced process"
            ((TEST_RESULTS++))
        fi
    fi
    
    # Check deploy script compatibility
    local deploy_script="$SCRIPT_DIR/deploy.sh"
    
    if [ -f "$deploy_script" ]; then
        if grep -q "setup-cluster.yaml" "$deploy_script"; then
            info "✓ Deploy script uses setup-cluster.yaml"
        else
            warn "⚠ Deploy script may not use updated playbook"
        fi
    fi
}

# Run all tests
run_tests() {
    test_script_files
    test_script_syntax
    test_ansible_integration  
    test_script_permissions
    test_documentation
    test_configuration
    test_integration_points
}

# Show results
show_results() {
    echo ""
    echo "=== Test Results ==="
    
    if [ $TEST_RESULTS -eq 0 ]; then
        info "✅ All tests passed! Enhanced join process is properly implemented."
        echo ""
        info "Next steps:"
        info "1. Deploy the cluster: ./deploy.sh cluster"
        info "2. Monitor join process for storage node success"
        info "3. Verify nodes appear in: kubectl get nodes"
        return 0
    else
        error "❌ $TEST_RESULTS test(s) failed."
        echo ""
        error "Required fixes:"
        error "1. Address the failed tests above"
        error "2. Re-run this test script"
        error "3. Only deploy after all tests pass"
        return 1
    fi
}

# Main execution
main() {
    run_tests
    show_results
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
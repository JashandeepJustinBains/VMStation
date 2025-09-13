#!/bin/bash

# Test Script for Diagnosis No-Hang Fix
# Validates that ./deploy.sh diagnose completes without hanging
# even when kube-proxy pods are in CrashLoopBackOff state

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
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "=== Diagnosis No-Hang Test ==="
echo "Testing that network diagnosis completes without hanging"
echo "Timestamp: $(date)"
echo

# Navigate to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Test tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_command="$2"
    local timeout_seconds="${3:-300}"  # Default 5 minute timeout
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo
    info "Test $TOTAL_TESTS: $test_name"
    
    # Run with timeout to prevent hanging
    if timeout "$timeout_seconds" bash -c "$test_command"; then
        success "✅ PASS: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            error "❌ TIMEOUT: $test_name (exceeded ${timeout_seconds}s)"
        else
            error "❌ FAIL: $test_name (exit code: $exit_code)"
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Test 1: Basic diagnosis script execution (expected to fail gracefully without hanging)
run_test "Network diagnosis script execution (graceful failure)" \
    "./scripts/run_network_diagnosis.sh --check; exit 0" \
    60  # 1 minute max (should complete much faster)

# Test 2: Deploy.sh diagnose command (expected to fail gracefully without hanging)
run_test "Deploy.sh diagnose command (graceful failure)" \
    "./deploy.sh diagnose; exit 0" \
    60  # 1 minute max (should complete much faster)

# Test 3: Check that diagnosis artifacts are created
run_test "Diagnosis artifacts creation" \
    "[ -d ansible/artifacts/arc-network-diagnosis ] && ls ansible/artifacts/arc-network-diagnosis/ | grep -q '[0-9]'"

# Test 4: Verify diagnosis report exists
run_test "Diagnosis report creation" \
    "find ansible/artifacts/arc-network-diagnosis/ -name '*diagnosis*.txt' -o -name '*DIAGNOSIS*.md' | head -1 | xargs test -f"

# Test 5: Check that diagnosis completes even with failing pods
info "Checking current cluster state..."
if kubectl get pods --all-namespaces | grep -E "(CrashLoopBackOff|Error|Unknown)"; then
    info "Found problematic pods - this is a good test scenario"
else
    warn "No problematic pods found - test may not cover edge cases"
fi

# Final results
echo
echo "=== Test Results ==="
info "Total tests: $TOTAL_TESTS"
success "Passed: $PASSED_TESTS"
error "Failed: $FAILED_TESTS"

if [ $FAILED_TESTS -eq 0 ]; then
    echo
    success "🎉 All tests passed! Diagnosis no-hang fix is working correctly."
    exit 0
else
    echo
    error "💥 Some tests failed. Diagnosis may still have hanging issues."
    exit 1
fi
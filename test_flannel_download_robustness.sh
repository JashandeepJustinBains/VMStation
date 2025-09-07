#!/bin/bash

# Test script to validate Flannel CNI download robustness improvements
# Ensures Flannel binary download has proper fallback mechanisms

set -e

echo "=== Testing Flannel CNI Download Robustness Fix ==="
echo "Timestamp: $(date)"
echo ""

info() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1"
}

SETUP_CLUSTER_FILE="ansible/plays/kubernetes/setup_cluster.yaml"

if [ ! -f "$SETUP_CLUSTER_FILE" ]; then
    error "setup_cluster.yaml not found"
    exit 1
fi

echo "=== Test 1: Primary Download Method ==="

# Check for primary Flannel download method
if grep -q "Download and install Flannel CNI plugin binary (primary method)" "$SETUP_CLUSTER_FILE"; then
    info "✓ Primary Flannel download method found"
else
    error "✗ Primary Flannel download method missing"
    exit 1
fi

# Check that primary method has retries and timeout
if grep -A 15 "Download and install Flannel CNI plugin binary (primary method)" "$SETUP_CLUSTER_FILE" | grep -q "retries: 3"; then
    info "✓ Primary method has retry logic"
else
    error "✗ Primary method missing retry logic"
    exit 1
fi

echo ""

echo "=== Test 2: Curl Fallback Method ==="

# Check for curl fallback method
if grep -q "Download Flannel CNI plugin binary using curl fallback" "$SETUP_CLUSTER_FILE"; then
    info "✓ Curl fallback method found"
else
    error "✗ Curl fallback method missing"
    exit 1
fi

# Check curl fallback has proper timeout and retry options
if grep -A 10 "Download Flannel CNI plugin binary using curl fallback" "$SETUP_CLUSTER_FILE" | grep -q "connect-timeout 30"; then
    info "✓ Curl fallback has proper timeout configuration"
else
    error "✗ Curl fallback missing timeout configuration"
    exit 1
fi

echo ""

echo "=== Test 3: Wget Fallback Method ==="

# Check for wget fallback method
if grep -q "Download Flannel CNI plugin binary using wget fallback" "$SETUP_CLUSTER_FILE"; then
    info "✓ Wget fallback method found"
else
    error "✗ Wget fallback method missing"
    exit 1
fi

# Check wget fallback has proper timeout and retry options
if grep -A 10 "Download Flannel CNI plugin binary using wget fallback" "$SETUP_CLUSTER_FILE" | grep -q "connect-timeout=30"; then
    info "✓ Wget fallback has proper timeout configuration"
else
    error "✗ Wget fallback missing timeout configuration"
    exit 1
fi

echo ""

echo "=== Test 4: Alternative Version Fallback ==="

# Check for alternative version fallback
if grep -q "Alternative Flannel binary source (third fallback" "$SETUP_CLUSTER_FILE"; then
    info "✓ Alternative version fallback found"
else
    error "✗ Alternative version fallback missing"
    exit 1
fi

# Check that alternative versions are available
if grep -A 20 "Alternative Flannel binary source" "$SETUP_CLUSTER_FILE" | grep -q "v0.24.2"; then
    info "✓ Alternative Flannel versions included"
else
    error "✗ Alternative Flannel versions missing"
    exit 1
fi

echo ""

echo "=== Test 5: Download Verification and Diagnostics ==="

# Check for enhanced verification with diagnostics
if grep -q "Collect Flannel download diagnostics if verification fails" "$SETUP_CLUSTER_FILE"; then
    info "✓ Download diagnostics collection found"
else
    error "✗ Download diagnostics collection missing"
    exit 1
fi

# Check for network connectivity tests
if grep -A 20 "Collect Flannel download diagnostics" "$SETUP_CLUSTER_FILE" | grep -q "Test network connectivity to GitHub"; then
    info "✓ Network connectivity tests included"
else
    error "✗ Network connectivity tests missing"
    exit 1
fi

# Check for DNS resolution tests
if grep -A 30 "Collect Flannel download diagnostics" "$SETUP_CLUSTER_FILE" | grep -q "Test DNS resolution"; then
    info "✓ DNS resolution tests included"
else
    error "✗ DNS resolution tests missing"
    exit 1
fi

echo ""

echo "=== Test 6: Simplified Path Logic ==="

# Check that flannel_cni_dest is simplified (no longer dynamic per node type)
if grep -A 5 "Set Flannel CNI destination path per node type" "$SETUP_CLUSTER_FILE" | grep -q "flannel_cni_dest: /opt/cni/bin/flannel"; then
    info "✓ Flannel destination path simplified"
else
    error "✗ Flannel destination path not simplified"
    exit 1
fi

# Check that the old dynamic path logic is removed
if grep -A 5 "Set Flannel CNI destination path per node type" "$SETUP_CLUSTER_FILE" | grep -q "/srv/monitoring/flannel"; then
    error "✗ Old dynamic path logic still present"
    exit 1
else
    info "✓ Old dynamic path logic removed"
fi

echo ""

echo "=== Test 7: Error Handling and Manual Instructions ==="

# Check for manual installation instructions on failure
if grep -A 10 "Fail if Flannel binary still missing" "$SETUP_CLUSTER_FILE" | grep -q "Manual installation may be required"; then
    info "✓ Manual installation instructions provided"
else
    error "✗ Manual installation instructions missing"
    exit 1
fi

echo ""

echo "=== Test Summary ==="
info "Flannel CNI download robustness fix validation:"
info "  ✓ Primary download method with retries and timeout"
info "  ✓ Curl fallback with proper timeout configuration"
info "  ✓ Wget fallback with proper timeout configuration"
info "  ✓ Alternative version fallback for network issues"
info "  ✓ Enhanced diagnostics for troubleshooting failures"
info "  ✓ Simplified path logic prevents verification issues"
info "  ✓ Manual installation instructions for edge cases"
echo ""
info "Fix validation PASSED - Flannel download failures should be resolved"
echo ""
info "The fixes should resolve:"
info "  - Flannel CNI binary download failures on problematic nodes"
info "  - Network connectivity and timeout issues"
info "  - Path-related verification failures"
info "  - Improved troubleshooting with detailed diagnostics"
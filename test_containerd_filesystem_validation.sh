#!/bin/bash

# Test Containerd Filesystem Validation Enhancement
# Validates the strengthened validation logic in fix_containerd_filesystem function

set -e

# Color codes  
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=== Testing Containerd Filesystem Validation Enhancement ==="
echo "Timestamp: $(date)"
echo ""

SCRIPT_FILE="scripts/enhanced_kubeadm_join.sh"

if [ ! -f "$SCRIPT_FILE" ]; then
    error "✗ FAIL: $SCRIPT_FILE not found"
    exit 1
fi

# Test 1: Check for strengthened validation logic
echo "Test 1: Strengthened containerd filesystem validation"
echo "Checking that the validation requires actual imageFilesystem capacity detection..."

if grep -A20 "Verify containerd image filesystem is properly initialized" "$SCRIPT_FILE" | \
   grep -E "(imageFilesystem.*capacityBytes|capacityBytes.*imageFilesystem)" >/dev/null; then
    info "✓ PASS: Enhanced validation checks for actual filesystem capacity"
else
    error "✗ FAIL: Missing enhanced validation for filesystem capacity"
    exit 1
fi

# Test 2: Check for improved initialization commands
echo ""
echo "Test 2: Enhanced containerd initialization sequence"
echo "Checking for more robust filesystem initialization commands..."

if grep -A10 "Force containerd to detect and initialize image filesystem capacity" "$SCRIPT_FILE" | \
   grep -E "(df.*containerd|du.*containerd)" >/dev/null; then
    info "✓ PASS: Filesystem capacity verification commands found"
else
    error "✗ FAIL: Missing filesystem capacity verification commands"
    exit 1
fi

# Test 3: Check for stronger error detection
echo ""
echo "Test 3: Improved error detection logic"
echo "Checking that validation fails if imageFilesystem capacity is not properly detected..."

if grep -A30 "Test both ctr command and CRI status" "$SCRIPT_FILE" | \
   grep -E "(capacityBytes.*0|invalid.*capacity)" >/dev/null; then
    info "✓ PASS: Zero capacity detection logic found"
else
    error "✗ FAIL: Missing zero capacity detection logic" 
    exit 1
fi

# Test 4: Check for enhanced retry logic
echo ""
echo "Test 4: Enhanced retry logic with filesystem verification"
echo "Checking that retries include filesystem capacity verification..."

if grep -A15 "Retry the initialization commands" "$SCRIPT_FILE" | \
   grep -E "(df.*var/lib/containerd|filesystem.*capacity)" >/dev/null; then
    info "✓ PASS: Retry logic includes filesystem verification"
else
    error "✗ FAIL: Missing filesystem verification in retry logic"
    exit 1
fi

echo ""
echo "=== All Tests Passed! ==="
echo ""
echo "Containerd Filesystem Validation Enhancement Summary:"
echo "- ✓ Enhanced validation checks for actual filesystem capacity"
echo "- ✓ Filesystem capacity verification commands added"
echo "- ✓ Zero capacity detection logic implemented"
echo "- ✓ Retry logic includes filesystem verification"
echo ""
echo "This enhancement ensures containerd filesystem initialization is"
echo "properly validated before declaring success, preventing false positives"
echo "that were causing persistent 'invalid capacity 0' errors."
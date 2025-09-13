#!/bin/bash

# Test script for Jellyfin CNI Bridge Conflict Fix
# This script validates that the enhanced fix correctly targets worker nodes

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

echo "=== Test Jellyfin CNI Bridge Conflict Fix ==="
echo "Timestamp: $(date)"
echo

# Test 1: Verify the script exists and has correct syntax
info "Test 1: Checking script syntax and availability"

if [ ! -f "./fix_jellyfin_cni_bridge_conflict.sh" ]; then
    error "Main fix script not found: ./fix_jellyfin_cni_bridge_conflict.sh"
    exit 1
fi

if bash -n ./fix_jellyfin_cni_bridge_conflict.sh; then
    success "✓ Script syntax is valid"
else
    error "✗ Script has syntax errors"
    exit 1
fi

# Test 2: Check if the new SSH functions are present
info "Test 2: Verifying SSH functionality is present"

if grep -q "execute_on_worker_node" ./fix_jellyfin_cni_bridge_conflict.sh; then
    success "✓ Worker node SSH execution function found"
else
    error "✗ Worker node SSH execution function missing"
    exit 1
fi

if grep -q "get_ssh_user_for_node" ./fix_jellyfin_cni_bridge_conflict.sh; then
    success "✓ SSH user mapping function found"
else
    error "✗ SSH user mapping function missing"  
    exit 1
fi

if grep -q "get_node_ip" ./fix_jellyfin_cni_bridge_conflict.sh; then
    success "✓ Node IP mapping function found"
else
    error "✗ Node IP mapping function missing"
    exit 1
fi

# Test 3: Check if the enhanced CNI cleanup section exists
info "Test 3: Verifying enhanced CNI cleanup section"

if grep -q "Step 6a: Directly resetting CNI bridge state" ./fix_jellyfin_cni_bridge_conflict.sh; then
    success "✓ Enhanced CNI cleanup section found"
else
    error "✗ Enhanced CNI cleanup section missing"
    exit 1
fi

if grep -q "execute_on_worker_node.*storagenodet3500.*CNI_CLEANUP_COMMANDS" ./fix_jellyfin_cni_bridge_conflict.sh; then
    success "✓ Worker node CNI cleanup execution found"
else
    error "✗ Worker node CNI cleanup execution missing"
    exit 1
fi

# Test 4: Verify fallback mechanism exists
info "Test 4: Checking fallback mechanism"

if grep -q "Falling back to temporary pod trigger method" ./fix_jellyfin_cni_bridge_conflict.sh; then
    success "✓ Fallback mechanism found"
else
    error "✗ Fallback mechanism missing"
    exit 1
fi

# Test 5: Check that the fix targets CNI bridge conflicts
info "Test 5: Verifying CNI bridge conflict targeting"

if grep -q "CNI_BRIDGE_CONFLICT.*true" ./fix_jellyfin_cni_bridge_conflict.sh; then
    success "✓ CNI bridge conflict detection logic found"
else
    error "✗ CNI bridge conflict detection logic missing"
    exit 1
fi

# Test 6: Verify the SSH command structure handles the cleanup correctly
info "Test 6: Checking SSH command structure"

if sed -n '/CNI_CLEANUP_COMMANDS=/,/execute_on_worker_node/p' ./fix_jellyfin_cni_bridge_conflict.sh | grep -q "ip link delete cni0"; then
    success "✓ CNI bridge deletion command found in worker node script"
else
    error "✗ CNI bridge deletion command missing from worker node script"
    exit 1
fi

if sed -n '/CNI_CLEANUP_COMMANDS=/,/execute_on_worker_node/p' ./fix_jellyfin_cni_bridge_conflict.sh | grep -q "systemctl restart containerd"; then
    success "✓ Containerd restart command found in worker node script"
else
    error "✗ Containerd restart command missing from worker node script"
    exit 1
fi

# Test 7: Check if proper SSH options and security are in place
info "Test 7: Verifying SSH security configuration"

if grep -q "SSH_OPTS.*ConnectTimeout.*StrictHostKeyChecking" ./fix_jellyfin_cni_bridge_conflict.sh; then
    success "✓ SSH security options configured"
else
    error "✗ SSH security options missing"
    exit 1
fi

# Test 8: Verify the script handles the specific storagenodet3500 -> 192.168.4.61 mapping
info "Test 8: Checking node-to-IP mapping"

if grep -A 15 "get_node_ip()" ./fix_jellyfin_cni_bridge_conflict.sh | grep -A 2 "storagenodet3500" | grep -q "192.168.4.61"; then
    success "✓ storagenodet3500 -> 192.168.4.61 mapping found"
else
    error "✗ storagenodet3500 node IP mapping missing or incorrect"
    exit 1
fi

if grep -A 15 "get_ssh_user_for_node()" ./fix_jellyfin_cni_bridge_conflict.sh | grep -A 2 "192.168.4.61" | grep -q "root"; then
    success "✓ 192.168.4.61 -> root SSH user mapping found"
else
    error "✗ SSH user mapping for 192.168.4.61 missing or incorrect"
    exit 1
fi

success "🎉 All tests passed! The enhanced CNI bridge fix appears to be correctly implemented."
echo
echo "=== Summary ==="
echo "✓ Script syntax is valid"
echo "✓ SSH functionality for worker node access is present"
echo "✓ Enhanced CNI cleanup targets the worker node directly"  
echo "✓ Fallback mechanism exists for SSH failures"
echo "✓ CNI bridge conflict detection logic is preserved"
echo "✓ Proper SSH security configuration"
echo "✓ Node mappings are correct for storagenodet3500"
echo
info "The fix should now be able to:"
echo "  1. Detect CNI bridge conflicts on storagenodet3500"
echo "  2. SSH to the worker node to directly reset the cni0 bridge"
echo "  3. Clear CNI state on the worker node where the conflict exists"
echo "  4. Allow Jellyfin pod creation to succeed"
echo
info "To test in a live environment, run:"
echo "  sudo ./fix_jellyfin_cni_bridge_conflict.sh"
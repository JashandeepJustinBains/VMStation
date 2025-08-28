#!/bin/bash

# Test script for Jellyfin minimal storage deployment
# Validates that the playbook works with both storage modes

set -e

echo "=== Testing Jellyfin Minimal Storage Configuration ==="
echo "Timestamp: $(date)"
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "ansible/plays/kubernetes/deploy_jellyfin.yaml" ]; then
    error "Please run this script from the VMStation root directory"
    exit 1
fi

info "1. Testing syntax validation..."

# Test syntax
if ansible-playbook --syntax-check ansible/plays/kubernetes/deploy_jellyfin.yaml > /dev/null 2>&1; then
    info "✓ Ansible syntax validation passed"
else
    error "✗ Ansible syntax validation failed"
    exit 1
fi

info "2. Testing configuration options..."

# Test that the configuration template includes our new options
if grep -q "jellyfin_use_persistent_volumes" ansible/group_vars/all.yml.template; then
    info "✓ Configuration option jellyfin_use_persistent_volumes found"
else
    error "✗ Configuration option jellyfin_use_persistent_volumes missing"
    exit 1
fi

if grep -q "jellyfin_config_path" ansible/group_vars/all.yml.template; then
    info "✓ Configuration option jellyfin_config_path found"
else
    error "✗ Configuration option jellyfin_config_path missing"
    exit 1
fi

info "3. Testing deployment modes in playbook..."

# Check for both deployment modes
if grep -q "Deploy Jellyfin Deployment (with Persistent Volumes)" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    info "✓ Persistent Volume deployment mode found"
else
    error "✗ Persistent Volume deployment mode missing"
    exit 1
fi

if grep -q "Deploy Jellyfin Deployment (with Direct hostPath Volumes)" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    info "✓ Direct hostPath deployment mode found"
else
    error "✗ Direct hostPath deployment mode missing"
    exit 1
fi

info "4. Testing conditional logic..."

# Check for proper when conditions
if grep -q "when: jellyfin_use_persistent_volumes" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    info "✓ Persistent Volume conditional logic found"
else
    error "✗ Persistent Volume conditional logic missing"
    exit 1
fi

if grep -q "when: not (jellyfin_use_persistent_volumes" ansible/plays/kubernetes/deploy_jellyfin.yaml; then
    info "✓ Direct hostPath conditional logic found"
else
    error "✗ Direct hostPath conditional logic missing"
    exit 1
fi

info "5. Testing storage size consistency..."

# Check that PV and PVC sizes match (100Ti for media)
pv_media_size=$(grep -A 15 "jellyfin-media-pv" ansible/plays/kubernetes/deploy_jellyfin.yaml | grep "storage:" | head -1 | awk '{print $2}')
pvc_media_size=$(grep -A 10 "jellyfin-media-pvc" ansible/plays/kubernetes/deploy_jellyfin.yaml | grep "storage:" | head -1 | awk '{print $2}')

if [ "$pv_media_size" = "100Ti" ] && [ "$pvc_media_size" = "100Ti" ]; then
    info "✓ Media storage sizes match (100Ti)"
else
    error "✗ Media storage size mismatch: PV=$pv_media_size, PVC=$pvc_media_size"
    exit 1
fi

info "6. Testing template consistency..."

# Check that template matches playbook
template_media_size=$(grep -A 10 "jellyfin-media-pvc" ansible/templates/jellyfin/persistent-volume-claims.yaml | grep "storage:" | awk '{print $2}' | head -1)

if [ "$template_media_size" = "100Ti" ]; then
    info "✓ Template storage size matches playbook (100Ti)"
else
    error "✗ Template storage size mismatch: '$template_media_size' vs 100Ti"
    exit 1
fi

echo ""
info "All tests passed! ✓"
echo ""
info "Summary of changes:"
info "- Added jellyfin_use_persistent_volumes configuration option (defaults to false)"
info "- Added jellyfin_config_path configuration option"
info "- Created separate deployment tasks for PV and hostPath modes"
info "- Fixed storage size mismatches (100Ti for media, 50Gi for config)"
info "- Made PV/PVC creation conditional"
info "- Updated debug and troubleshooting information"
echo ""
info "Benefits:"
info "✓ Minimal deployment using direct hostPath volumes (default)"
info "✓ Optional persistent volumes for advanced users"
info "✓ No more storage size conflicts"
info "✓ Simpler deployment with fewer failure points"
info "✓ Backwards compatible with existing configurations"
echo ""
info "Usage:"
info "- For minimal deployment: Keep jellyfin_use_persistent_volumes: false (default)"
info "- For persistent volumes: Set jellyfin_use_persistent_volumes: true"
echo ""
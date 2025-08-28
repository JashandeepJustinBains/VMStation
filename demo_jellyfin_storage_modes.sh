#!/bin/bash

# Demo script showing how to deploy Jellyfin in minimal vs advanced mode
# This script demonstrates the configuration options but doesn't actually deploy

set -e

echo "=== Jellyfin Storage Mode Configuration Demo ==="
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

demo() {
    echo -e "${BLUE}[DEMO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[CONFIG]${NC} $1"
}

demo "This demonstrates the two Jellyfin deployment modes available:"
echo ""

echo "1. MINIMAL DEPLOYMENT (Default - Recommended)"
echo "=============================================="
warn "jellyfin_use_persistent_volumes: false"
warn "jellyfin_media_path: /srv/media"
warn "jellyfin_config_path: /var/lib/jellyfin"
echo ""
info "Benefits:"
info "  ✓ Simple setup - no PV/PVC complexity"
info "  ✓ Faster deployment"
info "  ✓ Fewer failure points"
info "  ✓ No storage size conflicts"
info "  ✓ Direct volume mounting"
echo ""
info "Use case: Simple home media server, single-node storage"
echo ""

echo "2. ADVANCED DEPLOYMENT (Optional)"
echo "================================="
warn "jellyfin_use_persistent_volumes: true"
warn "jellyfin_media_path: /srv/media"
warn "jellyfin_config_path: /var/lib/jellyfin"
echo ""
info "Benefits:"
info "  ✓ Kubernetes-native storage management"
info "  ✓ Dynamic provisioning support"
info "  ✓ Better portability between nodes"
info "  ✓ Volume lifecycle management"
echo ""
info "Use case: Complex clusters, dynamic storage, multiple storage classes"
echo ""

echo "CONFIGURATION:"
echo "=============="
demo "Edit ansible/group_vars/all.yml with your preferred settings:"
echo ""
echo "For minimal deployment (default):"
echo "  jellyfin_use_persistent_volumes: false"
echo ""
echo "For advanced deployment:"  
echo "  jellyfin_use_persistent_volumes: true"
echo ""

demo "Example files provided:"
info "  • example_minimal_jellyfin_config.yml - Minimal deployment example"
info "  • ansible/group_vars/all.yml.template - Full template with both options"
echo ""

demo "Validation:"
info "  • Run: ./test_jellyfin_minimal_storage.sh"
info "  • Run: ./validate_jellyfin_pv_fix.sh"
echo ""

demo "The user's original error is now fixed:"
info "  'PersistentVolumeClaim \"jellyfin-media-pvc\" is invalid: spec.resources.requests.storage: Forbidden: field can not be less than previous value'"
echo ""
info "This error occurred because:"
info "  • Template defined 100Ti media storage"
info "  • Playbook requested 2Ti media storage" 
info "  • Kubernetes doesn't allow reducing PVC storage size"
echo ""
info "Solution implemented:"
info "  • Fixed storage size mismatch (both now use 100Ti)"
info "  • Added minimal deployment option (no PVC needed)"
info "  • Made storage mode configurable"
echo ""

demo "Result: Users get a working Jellyfin deployment with minimal complexity!"
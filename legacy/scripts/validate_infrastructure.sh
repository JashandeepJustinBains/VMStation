#!/bin/bash

# VMStation Infrastructure Validation Script (archived)
# Validates both Kubernetes and legacy Podman setups

set -e

echo "=== VMStation Infrastructure Validation ==="
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

# Detect infrastructure mode
INFRASTRUCTURE_MODE="unknown"
if command -v kubectl &> /dev/null && kubectl cluster-info &> /dev/null; then
    INFRASTRUCTURE_MODE="kubernetes"
elif command -v podman &> /dev/null && podman pod exists monitoring_pod 2>/dev/null; then
    INFRASTRUCTURE_MODE="podman"
elif [ -f "ansible/group_vars/all.yml" ]; then
    if grep -q "infrastructure_mode:.*kubernetes" ansible/group_vars/all.yml; then
        INFRASTRUCTURE_MODE="kubernetes"
    elif grep -q "infrastructure_mode:.*podman" ansible/group_vars/all.yml; then
        INFRASTRUCTURE_MODE="podman"
    fi
fi

info "Detected infrastructure mode: $INFRASTRUCTURE_MODE"
echo ""

case "$INFRASTRUCTURE_MODE" in
    "kubernetes")
        info "Validating Kubernetes infrastructure..."
        if [ -f "scripts/validate_k8s_monitoring.sh" ]; then
            ./scripts/validate_k8s_monitoring.sh
        else
            error "Kubernetes validation script not found"
            exit 1
        fi
        ;;
    "podman")
        warn "Validating legacy Podman infrastructure..."
        warn "Consider migrating to Kubernetes for better reliability"
        if [ -f "scripts/validate_monitoring.sh" ]; then
            ./scripts/validate_monitoring.sh
        else
            error "Podman validation script not found"
            exit 1
        fi
        ;;
    "unknown")
        error "Cannot detect infrastructure mode"
        error "Please ensure either Kubernetes or Podman is running"
        echo ""
        info "To check manually:"
        info "- Kubernetes: kubectl cluster-info"
        info "- Podman: podman pod ls"
        exit 1
        ;;
esac

echo ""
info "Validation completed for mode: $INFRASTRUCTURE_MODE"

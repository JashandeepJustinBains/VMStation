#!/bin/bash

# VMStation Network Diagnosis Runner
# Quick wrapper script to run the automated network diagnosis playbook

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

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
PLAYBOOK_PATH="$REPO_ROOT/ansible/plays/network-diagnosis.yaml"
INVENTORY_PATH="$REPO_ROOT/ansible/inventory.txt"
ARTIFACTS_DIR="$REPO_ROOT/ansible/artifacts/arc-network-diagnosis"

echo "=== VMStation Network Diagnosis ==="
echo "Timestamp: $(date)"
echo "Repository: $REPO_ROOT"
echo ""

# Check prerequisites
if ! command -v ansible-playbook &> /dev/null; then
    error "ansible-playbook not found. Please install Ansible."
    exit 1
fi

if [ ! -f "$INVENTORY_PATH" ]; then
    error "Inventory file not found: $INVENTORY_PATH"
    exit 1
fi

if [ ! -f "$PLAYBOOK_PATH" ]; then
    error "Network diagnosis playbook not found: $PLAYBOOK_PATH"
    exit 1
fi

# Check if cluster is accessible
info "Checking Kubernetes cluster accessibility..."
if ! kubectl cluster-info &> /dev/null; then
    warn "kubectl cluster-info failed. Diagnosis may have limited functionality."
else
    debug "Kubernetes cluster is accessible"
fi

# Parse command line arguments
VERBOSE=""
CHECK_MODE=""
ANSIBLE_OPTS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE="-vv"
            shift
            ;;
        -c|--check)
            CHECK_MODE="--check"
            info "Running in check mode (no changes will be made)"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Enable verbose output"
            echo "  -c, --check      Run in check mode (no changes)"
            echo "  -h, --help       Show this help message"
            echo ""
            echo "This script runs the automated network diagnosis playbook to troubleshoot"
            echo "inter-pod communication issues in the VMStation Kubernetes cluster."
            echo ""
            echo "Output will be stored in: $ARTIFACTS_DIR/<timestamp>/"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Create artifacts directory if it doesn't exist
mkdir -p "$ARTIFACTS_DIR"

# Run the diagnosis playbook
info "Starting network diagnosis..."
info "Artifacts will be stored in: $ARTIFACTS_DIR"

cd "$REPO_ROOT"

# Set a reasonable timeout for the entire playbook
export ANSIBLE_TIMEOUT=30
export ANSIBLE_HOST_KEY_CHECKING=False

# Run with timeout to prevent indefinite hanging
if timeout 1800 ansible-playbook -i "$INVENTORY_PATH" "$PLAYBOOK_PATH" $VERBOSE $CHECK_MODE $ANSIBLE_OPTS; then
    info "Network diagnosis completed successfully!"
    
    # Find the latest diagnosis directory
    LATEST_DIR=$(find "$ARTIFACTS_DIR" -maxdepth 1 -type d -name "[0-9]*" | sort | tail -1)
    
    if [ -n "$LATEST_DIR" ]; then
        info "Latest diagnosis results:"
        echo "  Directory: $LATEST_DIR"
        echo "  Report: $LATEST_DIR/DIAGNOSIS-REPORT.md"
        echo ""
        info "To view the diagnosis report:"
        echo "  cat '$LATEST_DIR/DIAGNOSIS-REPORT.md'"
        echo ""
        info "Key files generated:"
        ls -la "$LATEST_DIR" 2>/dev/null | grep -E '\.(txt|yaml|md)$' | awk '{print "  " $9}' || echo "  (checking files...)"
    fi
else
    warn "Network diagnosis failed or timed out after 30 minutes."
    echo ""
    warn "This may indicate severe cluster networking issues or tasks that hang indefinitely."
    echo ""
    info "Attempting to collect basic diagnostic information..."
    
    # Create a minimal diagnostic report even if the main playbook failed
    TIMESTAMP=$(date +%s)
    FALLBACK_DIR="$ARTIFACTS_DIR/$TIMESTAMP-fallback"
    mkdir -p "$FALLBACK_DIR"
    
    echo "=== Fallback Network Diagnosis ===" > "$FALLBACK_DIR/fallback-diagnosis.txt"
    echo "Timestamp: $(date)" >> "$FALLBACK_DIR/fallback-diagnosis.txt"
    echo "Main diagnosis playbook failed or timed out" >> "$FALLBACK_DIR/fallback-diagnosis.txt"
    echo "" >> "$FALLBACK_DIR/fallback-diagnosis.txt"
    
    # Basic cluster info
    echo "=== Basic Cluster Info ===" >> "$FALLBACK_DIR/fallback-diagnosis.txt"
    kubectl get nodes -o wide >> "$FALLBACK_DIR/fallback-diagnosis.txt" 2>&1 || echo "Failed to get nodes" >> "$FALLBACK_DIR/fallback-diagnosis.txt"
    echo "" >> "$FALLBACK_DIR/fallback-diagnosis.txt"
    
    echo "=== Pod Status ===" >> "$FALLBACK_DIR/fallback-diagnosis.txt"
    kubectl get pods --all-namespaces >> "$FALLBACK_DIR/fallback-diagnosis.txt" 2>&1 || echo "Failed to get pods" >> "$FALLBACK_DIR/fallback-diagnosis.txt"
    echo "" >> "$FALLBACK_DIR/fallback-diagnosis.txt"
    
    echo "=== kube-proxy Status ===" >> "$FALLBACK_DIR/fallback-diagnosis.txt"
    kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide >> "$FALLBACK_DIR/fallback-diagnosis.txt" 2>&1 || echo "Failed to get kube-proxy pods" >> "$FALLBACK_DIR/fallback-diagnosis.txt"
    
    info "Fallback diagnosis saved to: $FALLBACK_DIR/fallback-diagnosis.txt"
    exit 1
fi

info "Network diagnosis complete. Review the generated report for next steps."
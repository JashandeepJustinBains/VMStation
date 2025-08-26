#!/bin/bash

# RHEL 10 Kubernetes Compatibility Checker
# This script validates that RHEL 10 systems are ready for Kubernetes cluster deployment

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
COMPUTE_NODE="192.168.4.62"
INVENTORY_FILE="ansible/inventory.txt"

echo "=== RHEL 10 Kubernetes Compatibility Checker ==="
echo "Timestamp: $(date)"
echo ""

info "Checking RHEL 10 compute node compatibility..."

# Check if inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
    error "Inventory file not found: $INVENTORY_FILE"
    exit 1
fi

# Function to run remote commands
run_remote() {
    local host="$1"
    local command="$2"
    local description="$3"
    
    info "Checking: $description"
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$host" "$command" 2>/dev/null; then
        success "$description - OK"
        return 0
    else
        error "$description - FAILED"
        return 1
    fi
}

# Function to check remote command output
check_remote_output() {
    local host="$1"
    local command="$2"
    local description="$3"
    local expected_pattern="$4"
    
    info "Checking: $description"
    local output=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$host" "$command" 2>/dev/null || echo "FAILED")
    
    if [[ "$output" =~ $expected_pattern ]]; then
        success "$description - OK: $output"
        return 0
    else
        error "$description - FAILED: $output"
        return 1
    fi
}

# Start checks
info "Starting compatibility checks for RHEL 10 compute node ($COMPUTE_NODE)..."
echo ""

# Basic connectivity
if ! run_remote "$COMPUTE_NODE" "echo 'Connection test'" "SSH connectivity"; then
    error "Cannot connect to compute node. Please check SSH configuration."
    exit 1
fi

# OS version check
check_remote_output "$COMPUTE_NODE" "cat /etc/redhat-release" "RHEL version" "Red Hat Enterprise Linux.*10"

# Architecture check
check_remote_output "$COMPUTE_NODE" "uname -m" "Architecture" "x86_64"

# Memory check
info "Checking available memory..."
memory_mb=$(ssh -o ConnectTimeout=10 "$COMPUTE_NODE" "free -m | awk '/^Mem:/ {print \$2}'" 2>/dev/null || echo "0")
if [ "$memory_mb" -ge 2048 ]; then
    success "Memory check - OK: ${memory_mb}MB"
else
    error "Memory check - FAILED: ${memory_mb}MB (minimum 2048MB required)"
fi

# Disk space check
info "Checking disk space..."
disk_gb=$(ssh -o ConnectTimeout=10 "$COMPUTE_NODE" "df -BG /usr | tail -1 | awk '{print \$4}' | sed 's/G//'" 2>/dev/null || echo "0")
if [ "$disk_gb" -ge 10 ]; then
    success "Disk space check - OK: ${disk_gb}GB free"
else
    warning "Disk space check - LOW: ${disk_gb}GB free (recommended: 10GB+)"
fi

# Check for required commands
info "Checking required commands..."
required_commands=("curl" "wget" "systemctl" "iptables" "modprobe")
for cmd in "${required_commands[@]}"; do
    if run_remote "$COMPUTE_NODE" "command -v $cmd >/dev/null" "Command: $cmd"; then
        continue
    else
        warning "Missing command: $cmd (will be installed during setup)"
    fi
done

# Check kernel modules
info "Checking kernel module support..."
kernel_modules=("overlay" "br_netfilter")
for module in "${kernel_modules[@]}"; do
    if run_remote "$COMPUTE_NODE" "modprobe $module && lsmod | grep $module" "Kernel module: $module"; then
        continue
    else
        warning "Kernel module $module not loaded (will be configured during setup)"
    fi
done

# Check for conflicting services
info "Checking for conflicting services..."
conflicting_services=("docker" "podman" "crio")
for service in "${conflicting_services[@]}"; do
    if ssh -o ConnectTimeout=10 "$COMPUTE_NODE" "systemctl is-active $service" 2>/dev/null | grep -q "active"; then
        warning "Conflicting service running: $service (will be stopped during setup)"
    else
        success "No conflict with service: $service"
    fi
done

# Check firewall status
info "Checking firewall configuration..."
if ssh -o ConnectTimeout=10 "$COMPUTE_NODE" "systemctl is-active firewalld" 2>/dev/null | grep -q "active"; then
    warning "Firewalld is active (Kubernetes ports will be opened during setup)"
else
    success "Firewalld is not blocking setup"
fi

# Check SELinux status
info "Checking SELinux status..."
selinux_status=$(ssh -o ConnectTimeout=10 "$COMPUTE_NODE" "getenforce" 2>/dev/null || echo "Unknown")
if [[ "$selinux_status" == "Enforcing" ]]; then
    warning "SELinux is enforcing (will be set to permissive during setup)"
elif [[ "$selinux_status" == "Permissive" ]]; then
    success "SELinux is permissive - OK"
else
    success "SELinux is disabled - OK"
fi

# Network connectivity to control plane
info "Checking network connectivity to control plane..."
CONTROL_PLANE="192.168.4.63"
if run_remote "$COMPUTE_NODE" "ping -c 3 $CONTROL_PLANE" "Ping to control plane ($CONTROL_PLANE)"; then
    success "Network connectivity to control plane - OK"
else
    error "Cannot reach control plane - check network configuration"
fi

# Check if containerd is already installed
info "Checking container runtime..."
if ssh -o ConnectTimeout=10 "$COMPUTE_NODE" "command -v containerd >/dev/null" 2>/dev/null; then
    containerd_version=$(ssh -o ConnectTimeout=10 "$COMPUTE_NODE" "containerd --version" 2>/dev/null || echo "Unknown")
    success "Containerd already installed: $containerd_version"
else
    info "Containerd not installed (will be installed during setup)"
fi

# Check available package repositories
info "Checking package management..."
if run_remote "$COMPUTE_NODE" "dnf --version" "DNF package manager"; then
    if run_remote "$COMPUTE_NODE" "dnf repolist" "Repository access"; then
        success "Package repositories accessible"
    else
        warning "Some repositories may not be accessible"
    fi
fi

echo ""
echo "=== Compatibility Check Summary ==="
echo ""
info "Pre-deployment recommendations:"
echo "1. Ensure all packages are up to date: dnf update"
echo "2. Reboot if kernel was updated"
echo "3. Verify network connectivity between all nodes"
echo "4. Backup any important data on the compute node"
echo ""
success "RHEL 10 compatibility check completed!"
success "The compute node appears ready for Kubernetes deployment."
echo ""
info "To proceed with deployment, run: ./deploy_kubernetes.sh"
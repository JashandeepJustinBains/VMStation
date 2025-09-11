#!/bin/bash

# VMStation Comprehensive Worker Node Manual Setup
# This script provides a complete manual installation and configuration of all necessary
# components for worker nodes when the automated Ansible process encounters issues.

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

# Configuration
KUBERNETES_VERSION="1.29"
CNI_PLUGINS_VERSION="v1.3.0"
FLANNEL_CNI_VERSION="v1.7.1-flannel2"

echo "=== VMStation Comprehensive Worker Node Manual Setup ==="
echo "Timestamp: $(date)"
echo "Kubernetes Version: $KUBERNETES_VERSION"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        error "Cannot detect operating system"
        exit 1
    fi
    
    info "Detected OS: $OS $OS_VERSION"
}

# Step 1: System Prerequisites
install_system_prerequisites() {
    info "=== Step 1: Installing System Prerequisites ==="
    
    case $OS in
        ubuntu|debian)
            info "Updating package cache..."
            apt update
            
            info "Installing required system packages..."
            apt install -y apt-transport-https ca-certificates curl gnupg software-properties-common
            ;;
        centos|rhel|fedora)
            info "Installing required system packages..."
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y curl gnupg
            else
                yum install -y curl gnupg
            fi
            ;;
        *)
            error "Unsupported operating system: $OS"
            exit 1
            ;;
    esac
    
    info "✅ System prerequisites installed"
}

# Step 2: Disable swap
disable_swap() {
    info "=== Step 2: Disabling Swap ==="
    
    # Turn off all swap devices
    swapoff -a
    
    # Comment out swap entries in fstab
    if grep -q swap /etc/fstab; then
        info "Commenting out swap entries in /etc/fstab..."
        sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    fi
    
    info "✅ Swap disabled"
}

# Step 3: Configure kernel modules and sysctl
configure_kernel() {
    info "=== Step 3: Configuring Kernel Modules and Sysctl ==="
    
    # Load required kernel modules
    info "Loading kernel modules..."
    modprobe overlay
    modprobe br_netfilter
    
    # Create modules config file
    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
    
    # Configure sysctl parameters
    info "Configuring sysctl parameters..."
    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    
    # Apply sysctl settings
    sysctl --system
    
    info "✅ Kernel configuration complete"
}

# Step 4: Install containerd
install_containerd() {
    info "=== Step 4: Installing and Configuring containerd ==="
    
    case $OS in
        ubuntu|debian)
            # Install containerd
            apt install -y containerd
            ;;
        centos|rhel|fedora)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y containerd
            else
                yum install -y containerd
            fi
            ;;
    esac
    
    # Create containerd configuration directory
    mkdir -p /etc/containerd
    
    # Generate default containerd configuration
    info "Generating containerd configuration..."
    containerd config default > /etc/containerd/config.toml
    
    # Configure systemd cgroup driver
    info "Configuring containerd cgroup driver..."
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    # Create containerd directories
    mkdir -p /var/lib/containerd/{content,metadata,runtime,snapshots}
    mkdir -p /run/containerd
    chown -R root:root /var/lib/containerd
    chmod -R 755 /var/lib/containerd
    
    # Enable and start containerd
    systemctl enable containerd
    systemctl restart containerd
    
    # Wait for containerd to be ready
    info "Waiting for containerd to initialize..."
    sleep 15
    
    # Verify containerd is working
    local retry_count=0
    local max_retries=5
    while [ $retry_count -lt $max_retries ]; do
        if ctr version >/dev/null 2>&1; then
            info "✅ containerd is working"
            break
        else
            warn "containerd not ready yet, waiting... ($((retry_count + 1))/$max_retries)"
            sleep 5
            ((retry_count++))
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "containerd failed to start properly"
        exit 1
    fi
    
    # Initialize containerd namespaces
    info "Initializing containerd namespaces..."
    ctr namespace create k8s.io 2>/dev/null || true
    ctr --namespace k8s.io images ls >/dev/null 2>&1 || true
    
    info "✅ containerd installation complete"
}

# Step 5: Configure crictl
configure_crictl() {
    info "=== Step 5: Configuring crictl ==="
    
    # Create crictl configuration
    cat > /etc/crictl.yaml << EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
    
    # Verify crictl can communicate with containerd
    if crictl version >/dev/null 2>&1; then
        info "✅ crictl configuration successful"
    else
        error "crictl cannot communicate with containerd"
        exit 1
    fi
}

# Step 6: Install Kubernetes packages
install_kubernetes() {
    info "=== Step 6: Installing Kubernetes Packages ==="
    
    case $OS in
        ubuntu|debian)
            # Add Kubernetes GPG key
            info "Adding Kubernetes GPG key..."
            curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key" | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
            
            # Add Kubernetes repository
            info "Adding Kubernetes repository..."
            echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
            
            # Update package cache
            apt update
            
            # Install Kubernetes packages
            info "Installing Kubernetes packages..."
            apt install -y kubelet kubeadm kubectl
            
            # Hold packages
            apt-mark hold kubelet kubeadm kubectl
            ;;
        centos|rhel|fedora)
            # Add Kubernetes repository
            cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/rpm/repodata/repomd.xml.key
EOF
            
            # Install Kubernetes packages
            info "Installing Kubernetes packages..."
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y kubelet kubeadm kubectl
            else
                yum install -y kubelet kubeadm kubectl
            fi
            ;;
    esac
    
    # Verify package installation
    info "Verifying Kubernetes package installation..."
    for cmd in kubelet kubeadm kubectl; do
        if command -v "$cmd" >/dev/null 2>&1; then
            version=$($cmd --version 2>/dev/null | head -1)
            info "✓ $cmd: $version"
        else
            error "$cmd installation failed"
            exit 1
        fi
    done
    
    # Enable kubelet (but don't start it yet - kubeadm will handle that)
    systemctl enable kubelet
    
    # Verify kubelet service unit exists
    if systemctl list-unit-files | grep -q "kubelet.service"; then
        info "✓ kubelet service unit verified"
    else
        error "kubelet service unit not found"
        exit 1
    fi
    
    info "✅ Kubernetes packages installation complete"
}

# Step 7: Install CNI plugins
install_cni_plugins() {
    info "=== Step 7: Installing CNI Plugins ==="
    
    # Create CNI directories
    mkdir -p /opt/cni/bin
    mkdir -p /etc/cni/net.d
    mkdir -p /var/lib/cni/networks
    mkdir -p /var/lib/cni/results
    mkdir -p /run/flannel
    
    # Set proper permissions
    chmod 755 /opt/cni/bin
    chmod 755 /etc/cni/net.d
    chmod 755 /var/lib/cni/networks
    chmod 755 /var/lib/cni/results
    chmod 755 /run/flannel
    
    # Download and install Flannel CNI plugin
    info "Installing Flannel CNI plugin..."
    curl -L "https://github.com/flannel-io/cni-plugin/releases/download/${FLANNEL_CNI_VERSION}/flannel-amd64" -o /opt/cni/bin/flannel
    chmod 755 /opt/cni/bin/flannel
    
    # Download and install additional CNI plugins
    info "Installing additional CNI plugins..."
    curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-${CNI_PLUGINS_VERSION}.tgz" | tar -C /opt/cni/bin -xz
    
    # Verify CNI plugins installation
    info "Verifying CNI plugins installation..."
    required_plugins=("bridge" "host-local" "loopback" "flannel")
    for plugin in "${required_plugins[@]}"; do
        if [ -f "/opt/cni/bin/$plugin" ] && [ -x "/opt/cni/bin/$plugin" ]; then
            info "✓ CNI plugin: $plugin"
        else
            error "CNI plugin missing or not executable: $plugin"
            exit 1
        fi
    done
    
    info "✅ CNI plugins installation complete"
}

# Step 8: Final system configuration
final_configuration() {
    info "=== Step 8: Final System Configuration ==="
    
    # Create kubelet service directory
    mkdir -p /etc/systemd/system/kubelet.service.d
    
    # Reload systemd
    systemctl daemon-reload
    
    # Verify all services are properly configured
    info "Verifying service configuration..."
    
    # Check containerd
    if systemctl is-enabled containerd >/dev/null 2>&1; then
        info "✓ containerd service enabled"
    else
        error "containerd service not enabled"
        exit 1
    fi
    
    if systemctl is-active containerd >/dev/null 2>&1; then
        info "✓ containerd service active"
    else
        error "containerd service not active"
        exit 1
    fi
    
    # Check kubelet
    if systemctl is-enabled kubelet >/dev/null 2>&1; then
        info "✓ kubelet service enabled"
    else
        error "kubelet service not enabled"
        exit 1
    fi
    
    info "✅ Final configuration complete"
}

# Step 9: Validation
validate_installation() {
    info "=== Step 9: Installation Validation ==="
    
    echo ""
    info "🔍 Running comprehensive validation..."
    
    # Test containerd
    if ctr version >/dev/null 2>&1; then
        info "✅ containerd is working"
    else
        error "❌ containerd is not working"
        exit 1
    fi
    
    # Test crictl
    if crictl version >/dev/null 2>&1; then
        info "✅ crictl is working"
    else
        error "❌ crictl is not working"
        exit 1
    fi
    
    # Check containerd image filesystem
    if crictl info 2>/dev/null | grep -q "imageFilesystem"; then
        info "✅ containerd image filesystem initialized"
    else
        warn "⚠️  containerd image filesystem may not be fully initialized"
    fi
    
    # Verify kernel modules
    for module in overlay br_netfilter; do
        if lsmod | grep -q "$module"; then
            info "✅ Kernel module $module loaded"
        else
            error "❌ Kernel module $module not loaded"
            exit 1
        fi
    done
    
    # Verify sysctl parameters
    local sysctl_checks=(
        "net.bridge.bridge-nf-call-iptables=1"
        "net.bridge.bridge-nf-call-ip6tables=1"
        "net.ipv4.ip_forward=1"
    )
    
    for check in "${sysctl_checks[@]}"; do
        local key=$(echo "$check" | cut -d'=' -f1)
        local expected=$(echo "$check" | cut -d'=' -f2)
        local actual=$(sysctl -n "$key" 2>/dev/null || echo "0")
        
        if [ "$actual" = "$expected" ]; then
            info "✅ sysctl $key = $actual"
        else
            error "❌ sysctl $key = $actual (expected: $expected)"
            exit 1
        fi
    done
    
    # Check swap
    if swapon -s | grep -q "/"; then
        error "❌ Swap is still enabled"
        exit 1
    else
        info "✅ Swap is disabled"
    fi
    
    echo ""
    info "🎉 All validation checks passed!"
    echo ""
    info "Worker node is now ready for Kubernetes cluster join!"
    echo ""
    info "Next steps:"
    info "1. Obtain the join command from your control plane node:"
    info "   kubeadm token create --print-join-command"
    info "2. Run the join command on this worker node:"
    info "   sudo <join-command>"
    info "3. Verify the node joined successfully from the control plane:"
    info "   kubectl get nodes"
}

# Main execution
main() {
    info "Starting comprehensive worker node setup..."
    echo ""
    
    detect_os
    install_system_prerequisites
    disable_swap
    configure_kernel
    install_containerd
    configure_crictl
    install_kubernetes
    install_cni_plugins
    final_configuration
    validate_installation
    
    echo ""
    info "🎉 Comprehensive worker node setup completed successfully!"
    echo ""
    info "Summary of installed components:"
    info "• containerd (container runtime)"
    info "• kubelet, kubeadm, kubectl (Kubernetes components)"
    info "• CNI plugins (bridge, host-local, loopback, flannel)"
    info "• Proper kernel modules and sysctl configuration"
    info "• All required directories and permissions"
    echo ""
    info "The worker node is now ready to join a Kubernetes cluster."
}

# Allow script to be sourced or executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
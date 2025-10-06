#!/usr/bin/env bash
# Quick fix script to install Kubernetes binaries on masternode
# Run this if automated installation fails due to container environment

set -euo pipefail

echo "========================================="
echo " Kubernetes Binaries Manual Installation"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
fi

# Check OS
if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect OS. /etc/os-release not found."
fi

source /etc/os-release

info "Detected OS: $NAME $VERSION"
info ""

# Check if binaries already installed
if command -v kubeadm >/dev/null 2>&1 && \
   command -v kubelet >/dev/null 2>&1 && \
   command -v kubectl >/dev/null 2>&1; then
    info "Kubernetes binaries are already installed!"
    kubeadm version
    kubelet --version
    kubectl version --client
    exit 0
fi

info "Installing Kubernetes binaries..."

if [[ "$ID" == "debian" ]] || [[ "$ID" == "ubuntu" ]]; then
    # Debian/Ubuntu installation
    info "Installing prerequisites..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg software-properties-common

    info "Adding Kubernetes repository..."
    mkdir -p /etc/apt/keyrings
    
    if [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]]; then
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
            gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    fi

    if [[ ! -f /etc/apt/sources.list.d/kubernetes.list ]]; then
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | \
            tee /etc/apt/sources.list.d/kubernetes.list
    fi

    info "Installing Kubernetes packages..."
    apt-get update
    apt-get install -y kubelet kubeadm kubectl containerd

    info "Holding packages at current version..."
    apt-mark hold kubelet kubeadm kubectl

elif [[ "$ID" == "rhel" ]] || [[ "$ID" == "centos" ]] || [[ "$ID" == "rocky" ]]; then
    # RHEL/CentOS installation
    info "Adding Kubernetes repository..."
    cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF

    info "Installing Kubernetes packages..."
    yum install -y kubelet kubeadm kubectl containerd --disableexcludes=kubernetes

else
    error "Unsupported OS: $ID"
fi

# Configure containerd
info "Configuring containerd..."
mkdir -p /etc/containerd
if [[ ! -f /etc/containerd/config.toml ]]; then
    containerd config default > /etc/containerd/config.toml
fi

# Enable SystemdCgroup
if ! grep -q "SystemdCgroup = true" /etc/containerd/config.toml; then
    info "Enabling SystemdCgroup in containerd config..."
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
fi

# Start services if systemd is available
if [[ -d /run/systemd/system ]]; then
    info "Starting services..."
    systemctl daemon-reload
    systemctl enable --now containerd
    systemctl enable kubelet
else
    warn "Systemd not available - services not started"
    warn "Services will be started by kubeadm during cluster init"
fi

# Verify installation
info ""
info "========================================="
info " Installation Complete!"
info "========================================="
info ""

if command -v kubeadm >/dev/null 2>&1; then
    info "✓ kubeadm: $(kubeadm version -o short)"
else
    error "✗ kubeadm not found in PATH"
fi

if command -v kubelet >/dev/null 2>&1; then
    info "✓ kubelet: $(kubelet --version | awk '{print $2}')"
else
    error "✗ kubelet not found in PATH"
fi

if command -v kubectl >/dev/null 2>&1; then
    info "✓ kubectl: $(kubectl version --client -o json | grep gitVersion | head -1 | awk '{print $2}' | tr -d '\",')"
else
    error "✗ kubectl not found in PATH"
fi

if command -v containerd >/dev/null 2>&1; then
    info "✓ containerd: installed"
else
    warn "✗ containerd not found in PATH"
fi

info ""
info "You can now run the deployment:"
info "  ./deploy.sh all --with-rke2 --yes"
info ""

#!/bin/bash
# CCNA Lab - Homelab Node Preparation Script
# Run this on the homelab node (192.168.4.62) before Terraform deployment

set -e

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     CCNA Lab - Homelab Preparation Script                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root"
  exit 1
fi

echo "[1/7] Checking system requirements..."
# Check if running on RHEL/CentOS/Rocky
if [ ! -f /etc/redhat-release ]; then
  echo "WARNING: This script is designed for RHEL-based systems"
fi

echo "[2/7] Installing KVM and libvirt packages..."
dnf install -y \
  qemu-kvm \
  libvirt \
  libvirt-client \
  virt-install \
  virt-manager \
  bridge-utils \
  libvirt-daemon-kvm \
  || echo "Some packages may already be installed"

echo "[3/7] Enabling and starting libvirtd..."
systemctl enable libvirtd
systemctl start libvirtd
systemctl status libvirtd --no-pager

echo "[4/7] Creating storage directory for CCNA lab..."
mkdir -p /var/lib/libvirt/images/ccna-lab
mkdir -p /var/lib/libvirt/images/cisco
chown -R qemu:qemu /var/lib/libvirt/images/ccna-lab
chown -R qemu:qemu /var/lib/libvirt/images/cisco
chmod 755 /var/lib/libvirt/images/ccna-lab
chmod 755 /var/lib/libvirt/images/cisco

echo "[5/7] Configuring firewall for CCNA lab..."
# Allow SSH from production network for management
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=libvirt

# Allow libvirt bridge traffic
firewall-cmd --permanent --add-masquerade

# Reload firewall
firewall-cmd --reload

echo "[6/7] Verifying KVM/QEMU functionality..."
if ! virsh list >/dev/null 2>&1; then
  echo "ERROR: libvirt is not working properly"
  exit 1
fi

if ! lsmod | grep -q kvm; then
  echo "ERROR: KVM kernel module not loaded"
  exit 1
fi

echo "[7/7] Checking nested virtualization support..."
if [ -f /sys/module/kvm_intel/parameters/nested ]; then
  NESTED=$(cat /sys/module/kvm_intel/parameters/nested)
  echo "Nested virtualization (Intel): $NESTED"
elif [ -f /sys/module/kvm_amd/parameters/nested ]; then
  NESTED=$(cat /sys/module/kvm_amd/parameters/nested)
  echo "Nested virtualization (AMD): $NESTED"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Homelab Preparation Complete!                        ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "1. Copy your Cisco IOS images to /var/lib/libvirt/images/cisco/"
echo "2. Run Terraform from your workstation:"
echo "   cd terraform/ccna-lab"
echo "   terraform init"
echo "   terraform plan"
echo "   terraform apply"
echo ""

# Display system information
echo "System Information:"
echo "-------------------"
echo "Hostname: $(hostname)"
echo "IP Address: $(hostname -I | awk '{print $1}')"
echo "CPU Cores: $(nproc)"
echo "Total RAM: $(free -h | grep Mem | awk '{print $2}')"
echo "Available Disk: $(df -h /var/lib/libvirt/images | tail -1 | awk '{print $4}')"
echo ""

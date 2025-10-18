#!/bin/bash
# CCNA Lab - Destroy Script
# Safely destroys the CCNA lab environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     CCNA Lab - Destroy Script                            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

echo "⚠️  WARNING: This will destroy the entire CCNA lab environment!"
echo ""
echo "The following will be destroyed:"
echo "  - GNS3 server VM"
echo "  - All Ubuntu VMs"
echo "  - All Windows VMs (if any)"
echo "  - All libvirt networks"
echo "  - All storage volumes"
echo "  - Network isolation rules"
echo ""

read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
read -p "Type 'destroy-ccna-lab' to confirm: " CONFIRM2

if [ "$CONFIRM2" != "destroy-ccna-lab" ]; then
  echo "Confirmation failed. Aborted."
  exit 0
fi

echo ""
echo "[1/3] Stopping all VMs..."
virsh -c "qemu+ssh://root@192.168.4.62/system" list --name | grep ccna-lab | while read vm; do
  echo "Stopping $vm..."
  virsh -c "qemu+ssh://root@192.168.4.62/system" destroy "$vm" 2>/dev/null || true
done

echo ""
echo "[2/3] Running Terraform destroy..."
terraform destroy -auto-approve

echo ""
echo "[3/3] Cleaning up homelab node..."
HOMELAB_IP="192.168.4.62"
ssh "root@$HOMELAB_IP" << 'EOF'
  # Remove network isolation rules
  nft delete table ip ccna_lab_isolation 2>/dev/null || true
  
  # Clean up any remaining storage
  rm -rf /var/lib/libvirt/images/ccna-lab
  
  echo "Cleanup complete on homelab node"
EOF

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     CCNA Lab Destroyed Successfully                      ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "All resources have been cleaned up."
echo ""

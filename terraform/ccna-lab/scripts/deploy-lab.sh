#!/bin/bash
# CCNA Lab - Deployment Script
# Run this from your Windows workstation (WSL or Git Bash)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          CCNA Lab - Deployment Script                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
  echo "ERROR: Terraform is not installed"
  echo "Install from: https://www.terraform.io/downloads"
  exit 1
fi

echo "Terraform version:"
terraform version
echo ""

# Check if homelab is reachable
echo "[1/5] Checking connectivity to homelab node..."
HOMELAB_IP=$(grep -A 5 'libvirt_uri' terraform.tfvars | grep 'root@' | sed 's/.*root@\([0-9.]*\).*/\1/')
if [ -z "$HOMELAB_IP" ]; then
  HOMELAB_IP="192.168.4.62"
fi

if ! ping -c 1 "$HOMELAB_IP" &> /dev/null; then
  echo "ERROR: Cannot reach homelab node at $HOMELAB_IP"
  echo "Please check network connectivity"
  exit 1
fi
echo "✓ Homelab node reachable at $HOMELAB_IP"
echo ""

# Check SSH connectivity
echo "[2/5] Checking SSH connectivity..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$HOMELAB_IP" "echo SSH OK" &> /dev/null; then
  echo "ERROR: Cannot SSH to homelab node"
  echo "Please ensure SSH key authentication is configured"
  echo "Run: ssh-copy-id root@$HOMELAB_IP"
  exit 1
fi
echo "✓ SSH connectivity OK"
echo ""

# Initialize Terraform
echo "[3/5] Initializing Terraform..."
terraform init
echo ""

# Validate configuration
echo "[4/5] Validating Terraform configuration..."
terraform validate
echo ""

# Show plan
echo "[5/5] Generating Terraform plan..."
terraform plan -out=ccna-lab.tfplan
echo ""

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║          Ready to Deploy!                                ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Review the plan above. If everything looks good, run:"
echo ""
echo "  terraform apply ccna-lab.tfplan"
echo ""
echo "Or to apply without saving a plan:"
echo ""
echo "  terraform apply -auto-approve"
echo ""

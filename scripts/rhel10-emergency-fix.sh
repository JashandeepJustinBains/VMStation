#!/bin/bash
# RHEL 10 Emergency Fix for Flannel CrashLoopBackOff
# Run this script on the homelab node (192.168.4.62)

set -e

echo "=========================================="
echo "RHEL 10 Flannel Emergency Fix"
echo "=========================================="
echo ""

# Check if running on RHEL 10
if [ -f /etc/os-release ]; then
    source /etc/os-release
    if [[ "$ID" != "rhel" ]] || [[ "${VERSION_ID%%.*}" -lt 10 ]]; then
        echo "WARNING: This script is designed for RHEL 10+"
        echo "Current OS: $ID $VERSION_ID"
        read -p "Continue anyway? (y/N): " confirm
        [[ "$confirm" != "y" ]] && exit 1
    fi
fi

echo "Step 1: Checking current nftables configuration..."
echo "Current tables:"
nft list tables || true
echo ""

echo "Step 2: Creating flannel nftables tables..."
# Create flannel IPv4 table
if ! nft list table inet flannel-ipv4 &>/dev/null; then
    echo "  Creating inet flannel-ipv4 table..."
    nft add table inet flannel-ipv4
    echo "  ✓ Created inet flannel-ipv4"
else
    echo "  ✓ inet flannel-ipv4 already exists"
fi

# Create flannel IPv6 table
if ! nft list table inet flannel-ipv6 &>/dev/null; then
    echo "  Creating inet flannel-ipv6 table..."
    nft add table inet flannel-ipv6
    echo "  ✓ Created inet flannel-ipv6"
else
    echo "  ✓ inet flannel-ipv6 already exists"
fi
echo ""

echo "Step 3: Creating basic filter table if missing..."
if ! nft list table inet filter &>/dev/null; then
    echo "  Creating inet filter table..."
    nft add table inet filter
    nft add chain inet filter input '{ type filter hook input priority 0; policy accept; }'
    nft add chain inet filter forward '{ type filter hook forward priority 0; policy accept; }'
    nft add chain inet filter output '{ type filter hook output priority 0; policy accept; }'
    echo "  ✓ Created inet filter table with permissive chains"
else
    echo "  ✓ inet filter already exists"
fi
echo ""

echo "Step 4: Persisting nftables configuration..."
mkdir -p /etc/sysconfig
nft list ruleset > /etc/sysconfig/nftables.conf
echo "  ✓ Configuration saved to /etc/sysconfig/nftables.conf"
echo ""

echo "Step 5: Enabling nftables service..."
if systemctl enable nftables 2>/dev/null; then
    echo "  ✓ nftables service enabled"
else
    echo "  ! nftables service already enabled or not available"
fi

if systemctl start nftables 2>/dev/null; then
    echo "  ✓ nftables service started"
else
    echo "  ! nftables service already running or not available"
fi
echo ""

echo "Step 6: Verifying nftables tables..."
echo "All tables:"
nft list tables
echo ""

echo "Step 7: Checking for br_netfilter module (should NOT exist on RHEL 10)..."
if lsmod | grep -q br_netfilter; then
    echo "  WARNING: br_netfilter is loaded (unexpected on RHEL 10)"
elif modprobe br_netfilter 2>/dev/null; then
    echo "  WARNING: br_netfilter module exists (unexpected on RHEL 10)"
else
    echo "  ✓ br_netfilter module does not exist (expected on RHEL 10)"
fi
echo ""

echo "=========================================="
echo "Emergency Fix Complete!"
echo "=========================================="
echo ""
echo "Expected nftables tables:"
echo "  - table inet filter          ✓"
echo "  - table inet flannel-ipv4    ✓"
echo "  - table inet flannel-ipv6    ✓"
echo ""
echo "Next steps:"
echo "  1. From masternode, delete failing pods:"
echo "     kubectl delete pod -n kube-flannel kube-flannel-ds-5kvj9"
echo "     kubectl delete pod -n kube-system kube-proxy-d9vx8"
echo ""
echo "  2. Wait 30 seconds for pods to restart"
echo ""
echo "  3. Check status:"
echo "     kubectl get pods -A | grep homelab"
echo ""
echo "  4. All pods should be Running with low restart count"
echo ""
echo "=========================================="

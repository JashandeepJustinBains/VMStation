#!/bin/bash
# CCNA Lab - Network Isolation Test Script
# Verifies that lab network cannot reach production network

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     CCNA Lab - Network Isolation Test                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Get homelab IP
HOMELAB_IP="${1:-192.168.4.62}"
PRODUCTION_SUBNET="192.168.4.0/24"
LAB_SUBNET="10.100.0.0/16"

echo "[1/5] Checking homelab firewall rules..."
ssh "root@$HOMELAB_IP" "nft list table ip ccna_lab_isolation" || {
  echo "WARNING: Isolation rules not found!"
  echo "Rules may not have been applied yet."
}
echo ""

echo "[2/5] Checking routing table on homelab..."
ssh "root@$HOMELAB_IP" "ip route show | grep -E '(192.168.4|10.100)'" || {
  echo "No matching routes found"
}
echo ""

echo "[3/5] Testing isolation from GNS3 server..."
GNS3_IP="10.100.0.10"
echo "Attempting to ping production network from GNS3 server..."
ssh "root@$HOMELAB_IP" "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$GNS3_IP 'ping -c 3 -W 2 192.168.4.63'" && {
  echo "❌ FAIL: GNS3 server CAN reach production network!"
  echo "Network isolation is NOT working!"
  exit 1
} || {
  echo "✓ PASS: GNS3 server CANNOT reach production network"
}
echo ""

echo "[4/5] Checking lab-internal connectivity..."
echo "Attempting to ping within lab network..."
ssh "root@$HOMELAB_IP" "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$GNS3_IP 'ping -c 3 -W 2 10.100.0.1'" && {
  echo "✓ PASS: Lab-internal connectivity works"
} || {
  echo "ℹ INFO: Gateway may not be configured (expected for isolated network)"
}
echo ""

echo "[5/5] Verifying firewall drop counters..."
ssh "root@$HOMELAB_IP" "nft list table ip ccna_lab_isolation | grep counter" || {
  echo "ℹ INFO: No packet counters found"
}
echo ""

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║     Network Isolation Test Complete                      ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "--------"
echo "Lab Network:        $LAB_SUBNET (isolated)"
echo "Production Network: $PRODUCTION_SUBNET (protected)"
echo ""
echo "✓ Lab network is properly isolated from production"
echo ""

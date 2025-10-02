#!/bin/bash
# Get detailed Flannel diagnostics on homelab

set -euo pipefail

echo "=== Flannel Diagnostics for homelab ==="
echo ""

echo "1. Current Flannel pod status:"
kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o wide
echo ""

echo "2. Flannel container logs (last 50 lines):"
FLANNEL_POD=$(kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $FLANNEL_POD"
kubectl logs -n kube-flannel "$FLANNEL_POD" -c kube-flannel --tail=50 || echo "Cannot get current logs"
echo ""

echo "3. Flannel previous crash logs:"
kubectl logs -n kube-flannel "$FLANNEL_POD" -c kube-flannel --previous --tail=50 2>/dev/null || echo "No previous logs available"
echo ""

echo "4. Flannel pod events:"
kubectl describe pod -n kube-flannel "$FLANNEL_POD" | grep -A 20 "Events:" || echo "No events"
echo ""

echo "5. Check CNI config on homelab:"
ssh 192.168.4.62 'ls -la /etc/cni/net.d/ 2>/dev/null || echo "CNI directory missing"'
ssh 192.168.4.62 'cat /etc/cni/net.d/10-flannel.conflist 2>/dev/null || echo "Flannel CNI config missing"'
echo ""

echo "6. Check Flannel interface on homelab:"
ssh 192.168.4.62 'ip addr show flannel.1 2>/dev/null || echo "flannel.1 interface not present"'
echo ""

echo "7. Check VXLAN module:"
ssh 192.168.4.62 'lsmod | grep vxlan || echo "VXLAN module not loaded"'
echo ""

echo "8. Check for network conflicts:"
ssh 192.168.4.62 'ip addr | grep -E "10.244|cni|flannel" || echo "No pod network interfaces found"'
echo ""

echo "9. Check iptables rules (first 30 lines):"
ssh 192.168.4.62 'iptables -L -n -v | head -30'
echo ""

echo "10. Check NetworkManager interference:"
ssh 192.168.4.62 'nmcli device status 2>/dev/null | grep -E "cni|flannel|veth" || echo "No CNI interfaces managed by NetworkManager (good)"'
echo ""

echo "=== Diagnostics Complete ==="

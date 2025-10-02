#!/bin/bash
# Emergency fix for kube-proxy on homelab node

set -euo pipefail

echo "=== Emergency Fix for Homelab kube-proxy ==="
echo ""

echo "1. Ensuring conntrack is properly installed..."
ssh 192.168.4.62 'sudo dnf install -y conntrack-tools iptables iptables-services socat iproute-tc'
echo ""

echo "2. Loading required kernel modules..."
ssh 192.168.4.62 'sudo modprobe nf_conntrack && sudo modprobe nf_conntrack_ipv4 2>/dev/null || echo "nf_conntrack_ipv4 not available (normal on newer kernels)"'
ssh 192.168.4.62 'sudo modprobe br_netfilter overlay vxlan'
echo ""

echo "3. Setting iptables to legacy mode..."
ssh 192.168.4.62 'sudo alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || echo "alternatives command not available, trying update-alternatives"'
ssh 192.168.4.62 'sudo alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true'
echo ""

echo "4. Disabling SELinux temporarily (if enabled)..."
ssh 192.168.4.62 'sudo setenforce 0 2>/dev/null || echo "SELinux already permissive or disabled"'
echo ""

echo "5. Restarting kubelet on homelab..."
ssh 192.168.4.62 'sudo systemctl restart kubelet'
echo ""

echo "6. Deleting kube-proxy pod to force recreation..."
PROXY_POD=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod -n kube-system "$PROXY_POD"
echo ""

echo "7. Waiting for kube-proxy to restart..."
sleep 10
kubectl wait --for=condition=Ready pod -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab -n kube-system --timeout=60s || echo "kube-proxy not ready yet"
echo ""

echo "8. Checking kube-proxy status..."
kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab
echo ""

echo "=== Fix Complete - Check Results Above ==="

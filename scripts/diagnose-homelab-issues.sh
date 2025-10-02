#!/bin/bash
# Diagnose kube-proxy and networking issues on homelab node

set -euo pipefail

echo "=== Homelab Node Diagnostics ==="
echo ""

echo "1. Checking conntrack installation and functionality..."
ssh 192.168.4.62 'which conntrack && conntrack --version || echo "ERROR: conntrack not found or not working"'
echo ""

echo "2. Checking kernel modules loaded..."
ssh 192.168.4.62 'lsmod | grep -E "br_netfilter|nf_conntrack|vxlan|overlay" || echo "ERROR: Required modules not loaded"'
echo ""

echo "3. Checking iptables version and mode..."
ssh 192.168.4.62 'iptables --version && update-alternatives --display iptables 2>/dev/null || alternatives --display iptables 2>/dev/null || echo "Not using alternatives"'
echo ""

echo "4. Checking NetworkManager status and configuration..."
ssh 192.168.4.62 'systemctl status NetworkManager --no-pager -l || echo "NetworkManager not running"'
ssh 192.168.4.62 'cat /etc/NetworkManager/conf.d/99-kubernetes.conf 2>/dev/null || echo "NetworkManager config missing"'
echo ""

echo "5. Checking firewalld status..."
ssh 192.168.4.62 'systemctl status firewalld --no-pager || echo "firewalld not running (expected)"'
echo ""

echo "6. Getting kube-proxy logs..."
PROXY_POD=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab -o jsonpath='{.items[0].metadata.name}')
echo "kube-proxy pod: $PROXY_POD"
kubectl logs -n kube-system "$PROXY_POD" --tail=50 --previous 2>/dev/null || echo "No previous logs available"
echo ""
kubectl logs -n kube-system "$PROXY_POD" --tail=50 || echo "Cannot get current logs"
echo ""

echo "7. Checking flannel logs on homelab..."
FLANNEL_POD=$(kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o jsonpath='{.items[0].metadata.name}')
echo "flannel pod: $FLANNEL_POD"
kubectl logs -n kube-flannel "$FLANNEL_POD" -c kube-flannel --tail=30 || echo "Cannot get flannel logs"
echo ""

echo "8. Checking system packages on homelab..."
ssh 192.168.4.62 'rpm -qa | grep -E "iptables|conntrack|socat|iproute" | sort'
echo ""

echo "9. Checking SELinux status..."
ssh 192.168.4.62 'getenforce 2>/dev/null || echo "SELinux not available"'
echo ""

echo "10. Checking for any iptables rules blocking traffic..."
ssh 192.168.4.62 'iptables -L -n -v | head -50'
echo ""

echo "=== Diagnostics Complete ==="

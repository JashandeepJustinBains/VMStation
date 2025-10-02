#!/bin/bash
# Emergency fix for Flannel on homelab node

set -euo pipefail

echo "=== Emergency Flannel Fix for homelab ==="
echo ""

echo "1. Setting SELinux to permissive mode..."
jashandeepjustinbains@192.168.4.62 'sudo setenforce 0 2>/dev/null || echo "SELinux already permissive"'
jashandeepjustinbains@192.168.4.62sudo sed -i "s/^SELINUX=enforcing/SELINUX=permissive/" /etc/selinux/config 2>/dev/null || echo "SELinux config not modified"
echo ""

echo "2. Ensuring all kernel modules are loaded..."
jashandeepjustinbains@192.168.4.62 'sudo modprobe br_netfilter overlay nf_conntrack vxlan'
echo ""

echo "3. Verifying iptables is in legacy mode..."
jashandeepjustinbains@192.168.4.62 'sudo alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || echo "iptables-legacy already set or not available"'
jashandeepjustinbains@192.168.4.62 'sudo alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true'
echo ""

echo "4. Checking for CNI binary conflicts..."
jashandeepjustinbains@192.168.4.62 'ls -la /opt/cni/bin/ 2>/dev/null | grep -E "flannel|bridge|host-local" || echo "CNI binaries missing - flannel should install them"'
echo ""

echo "5. Removing any stale Flannel interfaces..."
jashandeepjustinbains@192.168.4.62 'sudo ip link delete flannel.1 2>/dev/null || echo "No flannel.1 interface to delete"'
jashandeepjustinbains@192.168.4.62 'sudo ip link delete cni0 2>/dev/null || echo "No cni0 interface to delete"'
echo ""

echo "6. Clearing CNI config (will be regenerated)..."
jashandeepjustinbains@192.168.4.62 'sudo rm -f /etc/cni/net.d/10-flannel.conflist 2>/dev/null || echo "No CNI config to remove"'
jashandeepjustinbains@192.168.4.62 'sudo rm -rf /var/lib/cni/flannel/* 2>/dev/null || echo "No flannel data to remove"'
echo ""

echo "7. Restarting kubelet..."
jashandeepjustinbains@192.168.4.62 'sudo systemctl restart kubelet'
jashandeepjustinbains@192.168.4.62 'sleep 5'
echo ""

echo "Waiting for Kubernetes API to become available..."
for i in {1..30}; do
	if kubectl get nodes >/dev/null 2>&1; then
		echo "Kubernetes API is available."
		break
	fi
	echo "  Waiting for API... ($i/30)"
	sleep 2
done
if ! kubectl get nodes >/dev/null 2>&1; then
	echo "ERROR: Kubernetes API is still unavailable after 60 seconds. Exiting."
	exit 1
fi

echo "8. Deleting Flannel pod to force recreation..."
FLANNEL_POD=$(kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o jsonpath='{.items[0].metadata.name}')
echo "Deleting pod: $FLANNEL_POD"
kubectl delete pod -n kube-flannel "$FLANNEL_POD"
echo ""

echo "9. Waiting for Flannel to restart (60 seconds)..."
sleep 60
echo ""

echo "10. Checking Flannel status..."
kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o wide
echo ""

echo "11. Checking Flannel logs..."
NEW_POD=$(kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n kube-flannel "$NEW_POD" -c kube-flannel --tail=30 || echo "Cannot get logs yet"
echo ""

echo "=== Fix Complete ==="
echo ""
echo "If Flannel is still CrashLoopBackOff, run:"
echo "  chmod +x scripts/diagnose-flannel-homelab.sh"
echo "  ./scripts/diagnose-flannel-homelab.sh"

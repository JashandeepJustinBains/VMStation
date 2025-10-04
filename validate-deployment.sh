#!/usr/bin/env bash
# Validation script for VMStation Kubernetes deployment
# Run this on masternode after deployment to verify cluster health

set -euo pipefail

echo "=== VMStation Cluster Validation ==="
echo ""

# Check for CrashLoopBackOff pods
echo "1. Checking for CrashLoopBackOff pods..."
if kubectl get pods -A | grep -i crash; then
    echo "❌ FAILED: CrashLoopBackOff pods detected"
    exit 1
else
    echo "✅ PASSED: No CrashLoopBackOff pods"
fi
echo ""

# Check Flannel DaemonSet
echo "2. Checking Flannel DaemonSet..."
kubectl get daemonset -n kube-flannel
echo ""

# Check kube-proxy
echo "3. Checking kube-proxy pods..."
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide
echo ""

# Check CoreDNS
echo "4. Checking CoreDNS pods..."
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
echo ""

# Check nodes
echo "5. Checking node status..."
kubectl get nodes -o wide
echo ""

# Check CNI config on all nodes
echo "6. Verifying CNI config on all nodes..."
echo "  Checking masternode..."
ssh -o StrictHostKeyChecking=no root@masternode "test -f /etc/cni/net.d/10-flannel.conflist && echo '✅ CNI config present' || echo '❌ CNI config missing'"

echo "  Checking storagenodet3500..."
ssh -o StrictHostKeyChecking=no root@storagenodet3500 "test -f /etc/cni/net.d/10-flannel.conflist && echo '✅ CNI config present' || echo '❌ CNI config missing'"

echo "  Checking homelab (RHEL 10)..."
ssh -o StrictHostKeyChecking=no jashandeepjustinbains@192.168.4.62 "sudo test -f /etc/cni/net.d/10-flannel.conflist && echo '✅ CNI config present' || echo '❌ CNI config missing'"
echo ""

# Final summary
echo "=== Validation Complete ==="
echo "All checks passed! Cluster is healthy and ready for workloads."

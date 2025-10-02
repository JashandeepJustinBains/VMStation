#!/usr/bin/env bash
# Quick validation script to verify cluster health after deploy
set -euo pipefail

echo "=== Cluster Health Validation ==="
echo

# Check nodes
echo "1. Node Status:"
kubectl get nodes -o wide
echo

# Check flannel
echo "2. Flannel Pods:"
kubectl get pods -n kube-flannel -o wide
echo

flannel_crashes=$(kubectl get pods -n kube-flannel -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{if($1>5)print}' | wc -l)
if [ "$flannel_crashes" -gt 0 ]; then
  echo "⚠️  WARNING: $flannel_crashes flannel pod(s) with >5 restarts"
else
  echo "✅ All flannel pods stable (≤5 restarts)"
fi
echo

# Check monitoring
echo "3. Monitoring Pods:"
kubectl get pods -n monitoring -o wide
echo

monitoring_pending=$(kubectl get pods -n monitoring --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
if [ "$monitoring_pending" -gt 0 ]; then
  echo "⚠️  WARNING: $monitoring_pending monitoring pod(s) pending"
  kubectl describe pod -n monitoring $(kubectl get pods -n monitoring --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) 2>/dev/null | grep -A5 "Events:" || true
else
  echo "✅ All monitoring pods scheduled"
fi
echo

# Check Jellyfin
echo "4. Jellyfin Pod:"
kubectl get pods -n jellyfin -o wide
echo

jellyfin_running=$(kubectl get pods -n jellyfin -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [ "$jellyfin_running" = "Running" ]; then
  echo "✅ Jellyfin is running"
else
  echo "⚠️  Jellyfin status: $jellyfin_running"
fi
echo

# Summary
echo "=== Summary ==="
total_pods=$(kubectl get pods -A --no-headers | wc -l)
running_pods=$(kubectl get pods -A --field-selector=status.phase=Running --no-headers | wc -l)
pending_pods=$(kubectl get pods -A --field-selector=status.phase=Pending --no-headers | wc -l)
failed_pods=$(kubectl get pods -A --field-selector=status.phase=Failed --no-headers | wc -l)

echo "Total pods: $total_pods"
echo "Running: $running_pods"
echo "Pending: $pending_pods"
echo "Failed: $failed_pods"
echo

if [ "$pending_pods" -eq 0 ] && [ "$failed_pods" -eq 0 ] && [ "$flannel_crashes" -eq 0 ]; then
  echo "✅ Cluster is healthy!"
  exit 0
else
  echo "⚠️  Cluster has issues - review output above"
  exit 1
fi

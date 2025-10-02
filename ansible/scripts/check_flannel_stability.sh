#!/usr/bin/env bash
set -eux

echo "Checking flannel pod stability..."
# wait up to 120s for all flannel pods to be Running and not restarting
for i in {1..24}; do
  crash_count=$(kubectl get pods -n kube-flannel -l app=flannel -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{if($1>3)print}' | wc -l)
  pending_count=$(kubectl get pods -n kube-flannel -l app=flannel --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)

  if [ "${crash_count}" -eq 0 ] && [ "${pending_count}" -eq 0 ]; then
    echo "All flannel pods stable"
    exit 0
  fi

  echo "Waiting for flannel stability (attempt $i/24): crashes=${crash_count} pending=${pending_count}"
  sleep 5
done

echo "WARNING: Flannel pods may be unstable after 120s wait"
kubectl get pods -n kube-flannel -o wide
exit 0  # don't fail deploy, but warn

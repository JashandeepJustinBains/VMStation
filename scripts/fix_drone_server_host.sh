#!/bin/bash

# Small helper to ensure drone server-host key exists in drone-secrets
# Usage: ./fix_drone_server_host.sh [HOST]

set -e

HOST=${1:-192.168.4.62}
NAMESPACE=drone
SECRET=drone-secrets

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found"
  exit 1
fi

if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "Namespace $NAMESPACE not found; nothing to do"
  exit 0
fi

if ! kubectl -n "$NAMESPACE" get secret "$SECRET" >/dev/null 2>&1; then
  echo "Secret $SECRET not found in namespace $NAMESPACE; nothing to do"
  exit 0
fi

b64_host=$(printf '%s' "$HOST" | base64 | tr -d '\n')

echo "Patching secret $SECRET in namespace $NAMESPACE to set server-host=$HOST"
if kubectl -n "$NAMESPACE" patch secret "$SECRET" --type='merge' -p "{\"data\":{\"server-host\":\"$b64_host\"}}"; then
  echo "Patched secret with server-host=$HOST"
  echo "If runners or server need restart, consider: kubectl -n drone rollout restart deployment/drone"
else
  echo "Failed to patch secret"
  exit 1
fi

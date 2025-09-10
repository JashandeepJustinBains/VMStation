#!/usr/bin/env bash
set -euo pipefail

# reset_kubelet_worker.sh
# Safe, interactive helper to reset kubeadm/kubelet state on a worker node.
# Creates backups of /etc/kubernetes and /var/lib/kubelet, runs `kubeadm reset -f`,
# and optionally removes CNI and kubelet state directories. Designed to be run on
# the worker node itself (not the control plane).

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Use sudo." >&2
  exit 2
fi

TS="$(date +%Y%m%d-%H%M%S)"
BK="/root/k8s-backup-${TS}"

echo "About to reset kubeadm/kubelet state on this node."
echo "A backup of /etc/kubernetes and /var/lib/kubelet will be made at: ${BK}"
read -rp "Continue? (y/N): " CONFIRM
if [ "${CONFIRM,,}" != "y" ]; then
  echo "Aborted by user."; exit 0
fi

mkdir -p "${BK}"
echo "Backing up /etc/kubernetes (if present)..."
if [ -d /etc/kubernetes ]; then
  cp -a /etc/kubernetes "${BK}/etc-kubernetes" || true
fi

echo "Backing up /var/lib/kubelet (if present)..."
if [ -d /var/lib/kubelet ]; then
  cp -a /var/lib/kubelet "${BK}/var-lib-kubelet" || true
fi

echo "Stopping kubelet and preventing auto-start while we reset..."
systemctl stop kubelet || true
systemctl disable kubelet || true
systemctl mask kubelet || true

echo "Running kubeadm reset -f ..."
# kubeadm reset will attempt to stop kubelet and clean state; we run it explicitly
if command -v kubeadm >/dev/null 2>&1; then
  kubeadm reset -f || true
else
  echo "Warning: kubeadm not found in PATH. Skipping kubeadm reset." >&2
fi

echo
echo "The reset above does NOT remove CNI files by default."
read -rp "Remove /etc/cni/net.d (flannel / CNI configs)? (y/N): " RM_CNI
if [ "${RM_CNI,,}" = "y" ]; then
  if [ -d /etc/cni/net.d ]; then
    rm -rf /etc/cni/net.d/*
    echo "/etc/cni/net.d cleaned"
  else
    echo "/etc/cni/net.d not found"
  fi
fi

read -rp "Remove /var/lib/kubelet (pod state) now? (y/N): " RM_KLET
if [ "${RM_KLET,,}" = "y" ]; then
  if [ -d /var/lib/kubelet ]; then
    rm -rf /var/lib/kubelet
    echo "/var/lib/kubelet removed"
  else
    echo "/var/lib/kubelet not found"
  fi
fi

echo "Ensure containerd is running..."
systemctl restart containerd || true

echo "Unmasking and enabling kubelet (will start kubelet)..."
systemctl unmask kubelet || true
systemctl enable kubelet || true
systemctl restart kubelet || true

echo
echo "Reset complete. Backups saved under: ${BK}"
echo "Next steps:"
echo "  1) From the control plane run: kubeadm token create --print-join-command"
echo "  2) On this node run the returned 'kubeadm join' command (do not ignore CA unless necessary)"
echo "  3) Monitor with: sudo journalctl -u kubelet -f"

exit 0

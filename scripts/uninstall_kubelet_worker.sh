#!/usr/bin/env bash
set -euo pipefail

# uninstall_kubelet_worker.sh
# Safely remove kubelet, kubeadm, kubectl and related state from a worker node.
# Backups of important directories are stored under /root/k8s-uninstall-backup-<ts>.
# Usage: sudo ./uninstall_kubelet_worker.sh [--yes]

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Use sudo." >&2
  exit 2
fi

TS="$(date +%Y%m%d-%H%M%S)"
BK="/root/k8s-uninstall-backup-${TS}"
AUTO_NO_PROMPT=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y) AUTO_NO_PROMPT=1 ;;
    --help|-h)
      cat <<'EOF'
Usage: sudo ./uninstall_kubelet_worker.sh [--yes]
This will:
  - stop kubelet and containerd services
  - run kubeadm reset -f (if kubeadm present)
  - purge kubelet, kubeadm, kubectl packages (apt)
  - backup and remove /etc/kubernetes, /var/lib/kubelet, /var/lib/etcd
  - optionally remove CNI configs and CNI binaries
  - restart containerd and reload systemd
EOF
      exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

echo "This script will permanently remove kubelet/kubeadm/kubectl and cluster state on this node."
if [ $AUTO_NO_PROMPT -eq 0 ]; then
  read -rp "Continue and create backup under ${BK}? (y/N): " OK
  if [ "${OK,,}" != "y" ]; then
    echo "Aborted."; exit 0
  fi
fi

mkdir -p "${BK}"
echo "Backing up /etc/kubernetes and /var/lib/kubelet and /var/lib/etcd (if present) to ${BK}"
if [ -d /etc/kubernetes ]; then cp -a /etc/kubernetes "${BK}/etc-kubernetes" || true; fi
if [ -d /var/lib/kubelet ]; then cp -a /var/lib/kubelet "${BK}/var-lib-kubelet" || true; fi
if [ -d /var/lib/etcd ]; then cp -a /var/lib/etcd "${BK}/var-lib-etcd" || true; fi

echo "Stopping kubelet and kube related services..."
systemctl stop kubelet || true
systemctl disable kubelet || true
systemctl mask kubelet || true

echo "Running kubeadm reset -f (if available)..."
if command -v kubeadm >/dev/null 2>&1; then
  kubeadm reset -f || true
else
  echo "kubeadm not found; skipping kubeadm reset"
fi

echo "Removing kubernetes packages via apt (if installed)..."
if command -v apt-get >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get purge -y kubeadm kubelet kubectl kube* || true
  DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true
  DEBIAN_FRONTEND=noninteractive apt-get autoclean -y || true
else
  echo "apt-get not found; please remove kube packages using your distro package manager" >&2
fi

echo "Removing systemd unit files and reloading daemon..."
systemctl daemon-reload || true

echo "Removing Kubernetes state directories (they are backed up):"
for d in /etc/kubernetes /var/lib/kubelet /var/lib/etcd /var/lib/dockershim; do
  if [ ! -e "$d" ]; then
    continue
  fi

  # Resolve real path (follow symlinks). If resolution fails, skip to be safe.
  realpath="$(readlink -f -- "$d" 2>/dev/null || true)"

  # Check if the resolved path is under /mnt/media to avoid deleting important media
  if [ -n "$realpath" ] && [[ "$realpath" == /mnt/media* ]]; then
    echo "SKIP: $d resolves to $realpath which is under /mnt/media — not removing"
    continue
  fi

  # Also check if the target is a mountpoint or is on a mount under /mnt/media
  if command -v findmnt >/dev/null 2>&1; then
    mp="$(findmnt -n -o TARGET --target -- "$d" 2>/dev/null || true)"
    if [ -n "$mp" ] && [[ "$mp" == /mnt/media* ]] || [ -n "$mp" ] && [[ "$mp" == /srv/media* ]]; then
      echo "SKIP: $d is mounted under $mp which is under /mnt/media or /srv/media — not removing"
      continue
    fi
  fi

  # Safe to remove
  rm -rf -- "$d" || true
  echo "Removed $d"
done

read -rp "Also remove /etc/cni/net.d and CNI binaries in /opt/cni/bin? (y/N): " RM_CNI
if [ "${RM_CNI,,}" = "y" ]; then
  if [ -d /etc/cni/net.d ]; then rm -rf /etc/cni/net.d/*; echo "/etc/cni/net.d cleaned"; fi
  if [ -d /opt/cni/bin ]; then rm -rf /opt/cni/bin/*; echo "/opt/cni/bin cleaned"; fi
fi

echo "Ensure containerd is running (or start it)..."
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart containerd || true
fi

echo "Unmasking kubelet (package removal may have removed units)..."
systemctl unmask kubelet || true

echo
echo "Uninstall complete. Backups are in: ${BK}"
echo "If you plan to reinstall using 'deploy.sh', you should now run that from your deployment host/control-plane."
echo "Example (on this node): sudo bash /path/to/deploy.sh"

exit 0

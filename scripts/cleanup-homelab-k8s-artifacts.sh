#!/usr/bin/env bash
# =============================================================================
# Cleanup Kubernetes Artifacts from Homelab Node
# =============================================================================
# This script removes all kubeadm-based Kubernetes artifacts from the homelab
# node in preparation for RKE2 installation.
#
# Usage:
#   sudo /srv/monitoring_data/VMStation/scripts/cleanup-homelab-k8s-artifacts.sh
#
# Or remotely:
#   ssh jashandeepjustinbains@192.168.4.62 'sudo bash /tmp/cleanup-homelab-k8s-artifacts.sh'
# =============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

log_warn "⚠️  WARNING: This will remove all Kubernetes artifacts from this node"
echo ""
echo "This includes:"
echo "  - kubeadm/kubelet/kubectl binaries"
echo "  - containerd runtime"
echo "  - CNI plugins and configurations"
echo "  - iptables rules and nftables tables"
echo "  - Kubernetes systemd services"
echo "  - All Kubernetes data directories"
echo ""
read -p "Continue with cleanup? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Cleanup cancelled"
    exit 0
fi

log_info "Starting cleanup..."

# Stop and disable services
log_info "Stopping Kubernetes services..."
systemctl stop kubelet 2>/dev/null || true
systemctl stop containerd 2>/dev/null || true
systemctl disable kubelet 2>/dev/null || true
systemctl disable containerd 2>/dev/null || true

# Kill any remaining processes
log_info "Killing remaining container processes..."
pkill -9 -f containerd-shim 2>/dev/null || true
pkill -9 -f containerd-shim-runc-v2 2>/dev/null || true
pkill -9 -f containerd 2>/dev/null || true
pkill -9 -f kubelet 2>/dev/null || true

# Get current SSH user's PIDs to protect them
CURRENT_USER="${SUDO_USER:-$USER}"
PROTECT_PIDS=""
if command -v pgrep >/dev/null 2>&1; then
    SSHD_PIDS=$(pgrep -x sshd || true)
    USER_PIDS=$(pgrep -u "$CURRENT_USER" || true)
    PROTECT_PIDS="$SSHD_PIDS $USER_PIDS"
fi

# Kill processes using Kubernetes directories (protect SSH)
kill_list() {
    local path="$1"
    if [[ ! -d "$path" ]]; then
        return 0
    fi
    if command -v fuser >/dev/null 2>&1; then
        PIDS=$(fuser -m "$path" 2>/dev/null || true)
        for p in $PIDS; do
            # skip empty and protect pids
            [ -z "$p" ] && continue
            if echo "$PROTECT_PIDS" | tr ' ' '\n' | grep -xq "$p"; then
                continue
            fi
            kill -9 "$p" 2>/dev/null || true
        done
    fi
}

log_info "Killing processes using Kubernetes directories..."
kill_list /var/lib/kubelet || true
kill_list /run/containerd || true

# Unmount any remaining mounts
log_info "Unmounting Kubernetes filesystems..."
if command -v findmnt >/dev/null 2>&1; then
    findmnt -rno TARGET -T /var/lib/kubelet 2>/dev/null | sort -r | xargs -r -n1 umount -l 2>/dev/null || true
    findmnt -rno TARGET -T /run/containerd 2>/dev/null | sort -r | xargs -r -n1 umount -l 2>/dev/null || true
else
    umount -l /var/lib/kubelet/pods/* 2>/dev/null || true
    umount -l /run/containerd/io.containerd.grpc.v1.cri/sandboxes/* 2>/dev/null || true
fi

# Remove Kubernetes binaries
log_info "Removing Kubernetes binaries..."
rm -f /usr/local/bin/kubeadm \
      /usr/local/bin/kubelet \
      /usr/local/bin/kubectl \
      /usr/bin/kubeadm \
      /usr/bin/kubelet \
      /usr/bin/kubectl \
      /usr/local/bin/containerd \
      /usr/local/bin/containerd-shim \
      /usr/local/bin/containerd-shim-runc-v2 \
      /usr/local/bin/ctr \
      /usr/local/bin/runc \
      /usr/bin/containerd \
      /usr/bin/ctr \
      /usr/bin/runc

# Remove CNI directories
log_info "Removing CNI directories..."
rm -rf /opt/cni/bin \
       /etc/cni

# Remove Kubernetes configuration and data directories
log_info "Removing Kubernetes data directories..."
rm -rf /etc/kubernetes \
       /var/lib/kubelet \
       /var/lib/etcd \
       /var/lib/containerd \
       /run/containerd \
       /run/flannel \
       /var/run/kubernetes

# Remove systemd service files
log_info "Removing systemd service files..."
rm -f /etc/systemd/system/kubelet.service \
      /etc/systemd/system/containerd.service \
      /usr/lib/systemd/system/kubelet.service \
      /usr/lib/systemd/system/containerd.service
rm -rf /etc/systemd/system/kubelet.service.d

# Reload systemd
log_info "Reloading systemd daemon..."
systemctl daemon-reload

# Clean iptables rules
log_info "Cleaning iptables rules..."
for table in nat filter mangle; do
    # Flush KUBE chains
    for chain in $(iptables -t $table -L -n 2>/dev/null | grep "^Chain KUBE-" | awk '{print $2}'); do
        iptables -t $table -F $chain 2>/dev/null || true
    done
    # Delete KUBE chains
    for chain in $(iptables -t $table -L -n 2>/dev/null | grep "^Chain KUBE-" | awk '{print $2}'); do
        iptables -t $table -X $chain 2>/dev/null || true
    done
    # Flush FLANNEL chains
    for chain in $(iptables -t $table -L -n 2>/dev/null | grep "^Chain FLANNEL" | awk '{print $2}'); do
        iptables -t $table -F $chain 2>/dev/null || true
        iptables -t $table -X $chain 2>/dev/null || true
    done
done

# Clean nftables (for RHEL 10)
if command -v nft >/dev/null 2>&1; then
    log_info "Cleaning nftables rules..."
    nft delete table inet flannel-ipv4 2>/dev/null || true
    nft delete table inet flannel-ipv6 2>/dev/null || true
fi

# Unload kernel modules
log_info "Unloading kernel modules..."
modprobe -r br_netfilter 2>/dev/null || true
modprobe -r overlay 2>/dev/null || true
modprobe -r vxlan 2>/dev/null || true

# Remove NetworkManager CNI exclusion config
log_info "Removing NetworkManager CNI exclusion..."
rm -f /etc/NetworkManager/conf.d/99-kubernetes.conf

# Restart NetworkManager
if systemctl is-active --quiet NetworkManager; then
    log_info "Restarting NetworkManager..."
    systemctl restart NetworkManager
fi

# Check for remaining processes
log_info "Checking for remaining Kubernetes processes..."
REMAINING=$(ps aux | grep -E "kube|containerd|flannel" | grep -v grep || true)
if [[ -n "$REMAINING" ]]; then
    log_warn "Some Kubernetes processes are still running:"
    echo "$REMAINING"
else
    log_info "No Kubernetes processes found"
fi

echo ""
log_info "✓ Cleanup Complete!"
echo ""
echo "Summary:"
echo "  ✓ Kubernetes services stopped and disabled"
echo "  ✓ Kubernetes binaries removed"
echo "  ✓ CNI plugins and configurations removed"
echo "  ✓ Kubernetes data directories removed"
echo "  ✓ iptables/nftables rules cleaned"
echo "  ✓ Kernel modules unloaded"
echo "  ✓ NetworkManager configuration cleaned"
echo ""
echo "Next Steps:"
echo "  1. Optional: Reboot the system for a completely clean state"
echo "     sudo reboot"
echo ""
echo "  2. Install RKE2:"
echo "     ansible-playbook -i inventory.ini ansible/playbooks/install-rke2-homelab.yml"
echo ""

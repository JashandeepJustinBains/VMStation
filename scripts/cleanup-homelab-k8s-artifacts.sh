#!/bin/bash
# Cleanup Script for Prior Kubernetes Artifacts on RHEL 10 Homelab Node
# This script removes all Kubernetes components installed before RKE2 migration
# Run this on the homelab node (192.168.4.62) or via Ansible

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}RHEL 10 Homelab Kubernetes Cleanup Script${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Confirm before proceeding
echo -e "${YELLOW}WARNING: This will remove all Kubernetes artifacts from this node.${NC}"
echo -e "${YELLOW}This includes:${NC}"
echo "  - kubeadm/kubelet/kubectl binaries"
echo "  - containerd runtime"
echo "  - CNI plugins and configurations"
echo "  - iptables rules and nftables tables"
echo "  - Kubernetes systemd services"
echo "  - All Kubernetes data directories"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo -e "${GREEN}Step 1: Stopping Kubernetes services...${NC}"
# Stop kubelet if running
if systemctl is-active --quiet kubelet; then
    echo "  Stopping kubelet..."
    systemctl stop kubelet || true
fi

# Stop containerd if running
if systemctl is-active --quiet containerd; then
    echo "  Stopping containerd..."
    systemctl stop containerd || true
fi

# Disable services
echo "  Disabling services..."
systemctl disable kubelet 2>/dev/null || true
systemctl disable containerd 2>/dev/null || true

echo ""
echo -e "${GREEN}Step 2: Removing Kubernetes binaries...${NC}"
# Remove Kubernetes binaries
for binary in kubeadm kubelet kubectl; do
    if [ -f "/usr/local/bin/$binary" ]; then
        echo "  Removing /usr/local/bin/$binary"
        rm -f "/usr/local/bin/$binary"
    fi
    if [ -f "/usr/bin/$binary" ]; then
        echo "  Removing /usr/bin/$binary"
        rm -f "/usr/bin/$binary"
    fi
done

# Remove containerd
if [ -f "/usr/local/bin/containerd" ] || [ -f "/usr/bin/containerd" ]; then
    echo "  Removing containerd binaries..."
    rm -f /usr/local/bin/containerd* /usr/local/bin/ctr /usr/local/bin/runc
    rm -f /usr/bin/containerd* /usr/bin/ctr /usr/bin/runc
fi

echo ""
echo -e "${GREEN}Step 3: Removing CNI plugins and configurations...${NC}"
if [ -d "/opt/cni/bin" ]; then
    echo "  Removing /opt/cni/bin"
    rm -rf /opt/cni/bin
fi
if [ -d "/etc/cni" ]; then
    echo "  Removing /etc/cni"
    rm -rf /etc/cni
fi

echo ""
echo -e "${GREEN}Step 4: Removing Kubernetes configuration and data directories...${NC}"
# Remove Kubernetes directories
directories=(
    "/etc/kubernetes"
    "/var/lib/kubelet"
    "/var/lib/etcd"
    "/var/lib/containerd"
    "/run/containerd"
    "/run/flannel"
    "/var/run/kubernetes"
    "/etc/systemd/system/kubelet.service"
    "/etc/systemd/system/kubelet.service.d"
    "/etc/systemd/system/containerd.service"
    "/usr/lib/systemd/system/kubelet.service"
    "/usr/lib/systemd/system/containerd.service"
)

for dir in "${directories[@]}"; do
    if [ -e "$dir" ]; then
        echo "  Removing $dir"
        rm -rf "$dir"
    fi
done

echo ""
echo -e "${GREEN}Step 5: Cleaning iptables rules...${NC}"
# Flush all iptables rules created by Kubernetes
echo "  Flushing KUBE-* chains..."
for table in nat filter mangle; do
    # List all chains
    chains=$(iptables -t $table -L -n | grep "^Chain KUBE-" | awk '{print $2}' || true)
    for chain in $chains; do
        echo "    Flushing chain $chain in table $table"
        iptables -t $table -F "$chain" 2>/dev/null || true
    done
done

# Delete KUBE-* chains
for table in nat filter mangle; do
    chains=$(iptables -t $table -L -n | grep "^Chain KUBE-" | awk '{print $2}' || true)
    for chain in $chains; do
        echo "    Deleting chain $chain in table $table"
        iptables -t $table -X "$chain" 2>/dev/null || true
    done
done

# Clean FLANNEL chains if they exist
for table in nat filter; do
    chains=$(iptables -t $table -L -n | grep "^Chain FLANNEL" | awk '{print $2}' || true)
    for chain in $chains; do
        echo "    Flushing and deleting FLANNEL chain $chain in table $table"
        iptables -t $table -F "$chain" 2>/dev/null || true
        iptables -t $table -X "$chain" 2>/dev/null || true
    done
done

echo ""
echo -e "${GREEN}Step 6: Cleaning nftables tables (RHEL 10 specific)...${NC}"
# Remove flannel nftables tables if they exist
if command -v nft &> /dev/null; then
    echo "  Removing flannel nftables tables..."
    nft delete table inet flannel-ipv4 2>/dev/null || echo "    (flannel-ipv4 table not found)"
    nft delete table inet flannel-ipv6 2>/dev/null || echo "    (flannel-ipv6 table not found)"
    
    # List remaining tables
    echo "  Remaining nftables tables:"
    nft list tables | sed 's/^/    /'
fi

echo ""
echo -e "${GREEN}Step 7: Removing kernel modules...${NC}"
# Unload Kubernetes-related kernel modules
modules=(
    "br_netfilter"
    "overlay"
    "vxlan"
)

for mod in "${modules[@]}"; do
    if lsmod | grep -q "^$mod"; then
        echo "  Unloading module $mod"
        rmmod "$mod" 2>/dev/null || echo "    (could not unload $mod, may be in use)"
    fi
done

echo ""
echo -e "${GREEN}Step 8: Cleaning NetworkManager CNI exclusions...${NC}"
if [ -f "/etc/NetworkManager/conf.d/99-kubernetes.conf" ]; then
    echo "  Removing /etc/NetworkManager/conf.d/99-kubernetes.conf"
    rm -f /etc/NetworkManager/conf.d/99-kubernetes.conf
    systemctl restart NetworkManager || true
fi

echo ""
echo -e "${GREEN}Step 9: Reloading systemd daemon...${NC}"
systemctl daemon-reload

echo ""
echo -e "${GREEN}Step 10: Checking for remaining artifacts...${NC}"
echo "  Checking for remaining Kubernetes processes..."
ps aux | grep -E "kube|containerd|flannel" | grep -v grep || echo "    No Kubernetes processes found"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  ✓ Kubernetes services stopped and disabled"
echo "  ✓ Kubernetes binaries removed"
echo "  ✓ CNI plugins and configurations removed"
echo "  ✓ Kubernetes data directories removed"
echo "  ✓ iptables/nftables rules cleaned"
echo "  ✓ Kernel modules unloaded"
echo "  ✓ NetworkManager configuration cleaned"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Verify no Kubernetes processes remain: ps aux | grep kube"
echo "  2. Optional: Reboot the system for a clean state"
echo "  3. Ready to install RKE2"
echo ""
echo -e "${YELLOW}To install RKE2, run:${NC}"
echo "  ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml"
echo ""

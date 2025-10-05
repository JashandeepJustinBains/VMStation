#!/bin/bash
# Fix CrashLoopBackOff issues on RHEL 10 homelab node
# This script applies network configuration fixes and forces pod recreation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The ansible directory lives at the repo root under 'ansible'. From scripts/ the correct
# relative path is one level up.
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/ansible"

echo "========================================="
echo "RHEL 10 CrashLoopBackOff Emergency Fix"
echo "========================================="
echo ""
echo "This script will:"
echo "1. Apply network-fix role to homelab node"
echo "2. Apply updated Flannel manifest with improved readiness probe"
echo "3. Force Flannel pod recreation on homelab"
echo "4. Validate all pods are running correctly"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Running playbook..."
# Run the playbook from the repository root so Ansible can locate roles under ansible/roles
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/fix-homelab-crashloop.yml

echo ""
echo "========================================="
echo "Fix complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Check pod status: kubectl get pods -A"
echo "2. If still failing, check logs: kubectl logs -n kube-flannel <pod-name> -c kube-flannel"
echo "3. Verify network: kubectl run test --image=busybox --rm -it -- ping 10.244.0.1"

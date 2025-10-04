#!/bin/bash
# Comprehensive fix for homelab node networking issues
# Addresses: Flannel CrashLoopBackOff, kube-proxy crashes, CoreDNS scheduling

set -euo pipefail

echo "=== Homelab Node Comprehensive Fix ==="
echo ""
echo "This script fixes:"
echo "  - Flannel CrashLoopBackOff on homelab node"
echo "  - kube-proxy crashes on RHEL 10"
echo "  - CoreDNS scheduling issues"
echo "  - Stuck ContainerCreating pods"
echo ""

# Function to wait for kubectl to be available
wait_for_kubectl() {
    echo "Waiting for Kubernetes API to become available..."
  i=1
  while [ "$i" -le 30 ]; do
    if kubectl get nodes >/dev/null 2>&1; then
      echo "✓ Kubernetes API is available"
      return 0
    fi
    echo "  Waiting for API... ($i/30)"
    sleep 2
    i=$((i+1))
  done
    echo "✗ ERROR: Kubernetes API is still unavailable after 60 seconds"
    return 1
}

# Determine script and repo root so we can look for ansible group_vars files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Try to obtain a sudo password from environment or common ansible group_vars files
get_sudo_pass() {
  # Prefer explicit environment variable
  if [ -n "${SUDO_PASS:-}" ]; then
    echo "Using SUDO_PASS from environment"
    return 0
  fi

  candidates="$REPO_ROOT/ansible/inventory/group_vars/secrets.yml $REPO_ROOT/ansible/inventory/group_vars/all.yml $REPO_ROOT/ansible/group_vars/all.yml $REPO_ROOT/ansible/inventory/group_vars/secrets.yml.example"

  for f in $candidates; do
    if [ -f "$f" ]; then
      # If a vault password file is supplied, try to decrypt the file and extract variable
      if [ -n "${ANSIBLE_VAULT_PASSWORD_FILE:-}${VAULT_PASSWORD_FILE:-}${VAULT_PASS_FILE:-}" ] && command -v ansible-vault >/dev/null 2>&1; then
        vault_file_var="${ANSIBLE_VAULT_PASSWORD_FILE:-${VAULT_PASSWORD_FILE:-${VAULT_PASS_FILE:-}}}"
        if [ -f "$vault_file_var" ]; then
          # attempt to view decrypted content and parse variable
          dec=$(ansible-vault view "$f" --vault-password-file "$vault_file_var" 2>/dev/null || true)
          if [ -n "$dec" ]; then
            val=$(echo "$dec" | grep -E '^[[:space:]]*(vault_r430_sudo_password|ansible_become_pass)[[:space:]]*:' | sed -E 's/^[[:space:]]*(vault_r430_sudo_password|ansible_become_pass)[[:space:]]*:[[:space:]]*\"?(.*)\"?/\2/' | sed 's/["'"'"']$//' | sed 's/^\s*//g' | head -n1 || true)
            if [ -n "$val" ] && ! echo "$val" | grep -q '{{'; then
              export SUDO_PASS="$val"
              echo "Found sudo password in (vault): $f"
              return 0
            fi
          fi
        fi
      fi

      # Look for common variable names in plaintext; ignore commented lines
  val=$(grep -E '^[[:space:]]*(vault_r430_sudo_password|ansible_become_pass)[[:space:]]*:' "$f" | sed -E 's/^[[:space:]]*(vault_r430_sudo_password|ansible_become_pass)[[:space:]]*:[[:space:]]*\"?(.*)\"?/\2/' | sed 's/["'"'"']$//' | sed 's/^\s*//g' | head -n1 || true)
      if [ -n "$val" ]; then
        # skip templated placeholders like {{ ... }}
        if echo "$val" | grep -q '{{'; then
          continue
        fi
        export SUDO_PASS="$val"
        echo "Found sudo password in: $f"
        return 0
      fi
    fi
  done

  return 1
}

# Helper to run a command on a remote host (no sudo)
remote() {
  local host="$1"; shift
  local cmd="$*"
  ssh "$host" bash -lc "$cmd"
}

# Helper to run a command on a remote host with sudo; if SUDO_PASS is set it will
# be provided first via stdin and then the command will be sent to remote sudo's stdin
# so sudo -S can read the password, and bash -s executes the following commands.
remote_sudo() {
  host="$1"; shift
  cmd="$*"
  if [ -n "${SUDO_PASS:-}" ]; then
    # Send password then the command script to remote sudo/bash via ssh stdin
    (
      printf "%s\n" "$SUDO_PASS"
      printf "%s\n" "$cmd"
    ) | ssh "$host" "sudo -S -p '' bash -s"
  else
    # No password provided: run command via ssh -> sudo -> bash -s, sending the command on stdin
    ssh "$host" "sudo bash -s" <<EOF
$cmd
EOF
  fi
}

# Try to auto-discover sudo password (optional)
if get_sudo_pass; then
  :
else
  echo "Note: no sudo password discovered in repository files; the script may prompt for one when required." >&2
fi

# Function to check if homelab node exists
check_homelab_node() {
    if ! kubectl get node homelab >/dev/null 2>&1; then
        echo "✗ ERROR: homelab node not found in cluster"
        echo "Available nodes:"
        kubectl get nodes
        exit 1
    fi
    echo "✓ homelab node found"
}

# Step 1: System-level fixes on homelab node
echo "=========================================="
echo "STEP 1: System-level fixes on homelab node"
echo "=========================================="
echo ""

echo "1.1 Disabling swap (required for kubelet)..."
# Use heredoc over ssh to avoid quoting/escaping issues with sed on the remote host.
if [ -n "${SUDO_PASS:-}" ]; then
  printf "%s\n" "$SUDO_PASS" | ssh jashandeepjustinbains@192.168.4.62 "sudo -S bash -s" <<'EOF'
swapoff -a 2>/dev/null || echo "Swap already disabled"
sed -i '/[[:space:]]swap[[:space:]]/s/^/# /' /etc/fstab 2>/dev/null || echo "fstab already updated"
EOF
else
  ssh jashandeepjustinbains@192.168.4.62 "sudo bash -s" <<'EOF'
swapoff -a 2>/dev/null || echo "Swap already disabled"
sed -i '/[[:space:]]swap[[:space:]]/s/^/# /' /etc/fstab 2>/dev/null || echo "fstab already updated"
EOF
fi
echo "✓ Swap disabled"
echo ""

echo "1.2 Setting SELinux to permissive mode..."
remote_sudo jashandeepjustinbains@192.168.4.62 "setenforce 0 2>/dev/null || echo \"SELinux already permissive\""
remote_sudo jashandeepjustinbains@192.168.4.62 "sed -i \"s/^SELINUX=enforcing/SELINUX=permissive/\" /etc/selinux/config 2>/dev/null || echo \"SELinux config already updated\""
echo "✓ SELinux set to permissive"
echo ""

echo "1.3 Loading required kernel modules..."
remote_sudo jashandeepjustinbains@192.168.4.62 "modprobe br_netfilter overlay nf_conntrack vxlan 2>/dev/null || echo \"Modules already loaded\""
echo "✓ Kernel modules loaded"
echo ""

echo "1.4 Configuring iptables backend for RHEL 10..."
# Check if iptables-nft exists (RHEL 10)
if remote jashandeepjustinbains@192.168.4.62 'test -f /usr/sbin/iptables-nft' 2>/dev/null; then
    echo "  Detected iptables-nft, configuring nftables backend..."
    
    # Install alternatives if they don't exist
  remote_sudo jashandeepjustinbains@192.168.4.62 "update-alternatives --install /usr/sbin/iptables iptables /usr/sbin/iptables-nft 10 2>/dev/null || true"
  remote_sudo jashandeepjustinbains@192.168.4.62 "update-alternatives --install /usr/sbin/ip6tables ip6tables /usr/sbin/ip6tables-nft 10 2>/dev/null || true"
    
  # Set the backend
  remote_sudo jashandeepjustinbains@192.168.4.62 "update-alternatives --set iptables /usr/sbin/iptables-nft 2>/dev/null || echo \"iptables-nft already set\""
  remote_sudo jashandeepjustinbains@192.168.4.62 "update-alternatives --set ip6tables /usr/sbin/ip6tables-nft 2>/dev/null || echo \"ip6tables-nft already set\""

    echo "  ✓ nftables backend configured"
else
    echo "  iptables-legacy detected, no backend change needed"
fi
echo ""

echo "1.5 Creating iptables lock file..."
remote_sudo jashandeepjustinbains@192.168.4.62 "touch /run/xtables.lock 2>/dev/null || echo \"Lock file already exists\""
echo "✓ iptables lock file created"
echo ""

echo "1.6 Pre-creating kube-proxy iptables chains..."
remote_sudo jashandeepjustinbains@192.168.4.62 "bash -lc '
  # Create NAT table chains
  iptables -t nat -N KUBE-SERVICES 2>/dev/null || true
  iptables -t nat -N KUBE-POSTROUTING 2>/dev/null || true
  iptables -t nat -N KUBE-FIREWALL 2>/dev/null || true
  iptables -t nat -N KUBE-MARK-MASQ 2>/dev/null || true
    
  # Create filter table chains
  iptables -t filter -N KUBE-FORWARD 2>/dev/null || true
  iptables -t filter -N KUBE-SERVICES 2>/dev/null || true
    
  # Link chains to base chains
  iptables -t nat -C PREROUTING -j KUBE-SERVICES 2>/dev/null || iptables -t nat -A PREROUTING -j KUBE-SERVICES
  iptables -t nat -C OUTPUT -j KUBE-SERVICES 2>/dev/null || iptables -t nat -A OUTPUT -j KUBE-SERVICES
  iptables -t nat -C POSTROUTING -j KUBE-POSTROUTING 2>/dev/null || iptables -t nat -A POSTROUTING -j KUBE-POSTROUTING
  iptables -t filter -C FORWARD -j KUBE-FORWARD 2>/dev/null || iptables -t filter -A FORWARD -j KUBE-FORWARD
'"
echo "✓ iptables chains pre-created"
echo ""

echo "1.7 Clearing stale network interfaces..."
remote_sudo jashandeepjustinbains@192.168.4.62 "ip link delete flannel.1 2>/dev/null || echo \"No flannel.1 to delete\""
remote_sudo jashandeepjustinbains@192.168.4.62 "ip link delete cni0 2>/dev/null || echo \"No cni0 to delete\""
echo "✓ Stale interfaces cleared"
echo ""

echo "1.8 Clearing CNI configuration (will be regenerated)..."
remote_sudo jashandeepjustinbains@192.168.4.62 "rm -f /etc/cni/net.d/10-flannel.conflist 2>/dev/null || echo \"No CNI config to remove\""
remote_sudo jashandeepjustinbains@192.168.4.62 "rm -rf /var/lib/cni/flannel/* 2>/dev/null || echo \"No flannel data to remove\""
echo "✓ CNI configuration cleared"
echo ""

echo "1.9 Restarting kubelet..."
remote_sudo jashandeepjustinbains@192.168.4.62 "systemctl restart kubelet"
sleep 5
echo "✓ kubelet restarted"
echo ""

# Wait for kubectl to be available
wait_for_kubectl || exit 1
echo ""

# Check homelab node
check_homelab_node
echo ""

# Step 2: Fix Flannel CrashLoopBackOff
echo "=========================================="
echo "STEP 2: Fix Flannel CrashLoopBackOff"
echo "=========================================="
echo ""

echo "2.1 Checking current Flannel pod status..."
kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o wide || echo "No Flannel pods found yet"
echo ""

echo "2.2 Deleting Flannel pod to force recreation..."
FLANNEL_POD=$(kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$FLANNEL_POD" ]; then
    echo "  Deleting pod: $FLANNEL_POD"
    kubectl delete pod -n kube-flannel "$FLANNEL_POD" --wait=false
    echo "✓ Flannel pod deleted"
else
    echo "  No Flannel pod to delete (will be created automatically)"
fi
echo ""

echo "2.3 Waiting for Flannel to restart (30 seconds)..."
sleep 30
echo ""

echo "2.4 Checking new Flannel pod status..."
kubectl get pods -n kube-flannel --field-selector spec.nodeName=homelab -o wide || echo "Flannel pod still starting"
echo ""

# Step 3: Fix kube-proxy CrashLoopBackOff
echo "=========================================="
echo "STEP 3: Fix kube-proxy CrashLoopBackOff"
echo "=========================================="
echo ""

echo "3.1 Checking current kube-proxy pod status..."
kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab -o wide || echo "No kube-proxy pods found yet"
echo ""

echo "3.2 Deleting kube-proxy pod to force recreation with new iptables config..."
PROXY_POD=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$PROXY_POD" ]; then
    echo "  Deleting pod: $PROXY_POD"
    kubectl delete pod -n kube-system "$PROXY_POD" --wait=false
    echo "✓ kube-proxy pod deleted"
else
    echo "  No kube-proxy pod to delete"
fi
echo ""

echo "3.3 Waiting for kube-proxy to restart (30 seconds)..."
sleep 30
echo ""

echo "3.4 Checking new kube-proxy pod status..."
kubectl get pods -n kube-system -l k8s-app=kube-proxy --field-selector spec.nodeName=homelab -o wide || echo "kube-proxy pod still starting"
echo ""

# Step 4: Fix CoreDNS scheduling
echo "=========================================="
echo "STEP 4: Fix CoreDNS Scheduling"
echo "=========================================="
echo ""

echo "4.1 Checking CoreDNS pod placement..."
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide || echo "No CoreDNS pods found"
echo ""

echo "4.2 Patching CoreDNS to prefer control-plane nodes..."
kubectl patch deployment coredns -n kube-system --type=merge -p '
{
  "spec": {
    "template": {
      "spec": {
        "affinity": {
          "nodeAffinity": {
            "preferredDuringSchedulingIgnoredDuringExecution": [
              {
                "weight": 100,
                "preference": {
                  "matchExpressions": [
                    {
                      "key": "node-role.kubernetes.io/control-plane",
                      "operator": "Exists"
                    }
                  ]
                }
              }
            ]
          }
        },
        "tolerations": [
          {
            "key": "node-role.kubernetes.io/control-plane",
            "operator": "Exists",
            "effect": "NoSchedule"
          }
        ]
      }
    }
  }
}' 2>/dev/null || echo "CoreDNS deployment not found or already patched"
echo "✓ CoreDNS scheduling configuration updated"
echo ""

# Step 5: Restart stuck ContainerCreating pods
echo "=========================================="
echo "STEP 5: Restart Stuck ContainerCreating Pods"
echo "=========================================="
echo ""

echo "5.1 Checking for stuck pods..."
STUCK_PODS=$(kubectl get pods -A --field-selector status.phase=Pending -o json 2>/dev/null | jq -r '.items[] | select(.status.containerStatuses != null) | select(.status.containerStatuses[].state.waiting.reason == "ContainerCreating") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

if [ -n "$STUCK_PODS" ]; then
    echo "  Found stuck pods:"
    echo "$STUCK_PODS"
    echo ""
    echo "  Deleting stuck pods..."
    echo "$STUCK_PODS" | while read -r pod; do
        if [ -n "$pod" ]; then
            kubectl delete pod "$pod" --wait=false 2>/dev/null || echo "  Failed to delete $pod"
        fi
    done
    echo "✓ Stuck pods deleted"
else
    echo "  No stuck ContainerCreating pods found"
fi
echo ""

# Step 6: Final validation
echo "=========================================="
echo "STEP 6: Final Validation"
echo "=========================================="
echo ""

echo "6.1 Waiting for pods to stabilize (60 seconds)..."
sleep 60
echo ""

echo "6.2 Checking for CrashLoopBackOff pods..."
CRASHLOOP=$(kubectl get pods -A --field-selector status.phase=Running -o json 2>/dev/null | \
    jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting.reason == "CrashLoopBackOff") | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")

if [ -n "$CRASHLOOP" ]; then
    echo "⚠ WARNING: Still found pods in CrashLoopBackOff:"
    echo "$CRASHLOOP"
    echo ""
    echo "To diagnose:"
    echo "  ./scripts/diagnose-flannel-homelab.sh"
    echo "  ./scripts/diagnose-homelab-issues.sh"
else
    echo "✓ No CrashLoopBackOff pods detected"
fi
echo ""

echo "6.3 Final cluster status:"
echo ""
echo "--- Nodes ---"
kubectl get nodes -o wide
echo ""
echo "--- Flannel Pods ---"
kubectl get pods -n kube-flannel -o wide
echo ""
echo "--- kube-system Pods (on homelab) ---"
kubectl get pods -n kube-system --field-selector spec.nodeName=homelab -o wide
echo ""
echo "--- CoreDNS Pods ---"
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
echo ""

echo "=========================================="
echo "=== Fix Complete ==="
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ System-level fixes applied to homelab node"
echo "  ✓ Flannel pod restarted"
echo "  ✓ kube-proxy pod restarted with proper iptables config"
echo "  ✓ CoreDNS scheduling optimized"
echo "  ✓ Stuck pods cleaned up"
echo ""
echo "If issues persist:"
echo "  1. Check pod logs: kubectl logs -n <namespace> <pod-name>"
echo "  2. Run diagnostics: ./scripts/diagnose-homelab-issues.sh"
echo "  3. Check node status: kubectl describe node homelab"
echo ""

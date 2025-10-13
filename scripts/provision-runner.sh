#!/usr/bin/env bash
# Simple local bootstrap script to prepare a control host for automation
set -euo pipefail

OP_USER="vmstation-ops"
VENV_DIR="/opt/kubespray-venv"
KUBECTL_VERSION="v1.29.0"

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root. Exiting." >&2
  exit 1
fi

# Create operator user
if ! id -u "$OP_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$OP_USER"
  echo "$OP_USER ALL=(ALL) NOPASSWD:SETENV: /usr/bin/ansible-playbook, /usr/bin/systemctl, /usr/bin/journalctl, /usr/bin/scp, /usr/bin/ssh, /usr/bin/wakeonlan, /usr/bin/cp" > /etc/sudoers.d/$OP_USER
  chmod 0440 /etc/sudoers.d/$OP_USER
fi

# Install packages (Debian/Ubuntu)
if command -v apt >/dev/null 2>&1; then
  apt update
  apt install -y python3-venv python3-pip git curl wget unzip sudo build-essential
fi

# Create venv
python3 -m venv "$VENV_DIR" || true
# Install pip pkgs
$VENV_DIR/bin/pip install --upgrade pip
$VENV_DIR/bin/pip install ansible==8.5.0 PyYAML ruamel.yaml

# Download kubectl
curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl
chmod +x /usr/local/bin/kubectl

# Create ssh key for operator user
sudo -u $OP_USER mkdir -p /home/$OP_USER/.ssh
if [[ ! -f /home/$OP_USER/.ssh/id_vmstation_ops ]]; then
  sudo -u $OP_USER ssh-keygen -t rsa -b 4096 -f /home/$OP_USER/.ssh/id_vmstation_ops -N ""
fi

echo "Bootstrap complete. Public key is at /home/$OP_USER/.ssh/id_vmstation_ops.pub - add it to target hosts' authorized_keys"

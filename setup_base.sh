#!/bin/bash
#This script ensures every machine has necessary system utilities.

echo "Updating system..."
apt update && apt upgrade -y

echo "Installing essential tools..."
apt install -y openssh-server net-tools htop tmux git curl wget ufw fail2ban

echo "Setting up firewall..."
ufw default deny incoming
ufw allow ssh
ufw enable

echo "Base setup complete. Please reboot!"
